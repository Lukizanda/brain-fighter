--!strict

----------------------------------------------------------------------
-- hunger_heal_capped — an eaten letter heals the configured fraction, never past max
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on a stand-in boss, ticked by hand (no real boss,
-- no Heartbeat), with a pull fast enough to arrive in one tick. Covers:
-- nothing is pulled before the interval has run; at the interval the letter
-- (which floats high above the boss) goes into tow; the next tick it arrives,
-- is eaten, and heals fraction * max health; a meal that would overshoot stops
-- at maximum health.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossHunger = require(ServerScriptService.Server.Boss.Scripts.BossHunger)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local ARENA_ID = "HungerHealCapped"
local INTERVAL_SEC = 5
local RADIUS_STUDS = 25
local FRACTION = 0.1
local MAX_HEALTH = 1000
local START_HEALTH = 500
local NEAR_HEALTH = 960
-- 10 across and 30 up: well inside the radius horizontally, out of it in 3D.
local BLOCK_OFFSET = Vector3.new(10, 30, 0)
local ARRIVE_DT_SEC = 0.1
local RESPAWN_SEC = 0.05
local REFILL_WAIT_SEC = 0.3

return {
	name = "hunger_heal_capped",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss(MAX_HEALTH, START_HEALTH)
		local zoneAt = root.Position + BLOCK_OFFSET
		-- A short respawn delay so the zone is back for the cap check.
		local pool = hf:pool({ hf:zone(zoneAt) }, RESPAWN_SEC)
		local hunger = BossHunger.new(boss, humanoid, root, hungerFixture.spec(
			INTERVAL_SEC, RADIUS_STUDS, FRACTION, hungerFixture.FAST_PULL_SPEED, hungerFixture.REACH_STUDS
		))
		ctx.enabled = hunger ~= nil
		if not hunger then
			return
		end

		hunger:tick(INTERVAL_SEC / 2)
		ctx.towedEarly = #hf:towed(pool) > 0
		ctx.healthEarly = humanoid.Health

		hunger:tick(INTERVAL_SEC / 2)
		ctx.towed = #hf:towed(pool) == 1
		ctx.healthWhileTowed = humanoid.Health

		hunger:tick(ARRIVE_DT_SEC)
		ctx.eaten = hf:blockAt(pool, zoneAt) == nil and #hf:towed(pool) == 0
		ctx.healthAfterMeal = humanoid.Health

		-- Near the top: the same meal would overshoot, so it stops at max.
		-- The eaten block's zone refills after the short delay, giving it one.
		humanoid.Health = NEAR_HEALTH
		task.wait(REFILL_WAIT_SEC)
		ctx.blockForCap = hf:blockAt(pool, zoneAt) ~= nil
		hunger:tick(INTERVAL_SEC)
		hunger:tick(ARRIVE_DT_SEC)
		ctx.healthAtCap = humanoid.Health
		ctx.maxHealth = humanoid.MaxHealth
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.enabled then
			return false, "BossHunger.new returned nil for a spec with eat values"
		end
		if ctx.towedEarly or ctx.healthEarly ~= START_HEALTH then
			return false, "it pulled a letter before the interval had run"
		end
		if not ctx.towed then
			return false, "no letter went into tow once the interval had run"
		end
		if ctx.healthWhileTowed ~= START_HEALTH then
			return false, "it healed before the letter arrived"
		end
		if not ctx.eaten then
			return false, "the letter was not eaten when it arrived"
		end
		local expected = START_HEALTH + MAX_HEALTH * FRACTION
		if math.abs(ctx.healthAfterMeal - expected) > 0.01 then
			return false, string.format("health after the meal was %s, expected %s", tostring(ctx.healthAfterMeal), tostring(expected))
		end
		if ctx.healthAtCap ~= ctx.maxHealth then
			return false, string.format(
				"a meal near the top left health at %s of %s (block present: %s)",
				tostring(ctx.healthAtCap), tostring(ctx.maxHealth), tostring(ctx.blockForCap)
			)
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
