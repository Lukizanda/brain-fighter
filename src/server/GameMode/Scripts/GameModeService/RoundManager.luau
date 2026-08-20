----------------------------------------------------------------------
-- RoundManager
----------------------------------------------------------------------
-- One round state machine per **session**: WaitingForPlayers → Countdown →
-- Active → PostRound → loop.
--
-- A session is one game mode definition bound to one arena slot, running its
-- own round lifecycle over its own roster of players — see
-- `wiki/design/lobby.md` § Session model. Phase 6 stage 1 turned this from a
-- server-wide singleton into an instance; `GameModeService` owns the table of
-- sessions and there is exactly one of them today, so behaviour is unchanged.
--
-- Mode-agnostic: the game mode definition provides win conditions and
-- callbacks. `GameModeService` wires each session up with ScoreTracker and
-- SpawnManager (both still server-wide singletons — stage 2/4 work).
--
-- Usage:
--   local session = RoundManager.new({ arenaId = "Default", ... })
--   session:addPlayer(player)  -- roster drives broadcasts + the min-player gate
--   session:start()            -- begins the loop
--   session:disable()          -- halts the loop (reversible)
--   session:destroy()          -- disable + drop all state (permanent)
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

local log = Logger.new("RoundManager")

local RoundState = GameModeConstants.RoundState

export type Dependencies = {
	-- Identifies the arena slot this session runs in. Stage 1 uses a single
	-- whole-server id; stage 2 binds these to tagged arena zones.
	arenaId: string,
	gameStateChangedRemote: RemoteEvent,
	roundStartedEvent: BindableEvent,
	roundEndedEvent: BindableEvent,
	modeDefinition: any, -- GameModeDefinition table
	scoreTracker: any, -- ScoreTracker module
	onRoundEnd: ((winnerId: number?, winnerName: string?, winnerTeamName: string?) -> ())?,
}

local RoundManager = {}
RoundManager.__index = RoundManager

export type RoundManager = typeof(setmetatable(
	{} :: {
		arenaId: string,
		_refs: Dependencies,
		_roster: { [Player]: true },
		_currentState: string,
		_timeRemaining: number,
		_running: boolean,
		_destroyed: boolean,
		-- Bumped on every `start()`. The round loop captures its value and
		-- checks it at every await point, so a `disable()` immediately
		-- followed by a `start()` cannot leave the old loop running
		-- alongside the new one.
		_generation: number,
		_thread: thread?,
	},
	RoundManager
))

function RoundManager.new(dependencies: Dependencies): RoundManager
	local self = setmetatable({
		arenaId = dependencies.arenaId,
		_refs = dependencies,
		_roster = {},
		_currentState = RoundState.WaitingForPlayers,
		_timeRemaining = 0,
		_running = false,
		_destroyed = false,
		_generation = 0,
		_thread = nil,
	}, RoundManager)

	log:info(string.format("[%s] Session created with mode: %s",
		self.arenaId, tostring(dependencies.modeDefinition.name)))

	return self
end

----------------------------------------------------------------------
-- Roster
----------------------------------------------------------------------
-- The set of players this session owns. Everything that used to reach for
-- `Players:GetPlayers()` reads this instead, so a second session's round
-- state never reaches players who aren't in it.

function RoundManager:addPlayer(player: Player)
	if self._destroyed then
		log:warn(string.format("[%s] addPlayer on a destroyed session: %s", self.arenaId, player.Name))
		return
	end
	self._roster[player] = true
end

function RoundManager:removePlayer(player: Player)
	self._roster[player] = nil
end

function RoundManager:hasPlayer(player: Player): boolean
	return self._roster[player] == true
end

function RoundManager:getPlayers(): { Player }
	local players: { Player } = {}
	for player in self._roster do
		table.insert(players, player)
	end
	return players
end

function RoundManager:getPlayerCount(): number
	local count = 0
	for _ in self._roster do
		count += 1
	end
	return count
end

----------------------------------------------------------------------
-- Loop liveness
----------------------------------------------------------------------
-- Single predicate for "should the loop that started at `generation` keep
-- going". Every await point in the state machine is a `task.wait` guarded by
-- this, which is what makes the flag-based `disable()` sufficient on its own.

function RoundManager:_isLive(generation: number): boolean
	return self._running and not self._destroyed and self._generation == generation
end

