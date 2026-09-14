--!strict

----------------------------------------------------------------------
-- BossStates
----------------------------------------------------------------------
-- State definitions for the Boss archetype. Follows the same
-- PatrollerStates pattern: build() returns (states, transitions)
-- for StateMachine.new().
--
-- StateMachine types every state fn's parameter as NPCTypes.Blackboard,
-- but a boss rig's blackboard is always a BossBlackboard — a structural
-- superset (see BossTypes). `bossOf` is the single place that widening is
-- written down; everything past it reads typed fields rather than the
-- untyped `(bb :: any).whatever` this file used to be built from.
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

local BossConstants    = require(ReplicatedStorage.Shared.Boss.BossConstants)
local BossTypes        = require(ReplicatedStorage.Shared.Boss.BossTypes)
local SkillDelivery    = require(ReplicatedStorage.Shared.Skills.SkillDelivery)
local NPCTypes         = require(ReplicatedStorage.Shared.NPC.NPCTypes)
local Logger           = require(ReplicatedStorage.Shared.Core.Logger)
local SkillTypes       = require(ReplicatedStorage.Shared.Skills.SkillTypes)
local SkillVisuals     = require(ReplicatedStorage.Shared.Skills.SkillVisuals)

local Actions = require(ServerScriptService.Server.AI.Scripts.Actions)

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

-- The boss blackboard behind the generic one the state machine hands us.
-- Safe by construction: BossController is the only thing that builds
-- these states, and it only ever ticks them with a BossBlackboard.
local function bossOf(bb: Blackboard): BB
	return (bb :: any) :: BB
end


-- Turns the boss toward its target on the Y axis.
--
-- This used to lerp `humanoidRootPart.CFrame` by hand, which is the one
-- thing the project rule forbids: the physics solver reasserts its own
-- transform on the next step and the boss shudders through every windup.
-- `Actions.FaceTarget` owns an AlignOrientation on the rig instead, at
-- NPCConstants.FACE_TURN_RATE_DEGREES — the same authored half-circle per
-- second the hand-rolled lerp was aiming for. Any state that stops facing
-- calls `Actions.ReleaseFacing` so the Humanoid steers the walk again.
local function faceTarget(bb: Blackboard)
	local targetRootPart = bb.targetRootPart
	if not targetRootPart or not targetRootPart.Parent then return end
	Actions.FaceTarget(bb, targetRootPart.Position)
end


-- ---------------------------------------------------------------
-- State definitions
-- ---------------------------------------------------------------

local IdleState: StateDefinition = {
	name = S.Idle,

	onEnter = function(bb)
		Actions.StopMoving(bb)
	end,

	update = function(bb)
		if bossOf(bb).bossTypeSpec.continuousFacing then
			faceTarget(bb)
		end
	end,
}

local PatrolState: StateDefinition = {
	name = S.Patrol,

	onEnter = function(bb)
		-- Clear stale path so MoveToWithPath recomputes toward the player.
		bb.currentPath = nil
		bb.targetPos   = nil
		-- Chasing: the Humanoid turns the boss along its path from here.
		Actions.ReleaseFacing(bb)
	end,

	update = function(bb)
		local targetRootPart = bb.targetRootPart
		if not targetRootPart or not targetRootPart.Parent then
			return
		end
		-- Chase the player using pathfinding
		Actions.MoveToWithPath(bb, targetRootPart.Position)
	end,
}

