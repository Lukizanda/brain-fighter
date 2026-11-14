--!strict

----------------------------------------------------------------------
-- gate_zone_must_pair
----------------------------------------------------------------------
-- A zone holds a gate only when GateId AND arena both match. With the
-- player standing in a zone of another GateId and in a zone of the same
-- GateId in another arena (the two overlap), the gate still re-seals. Also
-- checks a blank GateId on both sides counts as none.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "GateZonePair"
local OTHER_ARENA = "GateZonePairOther"
local GATE = "GateB"
local OTHER_GATE = "GateBOther"

type Ctx = {
	player: Player?,
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

return {
	name = "gate_zone_must_pair",

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
		local wrongGate = fixture:zone("WrongGateZone", OTHER_GATE)
		fixture:zone("WrongArenaZone", GATE, { arenaId = OTHER_ARENA, cframe = wrongGate.CFrame })
		fixture:zone("BlankZone", "", { cframe = wrongGate.CFrame })
		if not fixture:placePlayer(player, wrongGate.Position) then
			ctx.bwFailure = "the player has no character"
			return
		end

		local wall = fixture:brokenGate("UnheldGate", GATE)
		local blankWall = fixture:brokenGate("BlankGate", "")
		if not wall or not blankWall then
			ctx.bwFailure = "setup: a wall did not break"
			return
		end
		task.wait(breakableWallFixture.RESEAL_WAIT_SEC)
		if fixture:stateOf(wall) ~= C.State.Intact then
			ctx.bwFailure = "a zone with another GateId or in another arena held the gate"
		elseif fixture:stateOf(blankWall) ~= C.State.Intact then
			ctx.bwFailure = "a blank GateId held a gate"
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
