--!strict

----------------------------------------------------------------------
-- BossService
----------------------------------------------------------------------
-- Top-level boss lifecycle: spawn → tick → death → respawn.
--
-- Responsibilities:
--   - Find BossPoint in Workspace
--   - Resolve boss type via BossPoint:GetAttribute("BossType"), fallback to DEFAULT_TYPE
--   - Build the Boss Model via BossSpawner
--   - Create a BossController and run it on Heartbeat
--   - Forward boss HP changes to clients via BossHealthChanged
--   - Forward phase changes via BossPhaseChanged
--   - Handle boss death: destroy controller, pause, respawn
--
-- Death handling: Boss is NOT tagged "Damageable" — BossService owns
-- the full lifecycle so DeathHandler won't respawn or create templates.
-- humanoid.Died fires naturally when health reaches 0 (from SpellExecutor
-- direct writes or applyDamage.process firearm hits).
--
-- Audience (Phase 6 stage 3): BossHealthChanged and BossPhaseChanged draw
-- the BossHudGui, so they are screen-space — a duellist receiving them gets
-- a boss health bar over a fight that has no boss in it. The boss is not
-- owned by a session today, so the question "whose HUD" is answered the same
-- way every other arena-bound thing in the place answers it: BossPoint
-- carries an ArenaId attribute, and the audience is that arena's roster.
-- Stage 5's `Modes/PvEBoss.luau` takes ownership of the boss arena and will
-- set that attribute rather than inheriting the default; nothing below has
-- to change for it. See `wiki/design/lobby.md` § Broadcast audience.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local BossConfig        = require(ReplicatedStorage.Shared.Boss.BossConfig)
local Arena             = require(ReplicatedStorage.Shared.GameMode.Arena)
local BroadcastAudience = require(ReplicatedStorage.Shared.GameMode.BroadcastAudience)
local Logger            = require(ReplicatedStorage.Shared.Core.Logger)

local BossSpawner    = require(script.Parent.Scripts.BossSpawner)
local BossController = require(script.Parent.Scripts.BossController)

local bossEvents        = ReplicatedStorage.Shared.Boss.BossEvents
local BossHealthChanged = bossEvents.BossHealthChanged :: RemoteEvent
local BossPhaseChanged  = bossEvents.BossPhaseChanged  :: RemoteEvent

local log = Logger.new("BossService")

-- phaseIndex = 0 is the client sentinel meaning "boss defeated / no boss"
local PHASE_DEFEATED      = 0
local HEALTH_THROTTLE_SEC = 0.1  -- max frequency of BossHealthChanged fires

-- ---------------------------------------------------------------
-- startBossCycle
-- Spawns a boss and wires up its lifetime. Called recursively on
-- respawn — each call is fully self-contained with its own
-- Heartbeat connection and Died listener.
-- ---------------------------------------------------------------
local function startBossCycle(bossPoint: BasePart)
	-- Resolved per cycle rather than per fire: re-read on respawn so retagging
	-- BossPoint takes effect, but not 10× a second on the health path. The
	-- roster behind the id is still read at each fire — players join and leave
	-- a session while a boss is alive.
	local arenaId = Arena.idOf(bossPoint)
	local function bossAudience(): { Player }
		return BroadcastAudience.forArena(arenaId)
	end

	log:info(string.format("Starting boss cycle in arena %s", arenaId))

	local typeName = tostring(bossPoint:GetAttribute("BossType") or BossConfig.DEFAULT_TYPE)
	local typeSpec = BossConfig.BOSS_TYPES[typeName]
	assert(typeSpec, "Unknown boss type: " .. typeName)

	local boss = BossSpawner.spawn(bossPoint, typeSpec)
	if not boss then
		log:warn("BossSpawner returned nil — retrying in 5 s")
		task.delay(5, function()
			startBossCycle(bossPoint)
		end)
		return
	end

	local humanoid = boss:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		log:warn("Spawned boss has no Humanoid — aborting cycle")
		boss:Destroy()
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
		return
	end

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

	-- Death handling
	humanoid.Died:Connect(function()
		heartbeatConn:Disconnect()
		controller:destroy()

		-- Signal defeat (phaseIndex 0 = no boss)
		local deathAudience = bossAudience()
		BroadcastAudience.fire(BossHealthChanged, deathAudience, 0, humanoid.MaxHealth, PHASE_DEFEATED)
		BroadcastAudience.fire(BossPhaseChanged, deathAudience, PHASE_DEFEATED)

		log:info(string.format("Boss defeated — respawning in %d s", typeSpec.respawnDelaySec))

		-- Brief pause for death effect visibility, then destroy model
		task.delay(1, function()
			if boss and boss.Parent then
				boss:Destroy()
			end
		end)

		-- Respawn cycle
		task.delay(typeSpec.respawnDelaySec, function()
			startBossCycle(bossPoint)
		end)
	end)

	log:info("Boss cycle running")
end

-- ---------------------------------------------------------------
-- Initialization: find BossPoint and begin
-- ---------------------------------------------------------------
local bossPoint = workspace:FindFirstChild("BossPoint")
if not bossPoint or not bossPoint:IsA("BasePart") then
	log:warn("BossPoint not found in Workspace — boss system disabled")
else
	startBossCycle(bossPoint :: BasePart)
end

log:info("BossService ready")
