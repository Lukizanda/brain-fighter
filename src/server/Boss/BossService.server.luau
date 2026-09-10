--!strict

----------------------------------------------------------------------
-- BossService
----------------------------------------------------------------------
-- Top-level boss lifecycle: spawn → tick → death → respawn, one cycle
-- per arena session.
--
-- Responsibilities:
--   - Find the arena's BossPoint in Workspace (a BasePart named BossPoint
--     whose ArenaId attribute names the arena)
--   - Resolve boss type via BossPoint:GetAttribute("BossType"), fallback to DEFAULT_TYPE
--   - Build the Boss Model via BossSpawner and stamp it with the ArenaId
--   - Create a BossController and run it on Heartbeat
--   - Forward boss HP changes to the arena's roster via BossHealthChanged
--   - Forward phase changes via BossPhaseChanged
--   - Handle boss death: destroy controller, pause, respawn
--   - Start the cycle on the arena's RoundStarted, stop it on RoundEnded
--
-- Death handling: Boss is NOT tagged "Damageable" — BossService owns
-- the full lifecycle so DeathHandler won't respawn or create templates.
-- humanoid.Died fires naturally when health reaches 0 (from SpellExecutor
-- direct writes or applyDamage.process firearm hits).
--
-- Per-arena (refactor chunk 9). The boss used to be found once at boot as
-- `workspace.BossPoint` and lived for the server's lifetime, hunting
-- whoever was closest on the server. It is now created for an arena when
-- that arena's round starts — or at boot for a session already Active,
-- since the Default round starts during GameModeService's boot — and
-- torn down when the round ends. The Model carries the arena's ArenaId,
-- which is what scopes it: Perception (shared with the NPC system) scans
-- only that arena's roster, and the Hittables filter every skill reads
-- keeps its fire inside the arena. A hub player is never a boss target
-- because no boss carries `Lobby`.
--
-- Audience (Phase 6 stage 3): BossHealthChanged and BossPhaseChanged draw
-- the BossHudGui, so they are screen-space — a duellist receiving them gets
-- a boss health bar over a fight that has no boss in it. The audience is
-- the roster of the BossPoint's arena, resolved per fire because a roster
-- changes under a long-lived boss. Stage 5's `Modes/PvEBoss.luau` takes
-- ownership of the boss arena and sets the attribute rather than
-- inheriting the default; nothing below has to change for it. See
-- `wiki/design/lobby.md` § Broadcast audience.
----------------------------------------------------------------------

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig        = require(ReplicatedStorage.Shared.Boss.BossConfig)
local Arena             = require(ReplicatedStorage.Shared.GameMode.Arena)
local BroadcastAudience = require(ReplicatedStorage.Shared.GameMode.BroadcastAudience)
local Logger            = require(ReplicatedStorage.Shared.Core.Logger)

local BossSpawner    = require(script.Parent.Scripts.BossSpawner)
local BossController = require(script.Parent.Scripts.BossController)

-- Which sessions exist and whether their round is running, for the boot
-- reconcile. Called, never written to.
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local bossEvents        = ReplicatedStorage.Shared.Boss.BossEvents
local BossHealthChanged = bossEvents.BossHealthChanged :: RemoteEvent
local BossPhaseChanged  = bossEvents.BossPhaseChanged  :: RemoteEvent

local gameModeEvents    = ServerScriptService.Server.GameMode.Events
local roundStartedEvent = gameModeEvents.RoundStarted :: BindableEvent
local roundEndedEvent   = gameModeEvents.RoundEnded :: BindableEvent

local log = Logger.new("BossService")

-- phaseIndex = 0 is the client sentinel meaning "boss defeated / no boss"
local PHASE_DEFEATED      = 0
local HEALTH_THROTTLE_SEC = 0.1  -- max frequency of BossHealthChanged fires
-- The authored Part a boss spawns at. One per arena, carrying that
-- arena's ArenaId attribute (absent = Default, per Arena.idOf).
local BOSS_POINT_NAME     = "BossPoint"
-- Seconds before retrying a spawn BossSpawner refused.
local SPAWN_RETRY_SEC     = 5
-- Seconds the corpse stays for the death effect before the Model goes.
local DEATH_LINGER_SEC    = 1

type BossControllerInstance = BossController.BossControllerInstance

-- One arena's boss lifecycle: everything a stop has to undo.
type Cycle = {
	arenaId: string,
	bossPoint: BasePart,
	boss: Model?,
	controller: BossControllerInstance?,
	heartbeatConn: RBXScriptConnection?,
	-- The pending retry or respawn timer, so a round ending mid-wait
	-- doesn't spawn a boss into an arena with no round.
	pendingThread: thread?,
	stopped: boolean,
}

