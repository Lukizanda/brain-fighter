----------------------------------------------------------------------
-- ScoreboardGui
----------------------------------------------------------------------
-- Tab-to-open scoreboard showing all players' kills, deaths, assists.
-- Listens to ScoreUpdate RemoteEvent for score data.
-- Sorted by kills descending.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local HudConstants = require(ReplicatedStorage.Shared.Hud.HudConstants)
local HudGate = require(ReplicatedStorage.Shared.Hud.HudGate)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local ScoreboardBuilder = require(ReplicatedStorage.Shared.Hud.ScoreboardBuilder)
local ScoreboardConfig = require(ReplicatedStorage.Shared.Hud.ScoreboardConfig)
local log = Logger.new("ScoreboardGui")

local player = Players.LocalPlayer
local gameModeRemotes = ReplicatedStorage.Shared.GameMode.Remotes
local scoreUpdateRemote = gameModeRemotes.ScoreUpdate

----------------------------------------------------------------------
-- UI Construction
----------------------------------------------------------------------
local handle = ScoreboardBuilder.build()
handle.screenGui.DisplayOrder = HudConstants.LAYERS.Scoreboard -- above other HUD
handle.screenGui.Parent = player:WaitForChild("PlayerGui")

-- Round and competition chrome: no meaning in the hub.
HudGate.bindScreenGui(handle.screenGui, HudGate.Policy.ArenaOnly)
HudLayoutManager:attachScale(handle.screenGui)

----------------------------------------------------------------------
-- Input handling
----------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == ScoreboardConfig.TOGGLE_KEY then
		handle:setVisible(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == ScoreboardConfig.TOGGLE_KEY then
		handle:setVisible(false)
	end
end)

----------------------------------------------------------------------
-- Score updates
----------------------------------------------------------------------
scoreUpdateRemote.OnClientEvent:Connect(function(scores)
	handle:setScores(scores, player.UserId)
end)

log:info("Initialized")
