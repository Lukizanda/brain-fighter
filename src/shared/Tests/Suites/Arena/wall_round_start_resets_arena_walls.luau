--!strict

----------------------------------------------------------------------
-- wall_round_start_resets_arena_walls
----------------------------------------------------------------------
-- A round starting in an arena returns that arena's walls to intact at full
-- health with collision restored, including a wall that was broken for the
-- round (no RegenSec) and one that was merely cracked. A broken wall in a
-- DIFFERENT arena is untouched until that arena's own round starts.
--
-- Fires the real RoundStarted BindableEvent, with an empty roster, for an
-- arena id no session owns: the other listeners find no BossPoint and no
-- roster there and do nothing of note.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "BreakableWallTestRound"
local OTHER_ARENA = "BreakableWallTestRoundOther"
local MAX_HEALTH = 6
local CRACKING_HITS = 2

type Ctx = {
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

return {
	name = "wall_round_start_resets_arena_walls",

	setup = function(ctx: Ctx)
		ctx.bwFixture = breakableWallFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fixture = ctx.bwFixture :: breakableWallFixture.Fixture
		local broken = fixture:wall("RoundBroken", { maxHealth = MAX_HEALTH })
		local cracked = fixture:wall("RoundCracked", { maxHealth = MAX_HEALTH })
		local elsewhere = fixture:wall("RoundElsewhere", { maxHealth = MAX_HEALTH, arenaId = OTHER_ARENA })
		local boss = fixture:boss()
		fixture:settle()

		fixture:fireballs(broken, boss, MAX_HEALTH)
		fixture:fireballs(cracked, boss, CRACKING_HITS)
		fixture:fireballs(elsewhere, boss, MAX_HEALTH)
		if fixture:stateOf(broken) ~= C.State.Broken
			or fixture:stateOf(cracked) ~= C.State.Cracked
			or fixture:stateOf(elsewhere) ~= C.State.Broken
		then
			ctx.bwFailure = string.format("setup: states were %s / %s / %s, expected broken / cracked / broken",
				tostring(fixture:stateOf(broken)), tostring(fixture:stateOf(cracked)), tostring(fixture:stateOf(elsewhere)))
			return
		end
		if Arena.idOf(elsewhere) ~= OTHER_ARENA or Arena.idOf(broken) ~= TEST_ARENA then
			ctx.bwFailure = "setup: the fixture walls are not in the arenas the test thinks"
			return
		end

		fixture:roundStarted(TEST_ARENA)

		for _, wall in { broken, cracked } do
			if fixture:stateOf(wall) ~= C.State.Intact or fixture:healthOf(wall) ~= MAX_HEALTH then
				ctx.bwFailure = string.format("%s after round start: state=%s health=%s, expected intact/%d",
					wall.Name, tostring(fixture:stateOf(wall)), tostring(fixture:healthOf(wall)), MAX_HEALTH)
				return
			end
			if not (wall.CanCollide and wall.CanQuery and wall.CanTouch) then
				ctx.bwFailure = string.format("%s after round start has no collision (CanCollide=%s CanQuery=%s CanTouch=%s)",
					wall.Name, tostring(wall.CanCollide), tostring(wall.CanQuery), tostring(wall.CanTouch))
				return
			end
		end
		if fixture:stateOf(elsewhere) ~= C.State.Broken then
			ctx.bwFailure = string.format("a round in %s reset a wall in %s (state %s)",
				TEST_ARENA, OTHER_ARENA, tostring(fixture:stateOf(elsewhere)))
			return
		end

		-- And the other arena's own round start does reset it.
		fixture:roundStarted(OTHER_ARENA)
		if fixture:stateOf(elsewhere) ~= C.State.Intact then
			ctx.bwFailure = string.format("a round in %s did not reset its wall (state %s)",
				OTHER_ARENA, tostring(fixture:stateOf(elsewhere)))
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
