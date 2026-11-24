--!strict

----------------------------------------------------------------------
-- exposure_slam_stuns_and_exposes — after a Ground Slam the boss is stunned and exposed, hits do x1.5, spore pops included
----------------------------------------------------------------------
-- MODULE LEVEL: a real BossController on a stand-in boss (so its wiring of
-- BossExposure to the blackboard's onAttackFinished is what is tested), with
-- damage through the real `applyDamage.process`.
--   * a volley finishing changes nothing;
--   * a Ground Slam finishing sets the blackboard's stunnedUntil and
--     publishes StunnedUntil and ExposedUntil, each exposedAfterAttackSec on;
--   * a spell hit in the window does x exposedDamageMultiplier, and so does a
--     spore pop (BossSpores' own pop path, with the harness player as popper);
--   * the controller going takes the window with it.
--
-- NOT covered: the stun hold in Cooldown (BossStates, read-only here; it
-- reads stunnedUntil) and the client pose (seen in a playtest).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local Vulnerability = require(ReplicatedStorage.Shared.Health.Vulnerability)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)
local BossController = require(ServerScriptService.Server.Boss.Scripts.BossController)

local ARENA_ID = "ExposureSlam"
local SLAM = "GroundSlam"
local BOSS_MAX_HEALTH = 1000
local HIT = 100
local HEALTH_TOLERANCE = 0.01
-- Slack for the time between setting the window and reading it back.
local TIME_TOLERANCE_SEC = 0.25

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

local function near(value: any, expected: number): boolean
	return typeof(value) == "number" and math.abs(value - expected) <= TIME_TOLERANCE_SEC
end

return {
	name = "exposure_slam_stuns_and_exposes",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local spec: any = table.clone(BossConfig.BOSS_TYPES.Brain)
		ctx.spec = spec
		ctx.slamSec = spec.exposedAfterAttackSec and spec.exposedAfterAttackSec[SLAM]
		ctx.mult = spec.exposedDamageMultiplier
		local boss, humanoid = ctx.hf:fakeBoss(BOSS_MAX_HEALTH)
		local controller: any = BossController.new(boss, spec)
		if not controller then
			return
		end
		ctx.controller = controller
		local bb = controller._blackboard
		ctx.hooked = bb.onAttackFinished ~= nil
		if not ctx.hooked then
			return
		end

		bb.onAttackFinished(BossConstants.VOLLEY_ATTACK)
		ctx.volleyStun = bb.stunnedUntil
		ctx.volleyExposed = boss:GetAttribute(BossConstants.EXPOSED_UNTIL_ATTRIBUTE)
		hit(humanoid, HIT)
		ctx.plainCost = BOSS_MAX_HEALTH - humanoid.Health

		local before = humanoid.Health
		bb.onAttackFinished(SLAM)
		ctx.stunLeft = (bb.stunnedUntil or 0) - os.clock()
		local serverNow = workspace:GetServerTimeNow()
		ctx.exposedLeft = (boss:GetAttribute(BossConstants.EXPOSED_UNTIL_ATTRIBUTE) or 0) - serverNow
		ctx.stunnedLeft = (boss:GetAttribute(BossConstants.STUNNED_UNTIL_ATTRIBUTE) or 0) - serverNow
		hit(humanoid, HIT)
		ctx.exposedCost = before - humanoid.Health

		-- A spore pop in the window, through BossSpores' own pop path.
		local spores = controller._spores
		local player: Player? = ctx.player
		if spores and player then
			local beforePop = humanoid.Health
			spores:_onPopped(player)
			ctx.popCost = beforePop - humanoid.Health
		end

		controller:destroy()
		ctx.afterDestroyExposed = boss:GetAttribute(BossConstants.EXPOSED_UNTIL_ATTRIBUTE)
		ctx.afterDestroyStunned = boss:GetAttribute(BossConstants.STUNNED_UNTIL_ATTRIBUTE)
		ctx.afterDestroyMult = Vulnerability.multiplierFor(boss)
		ctx.done = true
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.slamSec or not ctx.mult or ctx.mult <= 1 then
			return false, "the Brain has no slam window or no multiplier in BossConfig"
		end
		if not ctx.hooked then
			return false, "BossController did not set the blackboard's onAttackFinished"
		end
		if not ctx.done then
			return false, "the test did not finish"
		end
		if ctx.volleyStun ~= nil or ctx.volleyExposed ~= nil then
			return false, "a volley finishing stunned or exposed the boss"
		end
		if math.abs(ctx.plainCost - HIT) > HEALTH_TOLERANCE then
			return false, string.format("an unexposed hit did %s, expected %d", tostring(ctx.plainCost), HIT)
		end
		if not near(ctx.stunLeft, ctx.slamSec) then
			return false, string.format("stunnedUntil was %s s ahead, expected %s", tostring(ctx.stunLeft), tostring(ctx.slamSec))
		end
		if not near(ctx.exposedLeft, ctx.slamSec) or not near(ctx.stunnedLeft, ctx.slamSec) then
			return false, string.format("published ExposedUntil %s s / StunnedUntil %s s ahead, expected %s",
				tostring(ctx.exposedLeft), tostring(ctx.stunnedLeft), tostring(ctx.slamSec))
		end
		if math.abs(ctx.exposedCost - HIT * ctx.mult) > HEALTH_TOLERANCE then
			return false, string.format("an exposed hit did %s, expected %s", tostring(ctx.exposedCost), tostring(HIT * ctx.mult))
		end
		if ctx.player and ctx.spec.sporePopDamageFraction then
			local expected = BOSS_MAX_HEALTH * ctx.spec.sporePopDamageFraction * ctx.mult
			if ctx.popCost == nil or math.abs(ctx.popCost - expected) > HEALTH_TOLERANCE then
				return false, string.format("an exposed spore pop did %s, expected %s", tostring(ctx.popCost), tostring(expected))
			end
		end
		if ctx.afterDestroyExposed ~= nil or ctx.afterDestroyStunned ~= nil or ctx.afterDestroyMult ~= 1 then
			return false, "the window outlived the controller"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.controller then
			ctx.controller:destroy()
		end
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
