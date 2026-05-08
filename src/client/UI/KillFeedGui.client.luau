----------------------------------------------------------------------
-- KillFeedGui
----------------------------------------------------------------------
-- Top-right HUD strip showing recent kills:
--    Player1 [Rifle] Player2
-- Listens to the GameMode KillFeed RemoteEvent. Names are tinted by
-- the killer/victim's current Team.TeamColor (FFA leaves both neutral).
-- Entries fade out after a fixed lifetime; the strip caps at a small
-- number of visible entries and trims the oldest off the top.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("KillFeedGui")

local localPlayer = Players.LocalPlayer
local killFeedRemote = ReplicatedStorage.Shared.GameMode.Remotes.KillFeed

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
local MAX_VISIBLE_ENTRIES = 5
local ENTRY_LIFETIME = 5 -- seconds before the entry begins fading
local FADE_DURATION = 0.4
local ENTRY_HEIGHT = 26
local ENTRY_PADDING = 4

local NAME_FONT = Enum.Font.GothamBold
local WEAPON_FONT = Enum.Font.GothamSemibold
local NAME_TEXT_SIZE = 14
local WEAPON_TEXT_SIZE = 13

local NEUTRAL_NAME_COLOR = Color3.fromRGB(220, 220, 220)
local LOCAL_PLAYER_OUTLINE = Color3.fromRGB(255, 255, 255)
local WEAPON_TEXT_COLOR = Color3.fromRGB(200, 200, 210)
local ENVIRONMENT_LABEL = "Environment"

local ENTRY_BG_COLOR = Color3.fromRGB(15, 15, 20)
local ENTRY_BG_TRANSPARENCY = 0.3

----------------------------------------------------------------------
-- Container
----------------------------------------------------------------------
local container = Instance.new("Frame")
container.Name = "KillFeed"
container.BackgroundTransparency = 1
container.Size = UDim2.new(1, 0, 0, 0)
container.AutomaticSize = Enum.AutomaticSize.Y

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, ENTRY_PADDING)
layout.Parent = container

HudLayoutManager:register("TopRight", container)

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local nextLayoutOrder = 0
local activeEntries: { Frame } = {}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function nameColorForUserId(userId: number, override: Color3?): Color3
	-- Server can pass an explicit override (used for non-Player entries
	-- like dev bots or NPCs that have a logical team but no real Player).
	if override then
		return override
	end
	-- userId == 0 means environment kill (server fills 0 for nil killer).
	if userId == 0 then
		return NEUTRAL_NAME_COLOR
	end

	local p = Players:GetPlayerByUserId(userId)
	if p and p.Team and not p.Neutral then
		return p.Team.TeamColor.Color
	end
	return NEUTRAL_NAME_COLOR
end

local function trimToCap()
	while #activeEntries > MAX_VISIBLE_ENTRIES do
		local oldest = table.remove(activeEntries, 1)
		if oldest then
			oldest:Destroy()
		end
	end
end

local function fadeAndDestroy(entry: Frame)
	-- Tween every TextLabel inside + the entry's own background to 1.
	local tweenInfo = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	TweenService:Create(entry, tweenInfo, { BackgroundTransparency = 1 }):Play()
	for _, descendant in entry:GetDescendants() do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, tweenInfo, {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end
	end

	task.delay(FADE_DURATION, function()
		-- The entry might already have been trimmed by the cap.
		if entry.Parent then
			for i, e in activeEntries do
				if e == entry then
					table.remove(activeEntries, i)
					break
				end
			end
			entry:Destroy()
		end
	end)
end

local function buildLabel(text: string, color: Color3, font: Enum.Font, textSize: number, isLocalPlayer: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.new(0, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = textSize
	label.Text = text
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	if isLocalPlayer then
		label.TextStrokeColor3 = LOCAL_PLAYER_OUTLINE
		label.TextStrokeTransparency = 0.3
	else
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0.5
	end
	return label
end

----------------------------------------------------------------------
-- Entry construction
----------------------------------------------------------------------
local function addEntry(entryData)
	local killerId = entryData.killerId or 0
	local victimId = entryData.victimId or 0
	local killerName = entryData.killerName or ENVIRONMENT_LABEL
	local victimName = entryData.victimName or "Unknown"
	local weaponName = entryData.weaponName or "Unknown"

	-- Suicide / self-elim: server emits killerId == victimId. Render as
	-- environment-style so the line doesn't read "Player [Sword] Player".
	local isSelfElim = killerId ~= 0 and killerId == victimId
	local isEnvKill = killerId == 0 or isSelfElim

	local entry = Instance.new("Frame")
	entry.Name = "KillFeedEntry"
	entry.BackgroundColor3 = ENTRY_BG_COLOR
	entry.BackgroundTransparency = ENTRY_BG_TRANSPARENCY
	entry.BorderSizePixel = 0
	entry.AutomaticSize = Enum.AutomaticSize.X
	entry.Size = UDim2.new(0, 0, 0, ENTRY_HEIGHT)
	entry.LayoutOrder = nextLayoutOrder
	nextLayoutOrder += 1

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = entry

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.Parent = entry

	local rowPadding = Instance.new("UIPadding")
	rowPadding.PaddingLeft = UDim.new(0, 8)
	rowPadding.PaddingRight = UDim.new(0, 8)
	rowPadding.Parent = entry

	local order = 0
	local function add(label: TextLabel)
		order += 1
		label.LayoutOrder = order
		label.Parent = entry
	end

	if not isEnvKill then
		local killerColor = nameColorForUserId(killerId, entryData.killerTeamColor)
		add(buildLabel(killerName, killerColor, NAME_FONT, NAME_TEXT_SIZE, killerId == localPlayer.UserId))
	end

	-- Weapon / cause text: e.g. "[Rifle]" or "[Fall]" for env kills.
	local causeText = isSelfElim and "[Self-elim]" or string.format("[%s]", weaponName)
	add(buildLabel(causeText, WEAPON_TEXT_COLOR, WEAPON_FONT, WEAPON_TEXT_SIZE, false))

	local victimColor = nameColorForUserId(victimId, entryData.victimTeamColor)
	add(buildLabel(victimName, victimColor, NAME_FONT, NAME_TEXT_SIZE, victimId == localPlayer.UserId))

	entry.Parent = container
	table.insert(activeEntries, entry)
	trimToCap()

	task.delay(ENTRY_LIFETIME, function()
		if entry.Parent then
			fadeAndDestroy(entry)
		end
	end)
end

----------------------------------------------------------------------
-- Hookup
----------------------------------------------------------------------
killFeedRemote.OnClientEvent:Connect(addEntry)

log:info("Initialized")
