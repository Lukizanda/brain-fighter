--!strict
----------------------------------------------------------------------
-- DashButtonGui
----------------------------------------------------------------------
-- Mounts the mobile dash button in the BottomRight vertical column,
-- directly above the native Roblox jump button (LayoutOrder = 1,
-- SpellMenu = 2). Visible only on touch input.
-- Tap → _G.BrainFighter.requestDash() → DashController:trigger().
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger            = require(ReplicatedStorage.Shared.Core.Logger)
local HudLayoutManager  = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local DashButtonBuilder = require(ReplicatedStorage.Shared.Hud.DashButtonBuilder)
local DashButtonConfig  = require(ReplicatedStorage.Shared.Hud.DashButtonConfig)
local InputCategorizer  = require(ReplicatedStorage.Shared.Core.InputCategorizer)

local log = Logger.new("DashButtonGui")

local DASH_REGION = "BottomRight"

local dashButton = DashButtonBuilder.build()
dashButton.gui.LayoutOrder = DashButtonConfig.LAYOUT_ORDER
HudLayoutManager:register(DASH_REGION, dashButton.gui)

-- Apply spacing config directly onto the region so both values are
-- the sole source of truth (UIPadding on the container would affect
-- children, not external spacing).
local region = HudLayoutManager:getRegion(DASH_REGION)
local regionLayout = region:FindFirstChildOfClass("UIListLayout")
if regionLayout then
	regionLayout.Padding = UDim.new(0, DashButtonConfig.SPELL_GAP)
end
region.Position = UDim2.new(1, -20, 1, -DashButtonConfig.BOTTOM_MARGIN)

local function updateVisible()
	dashButton.gui.Visible = HudLayoutManager:isTouch()
end

updateVisible()
InputCategorizer.lastInputCategoryChanged:Connect(updateVisible)

dashButton.activated:Connect(function()
	local api = _G.BrainFighter
	if api and api.requestDash then
		api.requestDash()
	else
		log:warn("dash tapped but _G.BrainFighter.requestDash unavailable")
	end
end)

_G.PlayerHud = _G.PlayerHud or {}
_G.PlayerHud.DashButton = dashButton

log:info("Initialized")
