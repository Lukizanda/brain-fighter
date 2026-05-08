local ReplicatedStorage = game:GetService("ReplicatedStorage")

local castRays = require(ReplicatedStorage.Shared.Weapon.Scripts.Utility.castRays)
local canPlayerDamageHumanoid = require(ReplicatedStorage.Shared.Weapon.Scripts.Utility.canPlayerDamageHumanoid)

local DIRECTION_BUFFER_CONSTANT = 10
local WALL_DISTANCE_BUFFER_CONSTANT = 5

local function validateTag(
	player: Player,
	taggedHumanoid: Humanoid,
	position: Vector3,
	direction: Vector3,
	rayResult: castRays.RayResult
): boolean
	-- Make sure the player is actually allowed to damage this humanoid. No team killing!
	if not canPlayerDamageHumanoid(player, taggedHumanoid) then
		return false
	end

	local character = taggedHumanoid:FindFirstAncestorOfClass("Model")
	if not character then
		return false
	end

	local pivot = character:GetPivot()
	local characterOffset = pivot.Position - position
	local characterDistance = characterOffset.Magnitude
	local rayDistance = (position - rayResult.position).Magnitude

	-- If the server's version of the ray hits static geometry before the player, then we know the shot
	-- the client reported could not be made.
	if rayDistance < characterDistance - WALL_DISTANCE_BUFFER_CONSTANT then
		return false
	end

	-- In order to make sure that the ray is actually aiming within a certain distance of the character,
	-- we'll calculate a maximum angle based on our DIRECTION_BUFFER_CONSTANT.
	-- DIRECTION_BUFFER_CONSTANT is that maximum amount of studs away from the character that the ray can aim.
	-- atan(DIRECTION_BUFFER_CONSTANT / characterDistance) will give us the maximum angle based on how far away the character is.
	--[[
		◎───y───
		▲     /
		│    /
		x   /
		│  /
		│θ/
		│/

		x = characterDistance
		y = DIRECTION_BUFFER_CONSTANT
		θ = atan(y/x)
	]]

	local maxAngle = math.atan(DIRECTION_BUFFER_CONSTANT / characterDistance)
	-- Check what angle the ray is actually aiming relative to the character and make sure it's within our maximum.
	-- This will stop a client from passing in arbitrary humanoids, only allowing them to damage what they could
	-- conceivably be aiming at.
	local angle = characterOffset:Angle(direction)
	if angle > maxAngle then
		return false
	end

	return true
end

return validateTag
