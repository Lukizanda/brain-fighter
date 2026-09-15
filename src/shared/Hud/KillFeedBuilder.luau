----------------------------------------------------------------------
-- KillFeedBuilder
----------------------------------------------------------------------
-- View-only builder for the top-right kill feed strip:
--    Player1 [Rifle] Player2
-- Names are tinted by the killer/victim's current Team.TeamColor (FFA
-- leaves both neutral). Entries fade out after a fixed lifetime; the
-- strip caps at a small number of visible entries and trims the oldest
-- off the top. Contains no remote wiring — KillFeedGui listens to the
-- GameMode KillFeed RemoteEvent and calls `addEntry`.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local KillFeedConfig = require(script.Parent.KillFeedConfig)

export type KillFeedEntryData = {
	killerId: number?,
	victimId: number?,
	killerName: string?,
	victimName: string?,
	weaponName: string?,
	killerTeamColor: Color3?,
	victimTeamColor: Color3?,
}

export type KillFeed = {
	container: Frame,
	addEntry: (self: KillFeed, entryData: KillFeedEntryData, localUserId: number) -> (),
	destroy: (self: KillFeed) -> (),
}

local KillFeedBuilder = {}

local function nameColorForUserId(userId: number, override: Color3?): Color3
	-- Server can pass an explicit override (used for non-Player entries
	-- like dev bots or NPCs that have a logical team but no real Player).
	if override then
		return override
	end
	-- userId == 0 means environment kill (server fills 0 for nil killer).
	if userId == 0 then
		return KillFeedConfig.NEUTRAL_NAME_COLOR
	end

	local p = Players:GetPlayerByUserId(userId)
	if p and p.Team and not p.Neutral then
		return p.Team.TeamColor.Color
	end
	return KillFeedConfig.NEUTRAL_NAME_COLOR
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
		label.TextStrokeColor3 = KillFeedConfig.LOCAL_PLAYER_OUTLINE
		label.TextStrokeTransparency = 0.3
	else
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0.5
	end
	return label
end

function KillFeedBuilder.build(): KillFeed
	local container = Instance.new("Frame")
	container.Name = "KillFeed"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, KillFeedConfig.ENTRY_PADDING)
	layout.Parent = container

	local nextLayoutOrder = 0
	local activeEntries: { Frame } = {}

	local function trimToCap()
		while #activeEntries > KillFeedConfig.MAX_VISIBLE_ENTRIES do
			local oldest = table.remove(activeEntries, 1)
			if oldest then
				oldest:Destroy()
			end
		end
	end

	local function fadeAndDestroy(entry: Frame)
		local tweenInfo = TweenInfo.new(KillFeedConfig.FADE_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		TweenService:Create(entry, tweenInfo, { BackgroundTransparency = 1 }):Play()
		for _, descendant in entry:GetDescendants() do
			if descendant:IsA("TextLabel") then
				TweenService:Create(descendant, tweenInfo, {
					TextTransparency = 1,
					TextStrokeTransparency = 1,
				}):Play()
			end
		end

		task.delay(KillFeedConfig.FADE_DURATION, function()
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

	local handle: KillFeed = {
		container = container,
		addEntry = function(_self, entryData: KillFeedEntryData, localUserId: number)
			local killerId = entryData.killerId or 0
			local victimId = entryData.victimId or 0
			local killerName = entryData.killerName or KillFeedConfig.ENVIRONMENT_LABEL
			local victimName = entryData.victimName or "Unknown"
			local weaponName = entryData.weaponName or "Unknown"

			-- Suicide / self-elim: server emits killerId == victimId. Render as
			-- environment-style so the line doesn't read "Player [Sword] Player".
			local isSelfElim = killerId ~= 0 and killerId == victimId
			local isEnvKill = killerId == 0 or isSelfElim

			local entry = Instance.new("Frame")
			entry.Name = "KillFeedEntry"
			entry.BackgroundColor3 = KillFeedConfig.ENTRY_BG_COLOR
			entry.BackgroundTransparency = KillFeedConfig.ENTRY_BG_TRANSPARENCY
			entry.BorderSizePixel = 0
			entry.AutomaticSize = Enum.AutomaticSize.X
			entry.Size = UDim2.new(0, 0, 0, KillFeedConfig.ENTRY_HEIGHT)
			entry.LayoutOrder = nextLayoutOrder
			nextLayoutOrder += 1

			local corner = Instance.new("UICorner")
			corner.CornerRadius = KillFeedConfig.ENTRY_CORNER_RADIUS
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
				add(buildLabel(killerName, killerColor, KillFeedConfig.NAME_FONT, KillFeedConfig.NAME_TEXT_SIZE, killerId == localUserId))
			end

			-- Weapon / cause text: e.g. "[Rifle]" or "[Fall]" for env kills.
			local causeText = isSelfElim and "[Self-elim]" or string.format("[%s]", weaponName)
			add(buildLabel(causeText, KillFeedConfig.WEAPON_TEXT_COLOR, KillFeedConfig.WEAPON_FONT, KillFeedConfig.WEAPON_TEXT_SIZE, false))

			local victimColor = nameColorForUserId(victimId, entryData.victimTeamColor)
			add(buildLabel(victimName, victimColor, KillFeedConfig.NAME_FONT, KillFeedConfig.NAME_TEXT_SIZE, victimId == localUserId))

			entry.Parent = container
			table.insert(activeEntries, entry)
			trimToCap()

			task.delay(KillFeedConfig.ENTRY_LIFETIME, function()
				if entry.Parent then
					fadeAndDestroy(entry)
				end
			end)
		end,
		destroy = function(self)
			self.container:Destroy()
		end,
	}

	return handle
end

return KillFeedBuilder
