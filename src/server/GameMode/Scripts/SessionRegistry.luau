----------------------------------------------------------------------
-- SessionRegistry
----------------------------------------------------------------------
-- The server's session tables, as a module: which sessions exist, which one
-- each player is in, and who is queued. `GameModeService` used to hold these
-- in a Script and hand them out through untyped Bindable functions
-- (`TransferPlayer`, `SetPlayerQueued`, `AllowsPvP`); every consumer now
-- requires this module instead (refactor chunk 8, F16 / Q6).
--
-- A session is a `RoundManager`: one mode definition bound to one arena
-- slot, with its own roster, round and scores. This module is the only
-- thing that creates one, and the only writer of the two Player attributes
-- (`ArenaId`, `PlayerState`) that publish where a player is.
--
-- Consumers:
--   GameModeService   — boot wiring, join/leave, kill routing
--   LobbyService      — transferPlayer / setQueued from the portals
--   HealthService     — allowsPvPFor(victim)
--   BroadcastAudience — resolver registered here at initialize()
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BroadcastAudience = require(ReplicatedStorage.Shared.GameMode.BroadcastAudience)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

-- Sibling ModuleScripts under the GameModeService Script. Required from here
-- rather than injected: a session *is* a RoundManager, and this registry is
-- the one thing that creates them.
local gameModeService = script.Parent:WaitForChild("GameModeService")
local RoundManager = require(gameModeService:WaitForChild("RoundManager"))
local SpawnManager = require(gameModeService:WaitForChild("SpawnManager"))

local log = Logger.new("SessionRegistry")

export type Session = RoundManager.RoundManager

export type Dependencies = {
	gameStateChangedRemote: RemoteEvent,
	roundStartedEvent: BindableEvent,
	roundEndedEvent: BindableEvent,
	-- What a player with no session answers mode questions with: the arena
	-- mode the server booted with. Only reachable in the gap between a
	-- player joining and being assigned, or after they were unassigned.
	fallbackMode: any,
}

local SessionRegistry = {}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

local sessions: { [string]: Session } = {}
local playerSessions: { [Player]: Session } = {}
-- Queue membership, pushed in by LobbyService. `Queued` is the one part of
-- PlayerState that cannot be derived from a roster — a queued player is
-- standing in the lobby like everybody else.
local queued: { [Player]: true } = {}

local refs: Dependencies? = nil

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- Absent `runsRounds` means true, so a mode written before the lobby keeps
-- its round loop without being edited.
local function runsRounds(modeDefinition: any): boolean
	return modeDefinition.getConfig().runsRounds ~= false
end

-- Publish the player's position in the lobby → arena cycle onto the Player
-- instance, where every client can read it without a remote.
--
-- The arena half is *derived* from the session's mode rather than stored,
-- so it cannot drift out of step with the roster it describes. `Queued` is
-- the exception and has to be pushed in.
local function publishPlayerState(player: Player)
	local session = playerSessions[player]
	if not session then
		player:SetAttribute(Arena.ID_ATTRIBUTE, nil)
		player:SetAttribute(Arena.STATE_ATTRIBUTE, nil)
		return
	end

	local state: string
	if runsRounds(session:getMode()) then
		state = Arena.PlayerState.InArena
	elseif queued[player] then
		state = Arena.PlayerState.Queued
	else
		state = Arena.PlayerState.InLobby
	end

	player:SetAttribute(Arena.ID_ATTRIBUTE, session:getArenaId())
	player:SetAttribute(Arena.STATE_ATTRIBUTE, state)
end

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------

-- Called once by GameModeService. Registers the BroadcastAudience resolver
-- here rather than in the service: the resolver reads these tables, and
-- the tables live here. It reads them lazily, so registering before any
-- session exists is safe — an unresolved lookup falls back to every client.
function SessionRegistry.initialize(dependencies: Dependencies)
	if refs then
		log:warn("Already initialized")
		return
	end
	refs = dependencies

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

	log:info("Initialized")
end

function SessionRegistry.runsRounds(modeDefinition: any): boolean
	return runsRounds(modeDefinition)
end

----------------------------------------------------------------------
-- Sessions
----------------------------------------------------------------------

-- Creates a session for an arena slot and binds the arena's spawn pads at
-- the same moment, so there is one place that knows an arena was created.
-- Does not start the round loop — that is the caller's decision, and the
-- lobby's session is never started.
function SessionRegistry.create(arenaId: string, modeDefinition: any): Session
	local dependencies = refs
	assert(dependencies, "SessionRegistry.create called before initialize")

	local existing = sessions[arenaId]
	if existing then
		log:warn(string.format("Session already exists for arena %s", arenaId))
		return existing
	end

	local session = RoundManager.new({
		arenaId = arenaId,
		gameStateChangedRemote = dependencies.gameStateChangedRemote,
		roundStartedEvent = dependencies.roundStartedEvent,
		roundEndedEvent = dependencies.roundEndedEvent,
		modeDefinition = modeDefinition,
	})

	SpawnManager.registerArena(arenaId, modeDefinition.getConfig().spawnTag)

	sessions[arenaId] = session
	return session
