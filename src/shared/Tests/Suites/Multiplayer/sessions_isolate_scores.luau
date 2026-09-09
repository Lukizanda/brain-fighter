--!strict

----------------------------------------------------------------------
-- sessions_isolate_scores — F12, the server-wide score table
----------------------------------------------------------------------
-- Before refactor chunk 8, ScoreTracker was one table for the whole
-- server: any session's round start zeroed every
-- player, and a win check in one arena read the other arena's kills. Each
-- session now owns its own tracker. This test starts a round in a second
-- session and asserts the first session's scores survive it.
--
-- Rosters: the harness has exactly one real Player and no way to make a
-- second, so the two sessions here both hold that player — the home
-- (lobby) session through the registry, the test session through its
-- roster alone. Overlapping is the *stronger* case for what is asserted:
-- if the trackers were still one table, a reset in the test session would
-- zero the very same Player's home score. Disjoint rosters are what the
-- two-client playtest checks.
--
-- Driven through the REAL round loop (`session:start()`), not by calling
-- `reset()` directly, because the round-start path is the one that used
-- to do the damage. This fires `RoundStarted` for the test roster — the
-- same thing the economy suite does by hand.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local NoOpMode = require(ReplicatedStorage.Shared.GameMode.Modes.NoOpMode)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local roundStartedEvent = ServerScriptService.Server.GameMode.Events.RoundStarted :: BindableEvent

-- An arena id no session in the shipped place uses.
local TEST_ARENA = "Chunk8TestA"
-- How long the round loop may take to leave WaitingForPlayers. MIN_PLAYERS
-- is 1 and NoOp has no countdown, so it is one `task.wait(1)` at most.
local ROUND_START_TIMEOUT_SEC = 5
local POLL_SEC = 0.1
-- A signal fired on a BindableEvent is delivered at the next resumption
-- point under deferred signal behaviour. `start()` reaches Active before
-- its first yield (MIN_PLAYERS is already met), so without this the
-- RoundStarted listener has not run when verify looks at it.
local SIGNAL_SETTLE_SEC = 0.1
-- What the kill feed shows for the seeded death; named so it is obviously
-- the harness.
local SEED_CAUSE = "chunk8_test"

type Ctx = {
	player: Player?,
	c8Home: SessionRegistry.Session?,
	c8Other: SessionRegistry.Session?,
	c8HomeDeathsBefore: number,
	c8HomeStateBefore: string,
	c8Rosters: { { Player } },
	c8Connection: RBXScriptConnection?,
}

return {
	name = "sessions_isolate_scores",

	setup = function(ctx: Ctx)
		ctx.c8Rosters = {}
		local player = ctx.player
		if not player then
			return
		end

		local home = SessionRegistry.forPlayer(player)
		assert(home, "the harness player has no session — GameModeService did not assign them")
		ctx.c8Home = home
		ctx.c8HomeStateBefore = home:getState()

		-- Give the home tracker something to lose.
		home:recordKill(nil, player, SEED_CAUSE)
		local homeScore = home:getScoreTracker():getScore(player)
		ctx.c8HomeDeathsBefore = homeScore and homeScore.deaths or 0

		local other = SessionRegistry.create(TEST_ARENA, NoOpMode)
		-- Roster only: the registry still maps the player to home.
		other:addPlayer(player)
		ctx.c8Other = other

		ctx.c8Connection = roundStartedEvent.Event:Connect(function(roster: { Player })
			table.insert(ctx.c8Rosters, roster)
		end)
	end,

	run = function(ctx: Ctx)
		local other = ctx.c8Other
		if not other then
			return
		end

		other:start()

		local deadline = os.clock() + ROUND_START_TIMEOUT_SEC
		while not other:isActive() and os.clock() < deadline do
			task.wait(POLL_SEC)
		end
		task.wait(SIGNAL_SETTLE_SEC)
	end,

	teardown = function(ctx: Ctx)
		if ctx.c8Connection then
			ctx.c8Connection:Disconnect()
		end
		SessionRegistry.destroy(TEST_ARENA)
		local home = ctx.c8Home
		if home then
			home:getScoreTracker():reset()
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local player = ctx.player
		local home = ctx.c8Home
		local other = ctx.c8Other
		if not player or not home or not other then
			return false, "no player on the server — the round-start assertion would be vacuous"
		end

		if ctx.c8HomeDeathsBefore < 1 then
			return false, "setup failed to seed a death on the home tracker"
		end

		if not other:isActive() then
			return false, string.format("the test session never reached Active (state=%s)", other:getState())
		end

		-- The round start reached exactly this session's roster.
		if #ctx.c8Rosters ~= 1 then
			return false, string.format("RoundStarted fired %d times, expected 1", #ctx.c8Rosters)
		end
		local roster = ctx.c8Rosters[1]
		if #roster ~= 1 or roster[1] ~= player then
			return false, "RoundStarted carried a roster other than the test session's"
		end

		-- The test session's own scores were reset by its round start.
		local otherScore = other:getScoreTracker():getScore(player)
		if not otherScore or otherScore.deaths ~= 0 then
			return false, "the test session's tracker was not reset on its own round start"
		end

		-- The home session was untouched: scores, state and membership.
		local homeScore = home:getScoreTracker():getScore(player)
		if not homeScore then
			return false, "the home tracker lost the player"
		end
		if homeScore.deaths ~= ctx.c8HomeDeathsBefore then
			return false, string.format(
				"a round start in %s changed the home session's deaths %d -> %d — scores are still server-wide",
				TEST_ARENA, ctx.c8HomeDeathsBefore, homeScore.deaths)
		end
		if home:getState() ~= ctx.c8HomeStateBefore then
			return false, string.format("the home session's state moved %s -> %s",
				ctx.c8HomeStateBefore, home:getState())
		end
		if home:getState() == GameModeConstants.RoundState.Active then
			return false, "the home (lobby) session is running a round"
		end
		if SessionRegistry.forPlayer(player) ~= home then
			return false, "a roster-only addPlayer moved the player's registry mapping"
		end

		return true, nil
	end,
}
