--!strict

----------------------------------------------------------------------
-- boss_instant_without_pad — no pad, or no delay, spawns the boss at once
----------------------------------------------------------------------
-- The REAL BossService, two throwaway arenas, run one after the other:
--
--   A. a boss type WITH an entranceDelaySec but an arena with NO entry pad
--      (the shipped arena, the duel pads, every fixture): the boss spawns as
--      soon as the round starts, and no countdown tell goes up;
--   B. an arena WITH a pad but a boss type with NO delay: the same.
--
-- Both must also not wait for any arrival.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local bossEntranceFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bossEntranceFixture)

-- A delay long enough that "spawned within the wait" cannot be the delay
-- running out.
local DELAY_SEC = 10
-- Far below DELAY_SEC; the spawn is one event hop away.
local SPAWN_WAIT_SEC = 1.5

type Case = {
	label: string,
	options: bossEntranceFixture.Options,
}

local CASES: { Case } = {
	{ label = "delay, no pad", options = { entranceDelaySec = DELAY_SEC, withPad = false } },
	{ label = "pad, no delay", options = { entranceDelaySec = nil, withPad = true } },
}

return {
	name = "boss_instant_without_pad",

	setup = function(ctx: any)
		ctx.failure = nil
	end,

	run = function(ctx: any)
		local player: Player? = ctx.player
		if not player then
			ctx.failure = "no player on the server"
			return
		end
		for _, case in CASES do
			local bf = bossEntranceFixture.new()
			ctx.bf = bf
			if not bf:build(player, case.options) then
				ctx.failure = case.label .. ": the transfer into the test arena failed"
				bf:cleanup(player)
				return
			end
			bf:startRound()
			local waited = bf:waitFor(function()
				return bf:boss() ~= nil
			end, SPAWN_WAIT_SEC)
			local tell = bf:tellUp(BossConstants.ENTRANCE_TAG)
			bf:cleanup(player)
			ctx.bf = nil
			if waited == nil then
				ctx.failure = string.format("%s: no boss within %.1f s of the round starting", case.label, SPAWN_WAIT_SEC)
				return
			end
			if tell then
				ctx.failure = case.label .. ": a countdown tell went up though no entrance applies"
				return
			end
		end
	end,

	verify = function(ctx: any): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.bf then
			ctx.bf:cleanup(ctx.player)
		end
	end,
}
