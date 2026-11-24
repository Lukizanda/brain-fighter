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
	-- Start a lob at `targetPosition`; `onLanded` runs when the spores land (the
	-- bomb's puzzle: when it lands). `targetRoot` is the
	-- boss's target, unused by both lobbers now. False (and `onLanded` never runs)
	-- when the lob could not start.
	beginLob: (self: any, targetPosition: Vector3, onLanded: () -> (), targetRoot: BasePart?) -> boolean,
}

-- The scramble bomb's object has the same two calls BossStates needs
-- (implemented by BossBombs). Its `beginLob` also takes the boss's target root
-- (unused by the puzzle, which lands where the target stood); the spore lob
-- ignores it. `onLanded` runs when the puzzle has landed.
export type BombLobber = SporeLobber

export type BossTypeSpec = {
	name: string,
	maxHealth: number,
	bodyScale: number,
	rigName: string?,
	hipHeight: number?,
	-- The animated body built on the rig at spawn (BrainBody.BODY_NAME), in
	-- place of the template's welded parts. Absent = the template as it is.
	-- See wiki/design/boss-movement.md.
	body: string?,
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
	-- Per-attack prep (AttackPrep) length, keyed by attack name including
	-- "SporeLob"; an attack not listed uses attackWindupSec. Long enough for
	-- the body's tell to read (wiki/design/boss-movement.md, stage 11b).
	attackPrepSec: { [string]: number }?,
	-- When true the boss smoothly rotates toward its target in all non-moving states.
	-- When false (default) facing only happens during AttackPrep (windup telegraph).
	continuousFacing: boolean?,
	-- Hungry brain (Phase 8 stage 9): every `eatIntervalSec` the living boss
	-- picks the nearest eligible letter block within `eatRadius` studs of
	-- itself (horizontal distance, height ignored) and pulls it toward itself
	-- "Lash and yank": it marks the letter and holds it where it is for
	-- `eatMarkSec`, then yanks it to itself over `eatSnapSec` on an ease-in
	-- curve; on arrival (within `eatReach` studs (3D) of the boss's root) the
	-- letter is eaten and the boss heals `eatHealFraction` of its maximum
	-- health. A player can pop the letter at any point first.
	-- A type that leaves out `eatIntervalSec` or `eatRadius`, or sets either
	-- to 0 or less, does not eat at all. One that has both but no positive
	-- `eatMarkSec`, `eatSnapSec` or `eatReach` is a config mistake: it warns
	-- and does not eat. A fraction of 0 or absent still pulls and eats
	-- (pressure without healing).
	eatIntervalSec: number?,
	eatRadius: number?,
	eatMarkSec: number?,
	eatSnapSec: number?,
	-- Legacy: only the fight simulator (Playtest/Sim/FightSim.luau) reads it;
	-- the live boss's pull is eatMarkSec + eatSnapSec now.
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
	-- Scramble bomb as a two-phase puzzle (Boss/Scripts/BossBombs,
	-- wiki/design/scramble-bomb.md): it takes the spore lob's slot. Every
	-- `bombEveryNthAttack`th attack that would have been a FireballVolley (none
	-- while the word ward is up) lobs ONE puzzle at the target: `bombFlightSec`
	-- in the air, landing within `bombLandRadius` studs (horizontal) of where
	-- the target stood. It rests as a scrambled word of
	-- `bombLettersByPhase[phase]` letters (the last entry holds for later
	-- phases) in one of `bombColors`; a player within `bombTapReach` studs of
	-- its centre locks the letters in order, a wrong tap costs
	-- `bombWrongTapPenaltySec` of the timer `bombFuseSecByLetters[letters]`,
	-- and the last letter costs the boss `bombDefuseDamageByLetters[letters]`
	-- of its maximum health. The hint shows `bombHintAfterSec` after landing.
	-- When the timer ends the unlocked letters hatch `bombHatchStaggerSec`
	-- apart into seekers: each chases a player at `bombSeekerSpeed` studs/s,
	-- rising linearly with its age to `bombSeekerSpeedMax` at
	-- `bombSeekerLifetimeSec`, `bombHoverHeight` over the ground beneath it,
	-- with a side slot of `bombSeekerSpacing` studs per slot that shrinks to 0
	-- within `bombSeekerConvergeStuds` of its player. It bursts for
	-- `bombBurstDamage` to every player of the arena within `bombBurstRadius`
	-- studs (horizontal) within `bombSeekerTriggerStuds` of its player, on
	-- world geometry, or when its lifetime ends. A pop within
	-- `bombSeekerTapReach` studs of a seeker only removes it.
	-- `bombEnergyScale` is the share of the word's energy credited for a solved
	-- puzzle (carried to the Economy by BombDefused).
	-- A type that leaves out `bombEveryNthAttack` or any number it needs, or
	-- sets one to 0 or less, never lobs.
	bombEveryNthAttack: number?,
	bombFlightSec: number?,
	bombLandRadius: number?,
	bombFuseSecByLetters: { [number]: number }?,
	bombWrongTapPenaltySec: number?,
	bombHatchStaggerSec: number?,
	bombSeekerSpeed: number?,
	bombSeekerSpeedMax: number?,
	bombSeekerLifetimeSec: number?,
	-- Seconds a freshly hatched seeker hangs still before it chases (optional, 0).
	bombSeekerArmSec: number?,
	-- Degrees a second a seeker can turn (optional; 0 or absent = it tracks
	-- its player exactly). With a limit a late sidestep makes it miss.
	bombSeekerTurnDegPerSec: number?,
	-- The launch (all optional, 0): each seeker of a puzzle starts
	-- `bombSeekerLaunchStaggerSec` after the one before, and rises
	-- `bombSeekerArcHeight` studs in an arc over its first `bombSeekerArcSec`.
	bombSeekerLaunchStaggerSec: number?,
	bombSeekerArcHeight: number?,
	bombSeekerArcSec: number?,
	-- The final approach (all optional; absent = it tracks to the end): within
	-- `bombSeekerCommitStuds` of its player a seeker stops tracking and flies
	-- straight at `bombSeekerDashSpeed` for at most `bombSeekerDashStuds`,
	-- then bursts where it is.
	bombSeekerCommitStuds: number?,
	bombSeekerDashSpeed: number?,
	bombSeekerDashStuds: number?,
	bombSeekerSpacing: number?,
	bombSeekerConvergeStuds: number?,
	bombSeekerTriggerStuds: number?,
	bombHoverHeight: number?,
	bombLettersByPhase: { number }?,
	bombHintAfterSec: number?,
	bombDefuseDamageByLetters: { [number]: number }?,
	-- false = a solved puzzle does not hurt the boss; the word's energy
	-- (`bombEnergyScale`) is the whole reward. Absent or true = it does.
	bombDefuseDamageEnabled: boolean?,
	bombBurstDamage: number?,
	bombBurstRadius: number?,
	bombTapReach: number?,
	-- false = no distance needed to solve a resting puzzle (the ordinary tap
	-- range applies instead). Absent or true = `bombTapReach` applies.
	bombTapReachEnabled: boolean?,
	bombSeekerTapReach: number?,
	bombColors: { string }?,
	bombEnergyScale: number?,
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
	-- Vulnerability windows (Boss/Scripts/BossExposure, stage 11c of
	-- wiki/design/boss-movement.md). After each attack named in
	-- `exposedAfterAttackSec` the boss is stunned (stands still) and exposed
	-- for that many seconds; when its word ward breaks it is exposed for
	-- `exposedOnWardBreakSec`. While exposed every hit on it is multiplied by
	-- `exposedDamageMultiplier` (Health's Vulnerability rule). A type that
	-- leaves out the multiplier, or sets it to 1 or less, has no windows.
	exposedAfterAttackSec: { [string]: number }?,
	exposedOnWardBreakSec: number?,
	exposedDamageMultiplier: number?,
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
	-- The boss's scramble bomb, nil for a type without the bomb config. Takes the
	-- lob slot ahead of `spores` when a type has both (BossStates).
	bombs: BombLobber?,
	-- Until this os.clock() time the boss is stunned: it stands still and
	-- does not leave Cooldown (wiki/design/boss-movement.md, stage 11c).
	stunnedUntil: number?,
	-- Called with the attack's name when an attack finishes (Attack →
	-- Cooldown). Set by BossController.
	onAttackFinished: ((attack: string) -> ())?,
}

return nil
