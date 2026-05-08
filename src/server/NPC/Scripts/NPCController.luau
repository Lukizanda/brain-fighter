--[[
	NPCController
	-------------
	Per-NPC orchestrator. Holds the blackboard and the decision instance
	(state machine for now, behavior tree later). Each tick:
	  1. Perception.update(bb)  — observe the world
	  2. decision:tick(bb)      — pick a state / action

	The state's update fn calls into Actions directly, which mutates
	the blackboard's movement state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local NPCTypes = require(ReplicatedStorage.Shared.NPC.NPCTypes)

local Perception = require(script.Parent.Perception)
local StateMachine = require(script.Parent.StateMachine)
local PatrollerStates = require(script.Parent.States.PatrollerStates)

type Blackboard = NPCTypes.Blackboard
type Archetype = NPCTypes.Archetype

local log = Logger.new("NPCController")

local NPCController = {}
NPCController.__index = NPCController

export type NPCControllerInstance = {
	tick: (self: NPCControllerInstance, dt: number) -> (),
	destroy: (self: NPCControllerInstance) -> (),
	getBlackboard: (self: NPCControllerInstance) -> Blackboard,
	_blackboard: Blackboard,
	_decision: StateMachine.StateMachineInstance,
	_archetype: Archetype,
	_alive: boolean,
}

-- ============================================================
-- Archetype-specific state builders
-- ============================================================
-- Maps archetype name -> module that returns (states, transitions).
-- Add new archetypes here as they're built.
local stateBuilders: { [string]: { build: () -> (any, any), cleanup: ((Blackboard) -> ())? } } = {
	Patroller = PatrollerStates,
}

-- ============================================================
-- Construction
-- ============================================================
function NPCController.new(npc: Model, archetype: Archetype, weapon: Tool?): NPCControllerInstance?
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local hrp = npc:FindFirstChild("HumanoidRootPart")

	if not humanoid then
		log:warn("NPC missing Humanoid:", npc.Name)
		return nil
	end
	if not hrp or not hrp:IsA("BasePart") then
		log:warn("NPC missing HumanoidRootPart:", npc.Name)
		return nil
	end

	local builder = stateBuilders[archetype.name]
	if not builder then
		log:warn("No state builder registered for archetype:", archetype.name)
		return nil
	end

	local states, transitions = builder.build()

	local blackboard: Blackboard = {
		npc = npc,
		humanoid = humanoid,
		humanoidRootPart = hrp :: BasePart,
		weapon = weapon,
		nearestPlayer = nil,
		distanceToNearest = math.huge,
		canSeeTarget = false,
		targetHumanoid = nil,
		targetRootPart = nil,
		currentState = archetype.initialState,
		targetPos = nil,
		currentPath = nil,
		currentWaypointIndex = 1,
		moveStartTime = 0,
		lastShotTime = 0,
		animations = {},
	}

	-- Load animations onto the humanoid's Animator so states/actions can play them
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	if archetype.animations then
		for name, assetId in archetype.animations do
			if assetId then
				local anim = Instance.new("Animation")
				anim.AnimationId = assetId
				local ok, track = pcall(function()
					return animator:LoadAnimation(anim)
				end)
				if ok and track then
					blackboard.animations[name] = track
				else
					log:warn(string.format("Failed to load %s animation for %s: %s",
						name, npc.Name, tostring(track)))
				end
			end
		end
	end

	local decision = StateMachine.new(states, transitions, archetype.initialState)

	local self = setmetatable({
		_blackboard = blackboard,
		_decision = decision,
		_archetype = archetype,
		_alive = true,
	}, NPCController)

	-- Expose initial state as an attribute (StateMachine sets it on transitions)
	npc:SetAttribute("CurrentState", archetype.initialState)

	-- Run onEnter for the initial state so it gets a chance to set up
	local initialStateDef = states[archetype.initialState]
	if initialStateDef and initialStateDef.onEnter then
		initialStateDef.onEnter(blackboard)
	end

	log:info(string.format("Created controller for %s (initial state: %s)",
		npc.Name, archetype.initialState))

	return (self :: any) :: NPCControllerInstance
end

-- ============================================================
-- Tick
-- ============================================================
-- ============================================================
-- Animation driver
-- ============================================================
-- Plays walk when the humanoid is moving, idle when it isn't.
-- Both animations are pre-loaded at spawn; we just toggle which is playing.
local MOVE_MAGNITUDE_THRESHOLD = 0.1

local function updateLocomotionAnimation(bb)
	local walk = bb.animations.walk
	local idle = bb.animations.idle
	if not walk and not idle then
		return
	end

	local isMoving = bb.humanoid.MoveDirection.Magnitude > MOVE_MAGNITUDE_THRESHOLD

	if isMoving then
		if idle and idle.IsPlaying then
			idle:Stop(0.2)
		end
		if walk and not walk.IsPlaying then
			walk.Looped = true
			walk.Priority = Enum.AnimationPriority.Movement
			walk:Play(0.2)
		end
	else
		if walk and walk.IsPlaying then
			walk:Stop(0.2)
		end
		if idle and not idle.IsPlaying then
			idle.Looped = true
			idle.Priority = Enum.AnimationPriority.Idle
			idle:Play(0.2)
		end
	end
end

function NPCController:tick(_dt: number)
	if not self._alive then
		return
	end

	-- Bail out if the NPC has been destroyed
	local npc = self._blackboard.npc
	if not npc or not npc.Parent then
		self:destroy()
		return
	end

	-- Bail out if the humanoid died
	if self._blackboard.humanoid.Health <= 0 then
		self:destroy()
		return
	end

	-- 1. Perception (Phase 4 — currently a no-op stub)
	Perception.update(self._blackboard)

	-- 2. Decision
	self._decision:tick(self._blackboard)

	-- 3. Locomotion animation (walk / idle based on humanoid movement)
	updateLocomotionAnimation(self._blackboard)
end

-- ============================================================
-- Cleanup
-- ============================================================
function NPCController:destroy()
	if not self._alive then
		return
	end
	self._alive = false

	-- Let the archetype's state module clean up any cached per-NPC data
	local builder = stateBuilders[self._archetype.name]
	if builder and builder.cleanup then
		builder.cleanup(self._blackboard)
	end

	-- Let perception drop its throttle counter for this NPC
	Perception.cleanup(self._blackboard)

	log:info("Destroyed controller for:", self._blackboard.npc and self._blackboard.npc.Name or "?")
end

function NPCController:getBlackboard(): Blackboard
	return self._blackboard
end

return NPCController
