----------------------------------------------------------------------
-- HudLayoutManager
----------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudConstants = require(script.Parent.HudConstants)
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
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0, 8)
			layout.Parent = region
		end

		self._regions[regionName] = region
	end

	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_updateScale()
	end)

	InputCategorizer.lastInputCategoryChanged:Connect(function()
		self:_onInputCategoryChanged()
	end)

	self:_updateScale()
	log:info("Initialized with " .. tostring(#self:_getRegionNames()) .. " regions")
end

function HudLayoutManager:_updateScale()
	local gui = self._screenGui
	if not gui then
		return
	end

	local minDimension = math.min(gui.AbsoluteSize.X, gui.AbsoluteSize.Y)
	local isSmall = minDimension < HudConstants.SMALL_SCREEN_THRESHOLD

	if self._uiScale then
		self._uiScale.Scale = if isSmall then HudConstants.SMALL_SCREEN_SCALE else 1
	end
end

function HudLayoutManager:_onInputCategoryChanged()
end

function HudLayoutManager:getRegion(regionName: string): Frame
	self:_init()

	local region = self._regions[regionName]
	if not region then
		log:warn("Unknown region: " .. regionName)
	end
	return region
end

function HudLayoutManager:register(regionName: string, element: GuiObject)
	local region = self:getRegion(regionName)
	if region then
		element.Parent = region
	end
end

function HudLayoutManager:unregister(element: GuiObject)
	element.Parent = nil
end

function HudLayoutManager:moveToRegion(element: GuiObject, newRegionName: string)
	local region = self:getRegion(newRegionName)
	if region then
		element.Parent = region
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
