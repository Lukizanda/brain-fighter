local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local log = Logger.new("CharacterSystemsLoader")

local CameraManager = require(script.Parent:WaitForChild("CameraManager"))
local LocomotionManager = require(script.Parent:WaitForChild("LocomotionManager"))

-- Apply game-wide UI visibility from GameConfig
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, GameConfig.SHOW_BACKPACK)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, GameConfig.SHOW_HEALTH)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, GameConfig.SHOW_PLAYER_LIST)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, GameConfig.SHOW_CHAT)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, GameConfig.SHOW_EMOTES)

log:info("Starting initialization...")

if GameConfig.TPS_CHARACTER_ENABLED then
	CameraManager.initialize()
	LocomotionManager.initialize(CameraManager.getCameraController())
	log:info("Initialization complete (TPS character stack active)")
else
	-- Apply default-camera behavior from GameConfig
	if GameConfig.CAMERA_TOGGLE_DISABLED then
		Players.LocalPlayer.DevComputerCameraMovementMode = Enum.DevComputerCameraMovementMode.Classic
		log:info("CameraToggle disabled — right-click hold-to-rotate (Classic) mode active")
	else
		Players.LocalPlayer.DevComputerCameraMovementMode = Enum.DevComputerCameraMovementMode.CameraToggle
		log:info("CameraToggle enabled — right-click toggles mouse lock")
	end
	log:info("TPS character disabled — default Roblox PlayerModule (free-look camera + AutoRotate character) in effect")
end
