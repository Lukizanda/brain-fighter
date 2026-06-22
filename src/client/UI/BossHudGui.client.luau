--!strict

----------------------------------------------------------------------
-- BossHudGui
----------------------------------------------------------------------
-- Boss health bar + phase indicator mounted in the TopCenter HUD
-- region. Listens to BossHealthChanged and BossPhaseChanged
-- RemoteEvents from BossService.
--
-- Hidden until a boss spawns (BossPhaseChanged fires with index ≥ 1).
-- Hides again when the boss is defeated (phase index = 0).
-- On load, checks Workspace for an existing Boss model so the HUD
-- is correct if the player joins mid-fight.
----------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local Logger           = require(ReplicatedStorage.Shared.Core.Logger)

local bossEvents        = ReplicatedStorage.Shared.Boss.BossEvents
local BossHealthChanged = bossEvents.BossHealthChanged :: RemoteEvent
local BossPhaseChanged  = bossEvents.BossPhaseChanged  :: RemoteEvent

local log = Logger.new("BossHudGui")

local PHASE_LABELS = { "I", "II", "III", "IV", "V" }
local BAR_TWEEN    = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ---------------------------------------------------------------
-- GUI Construction
-- ---------------------------------------------------------------

-- Own ScreenGui so we can use IgnoreGuiInset=true and sit flush at the
-- top of the screen where the round timer used to live.
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "BossHudGui"
screenGui.DisplayOrder   = 15
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.Parent         = Players.LocalPlayer:WaitForChild("PlayerGui")

local container = Instance.new("Frame")
container.Name               = "BossHud"
container.Size               = UDim2.new(0.4, 0, 0, 68)
container.Position           = UDim2.new(0.5, 0, 0, 8)
container.AnchorPoint        = Vector2.new(0.5, 0)
container.BackgroundColor3   = Color3.fromRGB(20, 0, 0)
container.BackgroundTransparency = 0.35
container.BorderSizePixel    = 0
container.Visible            = false  -- hidden until boss spawns
container.Parent             = screenGui

-- Rounded corners
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = container

-- Top row: boss name + phase label
local topRow = Instance.new("Frame")
topRow.Name               = "TopRow"
topRow.Size               = UDim2.new(1, -16, 0, 26)
topRow.Position           = UDim2.new(0, 8, 0, 6)
topRow.BackgroundTransparency = 1
topRow.Parent = container

local nameLabel = Instance.new("TextLabel")
nameLabel.Name             = "NameLabel"
nameLabel.Size             = UDim2.new(1, -60, 1, 0)
nameLabel.BackgroundTransparency = 1
nameLabel.TextColor3       = Color3.fromRGB(255, 220, 220)
nameLabel.TextXAlignment   = Enum.TextXAlignment.Left
nameLabel.TextScaled       = true
nameLabel.Font             = Enum.Font.GothamBold
nameLabel.Text             = "BOSS"
nameLabel.Parent           = topRow

local phaseLabel = Instance.new("TextLabel")
phaseLabel.Name            = "PhaseLabel"
phaseLabel.Size            = UDim2.new(0, 55, 1, 0)
phaseLabel.Position        = UDim2.new(1, -55, 0, 0)
phaseLabel.BackgroundTransparency = 1
phaseLabel.TextColor3      = Color3.fromRGB(255, 180, 60)
phaseLabel.TextXAlignment  = Enum.TextXAlignment.Right
phaseLabel.TextScaled      = true
phaseLabel.Font            = Enum.Font.GothamBold
phaseLabel.Text            = "Phase I"
phaseLabel.Visible         = false   -- hidden by default; toggle with P
phaseLabel.Parent          = topRow

-- Health bar background
local barBg = Instance.new("Frame")
barBg.Name             = "BarBg"
barBg.Size             = UDim2.new(1, -16, 0, 18)
barBg.Position         = UDim2.new(0, 8, 0, 38)
barBg.BackgroundColor3 = Color3.fromRGB(60, 10, 10)
barBg.BorderSizePixel  = 0
barBg.ClipsDescendants = true
barBg.Parent           = container

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 4)
barCorner.Parent       = barBg

-- Health bar fill
local barFill = Instance.new("Frame")
barFill.Name             = "Fill"
barFill.Size             = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(210, 30, 30)
barFill.BorderSizePixel  = 0
barFill.Parent           = barBg

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 4)
fillCorner.Parent       = barFill

-- ---------------------------------------------------------------
-- Update helpers
-- ---------------------------------------------------------------

local function setHealthFraction(fraction: number)
	local clamped = math.clamp(fraction, 0, 1)
	TweenService:Create(barFill, BAR_TWEEN, {
		Size = UDim2.new(clamped, 0, 1, 0),
	}):Play()
end

local function setPhase(phaseIndex: number)
	local label = PHASE_LABELS[phaseIndex] or tostring(phaseIndex)
	phaseLabel.Text = "Phase " .. label
end

local function showBoss(visible: boolean)
	container.Visible = visible
end

local phaseDebugVisible = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Semicolon then
		phaseDebugVisible = not phaseDebugVisible
		phaseLabel.Visible = phaseDebugVisible
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
		showBoss(false)
		return
	end

	showBoss(true)
	local fraction = if maxHP > 0 then currentHP / maxHP else 0
	setHealthFraction(fraction)
	setPhase(phaseIndex)
end)

BossPhaseChanged.OnClientEvent:Connect(function(phaseIndex: number)
	if phaseIndex == 0 then
		showBoss(false)
	else
		showBoss(true)
		setPhase(phaseIndex)
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

	showBoss(true)
	setHealthFraction(fraction)
	-- Phase index unknown without RemoteEvent; default to 1
	setPhase(1)

	log:info(string.format("Late-joined with existing boss (HP %.0f/%.0f)",
		humanoid.Health, humanoid.MaxHealth))
end

tryInitFromExistingBoss()