local cycles: { [string]: Cycle } = {}
local eventConns: { RBXScriptConnection } = {}

-- ---------------------------------------------------------------
-- BossPoint lookup
-- ---------------------------------------------------------------
local function bossPointFor(arenaId: string): BasePart?
	for _, inst in workspace:GetDescendants() do
		if inst.Name == BOSS_POINT_NAME and inst:IsA("BasePart") and Arena.idOf(inst) == arenaId then
			return inst
		end
	end
	return nil
end

-- ---------------------------------------------------------------
-- startBossCycle
-- Spawns a boss and wires up its lifetime. Called again on respawn
-- — each call is fully self-contained with its own Heartbeat
-- connection and Died listener, all recorded on the cycle so a stop
-- can undo them.
-- ---------------------------------------------------------------
local function startBossCycle(cycle: Cycle)
	if cycle.stopped then
		return
	end
	cycle.pendingThread = nil

	local arenaId = cycle.arenaId
	local bossPoint = cycle.bossPoint
	-- The roster behind the id is read at each fire — players join and
	-- leave a session while a boss is alive.
	local function bossAudience(): { Player }
		return BroadcastAudience.forArena(arenaId)
	end

	log:info(string.format("Starting boss cycle in arena %s", arenaId))

	local typeName = tostring(bossPoint:GetAttribute("BossType") or BossConfig.DEFAULT_TYPE)
	local typeSpec = BossConfig.BOSS_TYPES[typeName]
	assert(typeSpec, "Unknown boss type: " .. typeName)

	local boss = BossSpawner.spawn(bossPoint, typeSpec)
	if not boss then
		log:warn(string.format("BossSpawner returned nil — retrying in %d s", SPAWN_RETRY_SEC))
		cycle.pendingThread = task.delay(SPAWN_RETRY_SEC, function()
			startBossCycle(cycle)
		end)
		return
	end

	-- Which arena this boss fights for: Perception's target scope and the
	-- Hittables filter its own skills read.
	boss:SetAttribute(Arena.ID_ATTRIBUTE, arenaId)
	cycle.boss = boss

	local humanoid = boss:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		log:warn("Spawned boss has no Humanoid — aborting cycle")
		boss:Destroy()
		cycle.boss = nil
		return
	end

	-- Controller: phase-change callback fires the RemoteEvent
	local controller = BossController.new(boss, typeSpec, function(phaseIndex: number, _phaseSpec: any)
		BroadcastAudience.fire(BossPhaseChanged, bossAudience(), phaseIndex)
		log:info("Boss entered phase", phaseIndex)
	end)

	if not controller then
		log:warn("BossController failed to create — aborting cycle")
		boss:Destroy()
		cycle.boss = nil
		return
	end
	cycle.controller = controller

	-- Announce spawn to the arena
	local spawnAudience = bossAudience()
	BroadcastAudience.fire(BossPhaseChanged, spawnAudience, 1)
	BroadcastAudience.fire(BossHealthChanged, spawnAudience, humanoid.MaxHealth, humanoid.MaxHealth, 1)

	-- Throttled HP forwarding
	local lastHealthSendTime = 0

	humanoid.HealthChanged:Connect(function(health: number)
		local now = os.clock()
		if now - lastHealthSendTime < HEALTH_THROTTLE_SEC then return end
		lastHealthSendTime = now
		BroadcastAudience.fire(BossHealthChanged, bossAudience(),
			health, humanoid.MaxHealth, controller:getPhaseIndex())
	end)

	-- Main tick loop
	local heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		controller:tick(dt)
	end)
	cycle.heartbeatConn = heartbeatConn

	-- Death handling
	humanoid.Died:Connect(function()
		if cycle.stopped then
			return
		end
		heartbeatConn:Disconnect()
		cycle.heartbeatConn = nil
		controller:destroy()
		cycle.controller = nil

		-- Signal defeat (phaseIndex 0 = no boss)
		local deathAudience = bossAudience()
		BroadcastAudience.fire(BossHealthChanged, deathAudience, 0, humanoid.MaxHealth, PHASE_DEFEATED)
		BroadcastAudience.fire(BossPhaseChanged, deathAudience, PHASE_DEFEATED)

		log:info(string.format("[%s] Boss defeated — respawning in %d s", arenaId, typeSpec.respawnDelaySec))

		-- Brief pause for death effect visibility, then destroy model
		task.delay(DEATH_LINGER_SEC, function()
			if boss and boss.Parent then
				boss:Destroy()
			end
			if cycle.boss == boss then
				cycle.boss = nil
			end
		end)

		-- Respawn cycle
		cycle.pendingThread = task.delay(typeSpec.respawnDelaySec, function()
			startBossCycle(cycle)
		end)
	end)

	log:info(string.format("[%s] Boss cycle running", arenaId))
