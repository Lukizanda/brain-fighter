--!strict

----------------------------------------------------------------------
-- wall_default_health_outlasts_a_volley
----------------------------------------------------------------------
-- A wall with no MaxHealth attribute takes DEFAULT_MAX_HEALTH, and that has
-- to be more than one full Brain volley of fireballs landing on it, or
-- cover is paper. The volley size is read from the LIVE BossConfig, so
-- retuning the volley fails this test instead of silently thinning every
-- wall. Also checks the mirrored VOLLEY_SHOTS constant has not drifted.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "BreakableWallTestDefault"

type Ctx = {
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

local function volleyShots(): number?
	local brain: any = BossConfig.BOSS_TYPES[BossConfig.DEFAULT_TYPE]
	local skill = brain and brain.skills and brain.skills.FireballVolley
	local count = skill and skill.deliveryParams and skill.deliveryParams.count
	return if type(count) == "number" then count else nil
end

return {
	name = "wall_default_health_outlasts_a_volley",

	setup = function(ctx: Ctx)
		ctx.bwFixture = breakableWallFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local shots = volleyShots()
		if not shots then
			ctx.bwFailure = "could not read the default boss's FireballVolley count from BossConfig"
			return
		end
		if shots ~= C.VOLLEY_SHOTS then
			ctx.bwFailure = string.format(
				"BossConfig volley is %d shots but BreakableWallConstants.VOLLEY_SHOTS says %d", shots, C.VOLLEY_SHOTS)
			return
		end
		if C.DEFAULT_MAX_HEALTH <= shots * C.FIREBALL_WALL_DAMAGE then
			ctx.bwFailure = string.format("DEFAULT_MAX_HEALTH %s does not outlast a %d-shot volley",
				tostring(C.DEFAULT_MAX_HEALTH), shots)
			return
		end

		local fixture = ctx.bwFixture :: breakableWallFixture.Fixture
		local wall = fixture:wall("DefaultWall")
		local boss = fixture:boss()
		fixture:settle()

		-- One full volley, every shot landing on this wall.
		fixture:fireballs(wall, boss, shots)
		if fixture:stateOf(wall) == C.State.Broken then
			ctx.bwFailure = string.format("default wall broke inside a single %d-shot volley", shots)
			return
		end

		-- ...but not a whole round of them.
		fixture:fireballs(wall, boss, shots)
		if fixture:stateOf(wall) ~= C.State.Broken then
			ctx.bwFailure = string.format("default wall survived two full volleys (health %s)",
				tostring(fixture:healthOf(wall)))
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.bwFailure then
			return false, ctx.bwFailure
		end
		return true, nil
	end,

	teardown = function(ctx: Ctx)
		if ctx.bwFixture then
			ctx.bwFixture:destroy()
		end
	end,
}
