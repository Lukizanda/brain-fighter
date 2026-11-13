--!strict

----------------------------------------------------------------------
-- boss_holds_for_arrival — a padded arena holds the boss for the first arrival
----------------------------------------------------------------------
-- The REAL BossService, in a throwaway arena that has an ArenaEntryPad and a
-- boss type with a 1 s `entranceDelaySec`:
--
--   1. the round starts, nobody has arrived: no boss, no countdown tell;
--   2. the player steps on the pad (ArenaEntryService.handleTouch, which
--      announces PlayerEntered): the tell goes up on the BossPoint with an
--      appear time about `delay` ahead;
--   3. the boss is not there halfway through the delay, and is there about
--      `delay` after the arrival, with the tell taken off.
--
-- NOT covered: the client drawing the countdown from the tag and attribute,
-- and the VfxBroadcast world cues (both need a client view, vfx-sfx.md).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local bossEntranceFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bossEntranceFixture)

local DELAY_SEC = 1
-- How long the round runs with nobody arrived before we conclude it is held.
local HOLD_OBSERVE_SEC = 0.6
-- A moment after the arrival for the event to reach BossService.
local TELL_WAIT_SEC = 0.5
local HALF_DELAY_SEC = DELAY_SEC / 2
-- The boss may appear a little early or late of the delay (frame and poll
-- granularity); it may not appear at the arrival, nor seconds late.
local EARLY_TOLERANCE_SEC = 0.15
local LATE_TOLERANCE_SEC = 1.0

return {
	name = "boss_holds_for_arrival",

	setup = function(ctx: any)
		ctx.bf = bossEntranceFixture.new()
	end,

	run = function(ctx: any)
		local player: Player? = ctx.player
		if not player then
			return
		end
		local bf = ctx.bf
		ctx.built = bf:build(player, { entranceDelaySec = DELAY_SEC, withPad = true })
		if not ctx.built then
			return
		end

		bf:startRound()
		task.wait(HOLD_OBSERVE_SEC)
		ctx.bossBeforeArrival = bf:boss() ~= nil
		ctx.tellBeforeArrival = bf:tellUp(BossConstants.ENTRANCE_TAG)

		local arrivedAt = os.clock()
		ctx.touch = bf:arrive(player)
		ctx.tellAppeared = bf:waitFor(function()
			return bf:tellUp(BossConstants.ENTRANCE_TAG)
		end, TELL_WAIT_SEC) ~= nil
		local appearAt = bf.bossPoint and bf.bossPoint:GetAttribute(BossConstants.ENTRANCE_APPEAR_AT_ATTRIBUTE)
		ctx.appearAhead = if typeof(appearAt) == "number" then (appearAt :: number) - workspace:GetServerTimeNow() else nil

		task.wait(HALF_DELAY_SEC - (os.clock() - arrivedAt))
		ctx.bossAtHalf = bf:boss() ~= nil

		local waited = bf:waitFor(function()
			return bf:boss() ~= nil
		end, DELAY_SEC + LATE_TOLERANCE_SEC)
		ctx.elapsed = if waited then os.clock() - arrivedAt else nil
		ctx.tellAfterSpawn = bf:tellUp(BossConstants.ENTRANCE_TAG)
		ctx.attributeAfterSpawn = bf.bossPoint and bf.bossPoint:GetAttribute(BossConstants.ENTRANCE_APPEAR_AT_ATTRIBUTE)
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.built then
			return false, "no player on the server, or the transfer failed"
		end
		if ctx.bossBeforeArrival then
			return false, "the boss spawned with nobody on the island"
		end
		if ctx.tellBeforeArrival then
			return false, "the countdown tell was up before anyone arrived"
		end
		if ctx.touch ~= "teleported" then
			return false, "the arrival touch returned " .. tostring(ctx.touch)
		end
		if not ctx.tellAppeared then
			return false, "no countdown tell after the first arrival"
		end
		if ctx.appearAhead == nil or ctx.appearAhead <= 0 or ctx.appearAhead > DELAY_SEC then
			return false, string.format("appear time was %s s ahead, expected within (0, %d]",
				tostring(ctx.appearAhead), DELAY_SEC)
		end
		if ctx.bossAtHalf then
			return false, "the boss was already there halfway through the delay"
		end
		if ctx.elapsed == nil then
			return false, "the boss never appeared after the delay"
		end
		if ctx.elapsed < DELAY_SEC - EARLY_TOLERANCE_SEC or ctx.elapsed > DELAY_SEC + LATE_TOLERANCE_SEC then
			return false, string.format("the boss appeared %.2f s after the arrival, expected about %d", ctx.elapsed, DELAY_SEC)
		end
		if ctx.tellAfterSpawn or ctx.attributeAfterSpawn ~= nil then
			return false, "the countdown tell was not taken off when the boss appeared"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.bf then
			ctx.bf:cleanup(ctx.player)
		end
	end,
}
