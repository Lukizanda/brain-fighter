----------------------------------------------------------------------
-- RoundTimerGui
----------------------------------------------------------------------
-- Displays the current round state and timer at the top of the screen.
-- Listens to GameStateChanged RemoteEvent from the server.
--
-- Gated behind GameConfig.ROUND_TIMER_ENABLED — set false to hide
-- the timer entirely (score-only win condition mode).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)

if not GameConfig.ROUND_TIMER_ENABLED then
	return
end

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

local log = Logger.new("RoundTimerGui")

local player = Players.LocalPlayer
local gameStateChangedRemote = ReplicatedStorage.Shared.GameMode.Remotes.GameStateChanged

local RoundState = GameModeConstants.RoundState

----------------------------------------------------------------------
-- UI Construction
----------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RoundTimerGui"
screenGui.DisplayOrder = 15
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local container = Instance.new("Frame")
container.Name = "TimerContainer"
container.Size = UDim2.new(0, 300, 0, 50)
container.Position = UDim2.new(0.5, 0, 0, 8)
container.AnchorPoint = Vector2.new(0.5, 0)
container.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
container.BackgroundTransparency = 0.3
container.BorderSizePixel = 0
container.Parent = screenGui
Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerLabel"
timerLabel.Size = UDim2.new(1, 0, 0, 30)
timerLabel.Position = UDim2.new(0, 0, 0, 4)
timerLabel.BackgroundTransparency = 1
timerLabel.Text = "Waiting for players..."
timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timerLabel.TextSize = 20
timerLabel.Font = Enum.Font.GothamBold
timerLabel.Parent = container

local subLabel = Instance.new("TextLabel")
subLabel.Name = "SubLabel"
subLabel.Size = UDim2.new(1, 0, 0, 16)
subLabel.Position = UDim2.new(0, 0, 0, 32)
subLabel.BackgroundTransparency = 1
subLabel.Text = ""
subLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
subLabel.TextSize = 12
subLabel.Font = Enum.Font.Gotham
subLabel.Parent = container

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function formatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%d:%02d", mins, secs)
end

----------------------------------------------------------------------
-- State updates
----------------------------------------------------------------------
gameStateChangedRemote.OnClientEvent:Connect(function(state)
	local roundState = state.roundState
	local timeLeft = state.timeRemaining or 0

	if roundState == RoundState.WaitingForPlayers then
		timerLabel.Text = "Waiting for players..."
		timerLabel.TextColor3 = Color3.fromRGB(200, 200, 100)
		subLabel.Text = ""

	elseif roundState == RoundState.Countdown then
		timerLabel.Text = "Starting in " .. math.ceil(timeLeft) .. "..."
		timerLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
		subLabel.Text = "Get ready!"

	elseif roundState == RoundState.Active then
		timerLabel.Text = formatTime(timeLeft)
		subLabel.Text = ""
		if timeLeft <= 30 then
			timerLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		elseif timeLeft <= 60 then
			timerLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
		else
			timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		end

	elseif roundState == RoundState.PostRound then
		timerLabel.Text = state.winnerName and ("Winner: " .. state.winnerName) or "Round Over"
		timerLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		subLabel.Text = "Next round in " .. math.ceil(timeLeft) .. "..."
	end
end)

log:info("Initialized")
