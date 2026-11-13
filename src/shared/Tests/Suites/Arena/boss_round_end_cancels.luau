--!strict

----------------------------------------------------------------------
-- boss_round_end_cancels — RoundEnded during the entrance cancels the spawn
----------------------------------------------------------------------
-- The REAL BossService in a padded throwaway arena. The player arrives, the
-- countdown starts, and the round ends before it runs out. Waiting past the
-- original appear time must still show no boss, and the countdown tell must
-- be off the BossPoint (a stuck tell would leave a countdown on screen over
-- an arena with no round). Then a fresh round in the same arena, with the
-- player arriving again, spawns a boss normally: the cancelled timer left
-- nothing behind that blocks the next cycle.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local ArenaEntryService = require(ServerScriptService.Server.Arena.ArenaEntryService)
local bossEntranceFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bossEntranceFixture)

local DELAY_SEC = 1
local TELL_WAIT_SEC = 0.5
-- The round ends this long into the countdown.
local END_AFTER_SEC = 0.3
-- Past the original appear time with margin.
local PAST_APPEAR_SEC = DELAY_SEC + 0.7
local SECOND_SPAWN_WAIT_SEC = DELAY_SEC + 1.5

return {
	name = "boss_round_end_cancels",

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
		task.wait()
		bf:arrive(player)
		ctx.tellUp = bf:waitFor(function()
			return bf:tellUp(BossConstants.ENTRANCE_TAG)
		end, TELL_WAIT_SEC) ~= nil

		task.wait(END_AFTER_SEC)
		bf:endRound()
		task.wait(PAST_APPEAR_SEC)
		ctx.bossAfterEnd = bf:boss() ~= nil
		ctx.tellAfterEnd = bf:tellUp(BossConstants.ENTRANCE_TAG)
		ctx.attributeAfterEnd = bf.bossPoint and bf.bossPoint:GetAttribute(BossConstants.ENTRANCE_APPEAR_AT_ATTRIBUTE)

		-- A fresh round: the player arrives again (the cooldown from the first
		-- teleport is cleared), and the boss comes after the delay as normal.
		ArenaEntryService.resetState()
		bf:startRound()
		task.wait()
		bf:arrive(player)
		ctx.secondBoss = bf:waitFor(function()
			return bf:boss() ~= nil
		end, SECOND_SPAWN_WAIT_SEC) ~= nil
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.built then
			return false, "no player on the server, or the transfer failed"
		end
		if not ctx.tellUp then
			return false, "no countdown tell after the arrival, so the test never reached the cancel"
		end
		if ctx.bossAfterEnd then
			return false, "a boss spawned after the round ended mid-countdown"
		end
		if ctx.tellAfterEnd or ctx.attributeAfterEnd ~= nil then
			return false, "the countdown tell was left on the BossPoint after the round ended"
		end
		if not ctx.secondBoss then
			return false, "a fresh round after a cancelled entrance never spawned its boss"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.bf then
			ctx.bf:cleanup(ctx.player)
		end
	end,
}
