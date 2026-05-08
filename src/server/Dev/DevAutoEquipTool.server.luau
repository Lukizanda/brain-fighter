----------------------------------------------------------------------
-- DevAutoEquipTool
----------------------------------------------------------------------
-- Dev helper: auto-equips a named Tool from the player's backpack each
-- time the character spawns. Gated by GameConfig.DEV_AUTO_EQUIP_TOOL.
--
-- Useful when the default Backpack UI is hidden (SHOW_BACKPACK=false)
-- and you still want a specific weapon in-hand for testing. Leave the
-- config value empty/nil in shipped builds.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("DevAutoEquipTool")

local toolName = GameConfig.DEV_AUTO_EQUIP_TOOL
if type(toolName) ~= "string" or toolName == "" then
	return
end

local function equipOnCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	-- Backpack is populated shortly after CharacterAdded — small retry window.
	local deadline = os.clock() + 2
	while os.clock() < deadline do
		local tool = player.Backpack:FindFirstChild(toolName)
		if tool then
			humanoid:EquipTool(tool)
			log:info(string.format("Auto-equipped '%s' on %s", toolName, player.Name))
			return
		end
		task.wait(0.1)
	end
	log:warn(string.format("Tool '%s' not found in %s's backpack within timeout", toolName, player.Name))
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		equipOnCharacter(player, character)
	end)
	if player.Character then
		equipOnCharacter(player, player.Character)
	end
end)

-- Handle any players already connected (e.g. Studio playtest reload order)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(character)
		equipOnCharacter(player, character)
	end)
	if player.Character then
		equipOnCharacter(player, player.Character)
	end
end

log:info(string.format("Initialized (tool='%s')", toolName))
