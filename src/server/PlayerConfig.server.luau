local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local log = Logger.new("PlayerConfig")

if GameConfig.CAMERA_TOGGLE_DISABLED then
	StarterPlayer.DevComputerCameraMovementMode = Enum.DevComputerCameraMovementMode.Classic
	log:info("CameraToggle disabled — Classic (hold right-click to orbit) mode active")
else
	StarterPlayer.DevComputerCameraMovementMode = Enum.DevComputerCameraMovementMode.CameraToggle
	log:info("CameraToggle enabled — right-click toggles mouse lock")
end
