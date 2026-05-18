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
local SkillDelivery    = require(ReplicatedStorage.Shared.Skills.SkillDelivery)
local NPCTypes         = require(ReplicatedStorage.Shared.NPC.NPCTypes)
local Logger           = require(ReplicatedStorage.Shared.Core.Logger)
local SkillTypes       = require(ReplicatedStorage.Shared.Skills.SkillTypes)

local BossEventsFolder = ReplicatedStorage.Shared.Boss.BossEvents

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

-- Degrees per second the boss rotates toward its target during windup.
-- 180 = half-circle per second; fast enough to feel responsive but visibly smooth.
local FACE_TURN_RATE = 180

-- Smoothly rotates the boss HRP toward the target on the Y axis.
-- Uses os.clock() internally so it works without dt from the state machine.
local function faceTarget(bb: Blackboard)
	local bbany = bb :: any
	local targetRootPart = bbany.targetRootPart
	if not targetRootPart or not targetRootPart.Parent then return end

	local now = os.clock()
	local dt  = now - ((bbany._faceLastTime or now) :: number)
	bbany._faceLastTime = now

	local npcPos    = bb.humanoidRootPart.Position
	local targetPos = (targetRootPart :: BasePart).Position
	local lookTarget = Vector3.new(targetPos.X, npcPos.Y, targetPos.Z)
	if (lookTarget - npcPos).Magnitude < 0.5 then return end

	local currentCFrame = bb.humanoidRootPart.CFrame
	local desiredCFrame = CFrame.lookAt(npcPos, lookTarget)
	-- alpha scales with dt so turn speed is frame-rate-independent
	local alpha = math.min(1, dt * (FACE_TURN_RATE / 90))
	bb.humanoidRootPart.CFrame = currentCFrame:Lerp(desiredCFrame, alpha)
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
		if (bb :: any).bossTypeSpec and (bb :: any).bossTypeSpec.continuousFacing then
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

		-- Pick a random attack from the current phase's available set,
		-- excluding any skill whose minRange exceeds the current distance.
		local phaseSpec = bbany.currentPhaseSpec
		local bossbbPrep = bbany :: BB
		local dist = bb.distanceToNearest
		local candidates: { string } = {}
		if phaseSpec then
			for _, attackName in phaseSpec.availableAttacks do
				local skill: SkillTypes.SkillSpec? = bossbbPrep.bossTypeSpec.skills[attackName]
				if skill and (not skill.minRange or dist <= skill.minRange) then
					table.insert(candidates, attackName)
				end
			end
		end
		if #candidates > 0 then
			bbany.selectedAttack = candidates[math.random(1, #candidates)]
		else
			-- No eligible attack at this range — skip
			bbany.selectedAttack = nil
		end

		Actions.StopMoving(bb)
		-- Reset face timer so the first faceTarget call computes dt=0 (no stale jump)
		bbany._faceLastTime = nil

		-- Broadcast telegraph VFX to all clients and play windup animation
		local selectedAtk: string? = bbany.selectedAttack
		if selectedAtk then
			local bossbb = bbany :: BB
			local skill: SkillTypes.SkillSpec? = bossbb.bossTypeSpec.skills[selectedAtk]
			if skill then
				if skill.windupVfx then
					local windupEventInst = BossEventsFolder:FindFirstChild("BossWindupEvent")
					if windupEventInst then
						local totalDuration: number = bossbb.bossTypeSpec.attackWindupSec
						local aoeRadius: number? = nil
						if skill.delivery == "aoe" then
							totalDuration = totalDuration + ((skill.deliveryParams.windupSec or 0) :: number)
							aoeRadius = skill.deliveryParams.radius :: number
						end
						local windupEvent = windupEventInst :: RemoteEvent
						windupEvent:FireAllClients(bossbb.npc, skill.windupVfx, totalDuration, aoeRadius)
					else
						log:warn("BossWindupEvent not in BossEvents — sync Rojo to enable windup VFX")
					end
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
			bb.npc.Name, tostring((bbany :: any).selectedAttack)))
	end,

	update = function(bb)
		-- Keep facing the player during the telegraph window
		faceTarget(bb)
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

		-- Stop windup animation now that the attack is firing
		local windupTrack = bossbb.animations["windup_" .. attack]
		if windupTrack then
			local wt = windupTrack :: any
			if wt.IsPlaying then wt:Stop(0.1) end
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
		SkillDelivery.deliver(skill, ctx)
	end,

	update = function(bb)
		-- SkillDelivery handlers are async; attackComplete is set via ctx.onComplete.
		if (bb :: any).bossTypeSpec and (bb :: any).bossTypeSpec.continuousFacing then
			faceTarget(bb)
		end
	end,
}

local CooldownState: StateDefinition = {
	name = S.Cooldown,

	onEnter = function(bb)
		(bb :: any).cooldownStart = os.clock()
		Actions.StopMoving(bb)
	end,

	update = function(bb)
		-- Wait; transitions check the timer.
		if (bb :: any).bossTypeSpec and (bb :: any).bossTypeSpec.continuousFacing then
			faceTarget(bb)
		end
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
