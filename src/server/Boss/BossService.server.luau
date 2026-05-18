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
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local Logger     = require(ReplicatedStorage.Shared.Core.Logger)

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
	log:info("Starting boss cycle")

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
		BossPhaseChanged:FireAllClients(phaseIndex)
		log:info("Boss entered phase", phaseIndex)
	end)

	if not controller then
		log:warn("BossController failed to create — aborting cycle")
		boss:Destroy()
		return
	end

	-- Announce spawn to all clients
	BossPhaseChanged:FireAllClients(1)
	BossHealthChanged:FireAllClients(humanoid.MaxHealth, humanoid.MaxHealth, 1)

	-- Throttled HP forwarding
	local lastHealthSendTime = 0

	humanoid.HealthChanged:Connect(function(health: number)
		local now = os.clock()
		if now - lastHealthSendTime < HEALTH_THROTTLE_SEC then return end
		lastHealthSendTime = now
		BossHealthChanged:FireAllClients(health, humanoid.MaxHealth, controller:getPhaseIndex())
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
		BossHealthChanged:FireAllClients(0, humanoid.MaxHealth, PHASE_DEFEATED)
		BossPhaseChanged:FireAllClients(PHASE_DEFEATED)

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