local AttackPrepState: StateDefinition = {
	name = S.AttackPrep,

	onEnter = function(bb)
		local bossbb = bossOf(bb)
		bossbb.attackWindupStart = os.clock()
		bossbb.attackComplete    = false

		-- Pick a random attack from the current phase's available set,
		-- excluding any skill whose minRange exceeds the current distance.
		local phaseSpec = bossbb.currentPhaseSpec
		local dist = bb.distanceToNearest
		local candidates: { string } = {}
		if phaseSpec then
			for _, attackName in phaseSpec.availableAttacks do
				local skill: SkillTypes.SkillSpec? = bossbb.bossTypeSpec.skills[attackName]
				if skill and (not skill.minRange or dist <= skill.minRange) then
					table.insert(candidates, attackName)
				end
			end
		end
		if #candidates > 0 then
			bossbb.selectedAttack = candidates[math.random(1, #candidates)]
		else
			-- No eligible attack at this range — skip
			bossbb.selectedAttack = nil
		end

		Actions.StopMoving(bb)

		-- Broadcast telegraph VFX to all clients and play windup animation
		local selectedAtk: string? = bossbb.selectedAttack
		if selectedAtk then
			local skill: SkillTypes.SkillSpec? = bossbb.bossTypeSpec.skills[selectedAtk]
			if skill then
				if skill.windupVfx then
					-- The whole window the player has to react in, which for an
					-- aoe is this boss's windup plus the delivery's own: the
					-- disc has to still be pulsing when the circle fires.
					local totalDuration: number = bossbb.bossTypeSpec.attackWindupSec
					local aoeRadius: number? = nil
					if skill.delivery == "aoe" then
						totalDuration = totalDuration + ((skill.deliveryParams.windupSec or 0) :: number)
						aoeRadius = skill.deliveryParams.radius :: number
					end
					-- Described, not drawn: SkillVisuals broadcasts from the
					-- server and every client renders its own (refactor chunk
					-- 10 — this used to be a RemoteEvent of its own plus
					-- BossWindupClient).
					SkillVisuals.spawnTelegraph(skill.windupVfx, bossbb.npc, totalDuration, aoeRadius)
				end

				local track = bossbb.animations["windup_" .. selectedAtk]
				if track then
					local t = track :: any
					t.Priority = Enum.AnimationPriority.Action
					t.Looped   = false
					t:Play(0.1)
				end
			end
		end

		log:info(string.format("%s: AttackPrep → will use '%s'",
			bb.npc.Name, tostring(bossbb.selectedAttack)))
	end,

	update = function(bb)
		-- Keep facing the player during the telegraph window
		faceTarget(bb)
	end,
}

local AttackState: StateDefinition = {
	name = S.Attack,

	onEnter = function(bb)
		local bossbb = bossOf(bb)
		bossbb.attackComplete = false

		local attack: string? = bossbb.selectedAttack
		if not attack then
			bossbb.attackComplete = true
			return
		end

		local skill = bossbb.bossTypeSpec.skills[attack]
		if not skill then
			log:warn("Unknown attack:", attack, "— skipping")
			bossbb.attackComplete = true
			return
		end

		-- Stop windup animation now that the attack is firing
		local windupTrack = bossbb.animations["windup_" .. attack]
		if windupTrack then
			local wt = windupTrack :: any
			if wt.IsPlaying then wt:Stop(0.1) end
		end

		local hrp    = bossbb.humanoidRootPart
		local ctx: SkillTypes.DeliveryCtx = {
			origin     = CFrame.new(hrp.Position + Vector3.new(0, BossConstants.ATTACK_ORIGIN_HEIGHT, 0)),
			target     = bossbb.targetRootPart,
			aoeCenter  = hrp.Position,
			source     = bossbb.npc,
			-- Boss fire is server-only; no client predicts it.
			mode       = "authoritative",
			onComplete = function()
				bossbb.attackComplete = true
			end,
		}
		SkillDelivery.deliver(skill, ctx)
	end,

	update = function(bb)
		-- SkillDelivery handlers are async; attackComplete is set via ctx.onComplete.
		if bossOf(bb).bossTypeSpec.continuousFacing then
			faceTarget(bb)
		end
	end,
}

local CooldownState: StateDefinition = {
	name = S.Cooldown,

	onEnter = function(bb)
		bossOf(bb).cooldownStart = os.clock()
		Actions.StopMoving(bb)
	end,

	update = function(bb)
		-- Wait; transitions check the timer.
		if bossOf(bb).bossTypeSpec.continuousFacing then
			faceTarget(bb)
		end
	end,
}

-- ---------------------------------------------------------------
-- Transition conditions
-- ---------------------------------------------------------------

local function cooldownElapsed(bb: Blackboard): boolean
	local bossbb  = bossOf(bb)
	local elapsed = os.clock() - bossbb.cooldownStart
	local spec    = bossbb.currentPhaseSpec
	local cooldown = if spec then spec.attackCooldown else BossConstants.DEFAULT_ATTACK_COOLDOWN_SEC
	return elapsed >= cooldown
end

local function playerInRange(bb: Blackboard): boolean
	return bb.nearestPlayer ~= nil
		and bb.distanceToNearest <= bossOf(bb).bossTypeSpec.detectionRange
end

local function playerInAttackRange(bb: Blackboard): boolean
	return bb.nearestPlayer ~= nil
		and bb.distanceToNearest <= bossOf(bb).bossTypeSpec.attackRange
end

local function windupElapsed(bb: Blackboard): boolean
	local bossbb = bossOf(bb)
	local start = bossbb.attackWindupStart
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
			{ to = S.Cooldown, condition = function(bb) return bossOf(bb).attackComplete end },
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
