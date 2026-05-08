local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Weapon.Constants)
local canPlayerDamageHumanoid = require(ReplicatedStorage.Shared.Weapon.Scripts.Utility.canPlayerDamageHumanoid)

export type RayResult = {
	taggedHumanoid: Humanoid?,
	position: Vector3,
	normal: Vector3,
	instance: Instance?,
}

local function castRays(
	player: Player,
	position: Vector3,
	directions: { Vector3 },
	radius: number,
	staticOnly: boolean?
): { RayResult }
	local exclude = CollectionService:GetTagged(Constants.RAY_EXCLUDE_TAG)

	if staticOnly then
		local nonStatic = CollectionService:GetTagged(Constants.NON_STATIC_TAG)
		-- Append nonStatic to exclude
		table.move(nonStatic, 1, #nonStatic, #exclude + 1, exclude)
	end

	-- Always include the player's character in the exclude list
	if player.Character then
		table.insert(exclude, player.Character)
	end

	local collisionGroup = nil

	-- If the player is on a team, use that team's collision group to ensure the ray passes through
	-- characters and forcefields on that team.
	if player.Team and not player.Neutral then
		collisionGroup = player.Team.Name
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = exclude
	if collisionGroup then
		params.CollisionGroup = collisionGroup
	end

	local rayResults = {}

	for _, direction in directions do
		-- In order to provide a simple form of bullet magnetism, we use spherecasts with a small radius instead of raycasts.
		-- This allows closely grazing shots to register as hits, making blasters feel a bit more accurate and improving the 'game feel'.
		local raycastResult = Workspace:Spherecast(position, radius, direction, params)
		local rayResult: RayResult = {
			position = position + direction,
			normal = direction.Unit,
		}

		if raycastResult then
			rayResult.position = raycastResult.Position
			rayResult.normal = raycastResult.Normal
			rayResult.instance = raycastResult.Instance

			local humanoid = raycastResult.Instance.Parent:FindFirstChildOfClass("Humanoid")
			if humanoid and canPlayerDamageHumanoid(player, humanoid) then
				rayResult.taggedHumanoid = humanoid
			end
		end

		table.insert(rayResults, rayResult)
	end

	return rayResults
end

return castRays
