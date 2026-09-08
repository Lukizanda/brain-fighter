--!strict
----------------------------------------------------------------------
-- DashButtonGui
----------------------------------------------------------------------
-- Mounts the mobile dash button in the BottomRight vertical column,
-- directly above the native Roblox jump button (LayoutOrder = 1,
-- SpellMenu = 2). Visible only on touch input.
-- Tap → DashApi.requestDash() → DashController:trigger().
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger            = require(ReplicatedStorage.Shared.Core.Logger)
local HudLayoutManager  = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local DashButtonBuilder = require(ReplicatedStorage.Shared.Hud.DashButtonBuilder)
local DashButtonConfig  = require(ReplicatedStorage.Shared.Hud.DashButtonConfig)
local InputCategorizer  = require(ReplicatedStorage.Shared.Core.InputCategorizer)
local HudGate           = require(ReplicatedStorage.Shared.Hud.HudGate)
local DashApi           = require(script.Parent.Parent.DashApi)

local log = Logger.new("DashButtonGui")

local DASH_REGION = "BottomRight"

local dashButton = DashButtonBuilder.build()
dashButton.gui.LayoutOrder = DashButtonConfig.LAYOUT_ORDER
HudLayoutManager:register(DASH_REGION, dashButton.gui, HudGate.Policy.Always)

-- BottomRight column geometry (screen margin + SpellMenu↔DASH gap) is
-- owned by HudConstants.REGIONS.BottomRight, applied by HudLayoutManager.

local function updateVisible()
	dashButton.gui.Visible = HudLayoutManager:isTouch()
end

updateVisible()
InputCategorizer.lastInputCategoryChanged:Connect(updateVisible)

dashButton.activated:Connect(function()
	if not DashApi.requestDash() then
		log:warn("dash tapped but no dash provider is registered")
	end
end)

log:info("Initialized")
