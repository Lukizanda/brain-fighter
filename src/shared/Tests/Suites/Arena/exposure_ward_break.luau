--!strict

----------------------------------------------------------------------
-- exposure_ward_break — the ward floor holds against a multiplied hit, and breaking the ward exposes the boss
----------------------------------------------------------------------
-- MODULE LEVEL: a real BossController on a stand-in boss in the test's own
-- arena and pool (so its wiring of BossWard's onBroken to BossExposure is
-- what is tested), the ward ticked by hand, damage through the real
-- `applyDamage.process`. The slam window is shortened so the test need not
-- wait it out.
--   * a slam while the ward is up exposes the boss, but a hit still stops on
--     the ward's floor (the floor is applied after the multiplier);
--   * popping the last ward letter publishes ExposedUntil
--     exposedOnWardBreakSec on, without a stun, and the next hit does x1.5.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)
local BossController = require(ServerScriptService.Server.Boss.Scripts.BossController)

local ARENA_ID = "ExposureWard"
local SLAM = "GroundSlam"
local BOSS_MAX_HEALTH = 1000
local BIG_HIT = 700
local HIT = 100
local SHORT_WINDOW_SEC = 0.3
local PAST_WINDOW_SEC = 0.2
local ZONE_OFFSET = Vector3.new(0, 0, -60)
local NEVER_REFILL_SEC = 600
local TICK_SEC = 0.5
local HEALTH_TOLERANCE = 0.01
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

return {
	name = "exposure_ward_break",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local spec: any = table.clone(BossConfig.BOSS_TYPES.Brain)
		spec.exposedAfterAttackSec = { [SLAM] = SHORT_WINDOW_SEC }
		ctx.spec = spec
		ctx.mult = spec.exposedDamageMultiplier
		local boss, humanoid, root = hf:fakeBoss(BOSS_MAX_HEALTH)
		local pool = hf:pool({ hf:zone(root.Position + ZONE_OFFSET) }, NEVER_REFILL_SEC)
		local controller: any = BossController.new(boss, spec)
		if not controller or not controller._ward then
			return
		end
		ctx.controller = controller
		local ward = controller._ward
		local bb = controller._blackboard
		ctx.line = BOSS_MAX_HEALTH * spec.wardAtHpFraction

		hit(humanoid, BIG_HIT)
		ward:tick(TICK_SEC)
		local letters = pool:getWardLetters()
		if not ward:isUp() or #letters == 0 then
			return
		end
		ctx.wardUp = true

		-- A slam while warded: exposed, but the floor holds.
		bb.onAttackFinished(SLAM)
		ctx.exposedWhileWarded = boss:GetAttribute(BossConstants.EXPOSED_UNTIL_ATTRIBUTE) ~= nil
		hit(humanoid, HIT)
		ctx.healthWhileWarded = humanoid.Health
		task.wait(SHORT_WINDOW_SEC + PAST_WINDOW_SEC)
		controller._exposure:tick()
		ctx.closedBeforeBreak = boss:GetAttribute(BossConstants.EXPOSED_UNTIL_ATTRIBUTE) == nil

		for _, block in letters do
			block:Destroy()
		end
		ward:tick(TICK_SEC)
		ctx.broken = not ward:isUp()
		local serverNow = workspace:GetServerTimeNow()
		ctx.exposedLeft = (boss:GetAttribute(BossConstants.EXPOSED_UNTIL_ATTRIBUTE) or 0) - serverNow
		ctx.stunnedAttr = boss:GetAttribute(BossConstants.STUNNED_UNTIL_ATTRIBUTE)
		ctx.stunnedUntil = bb.stunnedUntil
		local before = humanoid.Health
		hit(humanoid, HIT)
		ctx.breakCost = before - humanoid.Health
		ctx.done = true
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.wardUp then
			return false, "the ward did not go up"
		end
		if not ctx.done then
			return false, "the test did not finish"
		end
		if not ctx.exposedWhileWarded then
			return false, "a slam while warded did not expose the boss"
		end
		if math.abs(ctx.healthWhileWarded - ctx.line) > HEALTH_TOLERANCE then
			return false, string.format("an exposed hit took the warded boss to %s, the floor is %s",
				tostring(ctx.healthWhileWarded), tostring(ctx.line))
		end
		if not ctx.closedBeforeBreak then
			return false, "the slam window was still published after it closed"
		end
		if not ctx.broken then
			return false, "the ward did not break"
		end
		local wardSec = ctx.spec.exposedOnWardBreakSec
		if math.abs(ctx.exposedLeft - wardSec) > TIME_TOLERANCE_SEC then
			return false, string.format("ExposedUntil was %s s ahead after the break, expected %s", tostring(ctx.exposedLeft), tostring(wardSec))
		end
		if ctx.stunnedAttr ~= nil then
			return false, "the ward break stunned the boss"
		end
		if math.abs(ctx.breakCost - HIT * ctx.mult) > HEALTH_TOLERANCE then
			return false, string.format("a hit after the break did %s, expected %s", tostring(ctx.breakCost), tostring(HIT * ctx.mult))
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
