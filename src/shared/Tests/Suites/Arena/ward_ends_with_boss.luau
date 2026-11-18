--!strict

----------------------------------------------------------------------
-- ward_ends_with_boss — destroying the ward removes its letters and the health floor; a type without the config has no ward; an arena without a pool does not leave the boss unkillable
----------------------------------------------------------------------
-- MODULE LEVEL: BossWard on stand-in bosses, ticked by hand.
--   * destroy() while the ward is up removes every ward letter and clears
--     the boss's health floor, and leaves the field blocks alone;
--   * destroy() before the line was reached clears the floor too;
--   * a spec with no `wardAtHpFraction` gets no ward and no floor;
--   * a boss in an arena with no block pool reaches the line, cannot hang
--     letters, and can then be hurt below the line.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local HealthFloor = require(ReplicatedStorage.Shared.Health.HealthFloor)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)
local BossWard = require(ServerScriptService.Server.Boss.Scripts.BossWard)

local ARENA_ID = "WardEnds"
local NO_POOL_ARENA = "WardEndsNoPool"
local BOSS_MAX_HEALTH = 1000
local BIG_HIT = 700
local SMALL_HIT = 100
local ZONE_OFFSET = Vector3.new(0, 0, -60)
local NEVER_REFILL_SEC = 600
local TICK_SEC = 0.5
local HEALTH_TOLERANCE = 0.01

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

return {
	name = "ward_ends_with_boss",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local spec: any = table.clone(BossConfig.BOSS_TYPES.Brain)

		-- Up, then destroyed.
		local boss, humanoid, root = hf:fakeBoss(BOSS_MAX_HEALTH)
		local pool = hf:pool({ hf:zone(root.Position + ZONE_OFFSET) }, NEVER_REFILL_SEC)
		local fieldCount = #pool:getActiveBlocks()
		local ward = BossWard.new(boss, humanoid, root, spec)
		if not ward then
			return
		end
		ctx.floorWhileArmed = HealthFloor.get(boss)
		hit(humanoid, BIG_HIT)
		ward:tick(TICK_SEC)
		ctx.lettersUp = #pool:getWardLetters()
		ward:destroy()
		ctx.lettersAfterDestroy = #pool:getWardLetters()
		ctx.floorAfterDestroy = HealthFloor.get(boss)
		ctx.fieldKept = #pool:getActiveBlocks() == fieldCount

		-- Destroyed before the line.
		local boss2, humanoid2, root2 = hf:fakeBoss(BOSS_MAX_HEALTH)
		local ward2 = BossWard.new(boss2, humanoid2, root2, spec)
		if not ward2 then
			return
		end
		ward2:destroy()
		ctx.floorArmedDestroyed = HealthFloor.get(boss2)

		-- No config, no ward.
		local plain: any = table.clone(spec)
		plain.wardAtHpFraction = nil
		local boss3, humanoid3, root3 = hf:fakeBoss(BOSS_MAX_HEALTH)
		ctx.plainWard = BossWard.new(boss3, humanoid3, root3, plain)
		ctx.plainEnabled = BossWard.isEnabledFor(plain)
		ctx.plainFloor = HealthFloor.get(boss3)

		-- No pool: the ward must not hold.
		local boss4, humanoid4, root4 = hf:fakeBoss(BOSS_MAX_HEALTH, nil, nil, NO_POOL_ARENA)
		local ward4 = BossWard.new(boss4, humanoid4, root4, spec)
		if not ward4 then
			return
		end
		hit(humanoid4, BIG_HIT)
		ward4:tick(TICK_SEC)
		ctx.noPoolUp = ward4:isUp()
		hit(humanoid4, SMALL_HIT)
		ctx.noPoolHealth = humanoid4.Health
		ctx.noPoolExpected = BOSS_MAX_HEALTH * spec.wardAtHpFraction - SMALL_HIT
		ward4:destroy()
		ctx.done = true
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.done then
			return false, "BossWard.new returned nil for the Brain's config, or the test did not finish"
		end
		if ctx.floorWhileArmed == nil then
			return false, "a boss with a ward had no health floor before the line"
		end
		if ctx.lettersUp == 0 then
			return false, "fixture: the ward did not go up"
		end
		if ctx.lettersAfterDestroy ~= 0 then
			return false, "destroy() left ward letters in the world"
		end
		if ctx.floorAfterDestroy ~= nil or ctx.floorArmedDestroyed ~= nil then
			return false, "destroy() left the boss's health floor set"
		end
		if not ctx.fieldKept then
			return false, "destroy() removed field blocks along with the ward letters"
		end
		if ctx.plainWard ~= nil or ctx.plainEnabled or ctx.plainFloor ~= nil then
			return false, "a type with no ward config got a ward or a floor"
		end
		if ctx.noPoolUp then
			return false, "the ward reported up with no pool to hang letters in"
		end
		if math.abs(ctx.noPoolHealth - ctx.noPoolExpected) > HEALTH_TOLERANCE then
			return false, "a boss whose ward could not hang letters could not be hurt below the line"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
