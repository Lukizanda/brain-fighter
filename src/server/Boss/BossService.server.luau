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
--   - Entrance (Phase 8): in an arena whose players enter through an
--     ArenaEntryPad, and for a boss type with `entranceDelaySec`, the FIRST
--     spawn of a cycle is held until the first player arrives on the island
--     (ArenaEntryService's `PlayerEntered`), then happens that many seconds
--     later, with a countdown tell at the BossPoint. The trigger is the
--     arrival, not the round start, because a round starts as soon as a
--     player is in the ready room: the Default PvEBoss round waits for its
--     first roster member (minPlayers 1), counts down 5 s, and goes Active
--     while that player is still on the ready-room side of the teleporter.
--     An arena with no pad, a type with no delay, and every respawn behave
--     exactly as they did before.
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

local CollectionService   = game:GetService("CollectionService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig        = require(ReplicatedStorage.Shared.Boss.BossConfig)
local BossConstants     = require(ReplicatedStorage.Shared.Boss.BossConstants)
local BossTypes         = require(ReplicatedStorage.Shared.Boss.BossTypes)
local Arena             = require(ReplicatedStorage.Shared.GameMode.Arena)
local BroadcastAudience = require(ReplicatedStorage.Shared.GameMode.BroadcastAudience)
local Logger            = require(ReplicatedStorage.Shared.Core.Logger)
local VfxBroadcast      = require(ReplicatedStorage.Shared.Vfx.VfxBroadcast)

local BossSpawner    = require(script.Parent.Scripts.BossSpawner)
local BossController = require(script.Parent.Scripts.BossController)

-- Which sessions exist and whether their round is running, for the boot
-- reconcile. Called, never written to.
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

-- Asked only "does this arena have an entry pad" — whether an arrival is
-- coming. The Arena domain keeps the definition.
local ArenaEntryService = require(ServerScriptService.Server.Arena.ArenaEntryService)

local bossEvents        = ReplicatedStorage.Shared.Boss.BossEvents
local BossHealthChanged = bossEvents.BossHealthChanged :: RemoteEvent
local BossPhaseChanged  = bossEvents.BossPhaseChanged  :: RemoteEvent
-- Server-side fact for the game mode: this arena's boss died. PvEBoss
-- ends its round on it (Phase 6 stage 5). Fired after the client
-- sentinels so the HUD and the mode see the same event order.
local BossDefeated      = bossEvents.BossDefeated      :: BindableEvent

-- Server-side fact from the Arena domain: a player teleported onto an
-- arena's island, `(player, arenaId)`. Starts the entrance countdown.
local playerEnteredEvent = ReplicatedStorage.Shared.Arena.ArenaEvents.PlayerEntered :: BindableEvent

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
type BossTypeSpec = BossTypes.BossTypeSpec

-- One arena's boss lifecycle: everything a stop has to undo.
type Cycle = {
	arenaId: string,
	bossPoint: BasePart,
	boss: Model?,
	controller: BossControllerInstance?,
	heartbeatConn: RBXScriptConnection?,
	-- The pending retry, respawn or entrance timer, so a round ending
	-- mid-wait doesn't spawn a boss into an arena with no round.
	pendingThread: thread?,
	-- Entrance: seconds to wait after the first arrival, and whether the
	-- cycle is still holding for that arrival. Both unset for an arena that
	-- spawns at once.
	entranceDelaySec: number?,
	awaitingArrival: boolean,
	stopped: boolean,
}

local cycles: { [string]: Cycle } = {}
local eventConns: { RBXScriptConnection } = {}

-- Players who teleported onto an arena's island, per arena. An arrival can
-- come before the round has started (a player is in the roster for the 5 s
-- countdown, and the pad is already usable), so it is remembered rather
-- than dropped. An entry stops counting the moment the player's session
-- changes (their `ArenaId` attribute: going home and coming back is a
-- pivot, not a reload, so the character alone cannot tell the two visits
-- apart) or they respawn (a new character, back in the ready room). All of
-- an arena's entries are dropped when its cycle stops.
type Arrival = {
	character: Model,
	-- Watches the player's `ArenaId` attribute; any change retires the entry.
	sessionConn: RBXScriptConnection,
}
local arrivals: { [string]: { [Player]: Arrival } } = {}

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

-- The boss type a BossPoint names, with the registry entry behind it.
-- Read per cycle, so retagging the point takes effect on the next one.
local function resolveBossType(bossPoint: BasePart): (string, BossTypeSpec)
	local typeName = tostring(bossPoint:GetAttribute("BossType") or BossConfig.DEFAULT_TYPE)
	local typeSpec = BossConfig.BOSS_TYPES[typeName]
	assert(typeSpec, "Unknown boss type: " .. typeName)
	return typeName, typeSpec
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

	local _typeName, typeSpec = resolveBossType(bossPoint)

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
		BossDefeated:Fire(arenaId)

		-- The respawn below is what an idle (NoOp) arena wants. A PvEBoss
		-- arena's round ends on the Fire above within one RoundManager tick,
		-- and its RoundEnded reaches stopArena, which cancels this timer.
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
-- Entrance
-- A cycle that holds its first spawn for an arrival, then counts down.
-- ---------------------------------------------------------------

-- The world point the tell is drawn at: the top of the BossPoint, where the
-- boss will stand.
local function entrancePoint(bossPoint: BasePart): Vector3
	return bossPoint.Position + Vector3.new(0, bossPoint.Size.Y / 2, 0)
end

-- Take the tell off the BossPoint: the tag coming off is what tells every
-- client to drop its countdown. Safe to call when no tell is up.
local function clearEntranceTell(bossPoint: BasePart)
	CollectionService:RemoveTag(bossPoint, BossConstants.ENTRANCE_TAG)
	bossPoint:SetAttribute(BossConstants.ENTRANCE_APPEAR_AT_ATTRIBUTE, nil)
end

-- The arrival is in: publish when the boss appears, play the start cue, and
-- schedule the spawn. The timer lives in `pendingThread`, so `stopArena`
-- cancels it exactly as it cancels a respawn.
local function beginEntrance(cycle: Cycle)
	if cycle.stopped or not cycle.awaitingArrival then
		return
	end
	cycle.awaitingArrival = false

	local delaySec = cycle.entranceDelaySec or 0
	local bossPoint = cycle.bossPoint
	local appearAt = workspace:GetServerTimeNow() + delaySec
	-- Attribute before tag: the client reads the attribute the moment the
	-- tag arrives, and a tag that landed first would find nothing to count to.
	bossPoint:SetAttribute(BossConstants.ENTRANCE_APPEAR_AT_ATTRIBUTE, appearAt)
	CollectionService:AddTag(bossPoint, BossConstants.ENTRANCE_TAG)
	VfxBroadcast.playAt(BossConstants.ENTRANCE_START_VFX, entrancePoint(bossPoint))
	log:info(string.format("[%s] First arrival — boss appears in %d s", cycle.arenaId, delaySec))

	cycle.pendingThread = task.delay(delaySec, function()
		-- A stop cancels this thread before it can run, but a cycle stopped in
		-- the same frame the timer fires would otherwise spawn into a dead arena.
		if cycle.stopped then
			return
		end
		clearEntranceTell(bossPoint)
		VfxBroadcast.playAt(BossConstants.ENTRANCE_APPEAR_VFX, entrancePoint(bossPoint))
		startBossCycle(cycle)
	end)
end

local function forgetArrival(arenaId: string, player: Player)
	local arrived = arrivals[arenaId]
	local entry = arrived and arrived[player]
	if arrived and entry then
		entry.sessionConn:Disconnect()
		arrived[player] = nil
	end
end

local function forgetArrivals(arenaId: string)
	local arrived = arrivals[arenaId]
	if not arrived then
		return
	end
	arrivals[arenaId] = nil
	for _, entry in arrived do
		entry.sessionConn:Disconnect()
	end
end

-- Has somebody already teleported onto this arena's island and is still
-- there, i.e. in the same character, alive, and in the arena's session?
local function hasArrivedPlayer(arenaId: string): boolean
	local arrived = arrivals[arenaId]
	if not arrived then
		return false
	end
	for player, entry in arrived do
		local character = entry.character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local session = SessionRegistry.forPlayer(player)
		if player.Character == character
			and humanoid ~= nil and humanoid.Health > 0
			and session ~= nil and session:getArenaId() == arenaId
		then
			return true
		end
	end
	return false
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

	local _typeName, typeSpec = resolveBossType(bossPoint)
	local entranceDelaySec = typeSpec.entranceDelaySec or 0
	-- Held only where an arrival is actually coming: the type asks for an
	-- entrance AND the arena's players enter by teleporter. Everything else
	-- (no pad, no delay) spawns at once, as it always did.
	local holdForArrival = entranceDelaySec > 0 and ArenaEntryService.hasPadFor(arenaId)

	local cycle: Cycle = {
		arenaId = arenaId,
		bossPoint = bossPoint,
		boss = nil,
		controller = nil,
		heartbeatConn = nil,
		pendingThread = nil,
		entranceDelaySec = if holdForArrival then entranceDelaySec else nil,
		awaitingArrival = holdForArrival,
		stopped = false,
	}
	cycles[arenaId] = cycle

	if not holdForArrival then
		startBossCycle(cycle)
	elseif hasArrivedPlayer(arenaId) then
		-- Somebody teleported in during the pre-round countdown.
		beginEntrance(cycle)
	else
		log:info(string.format("[%s] Holding the boss for the first arrival", arenaId))
	end
end

-- A player teleported onto an arena's island.
local function onPlayerEntered(player: any, arenaId: any)
	if typeof(player) ~= "Instance" or not (player :: Instance):IsA("Player") or type(arenaId) ~= "string" then
		log:warn("PlayerEntered fired with a bad payload — ignored")
		return
	end
	local character = (player :: Player).Character
	if not character then
		return
	end

	local who = player :: Player
	forgetArrival(arenaId, who)
	local arrived = arrivals[arenaId]
	if not arrived then
		arrived = {}
		arrivals[arenaId] = arrived
	end
	arrived[who] = {
		character = character,
		sessionConn = who:GetAttributeChangedSignal(Arena.ID_ATTRIBUTE):Connect(function()
			forgetArrival(arenaId, who)
		end),
	}

	local cycle = cycles[arenaId]
	if cycle and cycle.awaitingArrival then
		beginEntrance(cycle)
	end
end

-- Undo everything startBossCycle wired: the timer that would spawn the
-- next boss, the tick, the controller, and the Model — announcing the
-- defeat sentinel so the arena's BossHudGui clears rather than freezing
-- on the last health it saw.
local function stopArena(arenaId: string)
	-- Whatever happened, the round is over: arrivals belong to it.
	forgetArrivals(arenaId)

	local cycle = cycles[arenaId]
	if not cycle then
		return
	end
	cycles[arenaId] = nil
	cycle.stopped = true
	cycle.awaitingArrival = false
	-- A countdown tell still up (round ended mid-entrance) comes off with it.
	clearEntranceTell(cycle.bossPoint)

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
table.insert(eventConns, playerEnteredEvent.Event:Connect(onPlayerEntered))
reconcile()
game:BindToClose(BossService.destroy)

log:info("BossService ready")