end

-- Permanent teardown of one session. Players still mapped to it are
-- unassigned (attributes cleared) rather than moved: where they should go
-- is the caller's decision.
function SessionRegistry.destroy(arenaId: string)
	local session = sessions[arenaId]
	if not session then
		return
	end

	for player, owner in playerSessions do
		if owner == session then
			playerSessions[player] = nil
			queued[player] = nil
			publishPlayerState(player)
		end
	end

	sessions[arenaId] = nil
	SpawnManager.unregisterArena(arenaId)
	session:destroy()
end

function SessionRegistry.all(): { [string]: Session }
	return sessions
end

function SessionRegistry.forArena(arenaId: string): Session?
	return sessions[arenaId]
end

function SessionRegistry.forPlayer(player: Player): Session?
	return playerSessions[player]
end

-- The players in an arena's session; nil when no session exists for it,
-- which is distinct from an empty roster.
function SessionRegistry.rosterOf(arenaId: string): { Player }?
	local session = sessions[arenaId]
	return session and session:getPlayers()
end

----------------------------------------------------------------------
-- Per-player answers
----------------------------------------------------------------------

-- The mode a player is currently living under. With two sessions running
-- different definitions, "the active mode" is no longer a single answer:
-- respawn time and kill credit belong to the player's session, not to
-- whichever mode the server booted the arena with.
function SessionRegistry.modeFor(player: Player): any
	local session = playerSessions[player]
	if session then
		return session:getMode()
	end
	return refs and refs.fallbackMode or nil
end

-- Which arena to spawn a player into. Falls back to the default arena for a
-- player with no session — the same "put them somewhere" instinct as
-- SpawnManager's SpawnLocation fallback.
function SessionRegistry.arenaIdFor(player: Player): string
	local session = playerSessions[player]
	return session and session:getArenaId() or Arena.DEFAULT_ID
end

-- "Is *this player's* round active" — the per-session replacement for the
-- old singleton's global `isActive()`.
function SessionRegistry.isRoundActiveFor(player: Player): boolean
	local session = playerSessions[player]
	return session ~= nil and session:isActive()
end

-- HealthService's PvP gate: may other players damage this one? Answered
-- from the *victim's* session, so a duellist and a lobby player on the same
-- server get different answers. Before boot, or for a player with no
-- session, the answer is no.
function SessionRegistry.allowsPvPFor(victim: Player): boolean
	local mode = SessionRegistry.modeFor(victim)
	if not mode then
		return false
	end
	return mode.getConfig().allowsPvP == true
end

----------------------------------------------------------------------
-- Membership
----------------------------------------------------------------------

-- Which session a joining player belongs to: the hub, always. Walking out
-- of it is `transferPlayer`, and there is no path that puts a joining player
-- straight into an arena — see `wiki/design/lobby.md` § Player state.
function SessionRegistry.assign(player: Player): Session?
	local session = sessions[Arena.LOBBY_ID]
	if not session then
		log:warn("No lobby session to assign", player.Name, "to")
		return nil
	end

	playerSessions[player] = session
	session:addPlayer(player)
	publishPlayerState(player)
	return session
end

function SessionRegistry.unassign(player: Player)
	local session = playerSessions[player]
	if session then
		session:removePlayer(player)
		playerSessions[player] = nil
	end
	queued[player] = nil
	publishPlayerState(player)
end

-- Queue membership is meaningless once a player is in an arena, so
-- entering one clears it rather than leaving a stale flag to surface on
-- the way back out. Returns false for a player with no session.
function SessionRegistry.setQueued(player: Player, isQueued: boolean): boolean
	if not playerSessions[player] then
		return false
	end
	queued[player] = if isQueued then true else nil
	publishPlayerState(player)
	return true
end

----------------------------------------------------------------------
-- Transfer
----------------------------------------------------------------------
-- Move a player from one session to another. The whole of the lobby's
-- interesting behaviour, and what the PvE queue and the duel pads reduce to
-- once they have a queue in front of them.
--
-- The character is **pivoted, not reloaded**. Reloading would be the more
-- obvious "fresh start", but it resets health, drops the equipped Tool and
-- rebuilds every ScreenGui with `ResetOnSpawn = true` on a path a player
-- crosses several times a session. Restoring health belongs to a mode's
-- round start, where it can mean something; a transfer just moves you.
-- A player with no living character is reloaded, because there is nothing
-- to pivot.
function SessionRegistry.transferPlayer(player: Player, targetArenaId: string): boolean
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
	-- Either they got the slot they queued for or they went home. Both
	-- end the wait, and a stale flag would surface on the way back out.
	queued[player] = nil
	publishPlayerState(player)

	-- After the roster move, so the spawn scoring sees the player as
	-- belonging to the arena it is picking a pad in, and scores threats
	-- from that arena's roster alone.
	local spawnCFrame = SpawnManager.getBestSpawn(player, targetArenaId, target:getPlayers())

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

return SessionRegistry
