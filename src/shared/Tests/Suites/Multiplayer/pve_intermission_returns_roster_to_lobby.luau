--!strict

----------------------------------------------------------------------
-- pve_intermission_returns_roster_to_lobby — queue → round → back home
----------------------------------------------------------------------
-- The last leg of stage 5: once a finished round's intermission runs out,
-- SessionRegistry's `onIntermissionEnd` hook transfers the roster to the
-- Lobby session. This test moves the harness player into a throwaway
-- PvEBoss session for real (transferPlayer, so the registry mapping and
-- Player attributes move), ends the round with `BossDefeated`, waits out
-- the intermission and asserts the player is back in their home session
-- with the attributes to match, and the test roster is empty.
--
-- Slow by construction: PVE_COUNTDOWN_SEC + INTERMISSION_DURATION plus a
-- few ticks. The alternative — shortening the intermission for tests —
-- would test a different round than the one players get.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local PvEBoss = require(ReplicatedStorage.Shared.GameMode.Modes.PvEBoss)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local bossDefeatedEvent = ReplicatedStorage.Shared.Boss.BossEvents.BossDefeated :: BindableEvent

local RoundState = GameModeConstants.RoundState

local TEST_ARENA = "Stage5TestHome"
local ROUND_START_TIMEOUT_SEC = GameModeConstants.PVE_COUNTDOWN_SEC + 5
local ROUND_END_TIMEOUT_SEC = 3
-- The PostRound wait counts down INTERMISSION_DURATION one second at a
-- time, then the hook runs and the loop re-enters WaitingForPlayers.
local INTERMISSION_TIMEOUT_SEC = GameModeConstants.INTERMISSION_DURATION + 5
local POLL_SEC = 0.1

type Snapshot = {
	session: SessionRegistry.Session?,
	inTest: boolean,
	arenaAttr: any,
	stateAttr: any,
	testState: string,
}

type Ctx = {
	player: Player?,
	s5Home: SessionRegistry.Session?,
	s5HomeId: string?,
	s5Session: SessionRegistry.Session?,
	s5TransferOk: boolean,
	s5ReachedActive: boolean,
	s5ReachedPostRound: boolean,
	s5LeftPostRound: boolean,
	s5After: Snapshot?,
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
	name = "pve_intermission_returns_roster_to_lobby",

	setup = function(ctx: Ctx)
		ctx.s5TransferOk = false
		ctx.s5ReachedActive = false
		ctx.s5ReachedPostRound = false
		ctx.s5LeftPostRound = false
		local player = ctx.player
		if not player then
			return
		end
		local home = SessionRegistry.forPlayer(player)
		assert(home, "the harness player has no session")
		ctx.s5Home = home
		ctx.s5HomeId = home:getArenaId()
		ctx.s5Session = SessionRegistry.create(TEST_ARENA, PvEBoss)
	end,

	run = function(ctx: Ctx)
		local player = ctx.player
		local session = ctx.s5Session
		if not player or not session then
			return
		end

		ctx.s5TransferOk = SessionRegistry.transferPlayer(player, TEST_ARENA)
		if not ctx.s5TransferOk then
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
		ctx.s5ReachedPostRound = waitFor(function()
			return session:getState() == RoundState.PostRound
		end, ROUND_END_TIMEOUT_SEC)
		if not ctx.s5ReachedPostRound then
			return
		end

		ctx.s5LeftPostRound = waitFor(function()
			return session:getState() ~= RoundState.PostRound
		end, INTERMISSION_TIMEOUT_SEC)

		ctx.s5After = {
			session = SessionRegistry.forPlayer(player),
			inTest = session:hasPlayer(player),
			arenaAttr = player:GetAttribute(Arena.ID_ATTRIBUTE),
			stateAttr = player:GetAttribute(Arena.STATE_ATTRIBUTE),
			testState = session:getState(),
		}
	end,

	teardown = function(ctx: Ctx)
		local player = ctx.player
		local homeId = ctx.s5HomeId
		if player and homeId and ctx.s5Home and SessionRegistry.forPlayer(player) ~= ctx.s5Home then
			SessionRegistry.transferPlayer(player, homeId)
		end
		SessionRegistry.destroy(TEST_ARENA)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local player = ctx.player
		local home = ctx.s5Home
		local session = ctx.s5Session
		if not player or not home or not session then
			return false, "no player on the server — nothing to send home"
		end
		if home:getArenaId() ~= Arena.LOBBY_ID then
			return false, string.format("the harness player's home is %s, not the lobby — the hook sends players to %s",
				home:getArenaId(), Arena.LOBBY_ID)
		end
		if not ctx.s5TransferOk then
			return false, "transferPlayer into the PvE test arena returned false"
		end
		if not ctx.s5ReachedActive then
			return false, string.format("the PvE session never reached Active (state=%s)", session:getState())
		end
		if not ctx.s5ReachedPostRound then
			return false, "BossDefeated did not end the round"
		end
		if not ctx.s5LeftPostRound then
			return false, string.format("the session was still in PostRound %ds after the intermission should have ended",
				INTERMISSION_TIMEOUT_SEC)
		end

		local after = ctx.s5After
		if not after then
			return false, "no snapshot taken after the intermission"
		end
		if after.session ~= home then
			return false, string.format("after the intermission forPlayer is %s, expected the lobby",
				after.session and after.session:getArenaId() or "<nil>")
		end
		if after.inTest then
			return false, "the player is still on the PvE session's roster after being sent home"
		end
		if after.arenaAttr ~= Arena.LOBBY_ID then
			return false, string.format("ArenaId attribute after the intermission is %s", tostring(after.arenaAttr))
		end
		if after.stateAttr ~= Arena.PlayerState.InLobby then
			return false, string.format("PlayerState after the intermission is %s", tostring(after.stateAttr))
		end
		if after.testState ~= RoundState.WaitingForPlayers then
			return false, string.format("the emptied PvE session is in %s, expected WaitingForPlayers", after.testState)
		end
		return true, nil
	end,
}
