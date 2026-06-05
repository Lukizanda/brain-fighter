----------------------------------------------------------------------
-- SettingsMenuGui (client entry point)
----------------------------------------------------------------------
-- Wires the Escape keybind to open/close the settings menu.
-- Pauses mouse lock while the menu is open.
-- Applies settings immediately via player attributes for persistence
-- and direct runtime updates.
----------------------------------------------------------------------
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local log = Logger.new("SettingsMenuGui")

local SettingsMenuBuilder = require(ReplicatedStorage.Shared.Hud.SettingsMenuBuilder)
local SettingsMenuConfig = require(ReplicatedStorage.Shared.Hud.SettingsMenuConfig)

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- Player attributes for persistence across respawns
----------------------------------------------------------------------

local ATTR_SENSITIVITY = "Settings_Sensitivity"
local ATTR_FOV = "Settings_FieldOfView"
local ATTR_CROSSHAIR_R = "Settings_CrosshairR"
local ATTR_CROSSHAIR_G = "Settings_CrosshairG"
local ATTR_CROSSHAIR_B = "Settings_CrosshairB"
local ATTR_AIM_ASSIST = "Settings_AimAssist"

local function loadDefaults()
	-- Only set defaults if attributes don't already exist
	if player:GetAttribute(ATTR_SENSITIVITY) == nil then
		player:SetAttribute(ATTR_SENSITIVITY, SettingsMenuConfig.SENSITIVITY_DISPLAY_DEFAULT)
	end
	if player:GetAttribute(ATTR_FOV) == nil then
		player:SetAttribute(ATTR_FOV, SettingsMenuConfig.DEFAULT_FIELD_OF_VIEW)
	end
	if player:GetAttribute(ATTR_CROSSHAIR_R) == nil then
		local c = SettingsMenuConfig.DEFAULT_CROSSHAIR_COLOR
		player:SetAttribute(ATTR_CROSSHAIR_R, math.round(c.R * 255))
		player:SetAttribute(ATTR_CROSSHAIR_G, math.round(c.G * 255))
		player:SetAttribute(ATTR_CROSSHAIR_B, math.round(c.B * 255))
	end
	if player:GetAttribute(ATTR_AIM_ASSIST) == nil then
		player:SetAttribute(ATTR_AIM_ASSIST, SettingsMenuConfig.DEFAULT_AIM_ASSIST)
	end
end

----------------------------------------------------------------------
-- Mouse lock management
----------------------------------------------------------------------

local savedMouseBehavior: Enum.MouseBehavior = Enum.MouseBehavior.LockCenter
local savedMouseIconEnabled: boolean = false

local function pauseMouseLock()
	savedMouseBehavior = UserInputService.MouseBehavior
	savedMouseIconEnabled = UserInputService.MouseIconEnabled
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

local function restoreMouseLock()
	UserInputService.MouseBehavior = savedMouseBehavior
	UserInputService.MouseIconEnabled = savedMouseIconEnabled
end

----------------------------------------------------------------------
-- Build the menu
----------------------------------------------------------------------

local handle = SettingsMenuBuilder.build()
handle.gui.Parent = player.PlayerGui

----------------------------------------------------------------------
-- Wire callbacks — apply immediately and persist to attributes
----------------------------------------------------------------------

handle.callbacks.onSensitivityChanged = function(displayValue: number, _rawValue: number)
	player:SetAttribute(ATTR_SENSITIVITY, displayValue)
	log:info("Sensitivity changed to", displayValue)
end

handle.callbacks.onFieldOfViewChanged = function(fov: number)
	player:SetAttribute(ATTR_FOV, fov)
	log:info("FOV changed to", fov)
end

handle.callbacks.onCrosshairColorChanged = function(color: Color3)
	player:SetAttribute(ATTR_CROSSHAIR_R, math.round(color.R * 255))
	player:SetAttribute(ATTR_CROSSHAIR_G, math.round(color.G * 255))
	player:SetAttribute(ATTR_CROSSHAIR_B, math.round(color.B * 255))
	log:info("Crosshair color changed")
end

handle.callbacks.onAimAssistChanged = function(enabled: boolean)
	player:SetAttribute(ATTR_AIM_ASSIST, enabled)
	log:info("Aim assist changed to", tostring(enabled))
end

----------------------------------------------------------------------
-- Keybind: Escape to toggle
----------------------------------------------------------------------

-- We need to handle Escape carefully since Roblox uses it for the
-- default menu. We use GuiService to prevent the default Roblox menu
-- from opening when our settings menu is consuming the Escape key.

local connections: { RBXScriptConnection } = {}

table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode ~= SettingsMenuConfig.TOGGLE_KEY then
		return
	end

	-- If the Roblox menu is open, let the engine handle it
	if GuiService.MenuIsOpen then
		return
	end

	-- Toggle — always respond to the keybind regardless of gameProcessed,
	-- since P isn't used by other systems
	if handle:isVisible() then
		handle:close()
		restoreMouseLock()
	else
		pauseMouseLock()
		handle:open()
	end
end))

----------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------

loadDefaults()
log:info("Initialized")
