--!strict

----------------------------------------------------------------------
-- EnergyRoundReset
----------------------------------------------------------------------
-- Empties the local player's reservoirs when their round goes Active.
--
-- Phase 6 stage 4c. The lobby grants real energy, so without this a
-- player could fill every colour to CAP_PER_COLOR in the hub and walk
-- into a duel pre-loaded. But the bug is older than the lobby:
-- `RoundManager._activeRound` resets scores and never reset energy, so
-- round 2 of any multi-round session already inherited round 1's mana.
-- Clearing where rounds begin fixes both — see `wiki/concepts/HudGate.md`
-- § Resolved.
--
-- Client-side because that is where the energy lives (`PlayerSession`),
-- and it needs no new plumbing: `GameStateChanged` is already per-roster
-- as of Phase 6 stage 1, so a lobby player never receives an arena's
-- transition and is never cleared by someone else's round starting.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local PlayerSession = require(script.Parent.PlayerSession)

local log = Logger.new("EnergyRoundReset")

local gameStateChangedRemote = ReplicatedStorage.Shared.GameMode.Remotes.GameStateChanged :: RemoteEvent

local RoundState = GameModeConstants.RoundState

-- Only the *transition* into Active clears. RoundManager broadcasts
-- Active once a second for the whole round, and clearing on every one of
-- those would make energy unspendable.
local lastRoundState: string? = nil

gameStateChangedRemote.OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then
		return
	end

	local roundState = state.roundState
	if roundState == lastRoundState then
		return
	end

	local previous = lastRoundState
	lastRoundState = roundState

	if roundState ~= RoundState.Active then
		return
	end

	PlayerSession.get().energyReservoirs:reset()
	log:info(string.format("round went Active (from %s) — reservoirs cleared", tostring(previous)))
end)
