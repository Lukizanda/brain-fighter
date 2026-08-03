--!strict

----------------------------------------------------------------------
-- blockshoot_payload_validation — ConsumeBlock payload trust (5.4)
----------------------------------------------------------------------
-- Drives BlockShootValidation.checkBlock directly rather than firing
-- the remote, because the interesting inputs (a table wearing a Model's
-- property names) cannot be sent from a test that runs on the server.
--
-- These modules live under ReplicatedStorage but the autorunner is a
-- server Script, so reaching into ServerScriptService is valid here.
----------------------------------------------------------------------

local CollectionService  = game:GetService("CollectionService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local BlockShootValidation = require(ServerScriptService.Server.BlockShoot.BlockShootValidation)

type Ctx = {
	created: { Instance },
}

local function track(ctx: Ctx, inst: Instance): Instance
	table.insert(ctx.created, inst)
	return inst
end

return {
	name = "blockshoot_payload_validation",

	setup = function(ctx: Ctx)
		ctx.created = {}
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		-- A fake table shaped like a Model — the classic remote exploit.
		local imposter = { Name = "LetterBlock", ClassName = "Model" }
		local got, _ = BlockShootValidation.checkBlock(imposter)
		if got ~= nil then
			return false, "accepted a table imposter"
		end

		-- Primitives and nil.
		for _, bad in { 42, "LetterBlock", true } do
			if BlockShootValidation.checkBlock(bad) ~= nil then
				return false, string.format("accepted %s payload", typeof(bad))
			end
		end
		if BlockShootValidation.checkBlock(nil) ~= nil then
			return false, "accepted nil payload"
		end

		-- A real Instance of the wrong class.
		local part = track(ctx, Instance.new("Part")) :: Part
		part.Anchored = true
		part.Parent = workspace
		if BlockShootValidation.checkBlock(part) ~= nil then
			return false, "accepted a Part"
		end

		-- A real workspace Model with no LetterBlock tag — an exploiter
		-- naming an arbitrary world Model to grief it out of existence.
		local untagged = track(ctx, Instance.new("Model")) :: Model
		untagged.Name = "HardeningUntaggedModel"
		untagged.Parent = workspace
		if BlockShootValidation.checkBlock(untagged) ~= nil then
			return false, "accepted an untagged Model"
		end

		-- Tagged, but not in the world: the ReplicatedStorage template
		-- shape, and the already-consumed shape.
		local offstage = track(ctx, Instance.new("Model")) :: Model
		offstage.Name = "HardeningOffstageBlock"
		CollectionService:AddTag(offstage, LetterBlocks.TAG)
		offstage.Parent = ReplicatedStorage
		if BlockShootValidation.checkBlock(offstage) ~= nil then
			return false, "accepted a tagged Model outside workspace"
		end

		-- The legitimate case must still pass, or hardening broke play.
		local realBlock = track(ctx, Instance.new("Model")) :: Model
		realBlock.Name = "HardeningRealBlock"
		CollectionService:AddTag(realBlock, LetterBlocks.TAG)
		realBlock.Parent = workspace
		local accepted, reason = BlockShootValidation.checkBlock(realBlock)
		if accepted ~= realBlock then
			return false, string.format("rejected a legitimate LetterBlock: %s", tostring(reason))
		end

		-- ...and must stop passing once it has been consumed, which is
		-- what makes a double-consume race a no-op.
		realBlock.Parent = nil
		if BlockShootValidation.checkBlock(realBlock) ~= nil then
			return false, "accepted an already-consumed block"
		end

		return true, "rejected 7 malformed payloads, accepted the legitimate block"
	end,

	teardown = function(ctx: Ctx)
		for _, inst in ctx.created do
			inst:Destroy()
		end
	end,
}
