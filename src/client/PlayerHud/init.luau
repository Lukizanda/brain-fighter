--!strict
----------------------------------------------------------------------
-- PlayerHud (module)
----------------------------------------------------------------------
-- Builds the attribute-bar stack. Does NOT register with HudLayoutManager
-- or connect CharacterAdded — the coordinator (GameplayHudGui) owns those.
--
-- Public API:
--   PlayerHud.build()              → Frame  (PlayerAttributeStack)
--   PlayerHud.attachAdapters(char) → nil
--   PlayerHud.teardownAdapters()   → nil
----------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttributeBarBuilder = require(ReplicatedStorage.Shared.Hud.AttributeBarBuilder)
local AttributeBarConfig  = require(ReplicatedStorage.Shared.Hud.AttributeBarConfig)
local Logger              = require(ReplicatedStorage.Shared.Core.Logger)
local PlayerHudConfig     = require(script.PlayerHudConfig)

local log = Logger.new("PlayerHud")

type Slot = { bar: any, adapter: any? }
local slots: { [string]: Slot } = {}
local stackContainer: Frame? = nil

local function buildBars(stack: Frame)
	for index, entry in PlayerHudConfig.bars do
		local bar = AttributeBarBuilder.build({
			name          = entry.name,
			color         = entry.color,
			warningColor  = entry.warningColor,
			criticalColor = entry.criticalColor,
		})
		bar.gui.LayoutOrder = index
		bar.gui.Parent = stack
		slots[entry.name] = { bar = bar, adapter = nil }
	end
end

local PlayerHud = {}

function PlayerHud.build(): Frame
	if stackContainer and stackContainer.Parent then
		return stackContainer
	end
	local frame = Instance.new("Frame")
	frame.Name = "PlayerAttributeStack"
	frame.Size = UDim2.new(0, 400, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	-- LayoutOrder intentionally not set here; coordinator assigns it from LAYOUT.

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, AttributeBarConfig.BAR_SPACING)
	layout.Parent = frame

	buildBars(frame)
	stackContainer = frame
	log:info(string.format("Built %d bars", #PlayerHudConfig.bars))
	return frame
end

function PlayerHud.attachAdapters(character: Model)
	PlayerHud.teardownAdapters()
	for _, entry in PlayerHudConfig.bars do
		local slot = slots[entry.name]
		if not slot then continue end
		local ok, result = pcall(function()
			return entry.adapter.new(character, slot.bar)
		end)
		if ok then
			slot.adapter = result
		else
			log:warn(string.format("adapter '%s' failed: %s", entry.name, tostring(result)))
		end
	end
end

function PlayerHud.teardownAdapters()
	for _, slot in slots do
		if slot.adapter then
			slot.adapter:destroy()
			slot.adapter = nil
		end
	end
end

return PlayerHud
