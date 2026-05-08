----------------------------------------------------------------------
-- ScoreboardGui
----------------------------------------------------------------------
-- Tab-to-open scoreboard showing all players' kills, deaths, assists.
-- Listens to ScoreUpdate RemoteEvent for score data.
-- Sorted by kills descending.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local log = Logger.new("ScoreboardGui")

local player = Players.LocalPlayer
local gameModeRemotes = ReplicatedStorage.Shared.GameMode.Remotes
local scoreUpdateRemote = gameModeRemotes.ScoreUpdate

----------------------------------------------------------------------
-- Configuration
----------------------------------------------------------------------
local TOGGLE_KEY = Enum.KeyCode.Y
local HEADER_HEIGHT = 32
local ROW_HEIGHT = 28
local COLUMN_WIDTHS = { 0.35, 0.15, 0.15, 0.15, 0.20 } -- Name, Kills, Deaths, Assists, K/D

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local currentScores = {} -- { [userId]: { kills, deaths, assists, playerName } }
local isVisible = false

----------------------------------------------------------------------
-- UI Construction
----------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ScoreboardGui"
screenGui.DisplayOrder = 25 -- above other HUD
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Dimmed background
local dimmer = Instance.new("Frame")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.new(1, 0, 1, 0)
dimmer.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dimmer.BackgroundTransparency = 0.5
dimmer.BorderSizePixel = 0
dimmer.Visible = false
dimmer.Parent = screenGui

-- Scoreboard panel
local panel = Instance.new("Frame")
panel.Name = "ScoreboardPanel"
panel.Size = UDim2.new(0, 500, 0, 400)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 8)
panelPadding.PaddingBottom = UDim.new(0, 8)
panelPadding.PaddingLeft = UDim.new(0, 12)
panelPadding.PaddingRight = UDim.new(0, 12)
panelPadding.Parent = panel

-- Title
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "SCOREBOARD"
title.TextColor3 = Color3.fromRGB(0, 162, 255)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.Parent = panel

-- Header row
local headerFrame = Instance.new("Frame")
headerFrame.Name = "Header"
headerFrame.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
headerFrame.Position = UDim2.new(0, 0, 0, 34)
headerFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
headerFrame.BackgroundTransparency = 0.3
headerFrame.BorderSizePixel = 0
headerFrame.Parent = panel
Instance.new("UICorner", headerFrame).CornerRadius = UDim.new(0, 4)

local headers = { "Player", "Kills", "Deaths", "Assists", "K/D" }
local xOffset = 0
for i, headerText in headers do
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(COLUMN_WIDTHS[i], 0, 1, 0)
	label.Position = UDim2.new(xOffset, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = headerText
	label.TextColor3 = Color3.fromRGB(180, 180, 190)
	label.TextSize = 12
	label.Font = Enum.Font.GothamBold
	label.Parent = headerFrame
	xOffset += COLUMN_WIDTHS[i]
end

-- Scrolling rows container
local rowsScroll = Instance.new("ScrollingFrame")
rowsScroll.Name = "Rows"
rowsScroll.Size = UDim2.new(1, 0, 1, -72)
rowsScroll.Position = UDim2.new(0, 0, 0, 70)
rowsScroll.BackgroundTransparency = 1
rowsScroll.BorderSizePixel = 0
rowsScroll.ScrollBarThickness = 4
rowsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
rowsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
rowsScroll.Parent = panel

local rowsLayout = Instance.new("UIListLayout")
rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowsLayout.Padding = UDim.new(0, 2)
rowsLayout.Parent = rowsScroll

----------------------------------------------------------------------
-- Row rendering
----------------------------------------------------------------------
local function refreshRows()
	-- Clear existing rows
	for _, child in rowsScroll:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Sort by kills descending
	local sorted = {}
	for userId, data in currentScores do
		table.insert(sorted, { userId = userId, data = data })
	end
	table.sort(sorted, function(a, b)
		return a.data.kills > b.data.kills
	end)

	for rank, entry in sorted do
		local data = entry.data
		local isLocal = entry.userId == player.UserId

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.BackgroundColor3 = isLocal and Color3.fromRGB(0, 80, 140) or Color3.fromRGB(35, 35, 42)
		row.BackgroundTransparency = isLocal and 0.4 or 0.3
		row.BorderSizePixel = 0
		row.LayoutOrder = rank
		row.Parent = rowsScroll
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

		local kd = data.deaths > 0 and string.format("%.1f", data.kills / data.deaths) or tostring(data.kills)
		local values = { data.playerName, tostring(data.kills), tostring(data.deaths), tostring(data.assists), kd }
		local textColor = isLocal and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 220, 225)

		local x = 0
		for i, value in values do
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(COLUMN_WIDTHS[i], 0, 1, 0)
			label.Position = UDim2.new(x, 0, 0, 0)
			label.BackgroundTransparency = 1
			label.Text = value
			label.TextColor3 = textColor
			label.TextSize = 13
			label.Font = i == 1 and Enum.Font.GothamBold or Enum.Font.Gotham
			label.TextXAlignment = i == 1 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
			label.Parent = row

			if i == 1 then
				local padding = Instance.new("UIPadding")
				padding.PaddingLeft = UDim.new(0, 8)
				padding.Parent = label
			end

			x += COLUMN_WIDTHS[i]
		end
	end
end

----------------------------------------------------------------------
-- Visibility toggle
----------------------------------------------------------------------
local function setVisible(visible: boolean)
	isVisible = visible
	dimmer.Visible = visible
	panel.Visible = visible
	if visible then
		refreshRows()
	end
end

----------------------------------------------------------------------
-- Input handling
----------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == TOGGLE_KEY then
		setVisible(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == TOGGLE_KEY then
		setVisible(false)
	end
end)

----------------------------------------------------------------------
-- Score updates
----------------------------------------------------------------------
scoreUpdateRemote.OnClientEvent:Connect(function(scores)
	currentScores = scores
	if isVisible then
		refreshRows()
	end
end)

log:info("Initialized")
