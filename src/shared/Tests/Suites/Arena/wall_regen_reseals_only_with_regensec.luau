--!strict

----------------------------------------------------------------------
-- wall_regen_reseals_only_with_regensec
----------------------------------------------------------------------
-- Two walls broken in the same instant. The one carrying `RegenSec` is
-- still broken before that time has passed, then re-seals to full health
-- with its collision flags back. The one without it is still broken well
-- after, because "gone for the round" means gone until RoundStarted.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "BreakableWallTestRegen"
local MAX_HEALTH = 2
local REGEN_SEC = 1
-- Check "not yet" comfortably inside the regen window.
local EARLY_CHECK_FRACTION = 0.4
-- Past the regen time, plus one retry interval and a frame of slack.
local LATE_SLACK_SEC = C.REGEN_RETRY_SEC + 0.3

type Ctx = {
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

return {
	name = "wall_regen_reseals_only_with_regensec",

	setup = function(ctx: Ctx)
		ctx.bwFixture = breakableWallFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fixture = ctx.bwFixture :: breakableWallFixture.Fixture
		local regen = fixture:wall("RegenWall", { maxHealth = MAX_HEALTH, regenSec = REGEN_SEC })
		local gone = fixture:wall("GoneWall", { maxHealth = MAX_HEALTH })
		local boss = fixture:boss()
		fixture:settle()

		fixture:fireballs(regen, boss, MAX_HEALTH)
		fixture:fireballs(gone, boss, MAX_HEALTH)
		local brokeAt = os.clock()
		if fixture:stateOf(regen) ~= C.State.Broken or fixture:stateOf(gone) ~= C.State.Broken then
			ctx.bwFailure = "setup: the walls did not break"
			return
		end

		task.wait(REGEN_SEC * EARLY_CHECK_FRACTION)
		if fixture:stateOf(regen) ~= C.State.Broken then
			ctx.bwFailure = string.format("the regen wall re-sealed early, %.2fs into a %ds regen",
				os.clock() - brokeAt, REGEN_SEC)
			return
		end

		task.wait(REGEN_SEC + LATE_SLACK_SEC - (os.clock() - brokeAt))
		if fixture:stateOf(regen) ~= C.State.Intact or fixture:healthOf(regen) ~= MAX_HEALTH then
			ctx.bwFailure = string.format("the regen wall did not re-seal: state=%s health=%s after %.2fs",
				tostring(fixture:stateOf(regen)), tostring(fixture:healthOf(regen)), os.clock() - brokeAt)
			return
		end
		if not (regen.CanCollide and regen.CanQuery and regen.CanTouch) then
			ctx.bwFailure = string.format("the re-sealed wall did not get its collision back: CanCollide=%s CanQuery=%s CanTouch=%s",
				tostring(regen.CanCollide), tostring(regen.CanQuery), tostring(regen.CanTouch))
			return
		end
		if fixture:stateOf(gone) ~= C.State.Broken or gone.CanCollide then
			ctx.bwFailure = "the wall without RegenSec came back"
			return
		end

		-- A re-sealed wall is a fresh wall: it can be broken again.
		fixture:fireballs(regen, boss, MAX_HEALTH)
		if fixture:stateOf(regen) ~= C.State.Broken then
			ctx.bwFailure = "a re-sealed wall could not be broken a second time"
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
