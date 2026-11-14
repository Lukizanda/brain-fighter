--!strict

----------------------------------------------------------------------
-- gate_wall_without_gate_regens
----------------------------------------------------------------------
-- A wall with no GateId behaves as before even with a player standing in a
-- zone: it re-seals on time. (The zone pairs with nothing; the service
-- warns once about it, which this test does not assert.)
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "GateNoId"
local GATE = "GateF"

type Ctx = {
	player: Player?,
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

return {
	name = "gate_wall_without_gate_regens",

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
		local zone = fixture:zone("LonelyZone", GATE)
		if not fixture:placePlayer(player, zone.Position) then
			ctx.bwFailure = "the player has no character"
			return
		end
		local wall = fixture:brokenGate("NoIdGate", nil)
		if not wall then
			ctx.bwFailure = "setup: the wall did not break"
			return
		end
		task.wait(breakableWallFixture.RESEAL_WAIT_SEC)
		if fixture:stateOf(wall) ~= C.State.Intact then
			ctx.bwFailure = "a wall with no GateId did not re-seal on time"
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