----------------------------------------------------------------------
-- State broadcast
----------------------------------------------------------------------

function RoundManager:_broadcastState(winnerId: number?, winnerName: string?, winnerTeamName: string?)
	if self._destroyed then
		return
	end

	local remote = self._refs.gameStateChangedRemote
	if not remote then
		return
	end

	local payload = {
		roundState = self._currentState,
		timeRemaining = self._timeRemaining,
		winnerId = winnerId,
		winnerName = winnerName,
		winnerTeamName = winnerTeamName,
	}

	-- Per-roster `FireClient`, not `FireAllClients`: with more than one
	-- session live, a duellist would otherwise receive the boss arena's
	-- round state. Unobservable with today's single session, but it is the
	-- reason this refactor exists. The payload shape is deliberately
	-- unchanged — GameStateGui, RoundTimerGui and DeathScreenGui consume it.
	for player in self._roster do
		if player.Parent then
			remote:FireClient(player, payload)
		end
	end
end

----------------------------------------------------------------------
-- State handlers
----------------------------------------------------------------------

function RoundManager:_waitForPlayers(generation: number)
	self._currentState = RoundState.WaitingForPlayers
	log:info(string.format("[%s] Waiting for players... (need %d)",
		self.arenaId, GameModeConstants.MIN_PLAYERS))
	self:_broadcastState()

	while self:_isLive(generation) do
		-- Roster count, not the server population: another session's players
		-- must not be able to start this one's round.
		if self:getPlayerCount() >= GameModeConstants.MIN_PLAYERS then
			return
		end
		self:_broadcastState()
		task.wait(1)
	end
end

function RoundManager:_countdown(generation: number)
	if not GameConfig.ROUND_COUNTDOWN_ENABLED then
		log:info(string.format("[%s] Countdown disabled — skipping", self.arenaId))
		return
	end

	self._currentState = RoundState.Countdown
	self._timeRemaining = GameModeConstants.COUNTDOWN_DURATION
	log:info(string.format("[%s] Countdown: %d seconds", self.arenaId, self._timeRemaining))

	while self:_isLive(generation) and self._timeRemaining > 0 do
		self:_broadcastState()
		task.wait(1)
		self._timeRemaining -= 1
	end

	if not self:_isLive(generation) then
		return
	end

	self:_broadcastState()
end

function RoundManager:_activeRound(generation: number): (number?, string?)
	self._currentState = RoundState.Active
	local config = self._refs.modeDefinition.getConfig()
	self._timeRemaining = GameConfig.ROUND_TIMER_ENABLED and config.timeLimit or 0

	-- Reset scores and notify. The roster goes with it so the resulting
	-- ScoreUpdate lands on this session's players rather than the server —
	-- the scores it resets are still server-wide (stage 5), the broadcast is
	-- not. See `wiki/design/lobby.md` § Broadcast audience.
	self._refs.scoreTracker.resetAll(self:getPlayers())
	self._refs.modeDefinition.onRoundStart()
	self._refs.roundStartedEvent:Fire()

	log:info(string.format("[%s] Round started! Timer: %s Score limit: %s",
		self.arenaId,
		GameConfig.ROUND_TIMER_ENABLED and (self._timeRemaining .. "s") or "disabled",
		tostring(config.scoreLimit)))
	self:_broadcastState()

	while self:_isLive(generation) do
		task.wait(1)
		if not self:_isLive(generation) then
			break
		end

		if GameConfig.ROUND_TIMER_ENABLED then
			self._timeRemaining -= 1
			if self._timeRemaining <= 0 then
				break
			end
		end

		-- Check win condition each tick
		local scores = self._refs.scoreTracker.getAllScores()
		local shouldEnd, winnerId, winnerTeamName = self._refs.modeDefinition.checkWinCondition(scores)
		if shouldEnd then
			log:info(string.format("[%s] Win condition met! Winner: %s",
				self.arenaId,
				winnerTeamName or (winnerId and ("UserId=" .. winnerId)) or "none"))
			return winnerId, winnerTeamName
		end

		-- Broadcast time update every second
		self:_broadcastState()
	end

	-- Halted mid-round rather than reaching the time limit — there is no
	-- winner to resolve, and the caller is about to break out anyway.
	if not self:_isLive(generation) then
		return nil, nil
	end

	-- Time ran out — ask the mode who's leading.
	local scores = self._refs.scoreTracker.getAllScores()
	local leaderId, leaderTeamName = self._refs.modeDefinition.getRoundLeader(scores)
	return leaderId, leaderTeamName
