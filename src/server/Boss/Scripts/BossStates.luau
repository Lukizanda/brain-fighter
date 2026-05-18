--!strict

----------------------------------------------------------------------
-- BossStates
----------------------------------------------------------------------
-- State definitions for the Boss archetype. Follows the same
-- PatrollerStates pattern: build() returns (states, transitions)
-- for StateMachine.new().
--
-- Boss-specific blackboard fields are accessed via (bb :: any) since
-- StateMachine types the bb parameter as NPCTypes.Blackboard.
-- This matches the existing codebase pattern (see Actions.luau).
--
-- State diagram:
--   Idle ──(player detected)──────────────────► Patrol
--   Patrol ──(in attack range)────────────────► AttackPrep
--   Patrol ──(no player)──────────────────────► Idle
--   AttackPrep ──(windup elapsed)─────────────► Attack
--   Attack ──(attackComplete)─────────────────► Cooldown
--   Cooldown ──(timer + in range)─────────────► AttackPrep
--   Cooldown ──(timer + out of range)─────────► Patrol
--   Cooldown ──(timer + no player)────────────► Idle
----------------------------------------------------------------------

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossTypes        = require(ReplicatedStorage.Shared.Boss.BossTypes)
local DeliveryRegistry = require(ReplicatedStorage.Shared.Skills.DeliveryRegistry)
local NPCTypes         = require(ReplicatedStorage.Shared.NPC.NPCTypes)
local Logger           = require(ReplicatedStorage.Shared.Core.Logger)
local SkillTypes       = require(ReplicatedStorage.Shared.Skills.SkillTypes)

local Actions = require(ServerScriptService.Server.NPC.Scripts.Actions)

type BB              = BossTypes.BossBlackboard
type Blackboard      = NPCTypes.Blackboard
type StateDefinition = NPCTypes.StateDefinition
type TransitionRule  = NPCTypes.TransitionRule

local log = Logger.new("BossStates")

local BossStates = {}

-- State name constants (mirrored in BossController for attribute writes)
BossStates.State = {
	Idle       = "Idle",
	Patrol     = "Patrol",
	AttackPrep = "AttackPrep",
	Attack     = "Attack",
	Cooldown   = "Cooldown",
}

local S = BossStates.State

-- ---------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------

local function faceTaret(bb: Blackboard)
	local targetRootPart = (bb :: any).targetRootPart
	if not targetRootPart or not targetRootPart.Parent then return end
	local npcPos    = bb.humanoidRootPart.Position
	local targetPos = (targetRootPart :: BasePart).Position
	local lookTarget = Vector3.new(targetPos.X, npcPos.Y, targetPos.Z)
	if (lookTarget - npcPos).Magnitude > 0.5 then
		bb.humanoidRootPart.CFrame = CFrame.lookAt(npcPos, lookTarget)
	end
end


-- ---------------------------------------------------------------
-- State definitions
-- ---------------------------------------------------------------

local IdleState: StateDefinition = {
	name = S.Idle,

	onEnter = function(bb)
		Actions.StopMoving(bb)
	end,

	update = function(_bb)
		-- Stand still; transitions watch nearestPlayer.
	end,
}

local PatrolState: StateDefinition = {
	name = S.Patrol,

	onEnter = function(bb)
		-- Clear stale path so MoveToWithPath recomputes toward the player.
		bb.currentPath = nil
		bb.targetPos   = nil
	end,

	update = function(bb)
		local targetRootPart: any = (bb :: any).targetRootPart
		if not targetRootPart or not targetRootPart.Parent then
			return
		end
		-- Chase the player using pathfinding
		Actions.MoveToWithPath(bb, (targetRootPart :: BasePart).Position)
	end,
}

