--!strict

----------------------------------------------------------------------
-- wall_regen_waits_for_a_character
----------------------------------------------------------------------
-- A regenerating wall must not close on someone standing in it. A rig with
-- a Humanoid is parked inside the broken wall; well past RegenSec the wall
-- is still broken. Once the rig leaves, the next retry re-seals it.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "BreakableWallTestOverlap"
local MAX_HEALTH = 1
local REGEN_SEC = 0.5
-- Several retry intervals past the regen time with the rig still inside.
local HOLD_RETRIES = 3
-- After the rig leaves: one retry interval plus slack.
local RELEASE_SLACK_SEC = C.REGEN_RETRY_SEC + 0.3
local FAR_AWAY_STUDS = 500

type Ctx = {
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

return {
	name = "wall_regen_waits_for_a_character",

	setup = function(ctx: Ctx)
		ctx.bwFixture = breakableWallFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fixture = ctx.bwFixture :: breakableWallFixture.Fixture
		local wall = fixture:wall("OverlapWall", { maxHealth = MAX_HEALTH, regenSec = REGEN_SEC })
		local boss = fixture:boss()
		local rig = fixture:character(wall.Position)
		fixture:settle()

		fixture:fireballs(wall, boss, MAX_HEALTH)
		if fixture:stateOf(wall) ~= C.State.Broken then
			ctx.bwFailure = "setup: the wall did not break"
			return
		end

		task.wait(REGEN_SEC + C.REGEN_RETRY_SEC * HOLD_RETRIES)
		if fixture:stateOf(wall) ~= C.State.Broken then
			ctx.bwFailure = string.format("the wall re-sealed (%s) with a character standing inside it",
				tostring(fixture:stateOf(wall)))
			return
		end

		rig:PivotTo(rig:GetPivot() + Vector3.new(FAR_AWAY_STUDS, 0, 0))
		task.wait(RELEASE_SLACK_SEC)
		if fixture:stateOf(wall) ~= C.State.Intact then
			ctx.bwFailure = string.format("the wall did not re-seal after the character left (state %s)",
				tostring(fixture:stateOf(wall)))
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
