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
--   4. BossHunger.tick(dt)           — pull a nearby letter in and eat it, on a timer
--   5. BossSpores.tick()             — land lobbed spores, burst the ones whose fuse ran out
--   6. BossWard.tick(dt)             — raise the word ward at its line, carry its letters round
--
-- The ward runs before hunger in the tick so the boss does not eat on the
-- frame its ward goes up; it is listed last because it was added last.
----------------------------------------------------------------------

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossTypes  = require(ReplicatedStorage.Shared.Boss.BossTypes)
local NPCTypes   = require(ReplicatedStorage.Shared.NPC.NPCTypes)
local Logger     = require(ReplicatedStorage.Shared.Core.Logger)
local SkillTypes = require(ReplicatedStorage.Shared.Skills.SkillTypes)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local BrainBody = require(ReplicatedStorage.Shared.Boss.BrainBody)

local Actions      = require(ServerScriptService.Server.AI.Scripts.Actions)
local Perception   = require(ServerScriptService.Server.AI.Scripts.Perception)
local StateMachine = require(ServerScriptService.Server.AI.Scripts.StateMachine)

local BossStates      = require(script.Parent.BossStates)
local BossPhaseManager = require(script.Parent.BossPhaseManager)
local BossHunger       = require(script.Parent.BossHunger)
local BossSpores       = require(script.Parent.BossSpores)
local BossWard         = require(script.Parent.BossWard)

type BB                   = BossTypes.BossBlackboard
type BossTypeSpec         = BossTypes.BossTypeSpec
type NPCBlackboard        = NPCTypes.Blackboard
type StateMachineInstance = StateMachine.StateMachineInstance
type PhaseManagerInstance = BossPhaseManager.BossPhaseManagerInstance

-- The generic AI layer (Perception, StateMachine, the state fns) is typed
-- against NPCTypes.Blackboard. A BossBlackboard is a structural superset
-- of it (see BossTypes), so this narrowing is safe — and writing it once
-- here keeps the cast out of the three call sites that need it.
local function asNPC(bb: BB): NPCBlackboard
	return (bb :: any) :: NPCBlackboard
end

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
	_hunger: BossHunger.BossHungerInstance?,
	_spores: BossSpores.BossSporesInstance?,
	_ward: BossWard.BossWardInstance?,
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

	-- The spore lob, nil for a type that does not lob. Built first: the blackboard
	-- hands it to the attack states.
	local spores = BossSpores.new(boss, humanoid, hrp :: BasePart, typeSpec)

	local bb: BB = {
		-- ── NPCTypes.Blackboard fields ──────────────────────────
		npc                  = boss,
		humanoid             = humanoid,
		humanoidRootPart     = hrp :: BasePart,
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
		spores               = spores :: any,
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
		_hunger         = BossHunger.new(boss, humanoid, hrp :: BasePart, typeSpec),
		_spores         = spores,
		_ward           = BossWard.new(boss, humanoid, hrp :: BasePart, typeSpec),
		_onPhaseChanged = onPhaseChanged,
		_alive          = true,
	}, BossController)

	-- Run Idle.onEnter so the boss stops moving on spawn
	local idleState = states[BossStates.State.Idle]
	if idleState and idleState.onEnter then
		idleState.onEnter(asNPC(bb))
	end

	boss:SetAttribute("CurrentState", BossStates.State.Idle)

	log:info(string.format("BossController created (Phase 1, HP=%d, type=%s)", typeSpec.maxHealth, typeSpec.name))

	return (self :: any) :: BossControllerInstance
end

-- ---------------------------------------------------------------
-- Tick — called every Heartbeat from BossService
-- ---------------------------------------------------------------
function BossController:tick(dt: number)
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
	Perception.update(asNPC(bb))

	-- 2. Phase check: update HP thresholds
	local phaseChanged = self._phaseManager:update()
	if phaseChanged then
		local newIndex = self._phaseManager:getCurrentPhaseIndex()
		local newSpec  = self._phaseManager:getCurrentPhaseSpec()
		bb.currentPhaseIndex = newIndex
		bb.currentPhaseSpec  = newSpec
		-- The phase owns the boss's *base* speed. It only writes WalkSpeed
		-- itself when nothing else is holding the rig: a freeze pins
		-- WalkSpeed to 0 for its duration and restores this attribute when
		-- it lifts, so writing WalkSpeed here would thaw the boss early and
		-- then be undone with the previous phase's number.
		local character = bb.humanoid.Parent
		if character then
			character:SetAttribute(SkillConstants.BASE_WALK_SPEED_ATTRIBUTE, newSpec.walkSpeed)
			if not character:GetAttribute(SkillConstants.FROZEN_ATTRIBUTE) then
				bb.humanoid.WalkSpeed = newSpec.walkSpeed
			end
		end

		-- The phase's colour and number, for every client: the body wears
		-- the colour, the puppet reads the number (wiki/design/boss-movement.md).
		bb.npc:SetAttribute(BossConstants.PHASE_ATTRIBUTE, newIndex)
		if bb.npc:GetAttribute(BrainBody.BODY_ATTRIBUTE) == BrainBody.BODY_NAME then
			BrainBody.recolor(bb.npc, newSpec.bodyColor.Color)
		end

		if self._onPhaseChanged then
			self._onPhaseChanged(newIndex, newSpec)
		end
	end

	-- 3. Decision: advance state machine
	self._decision:tick(asNPC(bb))

	-- 6. The word ward: up when the boss reaches its line, down when popped away.
	local ward = self._ward
	if ward then
		ward:tick(dt)
	end

	-- 4. Hunger: a timer beside the state machine, not a state in it (the
	-- boss eats whatever it is doing). Nil for a type that does not eat.
	-- A warded boss does not eat: a fight cannot be stalled into a heal.
	local hunger = self._hunger
	if hunger and not (ward and ward:isUp()) then
		hunger:tick(dt)
	end

	-- 5. Spores: a lob lands and a fuse runs out whatever the boss is doing.
	local spores = self._spores
	if spores then
		spores:tick()
	end
end

-- ---------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------
function BossController:destroy()
	if not self._alive then return end
	self._alive = false

	-- A letter in tow goes with the boss.
	local hunger = self._hunger
	if hunger then
		hunger:destroy()
	end

	-- And its ward: the letters, and the floor under its health.
	local ward = self._ward
	if ward then
		ward:destroy()
	end

	-- So do the spores it lobbed, and a lob still in the air.
	local spores = self._spores
	if spores then
		spores:destroy()
	end

	Perception.cleanup(asNPC(self._blackboard))
	Actions.cleanup(asNPC(self._blackboard))

	log:info("BossController destroyed")
end

-- ---------------------------------------------------------------
-- Accessors (used by BossService for event payloads)
-- ---------------------------------------------------------------
function BossController:getPhaseIndex(): number
	return self._phaseManager:getCurrentPhaseIndex()
end

return BossController
