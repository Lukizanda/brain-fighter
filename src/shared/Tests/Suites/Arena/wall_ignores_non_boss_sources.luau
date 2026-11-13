--!strict

----------------------------------------------------------------------
-- wall_ignores_non_boss_sources
----------------------------------------------------------------------
-- Player spells must not damage walls: opening a vault with your own
-- Fireball would remove the baiting the layout is built around. Sources
-- tried, for both WorldImpact and AoeImpact: a player's real character, an
-- untagged rig, a nil source, and a non-Instance. None may move a wall's
-- health. A Boss-tagged source at the end proves the wall was listening at
-- all (otherwise "unchanged" would pass on a dead service).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)

local TEST_ARENA = "BreakableWallTestSources"
local MAX_HEALTH = 10
local HITS_PER_SOURCE = 5
local SLAM_RADIUS = 30

type Ctx = {
	player: Player?,
	bwFixture: breakableWallFixture.Fixture?,
	bwFailure: string?,
}

return {
	name = "wall_ignores_non_boss_sources",

	setup = function(ctx: Ctx)
		ctx.bwFixture = breakableWallFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fixture = ctx.bwFixture :: breakableWallFixture.Fixture
		local wall = fixture:wall("SourceWall", { maxHealth = MAX_HEALTH })
		fixture:settle()

		local sources: { { label: string, source: any } } = {
			{ label = "untagged rig", source = fixture:bystander() },
			{ label = "nil source", source = nil },
			{ label = "non-Instance source", source = "Boss" },
		}
		local character = if ctx.player then ctx.player.Character else nil
		if character then
			table.insert(sources, { label = "player character", source = character })
		end

		for _, entry in sources do
			fixture:fireballs(wall, entry.source, HITS_PER_SOURCE)
			fixture:slam(wall.Position, SLAM_RADIUS, entry.source)
			if fixture:healthOf(wall) ~= MAX_HEALTH or fixture:stateOf(wall) ~= C.State.Intact then
				ctx.bwFailure = string.format("%s damaged the wall: health=%s state=%s",
					entry.label, tostring(fixture:healthOf(wall)), tostring(fixture:stateOf(wall)))
				return
			end
		end

		-- Control: the same events from a boss do land.
		local boss = fixture:boss()
		fixture:fireballs(wall, boss, 1)
		if fixture:healthOf(wall) ~= MAX_HEALTH - C.FIREBALL_WALL_DAMAGE then
			ctx.bwFailure = string.format("control failed: a boss fireball left health at %s",
				tostring(fixture:healthOf(wall)))
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
