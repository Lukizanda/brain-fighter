--!strict

----------------------------------------------------------------------
-- BossHudGui
----------------------------------------------------------------------
-- Boss health bar + phase indicator mounted in its own ScreenGui.
-- Listens to BossHealthChanged and BossPhaseChanged RemoteEvents from
-- BossService.
--
-- Hidden until a boss spawns (BossPhaseChanged fires with index ≥ 1).
-- Hides again when the boss is defeated (phase index = 0).
-- On load, checks Workspace for an existing Boss model so the HUD
-- is correct if the player joins mid-fight.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local Logger            = require(ReplicatedStorage.Shared.Core.Logger)
local HudConstants       = require(ReplicatedStorage.Shared.Hud.HudConstants)
local HudGate            = require(ReplicatedStorage.Shared.Hud.HudGate)
local HudLayoutManager   = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local BossHudBuilder     = require(ReplicatedStorage.Shared.Hud.BossHudBuilder)
local BossHudConfig      = require(ReplicatedStorage.Shared.Hud.BossHudConfig)

local bossEvents        = ReplicatedStorage.Shared.Boss.BossEvents
local BossHealthChanged = bossEvents.BossHealthChanged :: RemoteEvent
local BossPhaseChanged  = bossEvents.BossPhaseChanged  :: RemoteEvent

local log = Logger.new("BossHudGui")

-- ---------------------------------------------------------------
-- GUI Construction
-- ---------------------------------------------------------------

local handle = BossHudBuilder.build()
-- Own ScreenGui so we can use IgnoreGuiInset=true and sit flush at the
-- top of the screen where the round timer used to live.
handle.screenGui.DisplayOrder = HudConstants.LAYERS.Overlay
handle.screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Round and competition chrome: no meaning in the hub.
HudGate.bindScreenGui(handle.screenGui, HudGate.Policy.ArenaOnly)
HudLayoutManager:attachScale(handle.screenGui)

-- ---------------------------------------------------------------
-- Debug hotkey
-- ---------------------------------------------------------------

local phaseDebugVisible = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == BossHudConfig.PHASE_DEBUG_KEY then
		phaseDebugVisible = not phaseDebugVisible
		handle.phaseLabel.Visible = phaseDebugVisible
		log:info("phase label " .. (phaseDebugVisible and "ON" or "OFF"))
	end
end)

-- ---------------------------------------------------------------
-- Remote event connections
-- ---------------------------------------------------------------

BossHealthChanged.OnClientEvent:Connect(function(
	currentHP: number,
	maxHP: number,
	phaseIndex: number
)
	if phaseIndex == 0 then
		-- Boss defeated
		handle:setShown(false)
		return
	end

	handle:setShown(true)
	local fraction = if maxHP > 0 then currentHP / maxHP else 0
	handle:setHealthFraction(fraction)
	handle:setPhase(phaseIndex)
end)

BossPhaseChanged.OnClientEvent:Connect(function(phaseIndex: number)
	if phaseIndex == 0 then
		handle:setShown(false)
	else
		handle:setShown(true)
		handle:setPhase(phaseIndex)
	end
end)

-- ---------------------------------------------------------------
-- Late-join: initialize from existing boss in Workspace
-- ---------------------------------------------------------------
local function tryInitFromExistingBoss()
	local boss = workspace:FindFirstChild("Boss")
	if not boss or not boss:IsA("Model") then return end

	local humanoid = boss:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local fraction = if humanoid.MaxHealth > 0
		then humanoid.Health / humanoid.MaxHealth
		else 0

	handle:setShown(true)
	handle:setHealthFraction(fraction)
	-- Phase index unknown without RemoteEvent; default to 1
	handle:setPhase(1)

	log:info(string.format("Late-joined with existing boss (HP %.0f/%.0f)",
		humanoid.Health, humanoid.MaxHealth))
end

tryInitFromExistingBoss()