local AttackPrepState: StateDefinition = {
	name = S.AttackPrep,

	onEnter = function(bb)
		local bbany = bb :: any
		bbany.attackWindupStart = os.clock()
		bbany.attackComplete    = false

		-- Pick a random attack from the current phase's available set
		local phaseSpec = bbany.currentPhaseSpec
		if phaseSpec and #phaseSpec.availableAttacks > 0 then
			bbany.selectedAttack = phaseSpec.availableAttacks[
				math.random(1, #phaseSpec.availableAttacks)
			]
		else
			-- Fallback: nothing available — mark done immediately
			bbany.selectedAttack = nil
		end

		Actions.StopMoving(bb)
		log:info(string.format("%s: AttackPrep → will use '%s'",
			bb.npc.Name, tostring((bbany :: any).selectedAttack)))
	end,

	update = function(bb)
		-- Keep facing the player during the telegraph window
		faceTaret(bb)
	end,
}

local AttackState: StateDefinition = {
	name = S.Attack,

	onEnter = function(bb)
		local bbany  = bb :: any
		local bossbb = bbany :: BB
		bbany.attackComplete = false

		local attack: string? = bbany.selectedAttack
		if not attack then
			bbany.attackComplete = true
			return
		end

		local skill = bossbb.bossTypeSpec.skills[attack]
		if not skill then
			log:warn("Unknown attack:", attack, "— skipping")
			bbany.attackComplete = true
			return
		end

		local hrp    = bossbb.humanoidRootPart
		local ctx: SkillTypes.DeliveryCtx = {
			origin     = CFrame.new(hrp.Position + Vector3.new(0, 2, 0)),
			target     = bossbb.targetRootPart,
			aoeCenter  = hrp.Position,
			source     = bossbb.npc,
			onComplete = function()
				bbany.attackComplete = true
			end,
		}
		DeliveryRegistry.deliver(skill, ctx)
	end,

	update = function(_bb)
		-- DeliveryRegistry handlers are async; attackComplete is set via ctx.onComplete.
	end,
}

local CooldownState: StateDefinition = {
	name = S.Cooldown,

	onEnter = function(bb)
		(bb :: any).cooldownStart = os.clock()
		Actions.StopMoving(bb)
	end,

	update = function(_bb)
		-- Wait; transitions check the timer.
	end,
}

-- ---------------------------------------------------------------
-- Transition conditions
-- ---------------------------------------------------------------

local function cooldownElapsed(bb: Blackboard): boolean
	local bbany   = bb :: any
	local elapsed = os.clock() - (bbany.cooldownStart or 0)
	local spec    = bbany.currentPhaseSpec
	local cooldown = spec and spec.attackCooldown or 4
	return elapsed >= cooldown
end

local function playerInRange(bb: Blackboard): boolean
	local bossbb = (bb :: any) :: BB
	return bb.nearestPlayer ~= nil
		and bb.distanceToNearest <= bossbb.bossTypeSpec.detectionRange
end

local function playerInAttackRange(bb: Blackboard): boolean
	local bossbb = (bb :: any) :: BB
	return bb.nearestPlayer ~= nil
		and bb.distanceToNearest <= bossbb.bossTypeSpec.attackRange
end

local function windupElapsed(bb: Blackboard): boolean
	local bbany = bb :: any
	local start = bbany.attackWindupStart
	local bossbb = bbany :: BB
	return start ~= nil and (os.clock() - start) >= bossbb.bossTypeSpec.attackWindupSec
end

-- ---------------------------------------------------------------
-- Public: build() returns states + transitions tables
-- ---------------------------------------------------------------
function BossStates.build()
	local states: { [string]: StateDefinition } = {
		[S.Idle]       = IdleState,
		[S.Patrol]     = PatrolState,
		[S.AttackPrep] = AttackPrepState,
		[S.Attack]     = AttackState,
		[S.Cooldown]   = CooldownState,
	}

	local transitions: { [string]: { TransitionRule } } = {
		[S.Idle] = {
			{ to = S.Patrol, condition = playerInRange },
		},
		[S.Patrol] = {
			-- Attack range takes priority over continued patrolling
			{ to = S.AttackPrep, condition = playerInAttackRange },
			{ to = S.Idle, condition = function(bb) return bb.nearestPlayer == nil end },
		},
		[S.AttackPrep] = {
			{ to = S.Attack, condition = windupElapsed },
		},
		[S.Attack] = {
			{ to = S.Cooldown, condition = function(bb) return (bb :: any).attackComplete == true end },
		},
		[S.Cooldown] = {
			{
				to = S.AttackPrep,
				condition = function(bb)
					return cooldownElapsed(bb) and playerInAttackRange(bb)
				end,
			},
			{
				to = S.Patrol,
				condition = function(bb)
					return cooldownElapsed(bb) and playerInRange(bb) and not playerInAttackRange(bb)
				end,
			},
			{
				to = S.Idle,
				condition = function(bb)
					return cooldownElapsed(bb) and bb.nearestPlayer == nil
				end,
			},
		},
	}

	return states, transitions
end

return BossStates
