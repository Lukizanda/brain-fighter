local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Constants = require(ReplicatedStorage.Shared.Weapon.Constants)
local safePlayerAdded = require(ReplicatedStorage.Utility.safePlayerAdded)

local function tagPart(part: BasePart)
	-- Tag all character parts as NON_STATIC, so they can be ignored when casting against static geometry
	part:AddTag(Constants.NON_STATIC_TAG)

	-- Tag parts in accessories and tools with RAY_EXCLUDE_TAG so they can be ignored by raycasts
	local accessory = part:FindFirstAncestorWhichIsA("Accessory")
	local tool = part:FindFirstAncestorWhichIsA("Tool")
	if accessory or tool then
		part:AddTag(Constants.RAY_EXCLUDE_TAG)
	end
end

local function onCharacterAdded(character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	character.DescendantAdded:Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			tagPart(instance)
		end
	end)

	for _, instance in character:GetDescendants() do
		if instance:IsA("BasePart") then
			tagPart(instance)
		end
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)

	if player.Character then
		onCharacterAdded(player.Character)
	end
end

safePlayerAdded(onPlayerAdded)
