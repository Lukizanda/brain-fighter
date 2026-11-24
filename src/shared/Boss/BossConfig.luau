--!strict

----------------------------------------------------------------------
-- BossConfig
----------------------------------------------------------------------
-- Boss type registry. Each entry defines a complete boss archetype:
-- vitals, engagement ranges, per-skill SkillSpecs, and phase list.
--
-- Level-driven selection: BossService reads
--   BossPoint:GetAttribute("BossType")
-- and falls back to DEFAULT_TYPE when the attribute is absent.
-- Adding a new boss type: add an entry to BOSS_TYPES with all required
-- fields. No code changes required unless the boss has a new delivery
-- or effect kind.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local BossTypes = require(ReplicatedStorage.Shared.Boss.BossTypes)

type BossTypeSpec = BossTypes.BossTypeSpec

local BossConfig = {}

BossConfig.DEFAULT_TYPE = "Brain"

local bossTypes: { [string]: BossTypeSpec } = {
	Brain = {
		name             = "Brain",
		maxHealth        = 1500,
		bodyScale        = 1,
		rigName          = "BossBrain",
		-- Lobes over a neon core on Motor6Ds, animated by each client
		-- (wiki/design/boss-movement.md).
		body             = "Brain",
		hipHeight        = 6,
		respawnDelaySec  = 5,
		-- Time for arriving players to read the island and reach cover before
		-- the boss appears; counted from the first arrival (see BossService).
		entranceDelaySec = 8,
		detectionRange   = 160,
		-- The boss attacks anything within attackRange but keeps walking
		-- toward its target until within stopRange (see BossStates), so it
		-- fires from afar while still closing the distance.
		attackRange      = 150,
		stopRange        = 70,
		attackWindupSec  = 0.5,
		-- Per-attack prep, long enough for the body's tell to read
		-- (wiki/design/boss-movement.md, stage 11b). The slam's total warning
		-- is this plus its delivery windupSec (0.8), so 1.8 s.
		attackPrepSec    = {
			FireballVolley = 0.8,
			SporeLob       = 0.9,
			GroundSlam     = 1.0,
		},
		continuousFacing = true,
		-- Hungry brain: every eatIntervalSec the boss pulls the nearest
		-- letter within eatRadius studs (horizontal; height ignored): it marks
		-- it and holds it in place for eatMarkSec, then yanks it to itself in
		-- eatSnapSec (an ease-in), eating it on arrival within eatReach and
		-- healing eatHealFraction of its health. A player can pop the letter
		-- at any point first. At these values it heals at most about 6% a
		-- minute, less in practice since a tow takes about 1.75 seconds.
		-- Setting eatHealFraction to 0 keeps the pressure and drops the heal.
		eatIntervalSec   = 5,
		eatRadius        = 60,
		eatMarkSec       = 1.4,
		eatSnapSec       = 0.35,
		-- Legacy: read only by the fight simulator (src/shared/Playtest/Sim/FightSim.luau),
		-- which still models the old constant pull. The live boss ignores it.
		eatPullSpeed     = 12,
		eatReach         = 8,
		eatHealFraction  = 0.005,
		-- Spore lob (wiki/design/ai-playtest.md, the spore decision): every
		-- second attack that would have been a FireballVolley is instead a lob
		-- of 3 letter blocks that land within 12 studs of the target 1.5 s
		-- later. Each is a Common-table letter in red or blue that bursts 6 s
		-- after landing for 15 damage to every player within 8 studs; popping
		-- one is a normal pop and costs the boss 3% of its health. Numbers
		-- from the fight simulator's sweep (FightSim tune.spore).
		-- The scramble bomb below took the spore lob's slot (2026-11-21): a
		-- type with both configured lobs the bomb only (BossStates picks
		-- `bombs or spores`), so the Brain no longer lobs spores. The spore
		-- values and code stay, and stay tested, until the spores are retired.
		sporeEveryNthAttack    = 2,
		sporeCount             = 3,
		sporeLandRadius        = 12,
		sporeFlightSec         = 1.5,
		sporeFuseSec           = 6,
		sporeBurstDamage       = 15,
		sporeBurstRadius       = 8,
		sporePopDamageFraction = 0.03,
		-- Hover height over the ground (the simulator's SPORE_HEIGHT), so a
		-- spore sits within a tap of a standing player.
		sporeHoverHeight       = 4,
		sporeLetterTable       = LetterTables.COMMON,
		sporeColors            = { "red", "blue" },
		-- Scramble bomb as a two-phase puzzle (wiki/design/scramble-bomb.md;
		-- starting numbers): every second attack that would have been a volley
		-- (never while the ward is up) lobs ONE puzzle at the target: 1.5 s in
		-- the air, landing within 12 studs of where the target stood. It rests
		-- there as a scrambled key word (3 letters, 4 from phase 2), red or blue,
		-- tapped in order from within 20 studs of its centre; the timer is 8 s
		-- (3 letters) / 10 s (4 letters) and a wrong tap costs 1 s. Solving it
		-- costs the boss 9% / 12% of its health. If the timer runs out the
		-- unsolved letters hatch 0.3 s apart into seekers that chase the nearest
		-- player at 20 studs/s for up to 6 s, 5 studs over the ground, each keeping
		-- its own 6-stud side slot until 10 studs from the player. A seeker bursts
		-- (15 damage within 6 studs) within 3 studs of the player, on a wall, or
		-- when its life ends; a pop reaches 45 studs from the seeker and only
		-- removes it. The hint shows 2 s after landing. bombEnergyScale (the share of the
		-- word's energy) rides on BombDefused.
		bombEveryNthAttack        = 2,
		bombFlightSec             = 1.5,
		bombLandRadius            = 12,
		bombFuseSecByLetters      = { [3] = 6, [4] = 8 },
		bombWrongTapPenaltySec    = 1,
		bombHatchStaggerSec       = 0.3,
		-- Fast but wide-turning (user, 2026-11-25): nearly twice a walk, so it
		-- cannot be outrun, with a turning circle of about 25 studs, so a
		-- sidestep in the last few studs makes it fly past and come round again.
		bombSeekerSpeed           = 30,
		bombSeekerSpeedMax        = 30,
		bombSeekerTurnDegPerSec   = 70,
		-- Final approach (user, 2026-11-25): 20 studs out it locks onto where
		-- the player stands, stops tracking and goes straight at 34 (half a
		-- second to step aside), bursting after 45 studs if it meets nothing.
		bombSeekerCommitStuds     = 30,
		bombSeekerDashSpeed       = 100,
		bombSeekerDashStuds       = 50,
		-- A hatched seeker hangs still this long first (first bot fight,
		-- 2026-11-24: without it the first burst came 0 to 0.7 s after the hatch).
		bombSeekerArmSec          = 1,
		-- They go one at a time, 0.7 s apart, each rising 5 studs in an arc
		-- over its first second (user, 2026-11-25).
		bombSeekerLaunchStaggerSec = 0.7,
		bombSeekerArcHeight       = 5,
		bombSeekerArcSec          = 1,
		bombSeekerLifetimeSec     = 9,
		bombSeekerSpacing         = 6,
		bombSeekerConvergeStuds   = 10,
		bombSeekerTriggerStuds    = 3,
		bombHoverHeight           = 5,
		bombLettersByPhase        = { 3, 4 },
		bombHintAfterSec          = 2,
		-- Switch for the boss damage of a solved puzzle. true: the boss loses
		-- bombDefuseDamageByLetters of its health. false: no damage, the word's
		-- energy (bombEnergyScale) is the whole reward. Off for now, with the
		-- energy at the full word, so the user can feel it (2026-11-25).
		bombDefuseDamageEnabled   = false,
		bombDefuseDamageByLetters = { [3] = 0.09, [4] = 0.12 },
		bombBurstDamage           = 15,
		bombBurstRadius           = 6,
		-- Switch for the distance needed to solve a resting puzzle. true: the
		-- player must be within bombTapReach of it. false: it can be solved from
		-- anywhere a letter block could be tapped (200 studs). Off for now so
		-- the user can feel the difference (2026-11-25).
		bombTapReachEnabled       = false,
		bombTapReach              = 20,
		bombSeekerTapReach        = 45,
		bombColors                = { "red", "blue" },
		bombEnergyScale           = 1,
		-- Word ward (wiki/design/ai-playtest.md, the ward decision): the
		-- boss's health stops at half and 4 Common-table letters circle it,
		-- 10 studs out and 6 up, once round every 8 s; nothing hurts it until
		-- all 4 are popped. Phase 2 below starts at the same half. The radius
		-- and height keep the letters inside the Premium zone's footprint, so
		-- they are tapped from wherever the premium letters are.
		wardAtHpFraction       = 0.5,
		wardLetterCount        = 4,
		wardOrbitRadius        = 10,
		wardOrbitHeight        = 6,
		wardOrbitPeriodSec     = 8,
		wardLetterTable        = LetterTables.COMMON,
		wardColors             = { "red", "green", "blue" },
		-- Vulnerability windows (wiki/design/boss-movement.md, stage 11c):
		-- after a Ground Slam the boss is stuck 1.5 s with its core open, and
		-- when the ward breaks it staggers open for 3 s; every hit in a window
		-- does x1.5. Swept in the fight simulator (FightSim `exposure`).
		exposedAfterAttackSec  = { GroundSlam = 1.5 },
		exposedOnWardBreakSec  = 3,
		exposedDamageMultiplier = 1.5,
		skills = {
			FireballVolley = {
				name      = "FireballVolley",
				delivery  = "projectile",
				windupVfx = "charge_glow",
				deliveryParams = {
					count            = 20,
					speed            = 90,
					-- Tightened from 10 on 2026-11-14: at 10 a volley fired from the
					-- boss's own stopping distance (attackRange) mostly missed a
					-- standing player, so nothing on the island was dangerous.
					spreadDegrees    = 4,
					lifetimeSec      = 3,
					proximityRadius  = 3,
					size             = 2,
					color            = Color3.fromRGB(255, 120, 0),
					staggerSec       = 0.15,
					trackTarget      = true,
					launchEffectId   = "projectile_boss_fireball",
					-- In-flight trail + comet body (2026-08-10). Until this
					-- the boss's only projectile cosmetic was the launch
					-- sound above, so a 20-shot volley crossed the arena as
					-- 20 bare orange cubes. Rates in that entry are held
					-- deliberately low — it runs 20 times at once.
					cosmeticEffectId = "projectile_boss_bolt",
					impactEffectId   = "impact_damage",
				},
				onImpact = {
					{ kind = "damage", amount = 5 },
				},
			},
			GroundSlam = {
				name      = "GroundSlam",
				delivery  = "aoe",
				maxSelectRange = 18,
				windupVfx = "aoe_indicator",
				deliveryParams = {
					radius           = 22,
					windupSec        = 0.8,
					completeSec      = 1.2,
					cosmeticEffectId = "aoe_boss_groundslam",
				},
				onImpact = {
					{ kind = "damage", amount = 25 },
					{ kind = "knockup", force = 60 },
				},
			},
		},
		phases = {
			{
				index            = 1,
				hpFraction       = 1.0,
				attackCooldown   = 4.0,
				walkSpeed        = 6,
				bodyColor        = BrickColor.new("Bright red"),
				availableAttacks = { "FireballVolley", "GroundSlam" },
			},
			-- The second half, from the word ward on: the same attacks,
			-- sooner and from a boss that closes faster.
			{
				index            = 2,
				hpFraction       = 0.5,
				attackCooldown   = 3.0,
				walkSpeed        = 9,
				bodyColor        = BrickColor.new("Crimson"),
				availableAttacks = { "FireballVolley", "GroundSlam" },
			},
		},
	},

	Wizard = {
		name            = "Wizard",
		maxHealth       = 800,
		bodyScale       = 2,
		respawnDelaySec = 5,
		detectionRange  = 100,
		attackRange     = 50,
		attackWindupSec = 0.3,
		skills = {
			FireballVolley = {
				name      = "FireballVolley",
				delivery  = "projectile",
				windupVfx = "charge_glow",
				deliveryParams = {
					count            = 5,
					speed            = 60,
					spreadDegrees    = 25,
					lifetimeSec      = 4,
					proximityRadius  = 3,
					size             = 0.8,
					color            = Color3.fromRGB(120, 80, 255),
					staggerSec       = 0.1,
					launchEffectId   = "projectile_boss_fireball",
					-- Violet, and pointedly not the fire trail the Brain
					-- uses: this shot freezes. Dressing it in the flame
					-- flipbook would promise the wrong status on a spell
					-- whose whole tell is that it isn't fire.
					cosmeticEffectId = "projectile_boss_arcane_bolt",
					-- Single impactEffectId slot; damage wins over freeze as the
					-- more generic "you got hit" cue since detonate() only plays
					-- one id per landed shot.
					impactEffectId   = "impact_damage",
				},
				onImpact = {
					{ kind = "damage", amount = 10 },
					{ kind = "freeze", durationSec = 1.5 },
				},
			},
		},
		phases = {
			{
				index            = 1,
				hpFraction       = 1.0,
				attackCooldown   = 2.5,
				walkSpeed        = 10,
				bodyColor        = BrickColor.new("Royal purple"),
				availableAttacks = { "FireballVolley" },
			},
		},
	},
}

BossConfig.BOSS_TYPES = bossTypes

return BossConfig