end

function RoundManager:_postRound(generation: number, winnerId: number?, winnerName: string?, winnerTeamName: string?)
	self._currentState = RoundState.PostRound
	self._timeRemaining = GameModeConstants.INTERMISSION_DURATION

	self._refs.modeDefinition.onRoundEnd()
	self._refs.roundEndedEvent:Fire(winnerId, winnerName, winnerTeamName)

	local label = winnerTeamName and (winnerTeamName .. " team")
		or winnerName
		or "none"
	log:info(string.format("[%s] Round over! Winner: %s. Intermission: %ds",
		self.arenaId, label, self._timeRemaining))

	if self._refs.onRoundEnd then
		self._refs.onRoundEnd(winnerId, winnerName, winnerTeamName)
	end

	self:_broadcastState(winnerId, winnerName, winnerTeamName)

	while self:_isLive(generation) and self._timeRemaining > 0 do
		task.wait(1)
		self._timeRemaining -= 1
		self:_broadcastState(winnerId, winnerName, winnerTeamName)
	end
end

----------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------

function RoundManager:_roundLoop(generation: number)
	while self:_isLive(generation) do
		self:_waitForPlayers(generation)
		if not self:_isLive(generation) then break end

		self:_countdown(generation)
		if not self:_isLive(generation) then break end

		local winnerId, winnerTeamName = self:_activeRound(generation)
		if not self:_isLive(generation) then break end

		-- Resolve player winner's display name (team-mode rounds skip this).
		-- Scans the roster: a winner of this round is by definition in it.
		local winnerName: string? = nil
		if winnerId then
			for player in self._roster do
				if player.UserId == winnerId then
					winnerName = player.Name
					break
				end
			end
		end

		self:_postRound(generation, winnerId, winnerName, winnerTeamName)
	end

	log:info(string.format("[%s] Round loop stopped", self.arenaId))
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function RoundManager:getArenaId(): string
	return self.arenaId
end

function RoundManager:getState(): string
	return self._currentState
end

function RoundManager:getTimeRemaining(): number
	return self._timeRemaining
end

function RoundManager:isActive(): boolean
	return self._currentState == RoundState.Active
end

function RoundManager:start()
	if self._destroyed then
		log:warn(string.format("[%s] Cannot start a destroyed session", self.arenaId))
		return
	end
	if self._running then
		log:warn(string.format("[%s] Already running", self.arenaId))
		return
	end

	self._running = true
	self._generation += 1

	local generation = self._generation
	self._thread = task.spawn(function()
		self:_roundLoop(generation)
	end)

	log:info(string.format("[%s] Started", self.arenaId))
end

-- Reversible halt (the old singleton's `stop()`). Clearing `_running` is the
-- only stop signal the loop needs: every await point is a `task.wait` inside
-- an `_isLive` check, so the loop unwinds itself within a second.
--
-- Deliberately NOT `task.cancel(self._thread)`, which the singleton also did.
-- Cancelling a thread parked in `task.wait` is redundant with the flag and
-- adds failure modes the flag does not have: `task.cancel` errors on a thread
-- that has already finished (the old `stop()` never cleared `roundThread` on
-- natural exit, so a second `stop()` would have thrown), it errors if a mode
-- callback such as `onRoundEnd` ever calls back into the session from the
-- round thread itself, and it tears the machine down between statements
-- rather than at a checkpoint. The one thing cancel bought — no overlap
-- between an old loop and a `start()` issued in the same second — is covered
-- by `_generation`.
function RoundManager:disable()
	self._running = false
	self._thread = nil
	self._currentState = RoundState.WaitingForPlayers
	self._timeRemaining = 0
	log:info(string.format("[%s] Disabled", self.arenaId))
end

-- Permanent teardown. `_refs` is deliberately left in place: a loop halted by
-- `disable()` above is still parked in a `task.wait` and will touch it once
-- more on its way out. The instance is dropped by its owner, so the
-- dependency table goes with it; the roster is what actually holds
-- references worth clearing eagerly.
function RoundManager:destroy()
	if self._destroyed then
		return
	end

	self:disable()
	self._destroyed = true
	table.clear(self._roster)

	log:info(string.format("[%s] Destroyed", self.arenaId))
end

return RoundManager
