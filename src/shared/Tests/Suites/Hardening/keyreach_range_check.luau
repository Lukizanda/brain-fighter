--!strict

----------------------------------------------------------------------
-- keyreach_range_check — the server refuses a pop of a key letter from beyond its own reach, and leaves ordinary blocks alone
----------------------------------------------------------------------
-- Drives BlockShootValidation.checkRange directly with a stand-in character
-- (a Model with a HumanoidRootPart) and stand-in blocks (a Model with one
-- part), as the other Hardening tests do. A block carrying a pop reach
-- (KeyConstants.POP_REACH_ATTRIBUTE) is accepted inside the reach, accepted
-- inside the reach plus the server's tolerance, and refused beyond it; a
-- block without one is accepted at the same distances.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local KeyConstants = require(ReplicatedStorage.Shared.BlockSpawner.KeyConstants)
local BlockShootConstants = require(ServerScriptService.Server.BlockShoot.BlockShootConstants)
local BlockShootValidation = require(ServerScriptService.Server.BlockShoot.BlockShootValidation)

local ORIGIN = Vector3.new(0, 6200, 0)
local REACH_STUDS = 40
local INSIDE_STUDS = 30
local BEYOND_MARGIN_STUDS = 2

local function standIn(name: string, position: Vector3, partName: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local part = Instance.new("Part")
	part.Name = partName
	part.Anchored = true
	part.Size = Vector3.one
	part.Position = position
	part.Parent = model
	model.PrimaryPart = part
	return model
end

return {
	name = "keyreach_range_check",

	run = function(ctx: any)
		local folder = Instance.new("Folder")
		folder.Name = "KeyReachTestFixture"
		folder.Parent = workspace
		ctx.folder = folder

		local character = standIn("KeyReachCharacter", ORIGIN, "HumanoidRootPart")
		character.Parent = folder
		local tolerance = BlockShootConstants.OWN_REACH_TOLERANCE_STUDS
		local function blockAt(distance: number, reach: number?): Model
			local block = standIn("KeyReachBlock", ORIGIN + Vector3.new(distance, 0, 0), "Body")
			if reach then
				block:SetAttribute(KeyConstants.POP_REACH_ATTRIBUTE, reach)
			end
			block.Parent = folder
			return block
		end

		ctx.inside = BlockShootValidation.checkRange(character, blockAt(INSIDE_STUDS, REACH_STUDS))
		ctx.inTolerance = BlockShootValidation.checkRange(character, blockAt(REACH_STUDS + tolerance / 2, REACH_STUDS))
		local beyondOk, beyondReason = BlockShootValidation.checkRange(
			character, blockAt(REACH_STUDS + tolerance + BEYOND_MARGIN_STUDS, REACH_STUDS)
		)
		ctx.beyond = beyondOk
		ctx.beyondReason = beyondReason
		ctx.plainFar = BlockShootValidation.checkRange(character, blockAt(REACH_STUDS + tolerance + BEYOND_MARGIN_STUDS, nil))
		ctx.done = true
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.done then
			return false, "the test did not finish"
		end
		if not ctx.inside then
			return false, "a key letter inside its reach was refused"
		end
		if not ctx.inTolerance then
			return false, "a key letter inside the reach plus the tolerance was refused"
		end
		if ctx.beyond or type(ctx.beyondReason) ~= "string" then
			return false, "a key letter beyond its reach was accepted"
		end
		if not ctx.plainFar then
			return false, "an ordinary block was refused at a distance only a key letter's reach forbids"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.folder then
			ctx.folder:Destroy()
		end
	end,
}
