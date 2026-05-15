--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LetterBlaster = require(ReplicatedStorage.Shared.LetterBlaster)
local Logger        = require(ReplicatedStorage.Shared.Core.Logger)

local log    = Logger.new("SpellingStaff")
local tool   = script.Parent.Parent :: Tool
local player = Players.LocalPlayer

-- PlayerSession lives in StarterPlayerScripts.Client — wait for it to load.
local PlayerSession = require(
	player:WaitForChild("PlayerScripts")
	      :WaitForChild("Client")
	      :WaitForChild("PlayerSession")
)

local controller: typeof(LetterBlaster.new(nil :: any, nil :: any))? = nil

tool.Equipped:Connect(function()
	controller = LetterBlaster.new(tool, PlayerSession.get())
	controller:mount()
end)

tool.Unequipped:Connect(function()
	if controller then
		controller:destroy()
		controller = nil
	end
end)

log:info("started")
