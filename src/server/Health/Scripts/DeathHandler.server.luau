local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("DeathHandler")

local healthEvents = ServerScriptService.Server.Health.Events
local playerEliminatedEvent = healthEvents.PlayerEliminated

local Debris = game:GetService("Debris")

local EXPLOSION_FORCE = 80
local EXPLOSION_RADIUS = 15
local FRAGMENT_COUNT = 8
local FRAGMENT_SIZE = Vector3.new(0.8, 0.8, 0.8)
local FRAGMENT_LIFETIME = 3

-- Templates are stored in ServerStorage.DamageableTemplates
-- On first death of a Damageable model, a template is auto-created if one doesn't exist
local templateFolder = ServerStorage:FindFirstChild("DamageableTemplates")
if not templateFolder then
	templateFolder = Instance.new("Folder")
	templateFolder.Name = "DamageableTemplates"
	templateFolder.Parent = ServerStorage
end

local pendingRespawns: { [string]: boolean } = {}

local function ensureTemplate(model: Model): Model?
	local templateName = model.Name
	local template = templateFolder:FindFirstChild(templateName)
	if template then
		return template
	end

	-- Auto-create template from the first instance we see
	template = model:Clone()
	template.Name = templateName
	template.Parent = templateFolder
	log:info(string.format(" Created template for '%s'", templateName))
	return template
end

local function spawnExplosionEffect(model: Model)
	local pivot = model:GetPivot()

	-- Visual-only explosion (no damage, no destruction)
	local explosion = Instance.new("Explosion")
	explosion.Position = pivot.Position
	explosion.BlastRadius = EXPLOSION_RADIUS
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace
	Debris:AddItem(explosion, 2)

	-- Scatter debris fragments from the model's position
	for i = 1, FRAGMENT_COUNT do
		local fragment = Instance.new("Part")
		fragment.Size = FRAGMENT_SIZE
		fragment.CFrame = pivot * CFrame.new(
			math.random() * 2 - 1,
			math.random() * 2,
			math.random() * 2 - 1
		)
		fragment.Color = Color3.fromRGB(
			math.random(60, 120),
			math.random(60, 120),
			math.random(60, 120)
		)
		fragment.Material = Enum.Material.Concrete
		fragment.Anchored = false
		fragment.CanCollide = true
		fragment.Parent = workspace

		-- Fling outward
		local direction = (fragment.Position - pivot.Position).Unit
			+ Vector3.new(0, 1.5, 0)
		fragment:ApplyImpulse(direction * EXPLOSION_FORCE)

		Debris:AddItem(fragment, FRAGMENT_LIFETIME)
	end
end

local function handleDeath(sourcePlayer: Player?, targetHumanoid: Humanoid, damageResult: any)
	local character = targetHumanoid:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end

	if Players:GetPlayerFromCharacter(character) then
		return
	end

	if not CollectionService:HasTag(character, HealthConstants.DAMAGEABLE_TAG) then
		return
	end

	local targetName = character.Name
	local sourceName = sourcePlayer and sourcePlayer.Name or "Environment"
	local respawnTime = character:GetAttribute(HealthConstants.RESPAWN_TIME_ATTRIBUTE) or HealthConstants.RESPAWN_TIME

	-- Use name-based key since the model instance will be destroyed
	local spawnKey = targetName .. "_" .. tostring(character:GetPivot())
	if pendingRespawns[spawnKey] then
		return
	end
	pendingRespawns[spawnKey] = true

	log:info(string.format(" %s eliminated %s (respawn in %ds)", sourceName, targetName, respawnTime))

	-- Remember where to respawn
	local spawnCFrame = character:GetPivot()
	local parentInstance = character.Parent

	-- Explosion effect then hide the model
	spawnExplosionEffect(character)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = 1
			part.CanCollide = false
		end
	end

	if respawnTime <= 0 then
		-- No respawn — destroy after explosion finishes
		task.delay(FRAGMENT_LIFETIME, function()
			character:Destroy()
			pendingRespawns[spawnKey] = nil
		end)
		return
	end

	task.delay(respawnTime, function()
		-- Destroy the dead model
		character:Destroy()

		-- Clone a fresh copy from template
		local template = templateFolder:FindFirstChild(targetName)
		if not template then
			log:warn(string.format(" No template found for '%s'", targetName))
			pendingRespawns[spawnKey] = nil
			return
		end

		local newModel = template:Clone()
		newModel:PivotTo(spawnCFrame)
		newModel.Parent = parentInstance

		pendingRespawns[spawnKey] = nil
		log:info(string.format(" %s respawned (fresh clone)", targetName))
	end)
end

local function initialize()
	-- Create templates for all existing Damageable objects
	for _, instance in CollectionService:GetTagged(HealthConstants.DAMAGEABLE_TAG) do
		if instance:IsA("Model") and not Players:GetPlayerFromCharacter(instance) then
			ensureTemplate(instance)
		end
	end

	CollectionService:GetInstanceAddedSignal(HealthConstants.DAMAGEABLE_TAG):Connect(function(instance)
		if instance:IsA("Model") and not Players:GetPlayerFromCharacter(instance) then
			ensureTemplate(instance)
		end
	end)

	playerEliminatedEvent.Event:Connect(handleDeath)
	log:info(" Initialized")
end

initialize()
