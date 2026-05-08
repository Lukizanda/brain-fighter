----------------------------------------------------------------------
-- BotSpawner
----------------------------------------------------------------------
-- Dev helper: spawns N stationary enemy-team bots so a single human
-- player can iterate on TDM Step 5 tuning (TTK feel, respawn cadence,
-- score-limit pacing, killfeed legibility, spawn-camping risk) without
-- needing a second client.
--
-- Bots are clones of a Workspace TargetDummy rig with their body parts
-- recolored to the enemy team's TeamColor. They're placed near the
-- enemy SpawnLocation (offset laterally so they're visible without
-- being stacked). The existing DeathHandler picks them up via the
-- Damageable tag and respawns them after RESPAWN_TIME — so we get
-- real respawn behaviour for free.
--
-- Score credit + kill feed: a single playerEliminatedEvent listener
-- recognises bot characters via the BotTeam attribute and routes the
-- kill through ScoreTracker.recordBotKill, which increments the
-- killer's score and fires a KillFeed entry with explicit team-color
-- overrides (the UI's UserId-based color lookup can't resolve bots).
--
-- Friendly fire is sidestepped by spawning bots only on the OPPOSITE
-- team to the local player, so the existing player-vs-player FF
-- filter doesn't have to learn about bots.
--
-- Gated by GameConfig.DEV_BOT_COUNT (0 = off).
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Teams = game:GetService("Teams")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("BotSpawner")

local botCount = GameConfig.DEV_BOT_COUNT
local spawningEnabled = type(botCount) == "number" and botCount > 0

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
local SPAWN_LATERAL_SPACING = 6 -- studs between adjacent bots
local SPAWN_FORWARD_OFFSET = 0 -- studs in front of the enemy SpawnLocation
local DAMAGEABLE_TAG = "Damageable"
local BOT_TEAM_ATTRIBUTE = "BotTeam" -- set on the Model so playerEliminatedEvent listener can recognise bot characters
local BOT_NAME_ATTRIBUTE = "BotDisplayName" -- set on the Model so the kill feed shows the right name even after the rig is recoloured
local BOT_NAME_PREFIX = "Bot"
local PLAYER_TEAM_TIMEOUT = 10 -- seconds to wait for the first player to land on a team before giving up

----------------------------------------------------------------------
-- Dependencies
----------------------------------------------------------------------
local healthEvents = ServerScriptService.Server.Health.Events
local playerEliminatedEvent = healthEvents.PlayerEliminated

local ScoreTracker = require(ServerScriptService.Server.GameMode.Scripts.GameModeService.ScoreTracker)

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function findRigTemplate(): Model?
	-- Prefer any existing TargetDummy in workspace as a known-good rig.
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("Model") and instance.Name:match("^TargetDummy") and instance:FindFirstChildOfClass("Humanoid") then
			return instance
		end
	end
	-- Fallback: any Damageable-tagged model with a Humanoid.
	for _, instance in CollectionService:GetTagged(DAMAGEABLE_TAG) do
		if instance:IsA("Model") and instance:FindFirstChildOfClass("Humanoid") then
			return instance
		end
	end
	return nil
end

local function findEnemySpawnLocation(enemyTeam: Team): SpawnLocation?
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") and not instance.Neutral and instance.TeamColor == enemyTeam.TeamColor then
			return instance
		end
	end
	return nil
end

local function tintRig(rig: Model, color: Color3)
	-- Recolour every BasePart so the bot reads as enemy-team at a glance.
	-- We don't try to preserve the dummy's two-tone scheme — uniform team
	-- colour is the clearest test signal.
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = color
			descendant.Material = Enum.Material.SmoothPlastic
		end
	end
end

local function waitForOppositeTeam(player: Player): Team?
	-- The player's team is set by TeamService.assignToSmallestTeam shortly
	-- after PlayerAdded; we wait briefly so we don't spawn before the
	-- assignment lands.
	local deadline = os.clock() + PLAYER_TEAM_TIMEOUT
	while os.clock() < deadline do
		if player.Team and not player.Neutral then
			break
		end
		task.wait(0.1)
	end

	if not player.Team or player.Neutral then
		log:warn("Local player never landed on a team — aborting bot spawn")
		return nil
	end

	for _, t in Teams:GetChildren() do
		if t:IsA("Team") and t ~= player.Team then
			return t
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Spawning
----------------------------------------------------------------------
local botCharacters: { [Model]: { team: Team, displayName: string } } = {}

