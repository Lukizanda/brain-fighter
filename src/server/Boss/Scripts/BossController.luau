--!strict

----------------------------------------------------------------------
-- BossController
----------------------------------------------------------------------
-- Per-boss orchestrator. Mirrors NPCController but uses a BossBlackboard
-- (superset of NPCTypes.Blackboard) and delegates phase management to
-- BossPhaseManager.
--
-- Each tick:
--   1. Perception.update(bb)         — observe nearest player / LOS
--   2. BossPhaseManager.update()     — check HP thresholds, fire callback
--   3. StateMachine.tick(bb)         — advance AI state
----------------------------------------------------------------------

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossTypes  = require(ReplicatedStorage.Shared.Boss.BossTypes)
local NPCTypes   = require(ReplicatedStorage.Shared.NPC.NPCTypes)
local Logger     = require(ReplicatedStorage.Shared.Core.Logger)
local SkillTypes = require(ReplicatedStorage.Shared.Skills.SkillTypes)

local Perception   = require(ServerScriptService.Server.NPC.Scripts.Perception)
local StateMachine = require(ServerScriptService.Server.NPC.Scripts.StateMachine)

local BossStates      = require(script.Parent.BossStates)
local BossPhaseManager = require(script.Parent.BossPhaseManager)

type BB                   = BossTypes.BossBlackboard
type BossTypeSpec         = BossTypes.BossTypeSpec
type NPCBlackboard        = NPCTypes.Blackboard
type StateMachineInstance = StateMachine.StateMachineInstance
type PhaseManagerInstance = BossPhaseManager.BossPhaseManagerInstance

local log = Logger.new("BossController")

local BossController = {}
BossController.__index = BossController

export type BossControllerInstance = {
	tick: (self: BossControllerInstance, dt: number) -> (),
	destroy: (self: BossControllerInstance) -> (),
	getPhaseIndex: (self: BossControllerInstance) -> number,
	_blackboard: BB,
	_decision: StateMachineInstance,
	_phaseManager: PhaseManagerInstance,
	_onPhaseChanged: ((number, any) -> ())?,
	_alive: boolean,
}

-- ---------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------
function BossController.new(
	boss: Model,
	typeSpec: BossTypeSpec,
	onPhaseChanged: ((phaseIndex: number, phaseSpec: any) -> ())?
): BossControllerInstance?
	local humanoid = boss:FindFirstChildOfClass("Humanoid")
	local hrp      = boss:FindFirstChild("HumanoidRootPart")

	if not humanoid then
		log:warn("Boss missing Humanoid:", boss.Name)
		return nil
	end
	if not hrp or not hrp:IsA("BasePart") then
		log:warn("Boss missing HumanoidRootPart:", boss.Name)
		return nil
	end

	local bb: BB = {
		-- ── NPCTypes.Blackboard fields ──────────────────────────
		npc                  = boss,
		humanoid             = humanoid,
		humanoidRootPart     = hrp :: BasePart,
		weapon               = nil,
		nearestPlayer        = nil,
		distanceToNearest    = math.huge,
		canSeeTarget         = false,
		targetHumanoid       = nil,
		targetRootPart       = nil,
		currentState         = BossStates.State.Idle,
		targetPos            = nil,
		currentPath          = nil,
		currentWaypointIndex = 1,
		moveStartTime        = 0,
		lastShotTime         = 0,
		animations           = {},
		-- ── Boss-specific fields ────────────────────────────────
		perceptionRange      = typeSpec.detectionRange,
		bossTypeSpec         = typeSpec,
		currentPhaseIndex    = 1,
		currentPhaseSpec     = typeSpec.phases[1],
		lastAttackTime       = 0,
		selectedAttack       = nil,
		destroyedParts       = {},
		minionCount          = 0,
		attackWindupStart    = nil,
		attackComplete       = false,
		cooldownStart        = 0,
	}

	-- Load per-skill windup animations into bb.animations["windup_<skillName>"]
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	for skillName, skill: SkillTypes.SkillSpec in typeSpec.skills do
		if skill.windupAnimId then
			local anim = Instance.new("Animation")
			anim.AnimationId = skill.windupAnimId
			local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
			if ok and track then
				bb.animations["windup_" .. skillName] = track
				log:info(string.format("Loaded windup anim for '%s'", skillName))
			else
				log:warn(string.format("Failed to load windup anim for '%s': %s", skillName, tostring(track)))
			end
		end
	end

	local states, transitions = BossStates.build()
	local decision = StateMachine.new(states, transitions, BossStates.State.Idle)

	local phaseManager = BossPhaseManager.new(humanoid, typeSpec)

	local self = setmetatable({
		_blackboard     = bb,
		_decision       = decision,
		_phaseManager   = phaseManager,
		_onPhaseChanged = onPhaseChanged,
		_alive          = true,
	}, BossController)

	-- Run Idle.onEnter so the boss stops moving on spawn
	local idleState = states[BossStates.State.Idle]
	if idleState and idleState.onEnter then
		idleState.onEnter((bb :: any) :: NPCBlackboard)
	end

	boss:SetAttribute("CurrentState", BossStates.State.Idle)

	log:info(string.format("BossController created (Phase 1, HP=%d, type=%s)", typeSpec.maxHealth, typeSpec.name))

	return (self :: any) :: BossControllerInstance
end

-- ---------------------------------------------------------------
-- Tick — called every Heartbeat from BossService
-- ---------------------------------------------------------------
function BossController:tick(_dt: number)
	if not self._alive then return end

	local bb = self._blackboard

	if not bb.npc or not bb.npc.Parent then
		self:destroy()
		return
	end
	if bb.humanoid.Health <= 0 then
		-- humanoid.Died will also fire; just stop ticking
		self:destroy()
		return
	end

	-- 1. Perception: find nearest player, LOS check
	Perception.update((bb :: any) :: NPCBlackboard)

	-- 2. Phase check: update HP thresholds
	local phaseChanged = self._phaseManager:update()
	if phaseChanged then
		local newIndex = self._phaseManager:getCurrentPhaseIndex()
		local newSpec  = self._phaseManager:getCurrentPhaseSpec()
		bb.currentPhaseIndex = newIndex
		bb.currentPhaseSpec  = newSpec
		bb.humanoid.WalkSpeed = newSpec.walkSpeed

		if self._onPhaseChanged then
			self._onPhaseChanged(newIndex, newSpec)
		end
	end

	-- 3. Decision: advance state machine
	self._decision:tick((bb :: any) :: NPCBlackboard)
end

-- ---------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------
function BossController:destroy()
	if not self._alive then return end
	self._alive = false

	Perception.cleanup((self._blackboard :: any) :: NPCBlackboard)

	log:info("BossController destroyed")
end

-- ---------------------------------------------------------------
-- Accessors (used by BossService for event payloads)
-- ---------------------------------------------------------------
function BossController:getPhaseIndex(): number
	return self._phaseManager:getCurrentPhaseIndex()
end

return BossController
