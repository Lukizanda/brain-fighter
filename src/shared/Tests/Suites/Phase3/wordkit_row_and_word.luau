--!strict

----------------------------------------------------------------------
-- wordkit_row_and_word
----------------------------------------------------------------------
-- A WordKit volume spawns exactly the letters of one curated word, all one
-- colour, in a row along the part's LOCAL X axis (the part is rotated, so
-- world X would fail this), evenly spaced across Size.X and centred on the
-- part, in an order that does not read as the word from either end.
-- Run over several rolls so a lucky shuffle cannot pass it.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local wordKitFixture = require(ReplicatedStorage.Shared.Tests.Helpers.wordKitFixture)

local TEST_ARENA_ID = "TestKitRow"
local ROLLS = 12

type Ctx = {
	kit: wordKitFixture.Fixture?,
	failure: string?,
}

return {
	name = "wordkit_row_and_word",

	setup = function(ctx: Ctx)
		ctx.kit = wordKitFixture.new(TEST_ARENA_ID)
	end,

	run = function(ctx: Ctx)
		local kit = ctx.kit :: wordKitFixture.Fixture
		local box = kit:kitBox()
		local cframe = box.cframe :: CFrame
		local rowLength = (box.size :: Vector3).X
		local length = wordKitFixture.KIT_WORD_LENGTH
		local cell = rowLength / length
		local tolerance = wordKitFixture.LOCAL_TOLERANCE_STUDS

		local pool = kit:pool({ boxes = { box } })
		pool:start()
		if pool:getTargetCount() ~= length then
			ctx.failure = string.format("target %d, expected the word length %d", pool:getTargetCount(), length)
			return
		end

		for roll = 1, ROLLS do
			if roll > 1 then
				pool:rerollKits()
			end
			local blocks = pool:getActiveBlocks()
			if #blocks ~= length then
				ctx.failure = string.format("roll %d: %d blocks, expected %d", roll, #blocks, length)
				return
			end

			local words = kit:wordsMatching(blocks)
			if #words == 0 then
				ctx.failure = string.format("roll %d: the letters are not an anagram of any curated %d-letter word", roll, length)
				return
			end
			local colors = kit:colorsOf(blocks)
			if #colors ~= 1 then
				ctx.failure = string.format("roll %d: %d colours, a kit is one colour", roll, #colors)
				return
			end

			-- On the part's local X axis: nothing off it, a cell apart, centred.
			local xs: { number } = {}
			for _, block in blocks do
				local localPosition = cframe:PointToObjectSpace(block:GetPivot().Position)
				if math.abs(localPosition.Y) > tolerance or math.abs(localPosition.Z) > tolerance then
					ctx.failure = string.format(
						"roll %d: a block is off the local X axis by (%.3f, %.3f)", roll, localPosition.Y, localPosition.Z
					)
					return
				end
				table.insert(xs, localPosition.X)
			end
			table.sort(xs)
			for i, x in xs do
				local expected = (i - 0.5) * cell - rowLength / 2
				if math.abs(x - expected) > tolerance then
					ctx.failure = string.format(
						"roll %d: letter %d at local X %.3f, expected %.3f (cell %.2f)", roll, i, x, expected, cell
					)
					return
				end
			end

			local reading = kit:readingOrder(blocks, cframe)
			for _, word in words do
				if reading == word or reading == string.reverse(word) then
					ctx.failure = string.format("roll %d: the row reads %s, it must be shuffled", roll, reading)
					return
				end
			end
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, string.format("%d rolls: one word, one colour, shuffled, on the local X axis", ROLLS)
	end,

	teardown = function(ctx: Ctx)
		if ctx.kit then
			ctx.kit:destroy()
		end
	end,
}
