--!strict

----------------------------------------------------------------------
-- LetterBlasterBoot
-- Finds the LetterBlaster Tool in the player's Backpack and wires
-- LetterBlasterController on Equipped / Unequipped.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterBlaster = require(ReplicatedStorage.Shared.LetterBlaster)
local PlayerSession  = require(script.Parent.PlayerSession)
local Logger         = require(ReplicatedStorage.Shared.Core.Logger)

local log    = Logger.new("LetterBlasterBoot")
local player = Players.LocalPlayer

local function setupTool(tool: Tool)
	local controller: typeof(LetterBlaster.new(nil :: any, nil :: any))? = nil

	tool.Equipped:Connect(function()
		local session = PlayerSession.get()
		controller = LetterBlaster.new(tool, session)
		controller:mount()
	end)

	tool.Unequipped:Connect(function()
		if controller then
			controller:destroy()
			controller = nil
		end
	end)
end

local function onCharacterAdded(_character: Model)
	local backpack = player:WaitForChild("Backpack", 10)
	if not backpack then
		log:warn("Backpack not found within timeout")
		return
	end

	local function trySetup(instance: Instance)
		if instance:IsA("Tool") and instance.Name == "LetterBlaster" then
			setupTool(instance :: Tool)
		end
	end

	for _, child in backpack:GetChildren() do
		trySetup(child)
	end
	backpack.ChildAdded:Connect(trySetup)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

log:info("LetterBlasterBoot started")
