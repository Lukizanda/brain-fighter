--!strict

----------------------------------------------------------------------
-- duel_waits_for_two — a duel pad does not start for one
----------------------------------------------------------------------
-- The whole point of `minPlayers` on the mode config: a PvPDuel session
-- with one roster member sits in WaitingForPlayers past its countdown
-- length, and reports one free seat so LobbyService knows it is a pad
-- worth topping up. Roster-only membership (the harness player is added
-- to the roster, not transferred), as in sessions_isolate_scores.
--
-- Also pins the seat rule the queue relies on: an empty pad offers
-- DUEL_PLAYERS seats, one player on it leaves DUEL_PLAYERS - 1.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local PvPDuel = require(ReplicatedStorage.Shared.GameMode.Modes.PvPDuel)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local RoundState = GameModeConstants.RoundState

local TEST_ARENA = "Stage6TestWait"
-- Long enough that a countdown that wrongly started would have finished
-- and the round gone Active.
local WAIT_SEC = GameModeConstants.DUEL_COUNTDOWN_SEC + 3

type Ctx = {
	player: Player?,
	s6Session: SessionRegistry.Session?,
	s6SeatsEmpty: number?,
	s6SeatsWithOne: number?,
	s6MinPlayers: number?,
	s6StateAfter: string?,
}

return {
	name = "duel_waits_for_two",

	setup = function(ctx: Ctx)
		local session = SessionRegistry.create(TEST_ARENA, PvPDuel)
		ctx.s6Session = session
		ctx.s6SeatsEmpty = session:freeSeats()
		ctx.s6MinPlayers = session:minPlayers()
	end,

	run = function(ctx: Ctx)
		local session = ctx.s6Session
		local player = ctx.player
		if not session or not player then
			return
		end

		session:addPlayer(player)
		ctx.s6SeatsWithOne = session:freeSeats()

		session:start()
		task.wait(WAIT_SEC)
		ctx.s6StateAfter = session:getState()
	end,

	teardown = function(_ctx: Ctx)
		SessionRegistry.destroy(TEST_ARENA)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if not ctx.player or not ctx.s6Session then
			return false, "no player on the server — nothing to seat"
		end
		if ctx.s6MinPlayers ~= GameModeConstants.DUEL_PLAYERS then
			return false, string.format("a duel session reports minPlayers=%s, expected %d",
				tostring(ctx.s6MinPlayers), GameModeConstants.DUEL_PLAYERS)
		end
		if ctx.s6SeatsEmpty ~= GameModeConstants.DUEL_PLAYERS then
			return false, string.format("an empty duel pad offers %s seats, expected %d",
				tostring(ctx.s6SeatsEmpty), GameModeConstants.DUEL_PLAYERS)
		end
		if ctx.s6SeatsWithOne ~= GameModeConstants.DUEL_PLAYERS - 1 then
			return false, string.format("a duel pad with one player offers %s seats, expected %d",
				tostring(ctx.s6SeatsWithOne), GameModeConstants.DUEL_PLAYERS - 1)
		end
		if ctx.s6StateAfter ~= RoundState.WaitingForPlayers then
			return false, string.format("a duel session with one player is in %s after %ds — it should still be waiting",
				tostring(ctx.s6StateAfter), WAIT_SEC)
		end
		return true, nil
	end,
}
