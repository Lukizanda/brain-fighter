----------------------------------------------------------------------
-- GameModeService
----------------------------------------------------------------------
-- Boot wiring for the session system. The session tables themselves live
-- in `SessionRegistry` (a module, so LobbyService and HealthService require
-- it rather than invoking Bindable functions — refactor chunk 8). This
-- Script does what a Script is for:
--
--   * resolves the remotes/events and the boot mode,
--   * initializes ScoreTracker (server-wide damage listener), SpawnManager
--     and SessionRegistry, then creates the two sessions — the hub and the
--     arena — and starts the one whose mode runs rounds,
--   * owns the player lifecycle: join → lobby session, leave → unassign,
--     and every character a player ever gets (chunk 5: one respawn owner),
--   * routes a player kill to the victim's session, whose ScoreTracker
--     credits it.
--
-- Hooks into the Health system via BindableEvents. Does NOT modify the
-- damage pipeline — listens to events only.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local GameModes = require(ReplicatedStorage.Shared.GameMode.Modes)
-- Required directly rather than resolved through the registry: which mode
-- the *arena* runs is a configurable question ("ActiveGameMode"), whether
-- there is a hub is not.
local LobbyMode = require(ReplicatedStorage.Shared.GameMode.Modes.LobbyMode)

local ACTIVE_MODE_ATTRIBUTE = "ActiveGameMode"

local ScoreTracker = require(script.ScoreTracker)
local SpawnManager = require(script.SpawnManager)
local SessionRegistry = require(script.Parent.SessionRegistry)

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
-- Boot mode
-- Resolved from workspace:GetAttribute("ActiveGameMode") at boot;
-- falls back to the registry default. Set the attribute in Studio
-- Properties before starting the server to pick a different mode.
----------------------------------------------------------------------
local requestedModeKey = workspace:GetAttribute(ACTIVE_MODE_ATTRIBUTE)
local activeMode, resolvedModeKey = GameModes.get(requestedModeKey)

----------------------------------------------------------------------
-- Player lifecycle
----------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	ScoreTracker.ensureLeaderstats(player)

	-- Assign before the mode hook, so `onPlayerJoin` is the *lobby's* hook
	-- rather than the arena's. It is the same call on the same player; the
	-- ordering is what stops "which mode did this player join under" from
	-- having two answers.
	SessionRegistry.assign(player)
	SessionRegistry.modeFor(player).onPlayerJoin(player)

	-- Per-character setup: spawn protection + Died → respawn loop.
	-- Defined as a local so we can both Connect it for future spawns
	-- AND apply it to the very-first character (a player already in the
	-- server when this Script initialized).
	local function setupCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid")

		-- Spawn protection: ForceField blocks all damage for a short duration
		if SessionRegistry.isRoundActiveFor(player) then
			local forceField = Instance.new("ForceField")
			forceField.Parent = character
			task.delay(GameModeConstants.SPAWN_PROTECTION_DURATION, function()
				if forceField and forceField.Parent then
					forceField:Destroy()
				end
			end)
		end

		-- Auto-respawn: wait the configured respawn time, then respawn at
		-- the best pad in whichever arena the player belongs to.
		--
		-- Gated on "has a session", not on "round active". The hub's
		-- session never enters Active, and a player who fell off the lobby
		-- still has to come back.
		humanoid.Died:Connect(function()
			if not SessionRegistry.forPlayer(player) then
				return
			end

			local config = SessionRegistry.modeFor(player).getConfig()
			task.wait(config.respawnTime)

			-- Player may have left during respawn wait
			if player.Parent == nil then
				return
			end

			local arenaId = SessionRegistry.arenaIdFor(player)
			local spawnCFrame = SpawnManager.getBestSpawn(player, arenaId, SessionRegistry.rosterOf(arenaId))
			player:LoadCharacter()

			-- PivotTo after character loads
			local newCharacter = player.Character or player.CharacterAdded:Wait()
			task.wait() -- wait one frame for character to initialize
			newCharacter:PivotTo(spawnCFrame)
		end)
	end

	-- Connect FIRST so the character we load below gets its Died handler.
	-- Then either adopt a character that already exists (a player who was
	-- in the server before this Script initialized) or spawn the first one.
	--
	-- `CharacterAutoLoads` is false (see `initialize`), so this is the only
	-- thing that gives a joining player a body. Deliberately a bare
	-- `LoadCharacter` rather than a pad pick: the engine's SpawnLocation
	-- choice is what auto-load used to do, and the first spawn is into the
	-- lobby, which has no threat scoring to do.
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		setupCharacter(player.Character)
	else
		player:LoadCharacter()
	end

	log:info("Player added:", player.Name)
