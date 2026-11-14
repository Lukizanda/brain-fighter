--!strict

----------------------------------------------------------------------
-- BossTypes
----------------------------------------------------------------------
-- BossBlackboard is a structural superset of NPCTypes.Blackboard.
-- All NPCTypes.Blackboard fields are present so Perception.update()
-- and StateMachine.tick() accept it without changes (cast at call site).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillTypes        = require(ReplicatedStorage.Shared.Skills.SkillTypes)

export type PhaseSpec = {
	index: number,
	hpFraction: number,
	attackCooldown: number,
	walkSpeed: number,
	bodyColor: BrickColor,
	availableAttacks: { string },
}

export type BossTypeSpec = {
	name: string,
	maxHealth: number,
	bodyScale: number,
	rigName: string?,
	hipHeight: number?,
	respawnDelaySec: number,
	-- Seconds between the first player arriving on an arena's island and
	-- the boss appearing, in an arena whose players enter through an
	-- ArenaEntryPad. Absent or 0 = spawn immediately, as before. Applies
	-- to the first spawn of a cycle only, not to a respawn.
	entranceDelaySec: number?,
	detectionRange: number,
	attackRange: number,
	attackWindupSec: number,
	-- When true the boss smoothly rotates toward its target in all non-moving states.
	-- When false (default) facing only happens during AttackPrep (windup telegraph).
	continuousFacing: boolean?,
	-- Hungry brain (Phase 8 stage 9): every `eatIntervalSec` the living boss
	-- picks the nearest eligible letter block within `eatRadius` studs of
	-- itself (horizontal distance, height ignored) and pulls it toward itself
	-- at `eatPullSpeed` studs a second; within `eatReach` studs (3D) of the
	-- boss's root the letter is eaten and the boss heals `eatHealFraction` of
	-- its maximum health. A player can pop the letter first.
	-- A type that leaves out `eatIntervalSec` or `eatRadius`, or sets either
	-- to 0 or less, does not eat at all. One that has both but no positive
	-- `eatPullSpeed` or `eatReach` is a config mistake: it warns and does not
	-- eat. A fraction of 0 or absent still pulls and eats (pressure without
	-- healing).
	eatIntervalSec: number?,
	eatRadius: number?,
	eatPullSpeed: number?,
	eatReach: number?,
	eatHealFraction: number?,
	skills: { [string]: SkillTypes.SkillSpec },
	phases: { PhaseSpec },
}

export type BossBlackboard = {
	-- ── NPCTypes.Blackboard fields ─────────────────────────────────
	npc: Model,
	humanoid: Humanoid,
	humanoidRootPart: BasePart,
	weapon: Tool?,
	nearestPlayer: Player?,
	distanceToNearest: number,
	canSeeTarget: boolean,
	targetHumanoid: Humanoid?,
	targetRootPart: BasePart?,
	perceptionRange: number?,
	currentState: string,
	targetPos: Vector3?,
	currentPath: { Vector3 }?,
	currentWaypointIndex: number,
	moveStartTime: number,
	lastShotTime: number,
	animations: { [string]: AnimationTrack },
	-- ── Boss-specific fields ────────────────────────────────────────
	bossTypeSpec: BossTypeSpec,
	currentPhaseIndex: number,
	currentPhaseSpec: PhaseSpec,
	lastAttackTime: number,
	selectedAttack: string?,
	destroyedParts: { [string]: boolean },
	minionCount: number,
	attackWindupStart: number?,
	attackComplete: boolean,
	cooldownStart: number,
}

return nil
