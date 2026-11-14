--!strict

----------------------------------------------------------------------
-- hunger_zero_fraction — a heal fraction of 0 still pulls and eats, but heals nothing
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on a stand-in boss, ticked by hand, once with the
-- fraction at 0 and once with it absent. Both pull the letter and eat it on
-- arrival (the pressure stays) and neither changes the boss's health.
--
-- NOT covered: that no heal cue is sent. The cue is a VfxBroadcast to
-- clients; the server has nothing to read back (vfx-sfx.md).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossHunger = require(ServerScriptService.Server.Boss.Scripts.BossHunger)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local ARENA_ID = "HungerZero"
local INTERVAL_SEC = 5
local RADIUS_STUDS = 25
local START_HEALTH = 500
local BLOCK_OFFSET = Vector3.new(8, 4, 0)
local ARRIVE_DT_SEC = 0.1
local NEVER_REFILL_SEC = 600

return {
	name = "hunger_zero_fraction",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss(nil, START_HEALTH)
		local zoneAt = root.Position + BLOCK_OFFSET
		local pool = hf:pool({ hf:zone(zoneAt) }, NEVER_REFILL_SEC)
		local hunger = BossHunger.new(boss, humanoid, root, hungerFixture.spec(
			INTERVAL_SEC, RADIUS_STUDS, 0, hungerFixture.FAST_PULL_SPEED, hungerFixture.REACH_STUDS
		))
		if not hunger then
			return
		end
		ctx.enabled = true

		hunger:tick(INTERVAL_SEC)
		ctx.pulled = #hf:towed(pool) == 1
		hunger:tick(ARRIVE_DT_SEC)
		ctx.eaten = hf:blockAt(pool, zoneAt) == nil
		ctx.health = humanoid.Health

		-- An absent fraction behaves the same. The first object's letter is
		-- gone, so a second pool gives the second object one.
		local pool2 = hf:pool({ hf:zone(zoneAt) }, NEVER_REFILL_SEC)
		local hungerNoFraction = BossHunger.new(boss, humanoid, root, hungerFixture.spec(
			INTERVAL_SEC, RADIUS_STUDS, nil, hungerFixture.FAST_PULL_SPEED, hungerFixture.REACH_STUDS
		))
		if not hungerNoFraction then
			return
		end
		hungerNoFraction:tick(INTERVAL_SEC)
		ctx.pulled2 = #hf:towed(pool2) == 1
		hungerNoFraction:tick(ARRIVE_DT_SEC)
		ctx.eaten2 = hf:blockAt(pool2, zoneAt) == nil
		ctx.health2 = humanoid.Health
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.enabled then
			return false, "BossHunger.new returned nil for a spec with a 0 or absent heal fraction"
		end
		if not ctx.pulled or not ctx.eaten then
			return false, "with fraction 0 the letter was not pulled and eaten"
		end
		if ctx.health ~= START_HEALTH then
			return false, "fraction 0 changed the boss's health"
		end
		if not ctx.pulled2 or not ctx.eaten2 then
			return false, "with no fraction the letter was not pulled and eaten"
		end
		if ctx.health2 ~= START_HEALTH then
			return false, "an absent fraction changed the boss's health"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
