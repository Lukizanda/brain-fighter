-- Dev-only: if workspace attribute "DevAutoEquipSword" is true at playtest
-- start, clone the Sword template into every joining player's Backpack
-- and equip it. Lets us run the melee hybrid E2E from a normal server
-- context (not from the MCP Command Bar), eliminating any edit-time
-- replication quirks that might come from execute_luau cloning.
--
-- To use during iteration: set workspace:SetAttribute("DevAutoEquipSword", true)
-- in the explorer before pressing Play. Remove the attribute for normal play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AUTO_EQUIP_ATTRIBUTE = "DevAutoEquipSword"

if not workspace:GetAttribute(AUTO_EQUIP_ATTRIBUTE) then
	return
end

local swordTemplate = ReplicatedStorage.Shared.Weapon.Templates.Sword

local function equipFor(player: Player)
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local sword = swordTemplate:Clone()
	sword.Parent = player.Backpack
	task.wait(0.1)
	humanoid:EquipTool(sword)
end

local function onPlayerAdded(player: Player)
	if player.Character then
		equipFor(player)
	end
	player.CharacterAdded:Connect(function()
		equipFor(player)
	end)
end

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