end

-- ---------------------------------------------------------------
-- Per-arena start / stop
-- ---------------------------------------------------------------
local function startArena(arenaId: string)
	if cycles[arenaId] then
		log:info(string.format("[%s] Boss cycle already running — leaving it", arenaId))
		return
	end

	local bossPoint = bossPointFor(arenaId)
	if not bossPoint then
		log:info(string.format("[%s] No %s for this arena — no boss", arenaId, BOSS_POINT_NAME))
		return
	end

	local cycle: Cycle = {
		arenaId = arenaId,
		bossPoint = bossPoint,
		boss = nil,
		controller = nil,
		heartbeatConn = nil,
		pendingThread = nil,
		stopped = false,
	}
	cycles[arenaId] = cycle
	startBossCycle(cycle)
end

-- Undo everything startBossCycle wired: the timer that would spawn the
-- next boss, the tick, the controller, and the Model — announcing the
-- defeat sentinel so the arena's BossHudGui clears rather than freezing
-- on the last health it saw.
local function stopArena(arenaId: string)
	local cycle = cycles[arenaId]
	if not cycle then
		return
	end
	cycles[arenaId] = nil
	cycle.stopped = true

	local pending = cycle.pendingThread
	if pending then
		pcall(task.cancel, pending)
		cycle.pendingThread = nil
	end
	if cycle.heartbeatConn then
		cycle.heartbeatConn:Disconnect()
		cycle.heartbeatConn = nil
	end
	if cycle.controller then
		cycle.controller:destroy()
		cycle.controller = nil
	end

	local boss = cycle.boss
	if boss and boss.Parent then
		local humanoid = boss:FindFirstChildOfClass("Humanoid")
		local maxHealth = if humanoid then humanoid.MaxHealth else 0
		local audience = BroadcastAudience.forArena(arenaId)
		BroadcastAudience.fire(BossHealthChanged, audience, 0, maxHealth, PHASE_DEFEATED)
		BroadcastAudience.fire(BossPhaseChanged, audience, PHASE_DEFEATED)
		boss:Destroy()
	end
	cycle.boss = nil

	log:info(string.format("[%s] Boss cycle stopped", arenaId))
end

-- ---------------------------------------------------------------
-- Round events
-- ---------------------------------------------------------------
local function onRoundStarted(_roster: { Player }, arenaId: any)
	if type(arenaId) ~= "string" then
		log:warn("RoundStarted fired without an arena id — no boss cycle started")
		return
	end
	startArena(arenaId)
end

local function onRoundEnded(_winnerId: any, _winnerName: any, arenaId: any)
	if type(arenaId) ~= "string" then
		return
	end
	stopArena(arenaId)
end

-- Sessions whose round was already running before this Script connected.
local function reconcile()
	for arenaId, session in SessionRegistry.all() do
		if session:isActive() and not cycles[arenaId] then
			startArena(arenaId)
		end
	end
end

-- ---------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------
local BossService = {}

-- Pause: every live boss stops ticking but stays standing. Reversible
-- via enable().
function BossService.disable()
	for _, cycle in cycles do
		if cycle.heartbeatConn then
			cycle.heartbeatConn:Disconnect()
			cycle.heartbeatConn = nil
		end
	end
	log:info("Disabled — boss ticks stopped")
end

function BossService.enable()
	for _, cycle in cycles do
		local controller = cycle.controller
		if controller and not cycle.heartbeatConn then
			cycle.heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
				controller:tick(dt)
			end)
		end
	end
	log:info("Enabled — boss ticks running")
end

-- Permanent teardown: every cycle, every boss, every listener.
function BossService.destroy()
	BossService.disable()
	for _, conn in eventConns do
		conn:Disconnect()
	end
	table.clear(eventConns)

	local arenaIds: { string } = {}
	for arenaId in cycles do
		table.insert(arenaIds, arenaId)
	end
	for _, arenaId in arenaIds do
		stopArena(arenaId)
	end
	log:info("Destroyed")
end

-- ---------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------
-- Listen first, then reconcile: a round that starts after this line is
-- caught by the event, one that started before it by the reconcile.
table.insert(eventConns, roundStartedEvent.Event:Connect(onRoundStarted))
table.insert(eventConns, roundEndedEvent.Event:Connect(onRoundEnded))
reconcile()
game:BindToClose(BossService.destroy)

log:info("BossService ready")
