local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Weapon.Constants)
local Ammo = require(ReplicatedStorage.Shared.Weapon.Scripts.Ammo)

local function validateReload(player: Player, blaster: Tool): boolean
	local character = player.Character
	if not character then
		return false
	end

	if blaster.Parent ~= character then
		return false
	end

	if blaster:GetAttribute(Constants.RELOADING_ATTRIBUTE) then
		return false
	end

	-- Reject when there's nothing to pull from or the magazine is already full
	if not Ammo.canReload(blaster) then
		return false
	end

	return true
end

return validateReload
