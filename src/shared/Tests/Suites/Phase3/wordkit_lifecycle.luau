--!strict

----------------------------------------------------------------------
-- wordkit_lifecycle
----------------------------------------------------------------------
-- disable() / start() / destroy() / rerollAll() with a kit in the pool:
--   - disable() leaves the kit standing and makes the gate and round
--     re-rolls no-ops; letters consumed while disabled are not refilled;
--   - start() fills a kit that was emptied while disabled, and leaves a
--     partly eaten one alone;
--   - rerollAll() replaces a GATED kit too (it would never come back by the
--     letter path), one respawnDelay later, whole;
--   - destroy() removes the kit and cancels a roll still queued, so nothing
--     spawns afterwards.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local wordKitFixture = require(ReplicatedStorage.Shared.Tests.Helpers.wordKitFixture)

local TEST_ARENA_ID = "TestKitLifecycle"
local GATE = "TestKitLifecycleGate"
local TEST_DELAY = 0.3
local DURING_DELAY_WAIT = 0.1
local PAST_DELAY_WAIT = 0.6

type Ctx = {
	kit: wordKitFixture.Fixture?,
	failure: string?,
}

return {
	name = "wordkit_lifecycle",

	setup = function(ctx: Ctx)
		ctx.kit = wordKitFixture.new(TEST_ARENA_ID)
	end,

	run = function(ctx: Ctx)
		local kit = ctx.kit :: wordKitFixture.Fixture
		local length = wordKitFixture.KIT_WORD_LENGTH
		local pool = kit:pool({ boxes = { kit:kitBox({ kitGate = GATE }) }, respawnDelay = TEST_DELAY })
		pool:start()

		-- disable(): kit stays, re-rolls are no-ops, nothing refills.
		local original = pool:getActiveBlocks()
		pool:disable()
		if kit:liveCount(original) ~= length then
			ctx.failure = "disable() removed kit letters"
			return
		end
		if pool:rerollKitsForGate(GATE) ~= 0 or pool:rerollKits() ~= 0 then
			ctx.failure = "a disabled pool re-rolled a kit"
			return
		end
		original[1]:Destroy()
		task.wait(PAST_DELAY_WAIT)
		-- The world is the truth here: a disabled pool is not tracking removals.
		if #kit.container:GetChildren() ~= length - 1 then
			ctx.failure = string.format("%d blocks in the world after a letter was consumed while disabled, expected %d", #kit.container:GetChildren(), length - 1)
			return
		end

		-- start() leaves a partly eaten kit alone (and forgets the consumed letter)...
		pool:start()
		task.wait(PAST_DELAY_WAIT)
		if #pool:getActiveBlocks() ~= length - 1 or #kit.container:GetChildren() ~= length - 1 then
			ctx.failure = string.format(
				"start() changed a partly eaten kit: %d tracked / %d in the world, expected %d / %d",
				#pool:getActiveBlocks(), #kit.container:GetChildren(), length - 1, length - 1
			)
			return
		end
		-- ...and fills one emptied while disabled.
		pool:disable()
		for _, block in pool:getActiveBlocks() do
			block:Destroy()
		end
		pool:start()
		if #pool:getActiveBlocks() ~= length then
			ctx.failure = string.format("start() left an emptied kit with %d blocks, expected %d", #pool:getActiveBlocks(), length)
			return
		end

		-- rerollAll(): a gated kit comes back whole after the delay.
		local beforeAll = pool:getActiveBlocks()
		pool:rerollAll()
		if kit:liveCount(beforeAll) ~= 0 or #pool:getActiveBlocks() ~= 0 then
			ctx.failure = "rerollAll() left kit letters standing"
			return
		end
		task.wait(DURING_DELAY_WAIT)
		if #pool:getActiveBlocks() ~= 0 then
			ctx.failure = "the kit came back before the respawn delay"
			return
		end
		task.wait(PAST_DELAY_WAIT)
		local afterAll = pool:getActiveBlocks()
		if #afterAll ~= length or #kit:wordsMatching(afterAll) == 0 then
			ctx.failure = string.format("%d blocks after rerollAll and the delay, expected a whole kit of %d", #afterAll, length)
			return
		end

		-- destroy(): removes the kit and cancels a queued roll.
		pool:rerollAll()
		pool:destroy()
		task.wait(TEST_DELAY + PAST_DELAY_WAIT)
		if #pool:getActiveBlocks() ~= 0 or #kit.container:GetChildren() ~= 0 then
			ctx.failure = string.format(
				"after destroy(): %d tracked, %d in the world, expected 0 and 0",
				#pool:getActiveBlocks(), #kit.container:GetChildren()
			)
			return
		end
		if pool:rerollKits() ~= 0 then
			ctx.failure = "a destroyed pool re-rolled a kit"
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, "disable/start/rerollAll/destroy all keep the kit whole and leave nothing behind"
	end,

	teardown = function(ctx: Ctx)
		if ctx.kit then
			ctx.kit:destroy()
		end
	end,
}