end

local function onPlayerRemoving(player: Player)
	SessionRegistry.unassign(player)
	ScoreTracker.forgetPlayer(player)
	log:info("Player removing:", player.Name)
end

----------------------------------------------------------------------
-- Kill tracking (hooks into Health system)
----------------------------------------------------------------------

local function onPlayerEliminated(sourcePlayer: Player?, targetHumanoid: Humanoid, result: DamageTypes.DamageResult?)
	local targetCharacter = targetHumanoid:FindFirstAncestorOfClass("Model")
	if not targetCharacter then
		return
	end

	local victim = Players:GetPlayerFromCharacter(targetCharacter)
	if not victim then
		return -- NPC/dummy kill, not tracked by game mode
	end

	-- The kill belongs to the *victim's* session: the victim is by
	-- definition in the arena the kill happened in, whereas a killer could
	-- in principle be reaching in from outside it.
	local session = SessionRegistry.forPlayer(victim)
	if not session then
		log:warn("Kill on a player with no session:", victim.Name)
		return
	end

	-- What the kill feed credits. The cause is stamped by whoever built
	-- the damage request — a skill name, a Cause id, a weapon name — which
	-- is the only party that knows.
	local cause = result and result.cause or DamageTypes.Cause.Unknown

	-- Let the mode process the kill (e.g. a Gun Game weapon switch), then
	-- the session's own tracker records and broadcasts it to its roster.
	session:getMode().onPlayerKill(sourcePlayer, victim, cause)
	session:recordKill(sourcePlayer, victim, cause)
end

----------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------

local function initialize()
	log:info(string.format("Initializing with mode: %s (key=%s, requested=%s)",
		activeMode.name, resolvedModeKey, tostring(requestedModeKey)))

	-- One respawn owner (chunk 5). The engine's auto-load was a third
	-- respawn path alongside this Script's `Died` handler and the old
	-- `RequestRespawn` remote, and it spawns a player wherever a
	-- SpawnLocation happens to be with no idea which session they are in.
	-- Turned off here, first thing, so that `onPlayerAdded` below is the
	-- only thing that ever hands a player their first character and the
	-- `Died` handler is the only thing that ever hands them a later one.
	Players.CharacterAutoLoads = false

	-- Initialize sub-systems with dependency injection. SessionRegistry
	-- registers the BroadcastAudience resolver, so it goes before anything
	-- that could broadcast.
	ScoreTracker.initialize({
		scoreUpdateRemote = scoreUpdateRemote,
		killFeedRemote = killFeedRemote,
		playerDamagedEvent = playerDamagedEvent,
	})

	SpawnManager.initialize()

	SessionRegistry.initialize({
		gameStateChangedRemote = gameStateChangedRemote,
		roundStartedEvent = roundStartedEvent,
		roundEndedEvent = roundEndedEvent,
		fallbackMode = activeMode,
	})

	-- Create both sessions before wiring players, so every player added
	-- below has somewhere to be assigned. `create` registers the arena's
	-- spawns, so this must precede any getBestSpawn call.
	--
	-- The lobby first, because it is the one players join.
	SessionRegistry.create(Arena.LOBBY_ID, LobbyMode)
	SessionRegistry.create(Arena.DEFAULT_ID, activeMode)

	-- Wire up player events
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Wire up Health system events
	playerEliminatedEvent.Event:Connect(onPlayerEliminated)

	-- Start each session's round loop. The lobby session is deliberately
	-- left unstarted: it holds a roster and owns spawn pads like any other
	-- session, it just has no round. That is the whole of how RoundManager
	-- avoids learning what a lobby is — see `Modes/LobbyMode.luau`.
	for arenaId, session in SessionRegistry.all() do
		if SessionRegistry.runsRounds(session:getMode()) then
			session:start()
			log:info("Session started:", arenaId)
		else
			log:info("Session idle (mode runs no rounds):", arenaId)
		end
	end

	log:info("Initialized — round loop started")
end

initialize()
