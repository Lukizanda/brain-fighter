----------------------------------------------------------------------
-- RoundManager
----------------------------------------------------------------------
-- Generic round state machine: WaitingForPlayers → Countdown → Active → PostRound → loop
-- Mode-agnostic: the game mode definition provides win conditions and callbacks.
-- The GameModeService wires this up with ScoreTracker and SpawnManager.
--
-- Usage:
--   RoundManager.initialize({ ... })
--   RoundManager.start() -- begins the loop
--   RoundManager.stop()  -- halts the loop
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

local log = Logger.new("RoundManager")

local RoundState = GameModeConstants.RoundState

local RoundManager = {}

-- Internal state
local currentState = RoundState.WaitingForPlayers
local timeRemaining = 0
local running = false
local roundThread: thread? = nil

-- Dependencies (injected via initialize)
local refs: {
	gameStateChangedRemote: RemoteEvent,
	roundStartedEvent: BindableEvent,
	roundEndedEvent: BindableEvent,
	modeDefinition: any, -- GameModeDefinition table
	scoreTracker: any, -- ScoreTracker module
	onRoundEnd: ((winnerId: number?, winnerName: string?, winnerTeamName: string?) -> ())?,
}

local initialized = false

----------------------------------------------------------------------
-- State broadcast
----------------------------------------------------------------------
local function broadcastState(winnerId: number?, winnerName: string?, winnerTeamName: string?)
	if not refs.gameStateChangedRemote then
		return
	end

	refs.gameStateChangedRemote:FireAllClients({
		roundState = currentState,
		timeRemaining = timeRemaining,
		winnerId = winnerId,
		winnerName = winnerName,
		winnerTeamName = winnerTeamName,
	})
end

----------------------------------------------------------------------
-- State handlers
----------------------------------------------------------------------

local function waitForPlayers()
	currentState = RoundState.WaitingForPlayers
	local config = refs.modeDefinition.getConfig()
	log:info("Waiting for players... (need", GameModeConstants.MIN_PLAYERS, ")")
	broadcastState()

	while running do
		if #Players:GetPlayers() >= GameModeConstants.MIN_PLAYERS then
			return
		end
		broadcastState()
		task.wait(1)
	end
end

local function countdown()
	currentState = RoundState.Countdown
	timeRemaining = GameModeConstants.COUNTDOWN_DURATION
	log:info("Countdown:", timeRemaining, "seconds")

	while running and timeRemaining > 0 do
		broadcastState()
		task.wait(1)
		timeRemaining -= 1
	end

	broadcastState()
end

local function activeRound()
	currentState = RoundState.Active
	local config = refs.modeDefinition.getConfig()
	timeRemaining = config.timeLimit

	-- Reset scores and notify
	refs.scoreTracker.resetAll()
	refs.modeDefinition.onRoundStart()
	refs.roundStartedEvent:Fire()

	log:info("Round started! Time limit:", timeRemaining, "Score limit:", config.scoreLimit)
	broadcastState()

	while running and timeRemaining > 0 do
		task.wait(1)
		timeRemaining -= 1

		-- Check win condition each tick
		local scores = refs.scoreTracker.getAllScores()
		local shouldEnd, winnerId, winnerTeamName = refs.modeDefinition.checkWinCondition(scores)
		if shouldEnd then
			log:info(string.format("Win condition met! Winner: %s",
				winnerTeamName or (winnerId and ("UserId=" .. winnerId)) or "none"))
			return winnerId, winnerTeamName
		end

		-- Broadcast time update every second
		broadcastState()
	end

	-- Time ran out — ask the mode who's leading.
	local scores = refs.scoreTracker.getAllScores()
	local leaderId, leaderTeamName = refs.modeDefinition.getRoundLeader(scores)
	return leaderId, leaderTeamName
end

local function postRound(winnerId: number?, winnerName: string?, winnerTeamName: string?)
	currentState = RoundState.PostRound
	timeRemaining = GameModeConstants.INTERMISSION_DURATION

	refs.modeDefinition.onRoundEnd()
	refs.roundEndedEvent:Fire(winnerId, winnerName, winnerTeamName)

	local label = winnerTeamName and (winnerTeamName .. " team")
		or winnerName
		or "none"
	log:info(string.format("Round over! Winner: %s. Intermission: %ds",
		label, timeRemaining))

	if refs.onRoundEnd then
		refs.onRoundEnd(winnerId, winnerName, winnerTeamName)
	end

	broadcastState(winnerId, winnerName, winnerTeamName)

	while running and timeRemaining > 0 do
		task.wait(1)
		timeRemaining -= 1
		broadcastState(winnerId, winnerName, winnerTeamName)
	end
end

----------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------
local function roundLoop()
	while running do
		waitForPlayers()
		if not running then break end

		countdown()
		if not running then break end

		local winnerId, winnerTeamName = activeRound()
		if not running then break end

		-- Resolve player winner's display name (team-mode rounds skip this)
		local winnerName: string? = nil
		if winnerId then
			for _, player in Players:GetPlayers() do
				if player.UserId == winnerId then
					winnerName = player.Name
					break
				end
			end
		end

		postRound(winnerId, winnerName, winnerTeamName)
	end

	log:info("Round loop stopped")
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function RoundManager.initialize(dependencies: {
	gameStateChangedRemote: RemoteEvent,
	roundStartedEvent: BindableEvent,
	roundEndedEvent: BindableEvent,
	modeDefinition: any,
	scoreTracker: any,
	onRoundEnd: ((winnerId: number?, winnerName: string?, winnerTeamName: string?) -> ())?,
})
	if initialized then
		log:warn("Already initialized")
		return
	end

	refs = dependencies
	initialized = true
	log:info("Initialized with mode:", refs.modeDefinition.name)
end

function RoundManager.start()
	if running then
		log:warn("Already running")
		return
	end

	running = true
	roundThread = task.spawn(roundLoop)
	log:info("Started")
end

function RoundManager.stop()
	running = false
	if roundThread then
		task.cancel(roundThread)
		roundThread = nil
	end
	currentState = RoundState.WaitingForPlayers
	timeRemaining = 0
	log:info("Stopped")
end

function RoundManager.getState(): string
	return currentState
end

function RoundManager.getTimeRemaining(): number
	return timeRemaining
end

function RoundManager.isActive(): boolean
	return currentState == RoundState.Active
end

return RoundManager
