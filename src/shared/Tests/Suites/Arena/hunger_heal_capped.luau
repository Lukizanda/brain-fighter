--!strict

----------------------------------------------------------------------
-- hunger_heal_capped — a bite heals the configured fraction, never past max
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on a stand-in boss, ticked by hand (no real boss,
-- no Heartbeat). Covers: nothing happens before the interval has run; the
-- bite takes the block and heals fraction * max health; a heal that would
-- overshoot stops at maximum health.
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
local BLOCK_OFFSET = Vector3.new(10, 0, 0)
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
		local hunger = BossHunger.new(boss, humanoid, root, hungerFixture.spec(INTERVAL_SEC, RADIUS_STUDS, FRACTION))
		ctx.enabled = hunger ~= nil
		if not hunger then
			return
		end

		hunger:tick(INTERVAL_SEC / 2)
		ctx.eatenEarly = hf:blockAt(pool, zoneAt) == nil
		ctx.healthEarly = humanoid.Health

		hunger:tick(INTERVAL_SEC / 2)
		ctx.eaten = hf:blockAt(pool, zoneAt) == nil
		ctx.healthAfterBite = humanoid.Health

		-- Near the top: the same bite would overshoot, so it stops at max.
		-- A fresh block (rerollAll replaces the field) gives it one to eat.
		-- The eaten block's zone refills after the short delay, giving it one.
		humanoid.Health = NEAR_HEALTH
		task.wait(REFILL_WAIT_SEC)
		ctx.blockForCap = hf:blockAt(pool, zoneAt) ~= nil
		hunger:tick(INTERVAL_SEC)
		ctx.healthAtCap = humanoid.Health
		ctx.maxHealth = humanoid.MaxHealth
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.enabled then
			return false, "BossHunger.new returned nil for a spec with eat values"
		end
		if ctx.eatenEarly or ctx.healthEarly ~= START_HEALTH then
			return false, "it bit before the interval had run"
		end
		if not ctx.eaten then
			return false, "the block in range was not eaten after the interval"
		end
		local expected = START_HEALTH + MAX_HEALTH * FRACTION
		if math.abs(ctx.healthAfterBite - expected) > 0.01 then
			return false, string.format("health after the bite was %s, expected %s", tostring(ctx.healthAfterBite), tostring(expected))
		end
		if ctx.healthAtCap ~= ctx.maxHealth then
			return false, string.format(
				"a bite near the top left health at %s of %s (block present: %s)",
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
