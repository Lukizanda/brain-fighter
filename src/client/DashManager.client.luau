local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DashController = require(ReplicatedStorage.Shared.Character.DashController)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("DashManager")
local player = Players.LocalPlayer
local activeController: DashController.DashController? = nil

local function onCharacterAdded(character: Model)
	if activeController then
		activeController:destroy()
		activeController = nil
	end

	-- Wait for physics-critical children before initialising
	character:WaitForChild("HumanoidRootPart")
	character:WaitForChild("Humanoid")

	local controller = DashController.new(character)
	controller:enable()
	activeController = controller
	log:info("DashController started for new character")
end

player.CharacterAdded:Connect(onCharacterAdded)

if player.Character then
	onCharacterAdded(player.Character)
end
