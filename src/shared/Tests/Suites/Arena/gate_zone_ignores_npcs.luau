--!strict

----------------------------------------------------------------------
-- gate_zone_ignores_npcs
----------------------------------------------------------------------
-- A Humanoid rig that is not a player (an NPC, the boss) standing in a hold
-- zone does not hold the gate. The rig is a stand-in on purpose: it is the
-- thing that must NOT count.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "GateZoneNpc"
local GATE = "GateC"

type Ctx = {
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

return {
	name = "gate_zone_ignores_npcs",

	setup = function(ctx: Ctx)
		ctx.bwFixture = breakableWallFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fixture = ctx.bwFixture :: breakableWallFixture.Fixture
		local zone = fixture:zone("NpcZone", GATE)
		fixture:character(zone.Position)
		local wall = fixture:brokenGate("NpcGate", GATE)
		if not wall then
			ctx.bwFailure = "setup: the wall did not break"
			return
		end
		task.wait(breakableWallFixture.RESEAL_WAIT_SEC)
		if fixture:stateOf(wall) ~= C.State.Intact then
			ctx.bwFailure = "a non-player rig in the zone held the gate"
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
