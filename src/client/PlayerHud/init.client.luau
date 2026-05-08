----------------------------------------------------------------------
-- PlayerHud (entry)
----------------------------------------------------------------------
-- Assembles the local player's attribute-bar stack from PlayerHudConfig.
-- For each entry:
--   1. Build an AttributeBar visual via AttributeBarBuilder
--   2. Parent it to a stacking container in the configured HUD region
--   3. Attach the corresponding adapter, which wires the data source
--
-- On CharacterAdded: tear down adapters, rebuild bars (bars stay),
-- re-attach adapters to the new character.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttributeBarBuilder = require(ReplicatedStorage.Shared.Hud.AttributeBarBuilder)
local AttributeBarConfig = require(ReplicatedStorage.Shared.Hud.AttributeBarConfig)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local player = Players.LocalPlayer
local PlayerHudConfig = require(script.PlayerHudConfig)

local log = Logger.new("PlayerHud")

-- Per-entry state: { bar = AttributeBar handle, adapter = Adapter? }
type Slot = { bar: any, adapter: any? }
local slots: { [string]: Slot } = {}

local stackContainer: Frame? = nil

local function ensureStackContainer(): Frame
	if stackContainer and stackContainer.Parent then
		return stackContainer
	end

	-- Dedicated container so we don't force a UIListLayout onto the shared
	-- region (other HUD elements may want to position differently there).
	local frame = Instance.new("Frame")
	frame.Name = "PlayerAttributeStack"
	frame.Size = UDim2.new(0, AttributeBarConfig.BAR_WIDTH, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	-- Bottom-up stacking: first bar in config ends up at the bottom, matching
	-- "Health is the most critical; put it closest to the player's eye"
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, AttributeBarConfig.BAR_SPACING)
	layout.Parent = frame

	HudLayoutManager:register(PlayerHudConfig.region, frame)
	stackContainer = frame
	return frame
end

local function buildBars()
	local stack = ensureStackContainer()

	for index, entry in PlayerHudConfig.bars do
		local bar = AttributeBarBuilder.build({
			name = entry.name,
			color = entry.color,
			warningColor = entry.warningColor,
			criticalColor = entry.criticalColor,
		})
		-- Higher LayoutOrder = lower on screen (VerticalAlignment = Bottom, SortOrder by LayoutOrder).
		-- Put Health last in config → LayoutOrder = #bars → ends up at the very bottom.
		bar.gui.LayoutOrder = index
		bar.gui.Parent = stack
		slots[entry.name] = { bar = bar, adapter = nil }
	end
end

local function teardownAdapters()
	for _, slot in slots do
		if slot.adapter then
			slot.adapter:destroy()
			slot.adapter = nil
		end
	end
end

local function attachAdaptersFor(character: Model)
	teardownAdapters()
	for _, entry in PlayerHudConfig.bars do
		local slot = slots[entry.name]
		if not slot then
			continue
		end
		local ok, adapterOrErr = pcall(function()
			return entry.adapter.new(character, slot.bar)
		end)
		if ok then
			slot.adapter = adapterOrErr
		else
			log:warn(string.format("adapter '%s' failed: %s", entry.name, tostring(adapterOrErr)))
		end
	end
end

local function initialize()
	buildBars()

	if player.Character then
		attachAdaptersFor(player.Character)
	end
	player.CharacterAdded:Connect(attachAdaptersFor)

	log:info(string.format("Initialized with %d bars in region '%s'",
		#PlayerHudConfig.bars, PlayerHudConfig.region))
end

initialize()
