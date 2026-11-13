--!strict

----------------------------------------------------------------------
-- wordkit_ungated_refill
----------------------------------------------------------------------
-- A kit with no KitGate is replaced whole a respawnDelay after its LAST
-- letter is consumed: nothing comes back while a letter is left, nothing
-- comes back during the delay, and then a complete new word appears at once.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local wordKitFixture = require(ReplicatedStorage.Shared.Tests.Helpers.wordKitFixture)

local TEST_ARENA_ID = "TestKitUngated"
local TEST_DELAY = 0.4
local DURING_DELAY_WAIT = 0.15
local PAST_DELAY_WAIT = 0.6

type Ctx = {
	kit: wordKitFixture.Fixture?,
	failure: string?,
}

return {
	name = "wordkit_ungated_refill",

	setup = function(ctx: Ctx)
		ctx.kit = wordKitFixture.new(TEST_ARENA_ID)
	end,

	run = function(ctx: Ctx)
		local kit = ctx.kit :: wordKitFixture.Fixture
		local length = wordKitFixture.KIT_WORD_LENGTH
		local pool = kit:pool({ boxes = { kit:kitBox() }, respawnDelay = TEST_DELAY })
		pool:start()

		local original = pool:getActiveBlocks()
		-- Leave one letter standing: the kit must not refill yet.
		for i = 1, length - 1 do
			original[i]:Destroy()
		end
		task.wait(TEST_DELAY + PAST_DELAY_WAIT)
		if #pool:getActiveBlocks() ~= 1 then
			ctx.failure = string.format("%d blocks with one letter left, expected 1", #pool:getActiveBlocks())
			return
		end

		-- Take the last one: empty, nothing during the delay, a whole kit after.
		original[length]:Destroy()
		task.wait(DURING_DELAY_WAIT)
		if #pool:getActiveBlocks() ~= 0 then
			ctx.failure = string.format("%d blocks during the delay, expected 0", #pool:getActiveBlocks())
			return
		end
		task.wait(PAST_DELAY_WAIT)
		local after = pool:getActiveBlocks()
		if #after ~= length then
			ctx.failure = string.format("%d blocks after the delay, expected a whole kit of %d", #after, length)
			return
		end
		if #kit:wordsMatching(after) == 0 or #kit:colorsOf(after) ~= 1 then
			ctx.failure = "the refilled kit is not one word in one colour"
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, "kit stayed empty for the delay after its last letter, then came back whole"
	end,

	teardown = function(ctx: Ctx)
		if ctx.kit then
			ctx.kit:destroy()
		end
	end,
}
