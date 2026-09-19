----------------------------------------------------------------------
-- RoundTimerGui
----------------------------------------------------------------------
-- Coordinator for the round state / timer strip at the top of the screen.
-- Listens to GameStateChanged and drives a RoundTimerBuilder handle; the
-- DOM and every literal live in RoundTimerBuilder / RoundTimerConfig
-- (ported to Builder + Config in Phase 6 stage 6, the last hand-built HUD
-- element from refactor chunk 12).
--
-- Shown only while the round payload carries a `timeLimit` — a mode with
-- no timer (Lobby, NoOp) never puts a "0:00" on screen. Read from the
-- payload rather than a global flag because the timer is a property of
-- the player's session's mode, and two sessions can differ.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local HudConstants = require(ReplicatedStorage.Shared.Hud.HudConstants)
local HudGate = require(ReplicatedStorage.Shared.Hud.HudGate)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local RoundTimerBuilder = require(ReplicatedStorage.Shared.Hud.RoundTimerBuilder)

local log = Logger.new("RoundTimerGui")

local player = Players.LocalPlayer
local gameStateChangedRemote = ReplicatedStorage.Shared.GameMode.Remotes.GameStateChanged

local RoundState = GameModeConstants.RoundState

----------------------------------------------------------------------
-- UI Construction
----------------------------------------------------------------------
local handle = RoundTimerBuilder.build()
handle.screenGui.DisplayOrder = HudConstants.LAYERS.Overlay
handle.screenGui.Parent = player:WaitForChild("PlayerGui")

-- Round and competition chrome: no meaning in the hub.
HudGate.bindScreenGui(handle.screenGui, HudGate.Policy.ArenaOnly)
HudLayoutManager:attachScale(handle.screenGui)

----------------------------------------------------------------------
-- State updates
----------------------------------------------------------------------
gameStateChangedRemote.OnClientEvent:Connect(function(state)
	local roundState = state.roundState
	local timeLeft = state.timeRemaining or 0

	-- A payload without a time limit is a session whose mode runs no
	-- timer; there is nothing to count down, so the chrome stays hidden.
	handle:setVisible(state.timeLimit ~= nil)

	if roundState == RoundState.WaitingForPlayers then
		handle:showWaiting()
	elseif roundState == RoundState.Countdown then
		handle:showCountdown(timeLeft)
	elseif roundState == RoundState.Active then
		handle:showActive(timeLeft)
	elseif roundState == RoundState.PostRound then
		handle:showPostRound(state.outcome, state.winnerName, timeLeft)
	end
end)

log:info("Initialized")
