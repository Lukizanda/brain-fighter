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

-- BottomRight column geometry (screen margin + SpellMenu↔DASH gap) is
-- owned by HudConstants.REGIONS.BottomRight, applied by HudLayoutManager.

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
