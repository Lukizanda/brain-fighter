local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockShoot = require(ReplicatedStorage.Shared.BlockShoot)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)

return {
	name = "BlockShoot helpers — findLetterBlock and readBlock",

	setup = function(ctx)
		local block = LetterBlocks.spawn("F", "blue", CFrame.new(0, 50, 0))
		ctx.block = block
		ctx.cube = block:FindFirstChild("Cube")
	end,

	verify = function(ctx)
		local found = BlockShoot.findLetterBlock(ctx.cube)
		if found ~= ctx.block then
			return false, "findLetterBlock did not return the parent Model from the Cube child"
		end

		local letter, color = BlockShoot.readBlock(ctx.block)
		if letter ~= "F" then
			return false, string.format("readBlock letter: expected F, got %s", tostring(letter))
		end
		if color ~= "blue" then
			return false, string.format("readBlock color: expected blue, got %s", tostring(color))
		end

		local noResult = BlockShoot.findLetterBlock(workspace.Terrain)
		if noResult ~= nil then
			return false, "findLetterBlock should return nil for untagged instance"
		end

		return true, "findLetterBlock traverses to tagged Model, readBlock returns correct attrs"
	end,

	teardown = function(ctx)
		if ctx.block then
			ctx.block:Destroy()
		end
	end,
}
