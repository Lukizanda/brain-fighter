local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Weapon.Constants)

local TIMESTAMP_BUFFER_CONSTANT = 1
local POSITION_BUFFER_CONSTANT = 5
local POSITION_BUFFER_FACTOR = 0.4

local function validateShot(player: Player, timestamp: number, blaster: Tool, origin: CFrame): boolean
	-- Validate timestamp
	local now = Workspace:GetServerTimeNow()
	if timestamp > now then
		return false
	end
	if timestamp < now - TIMESTAMP_BUFFER_CONSTANT then
		return false
	end

	-- Make sure the character exists, is alive, and has a PrimaryPart
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	if humanoid.Health <= 0 then
		return false
	end
	local primaryPart = character.PrimaryPart
	if not primaryPart then
		return false
	end

	-- Make sure the blaster is equipped
	if blaster.Parent ~= character then
		return false
	end

	-- Make sure the blaster is not being reloaded
	local isReloading = blaster:GetAttribute(Constants.RELOADING_ATTRIBUTE)
	if isReloading then
		return false
	end

	-- Make sure the blaster has enough ammo
	local ammo = blaster:GetAttribute(Constants.AMMO_ATTRIBUTE)
	if ammo <= 0 then
		return false
	end

	---- Make sure the origin position is within a reasonable distance from the character
	--local distance = (primaryPart.Position - origin.Position).Magnitude
	--local maxDistance = POSITION_BUFFER_CONSTANT + primaryPart.AssemblyLinearVelocity.Magnitude * POSITION_BUFFER_FACTOR
	--if distance > maxDistance then
	--	warn(string.format("[validateShot] %s: origin too far from character (distance=%.2f, maxDistance=%.2f)", playerName, distance, maxDistance))
	--	return false
	--end

	return true
end

return validateShot
