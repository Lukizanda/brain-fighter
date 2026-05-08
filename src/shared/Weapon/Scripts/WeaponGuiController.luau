local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Shared.Weapon.Constants)
local disconnectAndClear = require(ReplicatedStorage.Utility.disconnectAndClear)
local playSoundFromSource = require(ReplicatedStorage.Shared.Weapon.Scripts.Utility.playSoundFromSource)
local HudConstants = require(ReplicatedStorage.Shared.Hud.HudConstants)
local ReticleBuilder = require(ReplicatedStorage.Shared.Hud.ReticleBuilder)

local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local hitmarkerSound = script.Hitmarker
local audioTarget = SoundService.Audio.Busses.UI.AudioCompressor

-- Owns the per-weapon reticle (crosshair + hitmarker + spread). The
-- ammo counter used to live here too via a WeaponPanel builder; that
-- was removed because the WeaponRolodex now renders ammo in-card and
-- the big panel was redundant.
local WeaponGuiController = {}
WeaponGuiController.__index = WeaponGuiController

function WeaponGuiController.new(blaster: Tool)
	-- Reticle needs its own ScreenGui with IgnoreGuiInset = true so the
	-- crosshair aligns with the true viewport center (where the camera ray goes)
	local reticleScreenGui = Instance.new("ScreenGui")
	reticleScreenGui.Name = "ReticleGui"
	reticleScreenGui.ResetOnSpawn = false
	reticleScreenGui.IgnoreGuiInset = true
	reticleScreenGui.DisplayOrder = HudConstants.HUD_DISPLAY_ORDER + 1
	reticleScreenGui.Enabled = false
	reticleScreenGui.Parent = playerGui

	local reticleHandle = ReticleBuilder.build()
	reticleHandle.gui.Parent = reticleScreenGui

	local self = {
		blaster = blaster,
		reticleScreenGui = reticleScreenGui,
		reticleHandle = reticleHandle,
		enabled = false,
		connections = {},
	}
	setmetatable(self, WeaponGuiController)
	return self
end

-- Ammo / reload methods kept as no-ops so existing FirearmController
-- calls continue to work without churn. UI for ammo now flows via
-- WeaponRolodex's _ammo / _reserveAmmo attribute subscriptions.
function WeaponGuiController:setAmmo(_ammo: number) end
function WeaponGuiController:setReloading(_reloading: boolean) end
function WeaponGuiController:setReserveAmmo(_reserve: number?) end

function WeaponGuiController:showHitmarker()
	-- Slightly delay the hitmarker sound so it doesn't overlap the shooting sound
	task.delay(Constants.HITMARKER_SOUND_DELAY, function()
		playSoundFromSource(hitmarkerSound, audioTarget)
	end)

	self.reticleHandle:showHitmarker()
end

function WeaponGuiController:setSpread(normalized: number)
	self.reticleHandle:setSpread(normalized)
end

function WeaponGuiController:enable()
	if self.enabled then
		return
	end
	self.enabled = true
	self.reticleScreenGui.Enabled = true
end

function WeaponGuiController:disable()
	if not self.enabled then
		return
	end
	self.enabled = false
	self.reticleScreenGui.Enabled = false
end

function WeaponGuiController:destroy()
	self:disable()
	disconnectAndClear(self.connections)
	self.reticleHandle:destroy()
	self.reticleScreenGui:Destroy()
end

return WeaponGuiController
