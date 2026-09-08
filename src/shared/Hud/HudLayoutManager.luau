----------------------------------------------------------------------
-- HudLayoutManager
----------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudConstants = require(script.Parent.HudConstants)
local HudGate = require(script.Parent.HudGate)
local InputCategorizer = require(ReplicatedStorage.Shared.Core.InputCategorizer)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("HudLayout")

local player = Players.LocalPlayer

local HudLayoutManager = {}
HudLayoutManager._initialized = false
HudLayoutManager._screenGui = nil :: ScreenGui?
HudLayoutManager._regions = {} :: { [string]: Frame }
HudLayoutManager._uiScale = nil :: UIScale?

function HudLayoutManager:_init()
	if self._initialized then
		return
	end
	self._initialized = true

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HudGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = HudConstants.HUD_DISPLAY_ORDER
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = player.PlayerGui
	self._screenGui = screenGui

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = screenGui
	self._uiScale = uiScale

	for regionName, config in HudConstants.REGIONS do
		local region = Instance.new("Frame")
		region.Name = regionName
		region.Position = config.Position
		region.AnchorPoint = config.AnchorPoint
		region.Size = config.Size
		region.AutomaticSize = config.AutomaticSize
		region.BackgroundTransparency = 1
		region.BorderSizePixel = 0
		region.ZIndex = config.ZIndex
		region.Parent = screenGui

		if (config :: any).stackVertical then
			local layout = Instance.new("UIListLayout")
			layout.FillDirection = Enum.FillDirection.Vertical
			layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
			layout.HorizontalAlignment = (config :: any).stackHorizontalAlign or Enum.HorizontalAlignment.Right
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0, (config :: any).stackPadding or 8)
			layout.Parent = region
		end

		self._regions[regionName] = region
	end

	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_updateScale()
	end)

	self:_updateScale()
	log:info("Initialized with " .. tostring(#self:_getRegionNames()) .. " regions")
end

function HudLayoutManager:_updateScale()
	local gui = self._screenGui
	if not gui then
		return
	end

	if self._uiScale then
		local scale = gui.AbsoluteSize.Y / HudConstants.REFERENCE_HEIGHT
		self._uiScale.Scale = math.max(scale, HudConstants.MIN_SCALE)
	end
end

function HudLayoutManager:getRegion(regionName: string): Frame
	self:_init()

	local region = self._regions[regionName]
	if not region then
		log:warn("Unknown region: " .. regionName)
	end
	return region
end

-- `policy` is **required**. Every HUD element has to declare what it does
-- in the lobby, because the failure mode is silent: an element that
-- wrongly hides is reported in the first playtest, an element that wrongly
-- shows in the lobby is a wart nobody files. Making the argument
-- mandatory breaks all nine existing call sites on purpose — each one
-- became a deliberate decision. See [[concepts/HudGate]].
function HudLayoutManager:register(regionName: string, element: GuiObject, policy: HudGate.Policy)
	assert(policy ~= nil,
		"HudLayoutManager:register requires a HudGate policy (Always / ArenaOnly / LobbyOnly) for " .. element.Name)

	local region = self:getRegion(regionName)
	if region then
		element.Parent = region
		HudGate.bindElement(element, policy)
	end
end

function HudLayoutManager:getScreenGui(): ScreenGui
	self:_init()
	return self._screenGui :: ScreenGui
end

function HudLayoutManager:isTouch(): boolean
	return InputCategorizer.getLastInputCategory() == InputCategorizer.InputCategory.Touch
end

function HudLayoutManager:_getRegionNames(): { string }
	local names = {}
	for name in self._regions do
		table.insert(names, name)
	end
	return names
end

return HudLayoutManager
