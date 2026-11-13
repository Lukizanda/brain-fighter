local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)

local TEST_TARGET = 60
local ONLY_COLOR = "green"
local TEST_PARENT_NAME = "TestColorOnlyContainer"
local TEST_ARENA_ID = "TestColorOnly"
local WILD_ARENA_ID = "TestColorOnlyWildcard"

local function makeBox(letterTable: string?)
	return {
		boxMin = Vector3.new(-15, 10, -15),
		boxMax = Vector3.new(15, 20, 15),
		letterTable = letterTable,
		colorOnly = ONLY_COLOR,
		label = "TestColorOnlyVolume",
	}
end

return {
	name = "BlockSpawner ColorOnly gives one colour, but wildcards stay gold",

	setup = function(ctx)
		local container = Instance.new("Folder")
		container.Name = TEST_PARENT_NAME
		container.Parent = workspace
		ctx.container = container

		ctx.spawner = BlockSpawner.new({
			arenaId = TEST_ARENA_ID,
			boxes = { makeBox(nil) },
			targetCount = TEST_TARGET,
			parent = container,
		})
		ctx.spawner:start()

		-- A wildcard-only volume with ColorOnly set: every block is a
		-- wildcard, so every block must be gold, not green.
		ctx.wildSpawner = BlockSpawner.new({
			arenaId = WILD_ARENA_ID,
			boxes = { makeBox(LetterTables.WILDCARD) },
			targetCount = TEST_TARGET,
			parent = container,
		})
		ctx.wildSpawner:start()
	end,

	verify = function(ctx)
		local blocks = ctx.spawner:getActiveBlocks()
		if #blocks ~= TEST_TARGET then
			return false, string.format("expected %d blocks, got %d", TEST_TARGET, #blocks)
		end
		local plain = 0
		for _, block in blocks do
			local letter = block:GetAttribute(LetterBlocks.LETTER_ATTRIBUTE)
			local color = block:GetAttribute(LetterBlocks.COLOR_ATTRIBUTE)
			if Wildcard.isWildcard(letter) then
				if color ~= Wildcard.COLOR then
					return false, string.format("wildcard in ColorOnly volume was %s, expected %s", tostring(color), Wildcard.COLOR)
				end
			else
				plain += 1
				if color ~= ONLY_COLOR then
					return false, string.format("block %s was %s, expected %s", letter, tostring(color), ONLY_COLOR)
				end
			end
		end

		local wildBlocks = ctx.wildSpawner:getActiveBlocks()
		if #wildBlocks ~= TEST_TARGET then
			return false, string.format("wildcard volume: expected %d blocks, got %d", TEST_TARGET, #wildBlocks)
		end
		for _, block in wildBlocks do
			local letter = block:GetAttribute(LetterBlocks.LETTER_ATTRIBUTE)
			local color = block:GetAttribute(LetterBlocks.COLOR_ATTRIBUTE)
			if not Wildcard.isWildcard(letter) or color ~= Wildcard.COLOR then
				return false, string.format("wildcard-table block was %s/%s", tostring(letter), tostring(color))
			end
		end

		return true, string.format("%d non-wildcard blocks all %s; %d wildcard-table blocks all gold", plain, ONLY_COLOR, #wildBlocks)
	end,

	teardown = function(ctx)
		if ctx.spawner then
			ctx.spawner:destroy()
		end
		if ctx.wildSpawner then
			ctx.wildSpawner:destroy()
		end
		if ctx.container then
			ctx.container:Destroy()
		end
	end,
}
