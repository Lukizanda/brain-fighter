local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Constants = require(ReplicatedStorage.Shared.Weapon.Constants)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local getHitZone = require(ReplicatedStorage.Shared.Health.getHitZone)
local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)
local validateInstance = require(ServerScriptService.Server.Utility.TypeValidation.validateInstance)
local validateShootArguments = require(script.validateShootArguments)
local validateShot = require(script.validateShot)
local validateTag = require(script.validateTag)
local validateReload = require(script.validateReload)
local Ammo = require(ReplicatedStorage.Shared.Weapon.Scripts.Ammo)
local getRayDirections = require(ReplicatedStorage.Shared.Weapon.Scripts.Utility.getRayDirections)
local castRays = require(ReplicatedStorage.Shared.Weapon.Scripts.Utility.castRays)

local log = Logger.new("Blaster")

local remotes = ReplicatedStorage.Shared.Weapon.Remotes
local shootRemote = remotes.Shoot
local reloadRemote = remotes.Reload
local replicateShotRemote = remotes.ReplicateShot

local function onShootEvent(
	player: Player,
	timestamp: number,
	blaster: Tool,
	origin: CFrame,
	tagged: { [string]: Humanoid }
)
	local playerName = player and player.Name or "Unknown"
	log:info(
		string.format(
			"%s: event received (blaster='%s', timestamp=%.3f)",
			playerName,
			blaster and blaster.Name or "nil",
			timestamp or -1
		)
	)

	-- Validate the received arguments
	if not validateShootArguments(timestamp, blaster, origin, tagged) then
		log:warn(string.format(" %s: failed validateShootArguments", playerName))
		return
	end
	log:info(string.format(" %s: passed validateShootArguments", playerName))

	-- Validate that the player can make this shot
	if not validateShot(player, timestamp, blaster, origin) then
		log:warn(string.format(" %s: failed validateShot", playerName))
		return
	end
	log:info(string.format(" %s: passed validateShot", playerName))

	local spread = blaster:GetAttribute(Constants.SPREAD_ATTRIBUTE)
	local raysPerShot = blaster:GetAttribute(Constants.RAYS_PER_SHOT_ATTRIBUTE)
	local range = blaster:GetAttribute(Constants.RANGE_ATTRIBUTE)
	local rayRadius = blaster:GetAttribute(Constants.RAY_RADIUS_ATTRIBUTE)
	local damage = blaster:GetAttribute(Constants.DAMAGE_ATTRIBUTE)
	log:info(
		string.format(
			"%s: blaster attributes — spread=%s, raysPerShot=%s, range=%s, rayRadius=%s, damage=%s",
			playerName,
			tostring(spread),
			tostring(raysPerShot),
			tostring(range),
			tostring(rayRadius),
			tostring(damage)
		)
	)

	-- Subtract ammo
	local ammo = blaster:GetAttribute(Constants.AMMO_ATTRIBUTE)
	blaster:SetAttribute(Constants.AMMO_ATTRIBUTE, ammo - 1)

	-- The timestamp that was passed by the client also serves as the seed for the blaster's random spread.
	-- This allows us to recalculate the spread accurately on the server relative to the look direction, rather than simply
	-- accepting a direction or directions from the client.
	local spreadAngle = math.rad(spread)
	local rayDirections = getRayDirections(origin, raysPerShot, spreadAngle, timestamp)
	for index, direction in rayDirections do
		rayDirections[index] = direction * range
	end
	-- Raycast against static geometry only
	local rayResults = castRays(player, origin.Position, rayDirections, rayRadius, true)
	log:info(string.format(" %s: castRays returned %d results", playerName, #rayResults))

	-- Validate hits
	for indexString, taggedHumanoid in tagged do
		-- The tagged table contains a client-reported list of the humanoids hit by each of the rays that was fired.
		-- Strings are used for the indices since non-contiguous arrays do not get passed over the network correctly.
		-- (This may be non-contiguous in the case of firing a shotgun, where not all of the rays hit a target)
		-- For each humanoid that the client reports it tagged, we'll validate against the ray that was recast on the server.
		local index = tonumber(indexString)
		if not index then
			continue
		end
		local rayResult = rayResults[index]
		if not rayResults[index] then
			continue
		end
		local rayDirection = rayDirections[index]
		if not rayDirection then
			continue
		end

		-- Validate that the player is able to tag this humanoid based on the server raycast
		if not validateTag(player, taggedHumanoid, origin.Position, rayDirection, rayResult) then
			continue
		end

		rayResult.taggedHumanoid = taggedHumanoid

		-- Align the rayResult position to the tagged humanoid. This is necessary so that when we replicate
		-- this shot to the other clients they don't see lasers going through characters they should be hitting.
		local model = taggedHumanoid:FindFirstAncestorOfClass("Model")
		if model then
			local modelPosition = model:GetPivot().Position
			local distance = (modelPosition - origin.Position).Magnitude
			rayResult.position = origin.Position + rayDirection.Unit * distance
		end

		-- Apply damage through HealthService pipeline (health check is inside applyDamage)
		local hitZone = getHitZone(rayResult.instance)
		applyDamage.process({
			sourcePlayer = player,
			targetHumanoid = taggedHumanoid,
			baseDamage = damage,
			damageType = DamageTypes.DamageType.Bullet,
			hitZone = hitZone,
			sourceWeapon = blaster,
			timestamp = timestamp,
		})
	end

	-- Apply physics impulse
	-- This is the most straightforward way to do this, although there will be some latency since the impulse is being applied on the server
	local force = blaster:GetAttribute(Constants.UNANCHORED_IMPULSE_FORCE_ATTRIBUTE)
	if force ~= 0 then
		for index, rayResult in rayResults do
			-- We don't want to apply impulses to characters, so we'll skip if we tagged a humanoid
			if rayResult.taggedHumanoid then
				continue
			end

			if rayResult.instance and rayResult.instance:IsA("BasePart") and not rayResult.instance.Anchored then
				local direction = rayDirections[index]
				local impulse = direction * force
				rayResult.instance:ApplyImpulseAtPosition(impulse, rayResult.position)
			end
		end
	end

	-- Replicate shot to other players
	local replicatedCount = 0
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == player then
			continue
		end

		replicateShotRemote:FireClient(otherPlayer, blaster, origin.Position, rayResults)
		replicatedCount += 1
	end
	log:info(string.format(" %s: shot replicated to %d other player(s)", playerName, replicatedCount))
end

local function onReloadEvent(player: Player, blaster: Tool)
	-- Validate the received argument
	if not validateInstance(blaster, "Tool") then
		return
	end

	-- Make sure the player is able to reload this blaster
	if not validateReload(player, blaster) then
		return
	end

	local reloadTime = blaster:GetAttribute(Constants.RELOAD_TIME_ATTRIBUTE)

	local character = player.Character
	blaster:SetAttribute(Constants.RELOADING_ATTRIBUTE, true)

	local reloadTask
	local ancestryChangedConnection

	reloadTask = task.delay(reloadTime, function()
		Ammo.performReload(blaster)
		blaster:SetAttribute(Constants.RELOADING_ATTRIBUTE, false)
		ancestryChangedConnection:Disconnect()
	end)

	ancestryChangedConnection = blaster.AncestryChanged:Connect(function()
		if blaster.Parent ~= character then
			blaster:SetAttribute(Constants.RELOADING_ATTRIBUTE, false)

			task.cancel(reloadTask)
			ancestryChangedConnection:Disconnect()
		end
	end)
end

local function initialize()
	shootRemote.OnServerEvent:Connect(onShootEvent)
	reloadRemote.OnServerEvent:Connect(onReloadEvent)
end

initialize()
