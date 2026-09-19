--!strict

----------------------------------------------------------------------
-- pve_round_ends_on_boss_defeated — Phase 6 stage 5, the objective
----------------------------------------------------------------------
-- A PvEBoss round is meant to end when the arena's boss dies, without the
-- death being modelled as a player kill. BossService fires the shared
-- `BossDefeated(arenaId)` Bindable from its Died handler; this test fires
-- the same Bindable by hand for a throwaway session and asserts the REAL
-- round loop leaves Active for PostRound and announces `RoundEnded` with
-- no winner.
--
-- Roster-only membership (the harness player is added to the roster, not
-- transferred), as in sessions_isolate_scores, so the player's registry
-- mapping and character are untouched. The intermission → lobby hook is
-- exercised by pve_intermission_returns_roster_to_lobby instead.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local PvEBoss = require(ReplicatedStorage.Shared.GameMode.Modes.PvEBoss)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local bossDefeatedEvent = ReplicatedStorage.Shared.Boss.BossEvents.BossDefeated :: BindableEvent
local roundEndedEvent = ServerScriptService.Server.GameMode.Events.RoundEnded :: BindableEvent

local RoundState = GameModeConstants.RoundState

-- An arena id no session in the shipped place uses.
local TEST_ARENA = "Stage5TestDefeat"
-- PvEBoss has a countdown; the loop needs that plus a tick to reach Active.
local ROUND_START_TIMEOUT_SEC = GameModeConstants.PVE_COUNTDOWN_SEC + 5
-- The win check runs once a second; two ticks is generous.
local ROUND_END_TIMEOUT_SEC = 3
local POLL_SEC = 0.1

type Ended = { winnerId: number?, winnerName: string?, arenaId: string }

type Ctx = {
	player: Player?,
	s5Session: SessionRegistry.Session?,
	s5Connection: RBXScriptConnection?,
	s5Ended: { Ended },
	s5ReachedActive: boolean,
	s5StateAfter: string?,
}

local function waitFor(predicate: () -> boolean, timeoutSec: number): boolean
	local deadline = os.clock() + timeoutSec
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait(POLL_SEC)
	end
	return predicate()
end

return {
	name = "pve_round_ends_on_boss_defeated",

	setup = function(ctx: Ctx)
		ctx.s5Ended = {}
		ctx.s5ReachedActive = false
		local player = ctx.player
		if not player then
			return
		end

		local session = SessionRegistry.create(TEST_ARENA, PvEBoss)
		session:addPlayer(player)
		ctx.s5Session = session

		ctx.s5Connection = roundEndedEvent.Event:Connect(function(winnerId: number?, winnerName: string?, arenaId: string)
			if arenaId == TEST_ARENA then
				table.insert(ctx.s5Ended, { winnerId = winnerId, winnerName = winnerName, arenaId = arenaId })
			end
		end)
	end,

	run = function(ctx: Ctx)
		local session = ctx.s5Session
		if not session then
			return
		end

		session:start()
		ctx.s5ReachedActive = waitFor(function()
			return session:isActive()
		end, ROUND_START_TIMEOUT_SEC)
		if not ctx.s5ReachedActive then
			return
		end

		bossDefeatedEvent:Fire(TEST_ARENA)

		waitFor(function()
			return session:getState() == RoundState.PostRound
		end, ROUND_END_TIMEOUT_SEC)
		ctx.s5StateAfter = session:getState()
	end,

	teardown = function(ctx: Ctx)
		if ctx.s5Connection then
			ctx.s5Connection:Disconnect()
		end
		SessionRegistry.destroy(TEST_ARENA)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local session = ctx.s5Session
		if not ctx.player or not session then
			return false, "no player on the server — the round could never have started"
		end
		if not ctx.s5ReachedActive then
			return false, string.format("the PvE session never reached Active (state=%s)", session:getState())
		end
		if ctx.s5StateAfter ~= RoundState.PostRound then
			return false, string.format("BossDefeated did not end the round: state=%s after %ds",
				tostring(ctx.s5StateAfter), ROUND_END_TIMEOUT_SEC)
		end
		if #ctx.s5Ended ~= 1 then
			return false, string.format("RoundEnded fired %d times for %s, expected 1", #ctx.s5Ended, TEST_ARENA)
		end
		local ended = ctx.s5Ended[1]
		if ended.winnerId ~= nil or ended.winnerName ~= nil then
			return false, string.format("a co-op objective credited a winner: %s / %s",
				tostring(ended.winnerId), tostring(ended.winnerName))
		end
		return true, nil
	end,
}
