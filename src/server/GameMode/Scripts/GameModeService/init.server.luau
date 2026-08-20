----------------------------------------------------------------------
-- GameModeService
----------------------------------------------------------------------
-- Server session manager. Owns a table of RoundManager sessions keyed by
-- arena id, assigns each player to one, and wires them to:
--   ScoreTracker (kill/death tracking), SpawnManager (intelligent spawning),
--   and a GameModeDefinition.
--
-- Phase 6 stage 1 (see `wiki/design/lobby.md`) turned RoundManager from a
-- server-wide singleton into a per-session instance. Stage 2 bound the
-- world to it: each session names an arena slot, and SpawnManager resolves
-- that arena's spawn pads. Exactly one session is created at boot and every
-- player joins it, so behaviour is identical to the singleton — the seam is
-- here for stages 4-6 to hang arenas off.
--
-- Stage 3 scoped the rest of the screen-space broadcasts: this file
-- registers a `BroadcastAudience` resolver over the session tables, which is
-- how ScoreTracker and BossService reach a roster without being handed one.
-- ScoreTracker is still a server-wide singleton — its *scores* are stage 5's
-- problem; only its audience moved.
--
-- Hooks into existing Health system via BindableEvents.
-- Does NOT modify the damage pipeline — listens to events only.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BroadcastAudience = require(ReplicatedStorage.Shared.GameMode.BroadcastAudience)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local GameModes = require(ReplicatedStorage.Shared.GameMode.Modes)

local ACTIVE_MODE_ATTRIBUTE = "ActiveGameMode"

local ScoreTracker = require(script.ScoreTracker)
local SpawnManager = require(script.SpawnManager)
local RoundManager = require(script.RoundManager)

local log = Logger.new("GameModeService")

----------------------------------------------------------------------
-- Resolve dependencies
----------------------------------------------------------------------

-- GameMode remotes (client ↔ server)
local gameModeRemotes = ReplicatedStorage.Shared.GameMode.Remotes
local gameStateChangedRemote = gameModeRemotes.GameStateChanged
local scoreUpdateRemote = gameModeRemotes.ScoreUpdate
local killFeedRemote = gameModeRemotes.KillFeed

-- GameMode server events
local gameModeEvents = ServerScriptService.Server.GameMode.Events
local roundStartedEvent = gameModeEvents.RoundStarted
local roundEndedEvent = gameModeEvents.RoundEnded

-- Health system events (listen only — no modification)
local healthEvents = ServerScriptService.Server.Health.Events
local playerEliminatedEvent = healthEvents.PlayerEliminated
local playerDamagedEvent = healthEvents.PlayerDamaged

----------------------------------------------------------------------
-- Active game mode definition
-- Resolved from workspace:GetAttribute("ActiveGameMode") at boot;
-- falls back to the registry default. Set the attribute in Studio
-- Properties before starting the server to pick a different mode.
----------------------------------------------------------------------
local requestedModeKey = workspace:GetAttribute(ACTIVE_MODE_ATTRIBUTE)
local activeMode, resolvedModeKey = GameModes.get(requestedModeKey)

----------------------------------------------------------------------
-- Sessions
----------------------------------------------------------------------

local sessions: { [string]: RoundManager.RoundManager } = {}
local playerSessions: { [Player]: RoundManager.RoundManager } = {}

local function createSession(arenaId: string, modeDefinition: any): RoundManager.RoundManager
	local session = RoundManager.new({
		arenaId = arenaId,
		gameStateChangedRemote = gameStateChangedRemote,
		roundStartedEvent = roundStartedEvent,
		roundEndedEvent = roundEndedEvent,
		modeDefinition = modeDefinition,
		scoreTracker = ScoreTracker,
	})

	-- Bind the arena's spawn pads at the same moment its session exists, so
	-- there is one place that knows an arena was created.
	SpawnManager.registerArena(arenaId, modeDefinition.getConfig().spawnTag)

	sessions[arenaId] = session
	return session
end

-- Which session a joining player belongs to. Stage 2: the one whole-server
-- session. Stage 4 replaces this with lobby/queue assignment — see
-- `wiki/design/lobby.md` § Slot allocation.
local function pickSessionFor(_player: Player): RoundManager.RoundManager?
	return sessions[Arena.DEFAULT_ID]
end

local function assignPlayerToSession(player: Player)
	local session = pickSessionFor(player)
	if not session then
		log:warn("No session available for", player.Name)
		return
	end

	playerSessions[player] = session
	session:addPlayer(player)
end

local function unassignPlayer(player: Player)
	local session = playerSessions[player]
	if session then
		session:removePlayer(player)
		playerSessions[player] = nil
	end
end

-- "Is *this player's* round active" — the per-session replacement for the
-- singleton's global `RoundManager.isActive()`.
local function isPlayerRoundActive(player: Player): boolean
	local session = playerSessions[player]
	return session ~= nil and session:isActive()
end

-- Which arena to spawn a player into. Falls back to the default arena for a
-- player with no session — the same "put them somewhere" instinct as
-- SpawnManager's SpawnLocation fallback.
local function arenaIdForPlayer(player: Player): string
	local session = playerSessions[player]
	return session and session:getArenaId() or Arena.DEFAULT_ID
end

