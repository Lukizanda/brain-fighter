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
-- Stage 4a makes the second session real. The hub is an arena slot like any
-- other, running `LobbyMode`, and it is the session players join. What used
-- to be "the" session is now the arena they walk into. The primitive that
-- moves them is `transferPlayer`, exposed as a BindableFunction so stage 4c's
-- portal service can call it; stages 5 and 6 are that same call with a queue
-- in front of it.
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
-- Required directly rather than resolved through the registry: which mode
-- the *arena* runs is a configurable question ("ActiveGameMode"), whether
-- there is a hub is not.
local LobbyMode = require(ReplicatedStorage.Shared.GameMode.Modes.LobbyMode)

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

-- Server-side entry point for "move this player to that arena". A
-- BindableFunction rather than an exported module function because this file
-- is a Script, not a ModuleScript — the session tables live here and the
-- callers (stage 4c's portal service, dev probes) are other Scripts.
-- Invocation returns true on success, false with a reason logged otherwise.
local transferPlayerFunction = gameModeEvents.TransferPlayer

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

-- Absent `runsRounds` means true, so a mode written before stage 4a keeps
-- its round loop without being edited.
local function modeRunsRounds(modeDefinition: any): boolean
	return modeDefinition.getConfig().runsRounds ~= false
end

-- Which session a joining player belongs to: the hub, always. Walking out
-- of it is `transferPlayer`, and there is no path that puts a joining player
-- straight into an arena — see `wiki/design/lobby.md` § Player state.
local function pickSessionFor(_player: Player): RoundManager.RoundManager?
	return sessions[Arena.LOBBY_ID]
end

-- The mode a player is currently living under. With two sessions running
-- different definitions, "the active mode" is no longer a single answer:
-- respawn time and kill credit belong to the player's session, not to
-- whichever mode the server booted the arena with.
local function modeForPlayer(player: Player): any
	local session = playerSessions[player]
	return session and session:getMode() or activeMode
end

-- Which arena to spawn a player into. Falls back to the default arena for a
-- player with no session — the same "put them somewhere" instinct as
-- SpawnManager's SpawnLocation fallback.
local function arenaIdForPlayer(player: Player): string
	local session = playerSessions[player]
	return session and session:getArenaId() or Arena.DEFAULT_ID
end

-- Publish the player's position in the lobby → arena cycle onto the Player
-- instance, where every client can read it without a remote.
--
-- The state is *derived* from the session's mode rather than stored, so it
-- cannot drift out of step with the roster it describes. `Queued` is not
-- reachable yet: it belongs to stage 4c's portal queue, which is the only
-- thing that can hold a player in the hub while they wait for a slot.
local function publishPlayerState(player: Player)
	local session = playerSessions[player]
	if not session then
		player:SetAttribute(Arena.ID_ATTRIBUTE, nil)
		player:SetAttribute(Arena.STATE_ATTRIBUTE, nil)
		return
	end

	player:SetAttribute(Arena.ID_ATTRIBUTE, session:getArenaId())
	player:SetAttribute(Arena.STATE_ATTRIBUTE,
		modeRunsRounds(session:getMode()) and Arena.PlayerState.InArena or Arena.PlayerState.InLobby)
end

local function assignPlayerToSession(player: Player)
	local session = pickSessionFor(player)
	if not session then
		log:warn("No session available for", player.Name)
		return
	end

	playerSessions[player] = session
	session:addPlayer(player)
	publishPlayerState(player)
end

local function unassignPlayer(player: Player)
	local session = playerSessions[player]
	if session then
		session:removePlayer(player)
		playerSessions[player] = nil
	end
	publishPlayerState(player)
end

-- "Is *this player's* round active" — the per-session replacement for the
-- singleton's global `RoundManager.isActive()`.
local function isPlayerRoundActive(player: Player): boolean
	local session = playerSessions[player]
	return session ~= nil and session:isActive()
end

----------------------------------------------------------------------
-- Transfer
----------------------------------------------------------------------
-- Move a player from one session to another. The whole of stage 4's
-- interesting behaviour, and what stages 5 and 6 reduce to once they have a
-- queue in front of them.
--
-- The character is **pivoted, not reloaded**. Reloading would be the more
-- obvious "fresh start", but it resets health, drops the equipped Tool and
-- rebuilds every ScreenGui with `ResetOnSpawn = true` on a path a player
-- crosses several times a session. Restoring health belongs to a mode's
-- round start, where it can mean something; a transfer just moves you.
-- A player with no living character is reloaded, because there is nothing
-- to pivot.
local function transferPlayer(player: Player, targetArenaId: string): boolean
	if not player.Parent then
		return false
	end

	local target = sessions[targetArenaId]
	if not target then
		log:warn(string.format("Transfer refused: no session for arena %s", targetArenaId))
		return false
	end

	local current = playerSessions[player]
	if current == target then
		return true
	end

	if current then
		current:removePlayer(player)
	end

	playerSessions[player] = target
	target:addPlayer(player)
	publishPlayerState(player)

	-- After the roster move, so the spawn scoring sees the player as
	-- belonging to the arena it is picking a pad in.
	local spawnCFrame = SpawnManager.getBestSpawn(player, targetArenaId)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid and humanoid.Health > 0 then
		character:PivotTo(spawnCFrame)
	else
		player:LoadCharacter()
		local newCharacter = player.Character or player.CharacterAdded:Wait()
		task.wait() -- one frame for the character to initialize
		newCharacter:PivotTo(spawnCFrame)
	end

	log:info(string.format("Transferred %s: %s → %s",
		player.Name, current and current:getArenaId() or "<none>", targetArenaId))
	return true
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
	ScoreTracker.addPlayer(player)

	-- Assign before the mode hook, so `onPlayerJoin` is the *lobby's* hook
	-- rather than the arena's. It is the same call on the same player; the
	-- ordering is what stops "which mode did this player join under" from
	-- having two answers.
	assignPlayerToSession(player)
	modeForPlayer(player).onPlayerJoin(player)

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

		-- Auto-respawn: wait the configured respawn time, then respawn at
		-- the best pad in whichever arena the player belongs to.
		--
		-- Gated on "has a session", not on `isPlayerRoundActive`. The old
		-- gate was correct while every session ran a round; the hub's
		-- session never enters Active, so it would have left a player who
		-- fell off the lobby dead on the floor with nothing in the log.
		humanoid.Died:Connect(function()
			if not playerSessions[player] then
				return
			end

			local config = modeForPlayer(player).getConfig()
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

	-- Let the game mode definition process the kill (e.g., Gun Game weapon
	-- switch). Resolved from the *victim's* session: the victim is by
	-- definition in the arena the kill happened in, whereas a killer could
	-- in principle be reaching in from outside it.
	local scoreChange = modeForPlayer(victim).onPlayerKill(sourcePlayer, victim, weaponName)

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

	-- Create both sessions before wiring players, so every player added
	-- below has somewhere to be assigned. createSession registers the
	-- arena's spawns, so this must precede any getBestSpawn call.
	--
	-- The lobby first, because it is the one players join.
	createSession(Arena.LOBBY_ID, LobbyMode)
	createSession(Arena.DEFAULT_ID, activeMode)

	transferPlayerFunction.OnInvoke = function(player: Player, targetArenaId: string): boolean
		if typeof(player) ~= "Instance" or not player:IsA("Player") or type(targetArenaId) ~= "string" then
			log:warn("TransferPlayer invoked with bad arguments")
			return false
		end
		return transferPlayer(player, targetArenaId)
	end

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
	for arenaId, session in sessions do
		if modeRunsRounds(session:getMode()) then
			session:start()
			log:info("Session started:", arenaId)
		else
			log:info("Session idle (mode runs no rounds):", arenaId)
		end
	end

	log:info("Initialized — round loop started")
end

initialize()
