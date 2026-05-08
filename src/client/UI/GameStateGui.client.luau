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
local TweenService = game:GetService("TweenService")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

local log = Logger.new("GameStateGui")

local player = Players.LocalPlayer
local gameModeRemotes = ReplicatedStorage.Shared.GameMode.Remotes
local gameStateChangedRemote = gameModeRemotes.GameStateChanged
local scoreUpdateRemote = gameModeRemotes.ScoreUpdate

local RoundState = GameModeConstants.RoundState

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local currentScores = {}

----------------------------------------------------------------------
-- UI Construction
----------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameStateGui"
screenGui.DisplayOrder = 30 -- above scoreboard
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Full-screen overlay
local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.Parent = screenGui

-- Center container for results
local centerFrame = Instance.new("Frame")
centerFrame.Name = "CenterFrame"
centerFrame.Size = UDim2.new(0, 450, 0, 350)
centerFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
centerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
centerFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
centerFrame.BackgroundTransparency = 0.1
centerFrame.BorderSizePixel = 0
centerFrame.Parent = overlay
Instance.new("UICorner", centerFrame).CornerRadius = UDim.new(0, 12)

local centerLayout = Instance.new("UIListLayout")
centerLayout.SortOrder = Enum.SortOrder.LayoutOrder
centerLayout.Padding = UDim.new(0, 8)
centerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
centerLayout.Parent = centerFrame

local centerPadding = Instance.new("UIPadding")
centerPadding.PaddingTop = UDim.new(0, 20)
centerPadding.PaddingBottom = UDim.new(0, 20)
centerPadding.PaddingLeft = UDim.new(0, 20)
centerPadding.PaddingRight = UDim.new(0, 20)
centerPadding.Parent = centerFrame

-- "ROUND OVER" title
local roundOverLabel = Instance.new("TextLabel")
roundOverLabel.Size = UDim2.new(1, 0, 0, 30)
roundOverLabel.BackgroundTransparency = 1
roundOverLabel.Text = "ROUND OVER"
roundOverLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
roundOverLabel.TextSize = 24
roundOverLabel.Font = Enum.Font.GothamBold
roundOverLabel.LayoutOrder = 1
roundOverLabel.Parent = centerFrame

-- Winner name
local winnerLabel = Instance.new("TextLabel")
winnerLabel.Size = UDim2.new(1, 0, 0, 28)
winnerLabel.BackgroundTransparency = 1
winnerLabel.Text = ""
winnerLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
winnerLabel.TextSize = 20
winnerLabel.Font = Enum.Font.GothamBold
winnerLabel.LayoutOrder = 2
winnerLabel.Parent = centerFrame

-- Top players list
local topPlayersFrame = Instance.new("Frame")
topPlayersFrame.Size = UDim2.new(1, 0, 0, 180)
topPlayersFrame.BackgroundTransparency = 1
topPlayersFrame.LayoutOrder = 3
topPlayersFrame.Parent = centerFrame

local topPlayersLayout = Instance.new("UIListLayout")
topPlayersLayout.SortOrder = Enum.SortOrder.LayoutOrder
topPlayersLayout.Padding = UDim.new(0, 4)
topPlayersLayout.Parent = topPlayersFrame

-- Next round countdown
local nextRoundLabel = Instance.new("TextLabel")
nextRoundLabel.Size = UDim2.new(1, 0, 0, 24)
nextRoundLabel.BackgroundTransparency = 1
nextRoundLabel.Text = ""
nextRoundLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
nextRoundLabel.TextSize = 14
nextRoundLabel.Font = Enum.Font.Gotham
nextRoundLabel.LayoutOrder = 4
nextRoundLabel.Parent = centerFrame

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function refreshTopPlayers()
	for _, child in topPlayersFrame:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end

	local sorted = {}
	for userId, data in currentScores do
		table.insert(sorted, { userId = userId, data = data })
	end
	table.sort(sorted, function(a, b) return a.data.kills > b.data.kills end)

	local maxShow = math.min(#sorted, 5)
	for rank = 1, maxShow do
		local entry = sorted[rank]
		local data = entry.data
		local isLocal = entry.userId == player.UserId

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundColor3 = isLocal and Color3.fromRGB(0, 80, 140) or Color3.fromRGB(40, 40, 48)
		row.BackgroundTransparency = 0.4
		row.BorderSizePixel = 0
		row.LayoutOrder = rank
		row.Parent = topPlayersFrame
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Size = UDim2.new(0.1, 0, 1, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Text = "#" .. rank
		rankLabel.TextColor3 = rank == 1 and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(180, 180, 190)
		rankLabel.TextSize = 13
		rankLabel.Font = Enum.Font.GothamBold
		rankLabel.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.5, 0, 1, 0)
		nameLabel.Position = UDim2.new(0.1, 0, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = data.playerName
		nameLabel.TextColor3 = isLocal and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 220, 225)
		nameLabel.TextSize = 13
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		local statsLabel = Instance.new("TextLabel")
		statsLabel.Size = UDim2.new(0.4, 0, 1, 0)
		statsLabel.Position = UDim2.new(0.6, 0, 0, 0)
		statsLabel.BackgroundTransparency = 1
		statsLabel.Text = string.format("%d K / %d D / %d A", data.kills, data.deaths, data.assists)
		statsLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
		statsLabel.TextSize = 11
		statsLabel.Font = Enum.Font.Gotham
		statsLabel.Parent = row
	end
end

local function show()
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	TweenService:Create(overlay, TweenInfo.new(0.3), { BackgroundTransparency = 0.5 }):Play()
	refreshTopPlayers()
end

local function hide()
	local tween = TweenService:Create(overlay, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Wait()
	overlay.Visible = false
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
gameStateChangedRemote.OnClientEvent:Connect(function(state)
	local roundState = state.roundState

	if roundState == RoundState.PostRound then
		if state.winnerTeamName then
			winnerLabel.Text = state.winnerTeamName .. " team wins!"
		elseif state.winnerName then
			winnerLabel.Text = "Winner: " .. state.winnerName
		else
			winnerLabel.Text = "No winner"
		end
		nextRoundLabel.Text = "Next round in " .. math.ceil(state.timeRemaining or 0) .. "..."
		show()

	elseif roundState == RoundState.Countdown then
		hide()

	elseif roundState == RoundState.Active then
		if overlay.Visible then
			hide()
		end
	end

	-- Update countdown during post-round
	if roundState == RoundState.PostRound and overlay.Visible then
		nextRoundLabel.Text = "Next round in " .. math.ceil(state.timeRemaining or 0) .. "..."
	end
end)

scoreUpdateRemote.OnClientEvent:Connect(function(scores)
	currentScores = scores
	if overlay.Visible then
		refreshTopPlayers()
	end
end)

log:info("Initialized")
