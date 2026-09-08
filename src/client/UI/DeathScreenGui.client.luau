----------------------------------------------------------------------
-- DeathScreenGui
----------------------------------------------------------------------
-- Full-screen overlay + respawn countdown when the local player dies.
-- Hides automatically on CharacterAdded (new character = respawned).
--
-- Display only. GameModeService respawns every player who belongs to a
-- session — in the hub as well as mid-round — after that session's
-- `respawnTime`, so there is nothing for the player to ask for and no
-- request remote to ask on (chunk 5). All this does is count the same
-- delay the server broadcast down to zero.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local HudGate = require(ReplicatedStorage.Shared.Hud.HudGate)

local log = Logger.new("DeathScreen")

local player = Players.LocalPlayer
local gameModeRemotes = ReplicatedStorage.Shared.GameMode.Remotes

local gameStateChangedRemote = gameModeRemotes:WaitForChild("GameStateChanged")

-- Server-reported respawn delay for the player's current session (see
-- RoundManager._broadcastState). Defaults to the active-round value so a
-- death that lands before the first GameState broadcast still counts down
-- sanely.
local currentRespawnTime: number = GameModeConstants.RESPAWN_TIME
gameStateChangedRemote.OnClientEvent:Connect(function(state)
	currentRespawnTime = state.respawnTime or currentRespawnTime
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeathScreenGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 30 -- above damage flash
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Round and competition chrome: no meaning in the hub.
--
-- `screenGui.Enabled` belongs to the gate from here on: this script shows
-- and hides `overlay.Visible` instead, the same split GameStateGui and
-- ScoreboardGui use. An owner that also writes the gated property loses a
-- true -> false transition whenever the gate has already forced it false —
-- no changed signal fires, so the gate keeps `ownerWants = true` and
-- reveals the overlay to a living player on the next arena entry.
HudGate.bindScreenGui(screenGui, HudGate.Policy.ArenaOnly)

local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.4
overlay.BorderSizePixel = 0
overlay.Visible = false
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

local deathTime: number? = nil
local countdownTask: thread? = nil

local function hide()
	overlay.Visible = false
	deathTime = nil
	if countdownTask then
		task.cancel(countdownTask)
		countdownTask = nil
	end
end

local function show()
	overlay.Visible = true
	deathTime = os.clock()

	local respawnTime = currentRespawnTime

	countdownTask = task.spawn(function()
		local remaining = respawnTime
		while remaining > 0 and overlay.Visible do
			countdown.Text = string.format("Respawning in %d...", math.ceil(remaining))
			task.wait(0.1)
			remaining = respawnTime - (os.clock() - (deathTime :: number))
		end
		if overlay.Visible then
			countdown.Text = "Respawning..."
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
