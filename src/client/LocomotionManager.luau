local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocomotionController = require(ReplicatedStorage.Shared.Character.LocomotionController)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("LocomotionManager")

local player = Players.LocalPlayer

local locomotionController = LocomotionController.new()

local LocomotionManager = {}

function LocomotionManager.initialize(cameraController)
	log:info("Initializing")

	local character = player.Character or player.CharacterAdded:Wait()
	locomotionController:enable(character, cameraController)
	log:info("Enabled for:", character.Name)

	player.CharacterAdded:Connect(function(newCharacter)
		log:info("Re-enabling for respawned character:", newCharacter.Name)
		locomotionController:disable()
		locomotionController:enable(newCharacter, cameraController)
	end)
end

function LocomotionManager.getLocomotionController()
	return locomotionController
end

return LocomotionManager
