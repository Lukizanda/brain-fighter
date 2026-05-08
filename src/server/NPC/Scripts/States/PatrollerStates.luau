--[[
	PatrollerStates
	---------------
	State definitions for the Patroller archetype.
	Lives server-side because state update fns need to call Actions
	(which require server-only services like PathfindingService).

	The Patroller archetype in shared/ only describes the *shape*
	(state names, transitions). NPCController calls into this module
	to construct the actual state table when spawning a Patroller.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local NPCConstants = require(ReplicatedStorage.Shared.NPC.NPCConstants)
local NPCTypes = require(ReplicatedStorage.Shared.NPC.NPCTypes)

local Actions = require(script.Parent.Parent.Actions)

-- AIWorldData — authoritative source for patrol point positions
local WorldDataManager = require(ServerScriptService.Server.AI.Scripts.WorldDataManager)

type Blackboard = NPCTypes.Blackboard
type StateDefinition = NPCTypes.StateDefinition
type TransitionRule = NPCTypes.TransitionRule

local log = Logger.new("PatrollerStates")

local PatrollerStates = {}

-- ============================================================
-- Patrol point cache (per-NPC, keyed by blackboard)
-- ============================================================
-- Stores per-NPC patrol routing info that doesn't fit cleanly into the
-- shared blackboard schema. Maintains a cycling index of patrol points.
-- Positions come from WorldData (snapshotted at server startup).
type PatrolPointData = { name: string, position: Vector3 }

local patrolMemory: { [Blackboard]: {
	patrolPoints: { PatrolPointData },
	currentIndex: number,
} } = {}

local function getOrInitPatrolMemory(bb: Blackboard)
	local mem = patrolMemory[bb]
	if mem then
		return mem
	end

	-- First-time setup for this NPC: read patrol point positions from WorldDataManager
	local snapshots = WorldDataManager.getPatrolPoints()
	local points: { PatrolPointData } = {}
	for _, snapshot in snapshots do
		table.insert(points, { name = snapshot.name, position = snapshot.position })
	end

	-- Sort by name for deterministic ordering (PatrolPoint_1, _2, _3, _4)
	table.sort(points, function(a, b)
		return a.name < b.name
	end)

	mem = {
		patrolPoints = points,
		currentIndex = 1,
	}
	patrolMemory[bb] = mem

	log:info(string.format("%s: cached %d patrol points",
		bb.npc.Name, #points))

	return mem
end

local function pickNearestPatrolPoint(bb: Blackboard)
	local mem = getOrInitPatrolMemory(bb)
	if #mem.patrolPoints == 0 then
		return
	end

	local npcPos = bb.humanoidRootPart.Position
	local bestIdx = 1
	local bestDist = math.huge
	for i, pt in mem.patrolPoints do
		local d = (pt.position - npcPos).Magnitude
		if d < bestDist then
			bestDist = d
			bestIdx = i
		end
	end
	mem.currentIndex = bestIdx
end

local function advancePatrolIndex(bb: Blackboard)
	local mem = patrolMemory[bb]
	if not mem then return end
	mem.currentIndex += 1
	if mem.currentIndex > #mem.patrolPoints then
		mem.currentIndex = 1
	end
end

local function getCurrentPatrolTarget(bb: Blackboard): Vector3?
	local mem = getOrInitPatrolMemory(bb)
	if #mem.patrolPoints == 0 then
		return nil
	end
	local pt = mem.patrolPoints[mem.currentIndex]
	return pt and pt.position or nil
end

-- Public: clear cached patrol memory when an NPC is destroyed
function PatrollerStates.cleanup(bb: Blackboard)
	patrolMemory[bb] = nil
end

-- ============================================================
-- States
-- ============================================================
local PatrolState: StateDefinition = {
	name = NPCConstants.State.Patrol,

	onEnter = function(bb)
		-- On first enter (or re-enter after Idle), pick the nearest patrol
		-- point so we don't backtrack. Subsequent waypoint advances happen
		-- in update() when we reach a target.
		pickNearestPatrolPoint(bb)
	end,

	update = function(bb)
		local target = getCurrentPatrolTarget(bb)
		if not target then
			return
		end

		local result = Actions.MoveToWithPath(bb, target)

		if result == NPCConstants.ActionResult.Success then
			-- Arrived at this waypoint — advance to the next for the next tick
			local mem = patrolMemory[bb]
			if mem then
				log:info(string.format("%s: arrived at PatrolPoint_%d, advancing",
					bb.npc.Name, mem.currentIndex))
			end
			advancePatrolIndex(bb)
		elseif result == NPCConstants.ActionResult.Failure then
			-- Path failed — try the next waypoint instead of getting stuck
			log:warn(string.format("%s: patrol path failed, advancing to next waypoint",
				bb.npc.Name))
			advancePatrolIndex(bb)
		end
		-- Running: keep going
	end,
}

-- ============================================================
-- Idle state
-- ============================================================
-- Stops moving and watches the nearest player. Phase 5 entry condition:
-- a player gets close enough (IDLE_TRIGGER_DISTANCE).
local IdleState: StateDefinition = {
	name = NPCConstants.State.Idle,

	onEnter = function(bb)
		-- Stop the current movement so the NPC doesn't drift past the player
		Actions.StopMoving(bb)
		log:info(string.format("%s: entered Idle (watching %s)",
			bb.npc.Name,
			bb.nearestPlayer and bb.nearestPlayer.Name or "?"
		))
	end,

	update = function(_bb)
		-- No action — just stand still. Transitions handle resuming patrol.
	end,
}

-- ============================================================
-- Combat state
-- ============================================================
-- NPC engages the nearest visible player: stops moving, faces them, fires.
-- Entry: player visible within COMBAT_ENGAGE_DISTANCE
-- Exit: lost line of sight OR player moved beyond COMBAT_DISENGAGE_DISTANCE
local CombatState: StateDefinition = {
	name = NPCConstants.State.Combat,

	onEnter = function(bb)
		Actions.StopMoving(bb)

		-- Hold the "aim" pose — keeps arms raised between shots
		local aim = bb.animations.aim
		if aim and not aim.IsPlaying then
			aim.Looped = true
			aim.Priority = Enum.AnimationPriority.Action
			aim:Play(0.2)
		end

		log:info(string.format("%s: entered Combat (target=%s)",
			bb.npc.Name,
			bb.nearestPlayer and bb.nearestPlayer.Name or "?"
		))
	end,

	onExit = function(bb)
		local aim = bb.animations.aim
		if aim and aim.IsPlaying then
			aim:Stop(0.2)
		end
	end,

	update = function(bb)
		-- Face the target each tick (simple yaw alignment via CFrame)
		if bb.targetRootPart and bb.targetRootPart.Parent then
			local npcPos = bb.humanoidRootPart.Position
			local targetPos = bb.targetRootPart.Position
			-- Flatten to XZ so we don't pitch the whole body
			local lookTarget = Vector3.new(targetPos.X, npcPos.Y, targetPos.Z)
			bb.humanoidRootPart.CFrame = CFrame.lookAt(npcPos, lookTarget)
		end

		-- Fire — Actions.Shoot handles rate-of-fire throttling internally
		Actions.Shoot(bb)
	end,
}

-- ============================================================
-- Public API
-- ============================================================
-- Returns the states + transitions tables for the StateMachine constructor.
function PatrollerStates.build()
	local states: { [string]: StateDefinition } = {
		[NPCConstants.State.Patrol] = PatrolState,
		[NPCConstants.State.Idle] = IdleState,
		[NPCConstants.State.Combat] = CombatState,
	}

	-- Shared condition helpers: first match wins, ordering matters.
	-- Combat takes priority over Idle so visible enemies engage the NPC
	-- even if they're within the "idle" proximity range.
	local function canSeeAndEngage(bb): boolean
		return bb.nearestPlayer ~= nil
			and bb.canSeeTarget
			and bb.distanceToNearest < NPCConstants.COMBAT_ENGAGE_DISTANCE
	end

	local function tooFarForCombat(bb): boolean
		return bb.nearestPlayer == nil
			or bb.distanceToNearest > NPCConstants.COMBAT_DISENGAGE_DISTANCE
	end

	-- Transition rules. The first matching rule per tick wins.
	-- Hysteresis prevents flickering at threshold boundaries.
	local transitions: { [string]: { TransitionRule } } = {
		[NPCConstants.State.Patrol] = {
			-- Priority 1: engage visible enemy
			{ to = NPCConstants.State.Combat, condition = canSeeAndEngage },
			-- Priority 2: fall back to watchful Idle if they're close but hidden
			{
				to = NPCConstants.State.Idle,
				condition = function(bb)
					return bb.nearestPlayer ~= nil
						and bb.distanceToNearest < NPCConstants.IDLE_TRIGGER_DISTANCE
				end,
			},
		},
		[NPCConstants.State.Idle] = {
			-- Priority 1: engage if they pop out into view
			{ to = NPCConstants.State.Combat, condition = canSeeAndEngage },
			-- Priority 2: back to patrol if they backed off
			{
				to = NPCConstants.State.Patrol,
				condition = function(bb)
					return bb.nearestPlayer == nil
						or bb.distanceToNearest > NPCConstants.PATROL_RESUME_DISTANCE
				end,
			},
		},
		[NPCConstants.State.Combat] = {
			-- Disengage fully if target is gone or out of range
			{ to = NPCConstants.State.Patrol, condition = tooFarForCombat },
			-- Lost line of sight but still close: hold in Idle
			{
				to = NPCConstants.State.Idle,
				condition = function(bb)
					return bb.nearestPlayer ~= nil
						and not bb.canSeeTarget
				end,
			},
		},
	}

	return states, transitions
end

return PatrollerStates
