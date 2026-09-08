local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HealthConstants = require(ReplicatedStorage.Shared.Health.HealthConstants)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local SkillEffects = require(ReplicatedStorage.Shared.Skills.SkillEffects)
local applyDamage = require(script.applyDamage)

local log = Logger.new("HealthService")

local healthRemotes = ReplicatedStorage.Shared.Health.Remotes
local damageFeedbackRemote = healthRemotes.DamageFeedback
local damageConfirmRemote = healthRemotes.DamageConfirm

local healthEvents = ServerScriptService.Server.Health.Events
local playerDamagedEvent = healthEvents.PlayerDamaged
local playerEliminatedEvent = healthEvents.PlayerEliminated

-- "May other players damage this one?" — answered by GameModeService from
-- the victim's session. A BindableFunction because the session tables
-- live in a Script, not a module. GameModeService binds OnInvoke at file
-- scope, before anything yields, so an Invoke can never hang waiting.
local allowsPvPFunction = ServerScriptService.Server.GameMode.Events.AllowsPvP

local function initializeCharacterHealth(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.MaxHealth = HealthConstants.DEFAULT_MAX_HEALTH
	humanoid.Health = HealthConstants.DEFAULT_MAX_HEALTH
	log:info(string.format(" Initialized health for %s: %d/%d", character.Name, humanoid.Health, humanoid.MaxHealth))
end

local function onPlayerAdded(player: Player)
	if player.Character then
		initializeCharacterHealth(player.Character)
	end

	player.CharacterAdded:Connect(function(character)
		initializeCharacterHealth(character)
	end)
end

local function initializeDamageable(model: Instance)
	if not model:IsA("Model") then
		log:warn(string.format(" Damageable tag on non-Model: %s (%s)", model.Name, model.ClassName))
		return
	end

	local maxHealth = model:GetAttribute(HealthConstants.MAX_HEALTH_ATTRIBUTE) or HealthConstants.DEFAULT_MAX_HEALTH
	local respawnTime = model:GetAttribute(HealthConstants.RESPAWN_TIME_ATTRIBUTE)
	if respawnTime == nil then
		model:SetAttribute(HealthConstants.RESPAWN_TIME_ATTRIBUTE, HealthConstants.NPC_RESPAWN_TIME)
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
	end

	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth

	log:info(string.format(" Damageable initialized: %s (%d/%d HP, respawn=%ds)",
		model.Name, humanoid.Health, humanoid.MaxHealth,
		model:GetAttribute(HealthConstants.RESPAWN_TIME_ATTRIBUTE) or 0))
end

local function initialize()
	log:info(" Initializing...")

	applyDamage.initialize({
		damageFeedbackRemote = damageFeedbackRemote,
		damageConfirmRemote = damageConfirmRemote,
		playerDamagedEvent = playerDamagedEvent,
		playerEliminatedEvent = playerEliminatedEvent,
		allowsPvPFor = function(victim: Player): boolean
			return allowsPvPFunction:Invoke(victim) == true
		end,
	})

	-- Every spell's damage and heal lands here. Injected downward rather
	-- than required upward from SkillEffects, so ReplicatedStorage never
	-- reaches into ServerScriptService and the client build has no sink.
	SkillEffects.setDamageSink(applyDamage)

	-- Initialize players
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	-- No respawn path here. Player respawn has exactly one owner,
	-- GameModeService — it is the only thing that knows which session (and
	-- so which pads and which respawn delay) a dead player belongs to. See
	-- `wiki/systems/Health.md` § Respawn.

	-- Initialize Damageable tagged objects
	for _, instance in CollectionService:GetTagged(HealthConstants.DAMAGEABLE_TAG) do
		initializeDamageable(instance)
	end
	CollectionService:GetInstanceAddedSignal(HealthConstants.DAMAGEABLE_TAG):Connect(initializeDamageable)

	log:info(" Initialized")
end

initialize()
