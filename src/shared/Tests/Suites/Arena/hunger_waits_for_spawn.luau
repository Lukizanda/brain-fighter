--!strict

----------------------------------------------------------------------
-- hunger_waits_for_spawn — nothing is eaten during the entrance hold
----------------------------------------------------------------------
-- REAL BOSS, in a padded arena with a 1 s entrance delay and a very short eat
-- interval. A block sits beside the BossPoint. While the round runs with
-- nobody arrived there is no boss and the block stays; after the arrival the
-- boss appears and then eats it.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local bossEntranceFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bossEntranceFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local DELAY_SEC = 1
local INTERVAL_SEC = 0.2
-- Generous: the block is a few studs from the BossPoint and the boss stands on it.
local RADIUS_STUDS = 40
local BLOCK_OFFSET = Vector3.new(4, 4, 0)
-- Several intervals of hold with nobody arrived.
local HOLD_OBSERVE_SEC = INTERVAL_SEC * 4
local SPAWN_TIMEOUT_SEC = DELAY_SEC + 2
local EAT_TIMEOUT_SEC = 3
local NEVER_REFILL_SEC = 600

return {
	name = "hunger_waits_for_spawn",

	setup = function(ctx: any)
		ctx.bf = bossEntranceFixture.new()
	end,

	run = function(ctx: any)
		local player: Player? = ctx.player
		if not player then
			return
		end
		local bf = ctx.bf
		ctx.built = bf:build(player, {
			entranceDelaySec = DELAY_SEC,
			withPad = true,
			configureSpec = function(spec: any)
				spec.eatIntervalSec = INTERVAL_SEC
				spec.eatRadius = RADIUS_STUDS
				spec.eatHealFraction = 0
			end,
		})
		if not ctx.built or not bf.bossPoint then
			return
		end
		local hf = hungerFixture.new(bf.arenaId)
		ctx.hf = hf
		local blockAt = bf.bossPoint.Position + BLOCK_OFFSET
		local pool = hf:pool({ hf:zone(blockAt) }, NEVER_REFILL_SEC)

		bf:startRound()
		task.wait(HOLD_OBSERVE_SEC)
		ctx.bossDuringHold = bf:boss() ~= nil
		ctx.keptDuringHold = hf:blockAt(pool, blockAt) ~= nil

		ctx.touch = bf:arrive(player)
		ctx.spawned = bf:waitFor(function() return bf:boss() ~= nil end, SPAWN_TIMEOUT_SEC) ~= nil
		ctx.ateAfterSpawn = bf:waitFor(function()
			return hf:blockAt(pool, blockAt) == nil
		end, EAT_TIMEOUT_SEC) ~= nil
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.built then
			return false, "no player on the server, or the transfer failed"
		end
		if ctx.bossDuringHold then
			return false, "the boss spawned with nobody on the island"
		end
		if not ctx.keptDuringHold then
			return false, "a block was eaten during the entrance hold"
		end
		if ctx.touch ~= "teleported" then
			return false, "the arrival touch returned " .. tostring(ctx.touch)
		end
		if not ctx.spawned then
			return false, "the boss never appeared after the arrival"
		end
		if not ctx.ateAfterSpawn then
			return false, "the spawned boss never ate the block beside it"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
		if ctx.bf then
			ctx.bf:cleanup(ctx.player)
		end
	end,
}
