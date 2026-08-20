local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)

local TEST_TARGET = 8
local TEST_PARENT_NAME = "TestSpawnerContainer"
local TEST_ARENA_ID = "TestFillsToTarget"

return {
	name = "BlockSpawner fills to target count",

	setup = function(ctx)
		local container = Instance.new("Folder")
		container.Name = TEST_PARENT_NAME
		container.Parent = workspace
		ctx.container = container

		-- Its own pool in its own arena. As a singleton this fixture had to
		-- stop the live arena's spawner first and never restarted it, so a
		-- test run left the real arena empty for the rest of the playtest.
		-- Instances are isolated by construction: getActiveBlocks() sees
		-- only this pool's blocks, so the shipped arena keeps running.
		ctx.spawner = BlockSpawner.new({
			arenaId = TEST_ARENA_ID,
			targetCount = TEST_TARGET,
			boxMin = Vector3.new(-10, 10, -10),
			boxMax = Vector3.new(10, 18, 10),
			parent = container,
		})
		ctx.spawner:start()
	end,

	verify = function(ctx)
		local blocks = ctx.spawner:getActiveBlocks()
		if #blocks ~= TEST_TARGET then
			return false, string.format("expected %d blocks, got %d", TEST_TARGET, #blocks)
		end

		for _, block in blocks do
			if not CollectionService:HasTag(block, LetterBlocks.TAG) then
				return false, "block missing LetterBlock tag"
			end
			local letter = block:GetAttribute(LetterBlocks.LETTER_ATTRIBUTE)
			local color = block:GetAttribute(LetterBlocks.COLOR_ATTRIBUTE)
			if not letter or #letter ~= 1 then
				return false, string.format("invalid letter attribute: %s", tostring(letter))
			end
			if color ~= "red" and color ~= "green" and color ~= "blue" then
				return false, string.format("invalid color attribute: %s", tostring(color))
			end
		end

		return true, string.format("%d blocks spawned with valid attributes", #blocks)
	end,

	teardown = function(ctx)
		if ctx.spawner then
			-- destroy() halts the pool and removes its blocks.
			ctx.spawner:destroy()
		end
		if ctx.container then
			ctx.container:Destroy()
		end
	end,
}
