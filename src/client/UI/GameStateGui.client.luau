----------------------------------------------------------------------
-- GameStateGui
----------------------------------------------------------------------
-- Shows overlay screens for round state transitions:
--   - "Waiting for players" message
--   - Countdown overlay
--   - End-of-round results (winner + top players)
-- Listens to GameStateChanged and ScoreUpdate RemoteEvents.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local HudConstants = require(ReplicatedStorage.Shared.Hud.HudConstants)
local HudGate = require(ReplicatedStorage.Shared.Hud.HudGate)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local GameStateBuilder = require(ReplicatedStorage.Shared.Hud.GameStateBuilder)

local log = Logger.new("GameStateGui")

local player = Players.LocalPlayer
local gameModeRemotes = ReplicatedStorage.Shared.GameMode.Remotes
local gameStateChangedRemote = gameModeRemotes.GameStateChanged
local scoreUpdateRemote = gameModeRemotes.ScoreUpdate

local RoundState = GameModeConstants.RoundState

----------------------------------------------------------------------
-- UI Construction
----------------------------------------------------------------------
local handle = GameStateBuilder.build()
handle.screenGui.DisplayOrder = HudConstants.LAYERS.Modal -- above scoreboard
handle.screenGui.Parent = player:WaitForChild("PlayerGui")

-- Round and competition chrome: no meaning in the hub.
HudGate.bindScreenGui(handle.screenGui, HudGate.Policy.ArenaOnly)
HudLayoutManager:attachScale(handle.screenGui)

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
gameStateChangedRemote.OnClientEvent:Connect(function(state)
	local roundState = state.roundState

	if roundState == RoundState.PostRound then
		handle:setWinner(state.winnerName)
		handle:setNextRoundText("Next round in " .. math.ceil(state.timeRemaining or 0) .. "...")
		handle:show()

	elseif roundState == RoundState.Countdown then
		handle:hide()

	elseif roundState == RoundState.Active then
		if handle:isShown() then
			handle:hide()
		end
	end

	-- Update countdown during post-round
	if roundState == RoundState.PostRound and handle:isShown() then
		handle:setNextRoundText("Next round in " .. math.ceil(state.timeRemaining or 0) .. "...")
	end
end)

scoreUpdateRemote.OnClientEvent:Connect(function(scores)
	handle:setScores(scores, player.UserId)
end)

log:info("Initialized")
