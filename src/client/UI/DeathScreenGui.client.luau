----------------------------------------------------------------------
-- DeathScreenGui
----------------------------------------------------------------------
-- Full-screen overlay + respawn flow when the local player dies.
-- Hides automatically on CharacterAdded (new character = respawned).
--
-- Respawn behavior depends on round state:
--   • Active round      → server auto-respawns after GameMode's timer,
--                         we only display the countdown
--   • Otherwise         → manual respawn button appears after the timer
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

local log = Logger.new("DeathScreen")

local player = Players.LocalPlayer
local healthRemotes = ReplicatedStorage.Shared.Health.Remotes
local gameModeRemotes = ReplicatedStorage.Shared.GameMode.Remotes

local requestRespawnRemote = healthRemotes.RequestRespawn
local gameStateChangedRemote = gameModeRemotes:WaitForChild("GameStateChanged")

local currentRoundState = GameModeConstants.RoundState.WaitingForPlayers
gameStateChangedRemote.OnClientEvent:Connect(function(state)
	currentRoundState = state.roundState
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeathScreenGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 30 -- above damage flash
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.4
overlay.BorderSizePixel = 0
overlay.Parent = screenGui

local countdown = Instance.new("TextLabel")
countdown.Size = UDim2.new(0, 300, 0, 50)
countdown.Position = UDim2.new(0.5, -150, 0.4, 0)
countdown.BackgroundTransparency = 1
countdown.TextColor3 = Color3.fromRGB(255, 255, 255)
countdown.Font = Enum.Font.GothamBold
countdown.TextSize = 24
countdown.Text = "Eliminated"
countdown.Parent = overlay

local respawnButton = Instance.new("TextButton")
respawnButton.Size = UDim2.new(0, 200, 0, 50)
respawnButton.Position = UDim2.new(0.5, -100, 0.55, 0)
respawnButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
respawnButton.TextColor3 = Color3.fromRGB(200, 200, 200)
respawnButton.Font = Enum.Font.GothamBold
respawnButton.TextSize = 18
respawnButton.Text = "Respawn"
respawnButton.Visible = false
respawnButton.Parent = overlay

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 6)
buttonCorner.Parent = respawnButton

respawnButton.MouseButton1Click:Connect(function()
	requestRespawnRemote:FireServer()
end)

local deathTime: number? = nil
local countdownTask: thread? = nil

local function hide()
	screenGui.Enabled = false
	respawnButton.Visible = false
	deathTime = nil
	if countdownTask then
		task.cancel(countdownTask)
		countdownTask = nil
	end
end

local function show()
	screenGui.Enabled = true
	respawnButton.Visible = false
	deathTime = os.clock()

	local isActiveRound = currentRoundState == GameModeConstants.RoundState.Active
	local respawnTime = if isActiveRound
		then GameModeConstants.RESPAWN_TIME
		else HealthConstants.RESPAWN_TIME

	countdownTask = task.spawn(function()
		local remaining = respawnTime
		while remaining > 0 and screenGui.Enabled do
			countdown.Text = string.format("Respawning in %d...", math.ceil(remaining))
			task.wait(0.1)
			remaining = respawnTime - (os.clock() - (deathTime :: number))
		end
		if screenGui.Enabled then
			if isActiveRound then
				countdown.Text = "Respawning..."
			else
				countdown.Text = "Eliminated"
				respawnButton.Visible = true
			end
		end
	end)
end

local function bindCharacter(character: Model)
	hide()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(show)
end

if player.Character then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

log:info("Initialized")