local function spawnBots(enemyTeam: Team)
	local rigTemplate = findRigTemplate()
	if not rigTemplate then
		log:warn("No TargetDummy/Damageable rig found in workspace — can't clone a bot rig")
		return
	end

	local spawnLocation = findEnemySpawnLocation(enemyTeam)
	if not spawnLocation then
		log:warn(string.format("No SpawnLocation matching enemy team '%s' — bots won't spawn", enemyTeam.Name))
		return
	end

	local origin = spawnLocation.CFrame * CFrame.new(0, 0, -SPAWN_FORWARD_OFFSET)
	local color = enemyTeam.TeamColor.Color

	for i = 1, botCount do
		local lateral = (i - (botCount + 1) / 2) * SPAWN_LATERAL_SPACING
		local botCFrame = origin * CFrame.new(lateral, 0, 0)

		local rig = rigTemplate:Clone()
		local displayName = string.format("%s%d", BOT_NAME_PREFIX, i)
		rig.Name = displayName
		rig:SetAttribute(BOT_TEAM_ATTRIBUTE, enemyTeam.Name)
		rig:SetAttribute(BOT_NAME_ATTRIBUTE, displayName)
		tintRig(rig, color)

		-- Make sure the Damageable tag is present (clone preserves tags but
		-- belt-and-suspenders since the tag is what wires DeathHandler).
		if not CollectionService:HasTag(rig, DAMAGEABLE_TAG) then
			CollectionService:AddTag(rig, DAMAGEABLE_TAG)
		end

		rig.Parent = workspace
		rig:PivotTo(botCFrame)

		botCharacters[rig] = { team = enemyTeam, displayName = displayName }

		-- DeathHandler clones a fresh rig from the auto-template on death,
		-- so we re-register the new clone via DescendantAdded below.
	end

	log:info(string.format("Spawned %d bot(s) on team %s near %s", botCount, enemyTeam.Name, spawnLocation:GetFullName()))
end

----------------------------------------------------------------------
-- Kill credit
----------------------------------------------------------------------
local function onPlayerEliminated(sourcePlayer: Player?, targetHumanoid: Humanoid, _result)
	local character = targetHumanoid:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end

	-- Real-Player victims are handled by GameModeService.onPlayerEliminated.
	if Players:GetPlayerFromCharacter(character) then
		return
	end

	local botTeamName = character:GetAttribute(BOT_TEAM_ATTRIBUTE)
	local displayName = character:GetAttribute(BOT_NAME_ATTRIBUTE)
	if type(botTeamName) ~= "string" or type(displayName) ~= "string" then
		return -- not one of ours
	end

	local team = Teams:FindFirstChild(botTeamName)
	local color = team and team:IsA("Team") and team.TeamColor.Color or nil

	local weaponName = "Unknown"
	if sourcePlayer and sourcePlayer.Character then
		local tool = sourcePlayer.Character:FindFirstChildOfClass("Tool")
		if tool then
			weaponName = tool.Name
		end
	end

	ScoreTracker.recordBotKill(sourcePlayer, displayName, color, weaponName)
end

----------------------------------------------------------------------
-- Re-tag respawned clones
----------------------------------------------------------------------
-- DeathHandler templates a bot at the moment of its first death (auto-
-- template path — see DeathHandler.ensureTemplate). The respawn clones
-- the template, which already carries our BotTeam + BotDisplayName
-- attributes (attributes are preserved on clone), so no additional work
-- is needed: subsequent kills are credited correctly. This comment
-- is kept so future me doesn't add a re-tag listener thinking it's
-- needed.

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------
local started = false

local function startWith(player: Player)
	if started then
		return
	end
	started = true

	local enemyTeam = waitForOppositeTeam(player)
	if not enemyTeam then
		return
	end
	spawnBots(enemyTeam)
end

-- Always-on: kill credit for any humanoid carrying the BotTeam attribute,
-- regardless of whether DEV_BOT_COUNT spawned any. Tests + future bot
-- producers (e.g. the multiplayer test suite) can spawn synthetic enemies
-- and rely on this listener to route their deaths through ScoreTracker.
playerEliminatedEvent.Event:Connect(onPlayerEliminated)

if not spawningEnabled then
	log:info("Kill-credit listener armed (DEV_BOT_COUNT=0 so no bots will spawn)")
	return
end

Players.PlayerAdded:Connect(startWith)
for _, p in Players:GetPlayers() do
	task.spawn(startWith, p)
end

log:info(string.format("Initialized — armed for %d bot(s) on first player join", botCount))
