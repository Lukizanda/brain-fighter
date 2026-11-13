local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)
local EnergyEconomy = require(ReplicatedStorage.Shared.EnergyEconomy)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)

local TEST_TARGET = 60
local TEST_PARENT_NAME = "TestPremiumTableContainer"
local TEST_ARENA_ID = "TestPremiumTable"

return {
	name = "BlockSpawner Premium letter table yields only high-value letters or wildcards",

	setup = function(ctx)
		local container = Instance.new("Folder")
		container.Name = TEST_PARENT_NAME
		container.Parent = workspace
		ctx.container = container

		ctx.spawner = BlockSpawner.new({
			arenaId = TEST_ARENA_ID,
			boxes = { {
				boxMin = Vector3.new(-15, 10, -15),
				boxMax = Vector3.new(15, 20, 15),
				letterTable = LetterTables.PREMIUM,
				label = "TestPremiumVolume",
			} },
			targetCount = TEST_TARGET,
			parent = container,
		})
		ctx.spawner:start()
	end,

	verify = function(ctx)
		local blocks = ctx.spawner:getActiveBlocks()
		if #blocks ~= TEST_TARGET then
			return false, string.format("expected %d blocks, got %d", TEST_TARGET, #blocks)
		end

		local wildcards = 0
		for _, block in blocks do
			local letter = block:GetAttribute(LetterBlocks.LETTER_ATTRIBUTE)
			if Wildcard.isWildcard(letter) then
				wildcards += 1
			elseif EnergyEconomy.letterValue(letter) < LetterTables.PREMIUM_MIN_LETTER_VALUE then
				return false, string.format(
					"letter %s is worth %d, below the premium minimum %d",
					letter, EnergyEconomy.letterValue(letter), LetterTables.PREMIUM_MIN_LETTER_VALUE
				)
			end
		end

		return true, string.format("%d premium-table blocks, %d wildcards, no low-value letters", #blocks, wildcards)
	end,

	teardown = function(ctx)
		if ctx.spawner then
			ctx.spawner:destroy()
		end
		if ctx.container then
			ctx.container:Destroy()
		end
	end,
}
