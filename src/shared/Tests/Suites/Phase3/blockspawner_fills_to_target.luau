local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local Colors = require(ReplicatedStorage.Shared.Core.Colors)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)

local TEST_TARGET = 8
local TEST_PARENT_NAME = "TestSpawnerContainer"
local TEST_ARENA_ID = "TestFillsToTarget"

-- BlockSpawner's actual color vocabulary: the three reservoir colors
-- (Core/Colors' single source of truth) plus the wildcard tile color
-- (Wildcard's single source of truth) — not a hardcoded fourth string.
local VALID_TILE_COLORS: { [string]: boolean } = { [Wildcard.COLOR] = true }
for _, color in Colors.SPELL_COLORS do
	VALID_TILE_COLORS[color] = true
end

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
			if type(color) ~= "string" or not VALID_TILE_COLORS[color] then
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
