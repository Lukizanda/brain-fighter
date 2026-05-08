----------------------------------------------------------------------
-- DamageFeedbackGui
----------------------------------------------------------------------
-- Full-screen red flash when the local player takes damage. Reads from
-- the server-broadcast DamageFeedback remote (already populated by
-- HealthService). Intentionally **not** tied to any attribute bar — it
-- reacts to the damage event, not the Health value change, so it fires
-- even on shield/armor hits once those damage types are wired.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("DamageFeedback")

local player = Players.LocalPlayer
local damageFeedbackRemote = ReplicatedStorage.Shared.Health.Remotes.DamageFeedback

local FLASH_IN = TweenInfo.new(0, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
local FLASH_OUT = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DamageFeedbackGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 20 -- above attribute bars, below death screen
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Active = false
overlay.Parent = screenGui

damageFeedbackRemote.OnClientEvent:Connect(function(data: { [string]: any })
	-- Snap to visible, then fade. Intensity scales with damage so big hits feel bigger.
	local intensity = math.clamp((data.finalDamage or 0) / 50, 0.2, 0.6)
	TweenService:Create(overlay, FLASH_IN, { BackgroundTransparency = 1 - intensity }):Play()
	task.wait(0.05)
	TweenService:Create(overlay, FLASH_OUT, { BackgroundTransparency = 1 }):Play()

	log:info(string.format("Took %d %s damage%s",
		data.finalDamage or 0,
		data.damageType or "Unknown",
		data.wasLethal and " [LETHAL]" or ""
	))
end)

log:info("Initialized")
