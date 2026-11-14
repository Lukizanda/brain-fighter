--!strict

----------------------------------------------------------------------
-- gate_zone_holds_then_releases
----------------------------------------------------------------------
-- A broken regenerating gate stays open while the player's character is in
-- a hold zone with the same GateId (same arena), and re-seals after the
-- character leaves. Uses the real player's character: the service keys on
-- Players, so a stand-in rig cannot be a player.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "GateZoneHolds"
local GATE = "GateA"
local FAR_AWAY_STUDS = 500

type Ctx = {
	player: Player?,
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

return {
	name = "gate_zone_holds_then_releases",

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
		local zone = fixture:zone("HoldZone", GATE)
		local inside = fixture:placePlayer(player, zone.Position)
		if not inside then
			ctx.bwFailure = "the player has no character"
			return
		end
		local wall = fixture:brokenGate("HeldGate", GATE)
		if not wall then
			ctx.bwFailure = "setup: the wall did not break"
			return
		end

		task.wait(breakableWallFixture.HOLD_WAIT_SEC)
		if fixture:stateOf(wall) ~= C.State.Broken then
			ctx.bwFailure = "the gate re-sealed with a player inside its hold zone"
			return
		end

		fixture:placePlayer(player, zone.Position + Vector3.new(FAR_AWAY_STUDS, 0, 0))
		task.wait(breakableWallFixture.RESEAL_WAIT_SEC)
		if fixture:stateOf(wall) ~= C.State.Intact then
			ctx.bwFailure = "the gate did not re-seal after the player left the zone"
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
