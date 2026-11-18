--!strict

----------------------------------------------------------------------
-- ward_holds_then_breaks — the boss's health stops at the ward line, nothing hurts it until every ward letter is popped, then it can die
----------------------------------------------------------------------
-- MODULE LEVEL: BossWard on a stand-in boss in the test's own arena and pool,
-- ticked by hand, with damage through the real `applyDamage.process`.
--   * a hit that would cross the line lands exactly on it;
--   * the next tick hangs `wardLetterCount` marked letters at the orbit
--     radius, none of them in the pool's field count;
--   * a hit while they are out does nothing;
--   * the letters move round the boss and keep their distance;
--   * popping all but one leaves the ward up; popping the last drops it;
--   * afterwards damage lands, and the ward does not come back.
-- A pop here is the block being destroyed, which is all the ward reads.
--
-- NOT covered: the cues (VfxBroadcast, nothing to read back on the server)
-- and a real client's tap on a moving letter.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local WardConstants = require(ReplicatedStorage.Shared.BlockSpawner.WardConstants)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local HealthFloor = require(ReplicatedStorage.Shared.Health.HealthFloor)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)
local BossWard = require(ServerScriptService.Server.Boss.Scripts.BossWard)

local ARENA_ID = "WardHolds"
local BOSS_MAX_HEALTH = 1000
local BIG_HIT = 700
local SMALL_HIT = 100
local ZONE_OFFSET = Vector3.new(0, 0, -60)
local NEVER_REFILL_SEC = 600
local TICK_SEC = 0.5
local HEALTH_TOLERANCE = 0.01
local RADIUS_TOLERANCE = 0.1
local MOVED_AT_LEAST_STUDS = 0.5

local function hit(humanoid: Humanoid, amount: number)
	applyDamage.process({
		sourcePlayer = nil,
		targetHumanoid = humanoid,
		baseDamage = amount,
		damageType = DamageTypes.DamageType.Spell,
		hitZone = DamageTypes.HitZone.Torso,
		timestamp = os.clock(),
		cause = "WardTest",
	})
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

return {
	name = "ward_holds_then_breaks",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local spec: any = table.clone(BossConfig.BOSS_TYPES.Brain)
		ctx.spec = spec
		local boss, humanoid, root = hf:fakeBoss(BOSS_MAX_HEALTH)
		local pool = hf:pool({ hf:zone(root.Position + ZONE_OFFSET) }, NEVER_REFILL_SEC)
		ctx.fieldCount = #pool:getActiveBlocks()
		local ward = BossWard.new(boss, humanoid, root, spec)
		if not ward then
			return
		end
		ctx.built = true
		local line = BOSS_MAX_HEALTH * spec.wardAtHpFraction
		ctx.line = line

		ward:tick(TICK_SEC)
		ctx.upBeforeLine = ward:isUp()

		hit(humanoid, BIG_HIT)
		ctx.healthAfterCrossing = humanoid.Health
		ward:tick(TICK_SEC)
		ctx.upAtLine = ward:isUp()
		local letters = pool:getWardLetters()
		ctx.letterCount = #letters
		ctx.fieldCountWithWard = #pool:getActiveBlocks()
		ctx.allMarked = true
		ctx.radiusOk = true
		for _, block in letters do
			if block:GetAttribute(WardConstants.ATTRIBUTE) ~= true then
				ctx.allMarked = false
			end
			if math.abs(flatDistance(block:GetPivot().Position, root.Position) - spec.wardOrbitRadius) > RADIUS_TOLERANCE then
				ctx.radiusOk = false
			end
		end
		if #letters == 0 then
			return
		end

		hit(humanoid, SMALL_HIT)
		ctx.healthWhileUp = humanoid.Health

		local first = letters[1]
		local before = first:GetPivot().Position
		ward:tick(TICK_SEC)
		local after = first:GetPivot().Position
		ctx.moved = (after - before).Magnitude >= MOVED_AT_LEAST_STUDS
		ctx.radiusKept = math.abs(flatDistance(after, root.Position) - spec.wardOrbitRadius) <= RADIUS_TOLERANCE

		for index = 2, #letters do
			letters[index]:Destroy()
		end
		ward:tick(TICK_SEC)
		ctx.upWithOneLeft = ward:isUp()
		ctx.leftWithOne = ward:lettersLeft()

		first:Destroy()
		ward:tick(TICK_SEC)
		ctx.upAfterLast = ward:isUp()
		ctx.floorAfterLast = HealthFloor.get(boss)

		hit(humanoid, SMALL_HIT)
		ctx.healthAfterBreak = humanoid.Health
		ward:tick(TICK_SEC)
		ctx.upAgain = ward:isUp()
		ctx.lettersAgain = #pool:getWardLetters()
		ctx.done = true
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.built then
			return false, "BossWard.new returned nil for the Brain's own config"
		end
		if ctx.upBeforeLine then
			return false, "the ward was up at full health"
		end
		if math.abs(ctx.healthAfterCrossing - ctx.line) > HEALTH_TOLERANCE then
			return false, string.format("a hit across the line left %s health, expected %s", tostring(ctx.healthAfterCrossing), tostring(ctx.line))
		end
		if not ctx.upAtLine then
			return false, "the ward did not go up with the boss on the line"
		end
		if ctx.letterCount ~= ctx.spec.wardLetterCount then
			return false, string.format("%s ward letters, expected %s", tostring(ctx.letterCount), tostring(ctx.spec.wardLetterCount))
		end
		if not ctx.allMarked then
			return false, "a ward letter does not carry the ward mark"
		end
		if not ctx.radiusOk then
			return false, "a ward letter did not appear at the orbit radius"
		end
		if ctx.fieldCountWithWard ~= ctx.fieldCount then
			return false, "ward letters were counted as field blocks"
		end
		if not ctx.done then
			return false, "the test did not finish"
		end
		if math.abs(ctx.healthWhileUp - ctx.line) > HEALTH_TOLERANCE then
			return false, "a hit hurt the boss while its ward was up"
		end
		if not ctx.moved or not ctx.radiusKept then
			return false, "the ward letters did not circle the boss at the orbit radius"
		end
		if not ctx.upWithOneLeft or ctx.leftWithOne ~= 1 then
			return false, "the ward dropped (or miscounted) with one letter still out"
		end
		if ctx.upAfterLast or ctx.floorAfterLast ~= nil then
			return false, "the ward was still holding after its last letter was popped"
		end
		if math.abs(ctx.healthAfterBreak - (ctx.line - SMALL_HIT)) > HEALTH_TOLERANCE then
			return false, "damage did not land after the ward broke"
		end
		if ctx.upAgain or ctx.lettersAgain ~= 0 then
			return false, "the ward came back after being broken"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
