--!strict

----------------------------------------------------------------------
-- exposure_window_closes — the stun and the x1.5 end with the window, and the published instants are taken down
----------------------------------------------------------------------
-- MODULE LEVEL: BossExposure on a stand-in boss and a stand-in blackboard,
-- with a short slam window so the test does not wait the real 1.5 s.
--   * inside the window a hit is multiplied and the boss counts as stunned;
--   * once it has passed a hit lands as dealt and the stun is over, before
--     any tick (both are read against the clock);
--   * the next tick clears ExposedUntil, StunnedUntil and Health's window;
--   * a type without a multiplier above 1 gets no exposure object.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)
local BossExposure = require(ServerScriptService.Server.Boss.Scripts.BossExposure)

local ARENA_ID = "ExposureCloses"
local SLAM = "GroundSlam"
local BOSS_MAX_HEALTH = 1000
local HIT = 100
local SHORT_WINDOW_SEC = 0.3
local PAST_WINDOW_SEC = 0.2
local HEALTH_TOLERANCE = 0.01

local function hit(humanoid: Humanoid, amount: number)
	applyDamage.process({
		sourcePlayer = nil,
		targetHumanoid = humanoid,
		baseDamage = amount,
		damageType = DamageTypes.DamageType.Spell,
		hitZone = DamageTypes.HitZone.Torso,
		timestamp = os.clock(),
		cause = "ExposureTest",
	})
end

return {
	name = "exposure_window_closes",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local spec: any = table.clone(BossConfig.BOSS_TYPES.Brain)
		spec.exposedAfterAttackSec = { [SLAM] = SHORT_WINDOW_SEC }
		ctx.mult = spec.exposedDamageMultiplier
		local boss, humanoid = ctx.hf:fakeBoss(BOSS_MAX_HEALTH)
		local bb: any = { stunnedUntil = nil }
		local exposure = BossExposure.new(boss, bb, spec)
		if not exposure then
			return
		end
		ctx.exposure = exposure
		ctx.built = true

		exposure:onAttackFinished(SLAM)
		ctx.stunnedInside = exposure:isStunned()
		ctx.exposedInside = exposure:isExposed()
		local before = humanoid.Health
		hit(humanoid, HIT)
		ctx.insideCost = before - humanoid.Health

		task.wait(SHORT_WINDOW_SEC + PAST_WINDOW_SEC)
		ctx.stunnedAfter = exposure:isStunned()
		before = humanoid.Health
		hit(humanoid, HIT)
		ctx.afterCost = before - humanoid.Health

		exposure:tick()
		ctx.exposedAttr = boss:GetAttribute(BossConstants.EXPOSED_UNTIL_ATTRIBUTE)
		ctx.stunnedAttr = boss:GetAttribute(BossConstants.STUNNED_UNTIL_ATTRIBUTE)
		ctx.healthAttr = boss:GetAttribute(HealthConstants.VULNERABLE_UNTIL_ATTRIBUTE)

		local plain: any = table.clone(spec)
		plain.exposedDamageMultiplier = nil
		ctx.plainHasExposure = BossExposure.new(boss, bb, plain) ~= nil
		ctx.done = true
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.built then
			return false, "BossExposure.new returned nil for the Brain's own config"
		end
		if not ctx.done then
			return false, "the test did not finish"
		end
		if not ctx.stunnedInside or not ctx.exposedInside then
			return false, "the boss was not stunned and exposed inside the window"
		end
		if math.abs(ctx.insideCost - HIT * ctx.mult) > HEALTH_TOLERANCE then
			return false, string.format("a hit in the window did %s, expected %s", tostring(ctx.insideCost), tostring(HIT * ctx.mult))
		end
		if ctx.stunnedAfter then
			return false, "the stun outlasted its window"
		end
		if math.abs(ctx.afterCost - HIT) > HEALTH_TOLERANCE then
			return false, string.format("a hit after the window did %s, expected %d", tostring(ctx.afterCost), HIT)
		end
		if ctx.exposedAttr ~= nil or ctx.stunnedAttr ~= nil or ctx.healthAttr ~= nil then
			return false, "a tick after the window left its instants published"
		end
		if ctx.plainHasExposure then
			return false, "a type without a multiplier got an exposure object"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.exposure then
			ctx.exposure:destroy()
		end
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
