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

-- What BossStates needs of the boss's spore lob (implemented by BossSpores).
export type SporeLobber = {
	-- Call once for every attack that would have been a FireballVolley;
	-- true when this one is a lob instead.
	replacesVolley: (self: any) -> boolean,
	-- Start a lob at `targetPosition`; `onLanded` runs when the spores land.
	-- False (and `onLanded` never runs) when the lob could not start.
	beginLob: (self: any, targetPosition: Vector3, onLanded: () -> ()) -> boolean,
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
	-- The boss may attack a target within this many studs.
	attackRange: number,
	-- Distance at which the boss stops walking toward its target. A type that
	-- omits it stops at attackRange (the old behaviour). Set below attackRange
	-- to let the boss fire from afar while still closing in.
	stopRange: number?,
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
	-- Spore lob (the spore-letters mechanic, Boss/Scripts/BossSpores): every
	-- `sporeEveryNthAttack`th attack that would have been a FireballVolley is a
	-- lob instead. The boss throws `sporeCount` letter blocks that land within
	-- `sporeLandRadius` studs (horizontal) of its target `sporeFlightSec`
	-- seconds after the lob starts, hovering `sporeHoverHeight` studs over the
	-- ground. Each is an ordinary letter (rolled from `sporeLetterTable`, in one
	-- of `sporeColors`) that bursts `sporeFuseSec` after landing: it deals
	-- `sporeBurstDamage` to every player of the arena within `sporeBurstRadius`
	-- studs (horizontal) and is gone. Popping one is a normal pop, does not
	-- burst it, and costs the boss `sporePopDamageFraction` of its maximum
	-- health, credited to the popper.
	-- A type that leaves out `sporeEveryNthAttack`, `sporeCount`,
	-- `sporeLandRadius`, `sporeFlightSec`, `sporeFuseSec` or `sporeBurstRadius`,
	-- or sets one to 0 or less, never lobs.
	sporeEveryNthAttack: number?,
	sporeCount: number?,
	sporeLandRadius: number?,
	sporeFlightSec: number?,
	sporeFuseSec: number?,
	sporeBurstDamage: number?,
	sporeBurstRadius: number?,
	sporePopDamageFraction: number?,
	sporeHoverHeight: number?,
	sporeLetterTable: string?,
	sporeColors: { string }?,
	-- Word ward (Boss/Scripts/BossWard): the boss's health cannot be taken
	-- below `wardAtHpFraction` of its maximum until the ward is broken. The
	-- hit that would cross the line lands on it, `wardLetterCount` letter
	-- blocks (rolled from `wardLetterTable`, each in one of `wardColors`)
	-- appear and circle the boss `wardOrbitRadius` studs out and
	-- `wardOrbitHeight` studs above its root, once round every
	-- `wardOrbitPeriodSec` seconds, and nothing hurts the boss until every one
	-- has been popped. A boss has one ward. What changes afterwards (a faster
	-- boss) is an ordinary entry in `phases` at the same fraction.
	-- A type that leaves out `wardAtHpFraction`, or sets it to 0 or less,
	-- has no ward.
	wardAtHpFraction: number?,
	wardLetterCount: number?,
	wardOrbitRadius: number?,
	wardOrbitHeight: number?,
	wardOrbitPeriodSec: number?,
	wardLetterTable: string?,
	wardColors: { string }?,
	skills: { [string]: SkillTypes.SkillSpec },
	phases: { PhaseSpec },
}

export type BossBlackboard = {
	-- ── NPCTypes.Blackboard fields ─────────────────────────────────
	npc: Model,
	humanoid: Humanoid,
	humanoidRootPart: BasePart,
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
	-- The boss's spore lob, nil for a type without the spore config. The
	-- attack states ask it whether this volley becomes a lob and hand it the
	-- lob; it is a structural type so this shared file need not require the
	-- server module (Boss/Scripts/BossSpores).
	spores: SporeLobber?,
}

return nil
