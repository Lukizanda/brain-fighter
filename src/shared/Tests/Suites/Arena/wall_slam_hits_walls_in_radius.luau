--!strict

----------------------------------------------------------------------
-- wall_slam_hits_walls_in_radius
----------------------------------------------------------------------
-- A boss AoeImpact applies SLAM_WALL_DAMAGE to every wall whose NEAREST
-- point is inside the radius, not to walls whose centre is. The wall is 40
-- studs wide and the slam lands 30 studs from its centre along that axis,
-- so its nearest point is 10 studs away: a radius of 12 reaches it, a
-- radius of 8 must not (the centre is 30 away in both cases). A second
-- wall, far out of range, is the control.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "BreakableWallTestSlam"
local MAX_HEALTH = 25
local WALL_SIZE = Vector3.new(40, 12, 2)
local CENTRE_OFFSET_STUDS = 30
local REACHING_RADIUS = 12
local SHORT_RADIUS = 8

type Ctx = {
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

return {
	name = "wall_slam_hits_walls_in_radius",

	setup = function(ctx: Ctx)
		ctx.bwFixture = breakableWallFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fixture = ctx.bwFixture :: breakableWallFixture.Fixture
		local near = fixture:wall("SlamNear", { maxHealth = MAX_HEALTH, size = WALL_SIZE })
		local far = fixture:wall("SlamFar", { maxHealth = MAX_HEALTH, size = WALL_SIZE })
		local boss = fixture:boss()
		fixture:settle()

		local center = near.Position + Vector3.new(CENTRE_OFFSET_STUDS, 0, 0)

		fixture:slam(center, SHORT_RADIUS, boss)
		if fixture:healthOf(near) ~= MAX_HEALTH then
			ctx.bwFailure = string.format("a slam of radius %d damaged a wall whose nearest point is 10 away (health %s)",
				SHORT_RADIUS, tostring(fixture:healthOf(near)))
			return
		end

		fixture:slam(center, REACHING_RADIUS, boss)
		local expected = MAX_HEALTH - C.SLAM_WALL_DAMAGE
		if fixture:healthOf(near) ~= expected then
			ctx.bwFailure = string.format("a slam reaching the wall's edge left health %s, expected %d",
				tostring(fixture:healthOf(near)), expected)
			return
		end
		if fixture:healthOf(far) ~= MAX_HEALTH then
			ctx.bwFailure = string.format("a slam out of range damaged the far wall (health %s)",
				tostring(fixture:healthOf(far)))
			return
		end

		-- Enough slams break it, and a broken wall is no longer a target.
		fixture:slam(center, REACHING_RADIUS, boss)
		fixture:slam(center, REACHING_RADIUS, boss)
		if fixture:stateOf(near) ~= C.State.Broken then
			ctx.bwFailure = string.format("three slams did not break a %d-health wall (state %s)",
				MAX_HEALTH, tostring(fixture:stateOf(near)))
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
