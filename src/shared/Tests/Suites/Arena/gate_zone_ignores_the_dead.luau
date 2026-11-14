--!strict

----------------------------------------------------------------------
-- gate_zone_ignores_the_dead
----------------------------------------------------------------------
-- A dead player's character in a hold zone does not hold the gate. Kills
-- the real player's character (fixture teardown respawns it with
-- LoadCharacter), because a stand-in would not be a player at all.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "GateZoneDead"
local GATE = "GateD"

type Ctx = {
	player: Player?,
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

return {
	name = "gate_zone_ignores_the_dead",

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
		local zone = fixture:zone("DeadZone", GATE)
		if not fixture:placePlayer(player, zone.Position) then
			ctx.bwFailure = "the player has no character"
			return
		end
		local wall = fixture:brokenGate("DeadGate", GATE)
		if not wall then
			ctx.bwFailure = "setup: the wall did not break"
			return
		end

		-- Alive first: prove the zone does hold before the kill, so the
		-- re-seal below can only be the death.
		task.wait(breakableWallFixture.HOLD_WAIT_SEC)
		if fixture:stateOf(wall) ~= C.State.Broken then
			ctx.bwFailure = "the living player did not hold the gate (nothing to compare the dead one with)"
			return
		end
		if not fixture:killPlayer(player) then
			ctx.bwFailure = "could not kill the player's character"
			return
		end
		task.wait(breakableWallFixture.RESEAL_WAIT_SEC)
		if fixture:stateOf(wall) ~= C.State.Intact then
			ctx.bwFailure = "a dead character in the zone held the gate"
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
