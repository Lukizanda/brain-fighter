--!strict

----------------------------------------------------------------------
-- SettingsGui
----------------------------------------------------------------------
-- Coordinator for the settings surface: a gear button in the hub's
-- TopRight stack and a panel over the centre of the screen. Both are
-- `LobbyOnly` — settings live on the hub wall next to the portals, and
-- HudGate turns them off the moment the player enters an arena.
--
-- The panel is a view. Every change it asks for goes through
-- `Settings.write`, which normalizes it and lands it on the LocalPlayer
-- as an attribute; the panel is then painted from what was *stored*,
-- so a dragged 43 reads back as 45 and the knob snaps with it. What a
-- setting does is not this file's business — `SettingsController` owns
-- the sound group and the palette, `spawnEffect` / `ScreenImpact` read
-- the reduced flag themselves.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudConstants = require(ReplicatedStorage.Shared.Hud.HudConstants)
local HudGate = require(ReplicatedStorage.Shared.Hud.HudGate)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Settings = require(ReplicatedStorage.Shared.Settings)
local SettingsBuilder = require(ReplicatedStorage.Shared.Hud.SettingsBuilder)

local log = Logger.new("SettingsGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local holder = Settings.localHolder()
local K = Settings.Keys

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------

local gear = SettingsBuilder.buildGear()
HudLayoutManager:register("TopRight", gear.gui, HudGate.Policy.LobbyOnly)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SettingsGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = HudConstants.LAYERS.Modal
screenGui.Parent = playerGui
HudLayoutManager:attachScale(screenGui)
HudGate.bindScreenGui(screenGui, HudGate.Policy.LobbyOnly)

local panel = SettingsBuilder.build()
panel.gui.Parent = screenGui

----------------------------------------------------------------------
-- Stored value → panel
----------------------------------------------------------------------

local function paintFromStore()
	panel:setSfxVolume(Settings.read(holder, K.SfxVolume))
	panel:setReducedVfx(Settings.read(holder, K.ReducedVfx))
	panel:setPalette(Settings.read(holder, K.Palette))
end

paintFromStore()

-- Anything else that writes a setting (a debug hotkey, a future
-- persistence load) shows up on the panel without the panel knowing who.
for _, key in Settings.ORDERED_KEYS do
	Settings.changed(holder, key):Connect(paintFromStore)
end

----------------------------------------------------------------------
-- Panel → store
----------------------------------------------------------------------

panel.sfxVolumeChanged:Connect(function(volume: number)
	local stored = Settings.write(holder, K.SfxVolume, volume)
	-- Paint from the stored value even when the write was a no-op, so
	-- the knob snaps to the step while the pointer is still moving.
	panel:setSfxVolume(stored)
end)

panel.reducedVfxChanged:Connect(function(enabled: boolean)
	Settings.write(holder, K.ReducedVfx, enabled)
end)

panel.paletteChanged:Connect(function(name: string)
	Settings.write(holder, K.Palette, name)
end)

----------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------

gear.activated:Connect(function()
	panel:setShown(not panel:isShown())
end)

panel.closed:Connect(function()
	panel:setShown(false)
end)

-- Leaving the hub closes the panel rather than parking it open behind
-- the gate, so coming back does not greet the player with last visit's
-- panel.
HudGate.stateChanged:Connect(function()
	panel:setShown(false)
end)

log:info(string.format("ready — sfx=%d reduced=%s palette=%s",
	Settings.read(holder, K.SfxVolume), tostring(Settings.read(holder, K.ReducedVfx)),
	tostring(Settings.read(holder, K.Palette))))
