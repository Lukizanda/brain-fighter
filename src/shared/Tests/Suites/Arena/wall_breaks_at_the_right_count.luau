--!strict

----------------------------------------------------------------------
-- wall_breaks_at_the_right_count
----------------------------------------------------------------------
-- Boss-sourced WorldImpacts take a wall through intact -> cracked ->
-- critical -> broken at exactly the hit count the thresholds imply, and
-- breaking it turns off the three collision flags and leaves it in the
-- DataModel. Driven through the real WorldImpact BindableEvent against the
-- real BreakableWallService; the fixture's walls are tagged after boot.
--
-- MaxHealth 6 so every threshold lands on a whole hit:
--   1 hit  5/6 intact      2 hits 4/6 cracked (<= 2/3)
--   4 hits 2/6 critical (<= 1/3)    6 hits 0/6 broken
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "BreakableWallTestCount"
local MAX_HEALTH = 6
local EXTRA_HITS_AFTER_BREAK = 3
local State = C.State

type Ctx = {
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

-- Expected (hits taken -> state) for a MaxHealth 6 wall at 1 damage per hit.
local EXPECTED: { { hits: number, state: string } } = {
	{ hits = 1, state = State.Intact },
	{ hits = 2, state = State.Cracked },
	{ hits = 3, state = State.Cracked },
	{ hits = 4, state = State.Critical },
	{ hits = 5, state = State.Critical },
	{ hits = 6, state = State.Broken },
}

return {
	name = "wall_breaks_at_the_right_count",

	setup = function(ctx: Ctx)
		ctx.bwFixture = breakableWallFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fixture = ctx.bwFixture :: breakableWallFixture.Fixture
		local wall = fixture:wall("CountWall", { maxHealth = MAX_HEALTH })
		local boss = fixture:boss()
		fixture:settle()

		if fixture:stateOf(wall) ~= State.Intact or fixture:healthOf(wall) ~= MAX_HEALTH then
			ctx.bwFailure = string.format("fresh wall published state=%s health=%s, expected intact/%d",
				tostring(fixture:stateOf(wall)), tostring(fixture:healthOf(wall)), MAX_HEALTH)
			return
		end

		local taken = 0
		for _, step in EXPECTED do
			fixture:fireballs(wall, boss, step.hits - taken)
			taken = step.hits
			local state = fixture:stateOf(wall)
			local expectedHealth = math.max(0, MAX_HEALTH - taken * C.FIREBALL_WALL_DAMAGE)
			if state ~= step.state or fixture:healthOf(wall) ~= expectedHealth then
				ctx.bwFailure = string.format("after %d hit(s): state=%s health=%s, expected %s/%d",
					taken, tostring(state), tostring(fixture:healthOf(wall)), step.state, expectedHealth)
				return
			end
		end

		if wall.CanCollide or wall.CanQuery or wall.CanTouch then
			ctx.bwFailure = string.format("broken wall still has CanCollide=%s CanQuery=%s CanTouch=%s",
				tostring(wall.CanCollide), tostring(wall.CanQuery), tostring(wall.CanTouch))
			return
		end
		if not wall:IsDescendantOf(workspace) then
			ctx.bwFailure = "broken wall left the DataModel"
			return
		end

		-- A broken wall takes no more damage and does not come back by itself
		-- (no RegenSec on this one).
		fixture:fireballs(wall, boss, EXTRA_HITS_AFTER_BREAK)
		if fixture:stateOf(wall) ~= State.Broken or fixture:healthOf(wall) ~= 0 then
			ctx.bwFailure = "a broken wall changed state after more hits"
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
