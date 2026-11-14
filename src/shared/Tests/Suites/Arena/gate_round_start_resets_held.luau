--!strict

----------------------------------------------------------------------
-- gate_round_start_resets_held
----------------------------------------------------------------------
-- The round-start reset does not care about hold zones: a gate held open by
-- a player in its zone returns to intact on its arena's RoundStarted.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "GateZoneRound"
local GATE = "GateG"

type Ctx = {
	player: Player?,
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

return {
	name = "gate_round_start_resets_held",

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
		local zone = fixture:zone("RoundZone", GATE)
		if not fixture:placePlayer(player, zone.Position) then
			ctx.bwFailure = "the player has no character"
			return
		end
		local wall = fixture:brokenGate("RoundGate", GATE)
		if not wall then
			ctx.bwFailure = "setup: the wall did not break"
			return
		end
		task.wait(breakableWallFixture.HOLD_WAIT_SEC)
		if fixture:stateOf(wall) ~= C.State.Broken then
			ctx.bwFailure = "setup: the zone did not hold the gate"
			return
		end
		fixture:roundStarted(TEST_ARENA)
		if fixture:stateOf(wall) ~= C.State.Intact then
			ctx.bwFailure = "round start did not reset a gate held open by a zone"
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
