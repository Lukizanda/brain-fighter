local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local FirearmController = require(ReplicatedStorage.Shared.Weapon.Scripts.FirearmController)
local bindToInstanceDestroyed = require(ReplicatedStorage.Utility.bindToInstanceDestroyed)

local log = Logger.new("Rifle")

local tool = script.Parent.Parent
local player = Players.LocalPlayer

log:info("LocalScript started")

local CameraManager = require(player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("CameraManager"))
local cameraController = CameraManager.getCameraController()

local controller = FirearmController.new(tool, {
	cameraController = cameraController,
})

bindToInstanceDestroyed(tool, function()
	controller:destroy()
end)
