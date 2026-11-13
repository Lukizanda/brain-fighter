--!strict

----------------------------------------------------------------------
-- wordkit_no_letter_refill
----------------------------------------------------------------------
-- Consuming some of a kit's letters does not bring them back one by one:
-- the kit stays short, and no new block appears, however long the respawn
-- delay has been exceeded. (An ordinary or quota block would be replaced
-- after the delay; a kit letter is not.)
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local wordKitFixture = require(ReplicatedStorage.Shared.Tests.Helpers.wordKitFixture)

local TEST_ARENA_ID = "TestKitNoRefill"
local TEST_DELAY = 0.2
local PAST_DELAY_WAIT = 0.7
local CONSUMED = 2

type Ctx = {
	kit: wordKitFixture.Fixture?,
	failure: string?,
}

return {
	name = "wordkit_no_letter_refill",

	setup = function(ctx: Ctx)
		ctx.kit = wordKitFixture.new(TEST_ARENA_ID)
	end,

	run = function(ctx: Ctx)
		local kit = ctx.kit :: wordKitFixture.Fixture
		local length = wordKitFixture.KIT_WORD_LENGTH
		-- A gated kit, because the interesting claim is that nothing but the
		-- gate refills it; the ungated whole-kit refill has its own test.
		local pool = kit:pool({
			boxes = { kit:kitBox({ kitGate = "TestKitNoRefillGate" }) },
			respawnDelay = TEST_DELAY,
		})
		pool:start()

		local original = pool:getActiveBlocks()
		if #original ~= length then
			ctx.failure = string.format("started with %d blocks, expected %d", #original, length)
			return
		end
		local wordBefore = pool:getKitWords()[1]
		for i = 1, CONSUMED do
			original[i]:Destroy()
		end

		task.wait(PAST_DELAY_WAIT)
		local after = pool:getActiveBlocks()
		if #after ~= length - CONSUMED then
			ctx.failure = string.format(
				"%d blocks after the delay, expected %d: the kit refilled letter by letter", #after, length - CONSUMED
			)
			return
		end
		local originalSet: { [Model]: boolean } = {}
		for _, block in original do
			originalSet[block] = true
		end
		for _, block in after do
			if not originalSet[block] then
				ctx.failure = "a block appeared that was not in the original kit"
				return
			end
		end
		if pool:getKitWords()[1] ~= wordBefore then
			ctx.failure = "the kit's word changed without a re-roll"
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, string.format("%d of %d letters consumed, none came back after the delay", CONSUMED, wordKitFixture.KIT_WORD_LENGTH)
	end,

	teardown = function(ctx: Ctx)
		if ctx.kit then
			ctx.kit:destroy()
		end
	end,
}
