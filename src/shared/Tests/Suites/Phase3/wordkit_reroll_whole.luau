--!strict

----------------------------------------------------------------------
-- wordkit_reroll_whole
----------------------------------------------------------------------
-- A re-roll replaces the kit whole: every old letter is gone (including
-- ones the player had not taken), a full new word is there, it is a
-- different word, and without ColorOnly a different colour; with ColorOnly
-- the colour holds. rerollKitsForGate touches only kits on that gate and
-- reports how many it rolled; rerollKits (a new round) touches all of them.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local wordKitFixture = require(ReplicatedStorage.Shared.Tests.Helpers.wordKitFixture)

local TEST_ARENA_ID = "TestKitReroll"
local GATE = "TestKitRerollGate"
local OTHER_GATE = "TestKitRerollOther"
local FIXED_COLOR = "blue"
local ROLLS = 8
-- The second kit sits clear of the first (the volumes' rows do not overlap).
local SECOND_KIT_OFFSET = Vector3.new(0, 0, 200)

type Ctx = {
	kit: wordKitFixture.Fixture?,
	failure: string?,
}

return {
	name = "wordkit_reroll_whole",

	setup = function(ctx: Ctx)
		ctx.kit = wordKitFixture.new(TEST_ARENA_ID)
	end,

	run = function(ctx: Ctx)
		local kit = ctx.kit :: wordKitFixture.Fixture
		local length = wordKitFixture.KIT_WORD_LENGTH

		local free = kit:kitBox({ kitGate = GATE, label = "FreeColourKit" })
		local fixed = kit:kitBox({ kitGate = OTHER_GATE, colorOnly = FIXED_COLOR, label = "FixedColourKit" })
		fixed.cframe = (fixed.cframe :: CFrame) + SECOND_KIT_OFFSET
		local pool = kit:pool({ boxes = { free, fixed } })
		pool:start()
		if pool:getTargetCount() ~= length * 2 or #pool:getActiveBlocks() ~= length * 2 then
			ctx.failure = string.format(
				"two kits: target %d / live %d, expected %d", pool:getTargetCount(), #pool:getActiveBlocks(), length * 2
			)
			return
		end

		-- Take two letters, then re-roll the free kit by its gate.
		local function blocksOf(cframe: CFrame): { Model }
			local mine: { Model } = {}
			for _, block in pool:getActiveBlocks() do
				if cframe:PointToObjectSpace(block:GetPivot().Position).Magnitude < wordKitFixture.KIT_ROW_STUDS then
					table.insert(mine, block)
				end
			end
			return mine
		end

		local initial = blocksOf(free.cframe :: CFrame)
		local previousColor: string? = kit:colorsOf(initial)[1]
		local previousWord: string? = kit:wordsMatching(initial)[1]
		for roll = 1, ROLLS do
			local before = blocksOf(free.cframe :: CFrame)
			local fixedBefore = blocksOf(fixed.cframe :: CFrame)
			if #before ~= length then
				ctx.failure = string.format("roll %d: free kit holds %d, expected %d", roll, #before, length)
				return
			end
			before[1]:Destroy()
			before[2]:Destroy()

			local rolled = pool:rerollKitsForGate(GATE)
			if rolled ~= 1 then
				ctx.failure = string.format("roll %d: rerollKitsForGate rolled %d kits, expected 1", roll, rolled)
				return
			end
			if kit:liveCount(before) ~= 0 then
				ctx.failure = string.format("roll %d: old letters survived the re-roll", roll)
				return
			end
			local after = blocksOf(free.cframe :: CFrame)
			if #after ~= length then
				ctx.failure = string.format("roll %d: re-rolled kit holds %d, expected %d", roll, #after, length)
				return
			end
			if #kit:wordsMatching(after) == 0 then
				ctx.failure = string.format("roll %d: re-rolled letters are not a curated word", roll)
				return
			end
			-- The kit on the other gate was left alone.
			if kit:liveCount(fixedBefore) ~= length then
				ctx.failure = string.format("roll %d: re-rolling %s disturbed the kit on %s", roll, GATE, OTHER_GATE)
				return
			end

			local color = kit:colorsOf(after)[1]
			local word = kit:wordsMatching(after)[1]
			if color == previousColor then
				ctx.failure = string.format("roll %d: colour stayed %s across a re-roll", roll, color)
				return
			end
			if word == previousWord then
				ctx.failure = string.format("roll %d: word stayed %s across a re-roll", roll, word)
				return
			end
			previousColor, previousWord = color, word
		end

		-- ColorOnly holds across every roll; a gate nobody has returns 0.
		for roll = 1, ROLLS do
			pool:rerollKitsForGate(OTHER_GATE)
			local colors = kit:colorsOf(blocksOf(fixed.cframe :: CFrame))
			if #colors ~= 1 or colors[1] ~= FIXED_COLOR then
				ctx.failure = string.format("ColorOnly roll %d: colours %s, expected only %s", roll, table.concat(colors, ","), FIXED_COLOR)
				return
			end
		end
		if pool:rerollKitsForGate("NoSuchGate") ~= 0 then
			ctx.failure = "a gate no kit listens for re-rolled something"
			return
		end

		-- A new round re-rolls every kit, gated or not.
		local freeBefore = blocksOf(free.cframe :: CFrame)
		local fixedBefore = blocksOf(fixed.cframe :: CFrame)
		if pool:rerollKits() ~= 2 then
			ctx.failure = "rerollKits did not roll both kits"
			return
		end
		if kit:liveCount(freeBefore) ~= 0 or kit:liveCount(fixedBefore) ~= 0 then
			ctx.failure = "rerollKits left old letters behind"
			return
		end
		if #pool:getActiveBlocks() ~= length * 2 then
			ctx.failure = string.format("after rerollKits %d blocks, expected %d", #pool:getActiveBlocks(), length * 2)
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, string.format("%d gate re-rolls: whole kit replaced, new word and colour each time", ROLLS)
	end,

	teardown = function(ctx: Ctx)
		if ctx.kit then
			ctx.kit:destroy()
		end
	end,
}
