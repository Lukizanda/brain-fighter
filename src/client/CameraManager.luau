local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraController = require(ReplicatedStorage.Shared.Character.CameraController)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("CameraManager")

local player = Players.LocalPlayer

local cameraController = CameraController.new()

-- Track current tool
local currentTool: Tool? = nil

local CameraManager = {}

function CameraManager.initialize()
	log:info("Initializing")

	local character = player.Character or player.CharacterAdded:Wait()
	log:info("Character found:", character.Name)

	cameraController:enable(character)
	cameraController:setMode("Default")

	player.CharacterAdded:Connect(function(newCharacter)
		log:info("Character respawned:", newCharacter.Name)
		cameraController:disable()
		cameraController:enable(newCharacter)
		cameraController:setMode("Default")
		if currentTool then
			CameraManager.applyToolCameraMode(currentTool)
		end
	end)

	CameraManager.setupToolListeners(character)

	for _, tool in character:GetChildren() do
		if tool:IsA("Tool") then
			CameraManager.onToolEquipped(tool)
		end
	end
end

function CameraManager.setupToolListeners(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			child.Equipped:Connect(function()
				CameraManager.onToolEquipped(child)
			end)
			child.Unequipped:Connect(function()
				CameraManager.onToolUnequipped(child)
			end)
		end
	end)
end

function CameraManager.onToolEquipped(tool: Tool)
	currentTool = tool
	CameraManager.applyToolCameraMode(tool)
end

function CameraManager.onToolUnequipped(tool: Tool)
	if currentTool == tool then
		currentTool = nil
		cameraController:setMode("Default")
	end
end

function CameraManager.applyToolCameraMode(tool: Tool)
	local cameraMode = tool:GetAttribute("CameraMode")

	if cameraMode then
		if CameraController.CameraModes[cameraMode] then
			cameraController:setMode(cameraMode)
			return
		end
	end

	local toolName = string.lower(tool.Name)
	for modeName, _ in CameraController.CameraModes do
		if string.find(toolName, string.lower(modeName)) then
			cameraController:setMode(modeName)
			return
		end
	end

	cameraController:setMode("Default")
end

function CameraManager.registerToolCameraMode(tool: Tool, modeName: string)
	tool:SetAttribute("CameraMode", modeName)
end

function CameraManager.registerCameraMode(modeName: string, mode: any)
	cameraController:registerMode(modeName, mode)
end

function CameraManager.getCameraController()
	return cameraController
end

return CameraManager
