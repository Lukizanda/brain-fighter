--!strict

----------------------------------------------------------------------
-- gate_zone_rotated
----------------------------------------------------------------------
-- A zone turned 45 degrees is honoured: a point inside its axis-aligned
-- bounds but outside the turned box does not hold the gate, and a point
-- along its long axis does.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "GateZoneRotated"
local GATE = "GateE"
local ZONE_SIZE = Vector3.new(40, 12, 4)
local YAW_DEG = 45
local ZONE_CENTER = Vector3.new(0, 4000, -400) -- clear of the fixture's walls
-- Along the zone's long axis (inside), and across its short one (outside,
-- yet within the axis-aligned bounds: the turned box reaches ~15.6 studs on
-- each world axis and this point is ~9.9 on each).
local ALONG_LOCAL = Vector3.new(14, 0, 0)
local ACROSS_LOCAL = Vector3.new(0, 0, 14)

type Ctx = {
	player: Player?,
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

return {
	name = "gate_zone_rotated",

	setup = function(ctx: Ctx)
		ctx.bwFixture = breakableWallFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fixture = ctx.bwFixture :: breakableWallFixture.Fixture
		local player = ctx.player
		if not player then
			ctx.bwFailure = "no player in the playtest"
			return
		end
		local zone = fixture:zone("RotatedZone", GATE, {
			size = ZONE_SIZE,
			cframe = CFrame.new(ZONE_CENTER) * CFrame.Angles(0, math.rad(YAW_DEG), 0),
		})

		-- Outside the turned box, inside its axis-aligned bounds.
		local across = zone.CFrame:PointToWorldSpace(ACROSS_LOCAL)
		if not fixture:placePlayer(player, across) then
			ctx.bwFailure = "the player has no character"
			return
		end
		local freeWall = fixture:brokenGate("AcrossGate", GATE)
		if not freeWall then
			ctx.bwFailure = "setup: a wall did not break"
			return
		end
		task.wait(breakableWallFixture.RESEAL_WAIT_SEC)
		if fixture:stateOf(freeWall) ~= C.State.Intact then
			ctx.bwFailure = "a point outside the rotated zone (inside its axis-aligned bounds) held the gate"
			return
		end

		-- Inside the turned box.
		fixture:placePlayer(player, zone.CFrame:PointToWorldSpace(ALONG_LOCAL))
		local heldWall = fixture:brokenGate("AlongGate", GATE)
		if not heldWall then
			ctx.bwFailure = "setup: the second wall did not break"
			return
		end
		task.wait(breakableWallFixture.HOLD_WAIT_SEC)
		if fixture:stateOf(heldWall) ~= C.State.Broken then
			ctx.bwFailure = "a point inside the rotated zone did not hold the gate"
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
