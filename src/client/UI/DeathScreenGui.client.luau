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
local HudConstants = require(ReplicatedStorage.Shared.Hud.HudConstants)
local HudGate = require(ReplicatedStorage.Shared.Hud.HudGate)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local DeathScreenBuilder = require(ReplicatedStorage.Shared.Hud.DeathScreenBuilder)

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

local handle = DeathScreenBuilder.build()
handle.screenGui.DisplayOrder = HudConstants.LAYERS.Modal -- above damage flash
handle.screenGui.Parent = player:WaitForChild("PlayerGui")

-- Round and competition chrome: no meaning in the hub.
--
-- `screenGui.Enabled` belongs to the gate from here on: this script shows
-- and hides `overlay.Visible` instead, the same split GameStateGui and
-- ScoreboardGui use. An owner that also writes the gated property loses a
-- true -> false transition whenever the gate has already forced it false —
-- no changed signal fires, so the gate keeps `ownerWants = true` and
-- reveals the overlay to a living player on the next arena entry.
HudGate.bindScreenGui(handle.screenGui, HudGate.Policy.ArenaOnly)
HudLayoutManager:attachScale(handle.screenGui)

local function bindCharacter(character: Model)
	handle:hide()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		handle:show(currentRespawnTime)
	end)
end

if player.Character then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

log:info("Initialized")
