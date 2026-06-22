local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local log = Logger.new("CharacterSystemsLoader")

-- Apply game-wide UI visibility from GameConfig
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, GameConfig.SHOW_BACKPACK)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, GameConfig.SHOW_HEALTH)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, GameConfig.SHOW_PLAYER_LIST)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, GameConfig.SHOW_CHAT)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, GameConfig.SHOW_EMOTES)

log:info("Initialized")
