----------------------------------------------------------------------
-- TeamScoreGui
----------------------------------------------------------------------
-- Top-center HUD strip showing team-aggregated kills, e.g.
--    [ RED  7 ]  —  [ BLUE 4 ]
-- Listens to ScoreUpdate (per-player kills) and sums by Player.Team.
-- The team aggregation lives client-side so server's ScoreTracker
-- stays mode-agnostic (player-keyed only). Updates whenever the
-- remote fires or when local Team membership changes.
--
-- Hides itself entirely when no player has a team — keeps the FFA HUD
-- from getting a "Red 0 — Blue 0" strip that doesn't apply.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("TeamScoreGui")

-- Teams gate: this LocalScript auto-runs on every player join, so the
-- only way to suppress the team-score HUD without deleting the file is
-- to bail at the very top before any container or remote hook is built.
if not GameConfig.TEAMS_ENABLED then
	log:info("TEAMS_ENABLED=false — TeamScoreGui suppressed")
	return
end

local player = Players.LocalPlayer
local scoreUpdateRemote = ReplicatedStorage.Shared.GameMode.Remotes.ScoreUpdate

local SCORE_FONT = Enum.Font.GothamBold
local NAME_FONT = Enum.Font.GothamSemibold
local NEUTRAL_COLOR = Color3.fromRGB(220, 220, 220)
local DIVIDER_COLOR = Color3.fromRGB(150, 150, 160)

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local latestScores: { [number]: { kills: number, deaths: number, assists: number, playerName: string } } = {}
local entries: { [string]: { container: Frame, label: TextLabel, score: TextLabel } } = {}

----------------------------------------------------------------------
-- UI construction
----------------------------------------------------------------------
local container = Instance.new("Frame")
container.Name = "TeamScores"
container.Size = UDim2.new(0, 280, 0, 36)
container.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
container.BackgroundTransparency = 0.25
container.BorderSizePixel = 0
container.Visible = false

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = container

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 12)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = container

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 14)
padding.PaddingRight = UDim.new(0, 14)
padding.PaddingTop = UDim.new(0, 4)
padding.PaddingBottom = UDim.new(0, 4)
padding.Parent = container

-- Build one team-name + score pair. We rebuild the entry list whenever the
-- Teams collection changes, so newly added Team instances appear without
-- a HUD reload.
local function buildEntryFor(team: Team, layoutOrder: number)
	if entries[team.Name] then
		return
	end

	local entry = Instance.new("Frame")
	entry.Name = team.Name
	entry.AutomaticSize = Enum.AutomaticSize.X
	entry.Size = UDim2.new(0, 0, 1, 0)
	entry.BackgroundTransparency = 1
	entry.LayoutOrder = layoutOrder

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.Parent = entry

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.AutomaticSize = Enum.AutomaticSize.X
	nameLabel.Size = UDim2.new(0, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = NAME_FONT
	nameLabel.TextSize = 16
	nameLabel.TextColor3 = team.TeamColor.Color
	nameLabel.Text = string.upper(team.Name)
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = entry

	local scoreLabel = Instance.new("TextLabel")
	scoreLabel.Name = "Score"
	scoreLabel.AutomaticSize = Enum.AutomaticSize.X
	scoreLabel.Size = UDim2.new(0, 0, 1, 0)
	scoreLabel.BackgroundTransparency = 1
	scoreLabel.Font = SCORE_FONT
	scoreLabel.TextSize = 20
	scoreLabel.TextColor3 = Color3.fromRGB(245, 245, 250)
	scoreLabel.Text = "0"
	scoreLabel.LayoutOrder = 2
	scoreLabel.Parent = entry

	entry.Parent = container
	entries[team.Name] = { container = entry, label = nameLabel, score = scoreLabel }
end

local function rebuildEntries()
	-- Wipe existing entries and dividers so order matches Teams children.
	for _, child in container:GetChildren() do
		if child:IsA("Frame") or (child:IsA("TextLabel") and child.Name == "Divider") then
			child:Destroy()
		end
	end
	table.clear(entries)

	local teams = Teams:GetChildren()
	for i, t in teams do
		if t:IsA("Team") then
			if i > 1 then
				local divider = Instance.new("TextLabel")
				divider.Name = "Divider"
				divider.AutomaticSize = Enum.AutomaticSize.X
				divider.Size = UDim2.new(0, 0, 1, 0)
				divider.BackgroundTransparency = 1
				divider.Font = NAME_FONT
				divider.TextSize = 18
				divider.TextColor3 = DIVIDER_COLOR
				divider.Text = "—"
				divider.LayoutOrder = (i * 2) - 1
				divider.Parent = container
			end
			buildEntryFor(t, i * 2)
		end
	end
end

----------------------------------------------------------------------
-- Aggregation
----------------------------------------------------------------------
local function teamForUserId(userId: number): Team?
	local p = Players:GetPlayerByUserId(userId)
	return p and p.Team or nil
end

local function refresh()
	-- Hide the strip when no team-mode is active. We detect that by
	-- checking if any current Player has a Team set; if everyone is
	-- Neutral / nil there's nothing to show.
	local anyTeam = false
	for _, p in Players:GetPlayers() do
		if p.Team then
			anyTeam = true
			break
		end
	end
	if not anyTeam then
		container.Visible = false
		return
	end
	container.Visible = true

	-- Sum per-team
	local totals: { [string]: number } = {}
	for userId, score in latestScores do
		local team = teamForUserId(userId)
		if team then
			totals[team.Name] = (totals[team.Name] or 0) + (score.kills or 0)
		end
	end

	for teamName, entry in entries do
		entry.score.Text = tostring(totals[teamName] or 0)
	end
end

----------------------------------------------------------------------
-- Hookup
----------------------------------------------------------------------
HudLayoutManager:register("TopCenter", container)

rebuildEntries()
refresh()

scoreUpdateRemote.OnClientEvent:Connect(function(scores)
	latestScores = scores or {}
	refresh()
end)

-- Team set rebalanced (added / removed teams). Keep the strip current
-- without requiring a HUD reload.
Teams.ChildAdded:Connect(function(child)
	if child:IsA("Team") then
		rebuildEntries()
		refresh()
	end
end)
Teams.ChildRemoved:Connect(function(child)
	if child:IsA("Team") then
		rebuildEntries()
		refresh()
	end
end)

-- Local player team change → re-evaluate visibility quickly.
player:GetPropertyChangedSignal("Team"):Connect(refresh)

log:info("Initialized")