----------------------------------------------------------------------
-- Broadcast audience
----------------------------------------------------------------------
-- ScoreTracker and BossService also send screen-space remotes, and neither
-- can be handed a roster the way RoundManager holds one: ScoreTracker is a
-- server-wide singleton and BossService is a top-level Script nothing
-- injects into. Registering a resolver over the session tables gives them
-- the same answer without either of them learning what a session is.
--
-- `nil` means "no session", which BroadcastAudience reads as "fall back to
-- every client" — deliberately not the same as an empty roster.
local function registerBroadcastAudience()
	BroadcastAudience.setResolver({
		forPlayer = function(player: Player): { Player }?
			local session = playerSessions[player]
			return session and session:getPlayers()
		end,

		forArena = function(arenaId: string): { Player }?
			local session = sessions[arenaId]
			return session and session:getPlayers()
		end,
	})
end

----------------------------------------------------------------------
-- Player management
----------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	activeMode.onPlayerJoin(player)

	ScoreTracker.addPlayer(player)
	assignPlayerToSession(player)

	-- Per-character setup: spawn protection + Died → respawn loop.
	-- Defined as a local so we can both Connect it for future spawns
	-- AND apply it to the very-first character (which may or may not
	-- exist yet depending on CharacterAutoLoads / our explicit
	-- LoadCharacter below).
	local function setupCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid")

		-- Spawn protection: ForceField blocks all damage for a short duration
		if isPlayerRoundActive(player) then
			local forceField = Instance.new("ForceField")
			forceField.Parent = character
			task.delay(GameModeConstants.SPAWN_PROTECTION_DURATION, function()
				if forceField and forceField.Parent then
					forceField:Destroy()
				end
			end)
		end

		-- Auto-respawn: when character dies during an active round,
		-- wait the configured respawn time then respawn at best spawn
		humanoid.Died:Connect(function()
			if not isPlayerRoundActive(player) then
				return
			end

			local config = activeMode.getConfig()
			task.wait(config.respawnTime)

			-- Player may have left during respawn wait
			if player.Parent == nil then
				return
			end

			local spawnCFrame = SpawnManager.getBestSpawn(player, arenaIdForPlayer(player))
			player:LoadCharacter()

			-- PivotTo after character loads
			local newCharacter = player.Character or player.CharacterAdded:Wait()
			task.wait() -- wait one frame for character to initialize
			newCharacter:PivotTo(spawnCFrame)
		end)
	end

	-- Connect FIRST so the next character (whether triggered by us via
	-- LoadCharacter below, or by Roblox auto-load in non-team modes) gets
	-- its Died handler. Then handle any character that's already loaded
	-- (e.g. a player joining mid-round in a non-team mode).
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		setupCharacter(player.Character)
	end

	log:info("Player added:", player.Name)
end

local function onPlayerRemoving(player: Player)
	unassignPlayer(player)
	ScoreTracker.removePlayer(player)
	log:info("Player removing:", player.Name)
end

----------------------------------------------------------------------
-- Kill tracking (hooks into Health system)
----------------------------------------------------------------------

local function onPlayerEliminated(sourcePlayer: Player?, targetHumanoid: Humanoid, _result)
	local targetCharacter = targetHumanoid:FindFirstAncestorOfClass("Model")
	if not targetCharacter then
		return
	end

	local victim = Players:GetPlayerFromCharacter(targetCharacter)
	if not victim then
		return -- NPC/dummy kill, not tracked by game mode
	end

	-- Determine weapon name from the source player's equipped tool
	local weaponName = "Unknown"
	if sourcePlayer and sourcePlayer.Character then
		local tool = sourcePlayer.Character:FindFirstChildOfClass("Tool")
		if tool then
			weaponName = tool.Name
		end
	end

	-- Let the game mode definition process the kill (e.g., Gun Game weapon switch)
	local scoreChange = activeMode.onPlayerKill(sourcePlayer, victim, weaponName)

	-- Record in ScoreTracker (handles broadcast to clients)
	ScoreTracker.recordKill(sourcePlayer, victim, weaponName)
end

----------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------

local function initialize()
	log:info(string.format("Initializing with mode: %s (key=%s, requested=%s)",
		activeMode.name, resolvedModeKey, tostring(requestedModeKey)))

	-- First, so nothing broadcasts before an audience can be resolved. The
	-- resolver reads the session tables lazily, so it is safe to register
	-- before any session exists — an unresolved lookup falls back to every
	-- client, which is exactly the pre-stage-3 behaviour.
	registerBroadcastAudience()

	-- Initialize sub-systems with dependency injection
	ScoreTracker.initialize({
		scoreUpdateRemote = scoreUpdateRemote,
		killFeedRemote = killFeedRemote,
		playerDamagedEvent = playerDamagedEvent,
	})

	SpawnManager.initialize()

	-- Create the session before wiring players, so every player added below
	-- has somewhere to be assigned. createSession registers the arena's
	-- spawns, so this must precede any getBestSpawn call.
	createSession(Arena.DEFAULT_ID, activeMode)

	-- Wire up player events
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Wire up Health system events
	playerEliminatedEvent.Event:Connect(onPlayerEliminated)

	-- Start each session's round loop
	for arenaId, session in sessions do
		session:start()
		log:info("Session started:", arenaId)
	end

	log:info("Initialized — round loop started")
end

initialize()
