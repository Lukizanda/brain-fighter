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
		continuousFacing = true,
		-- Hungry brain: every eatIntervalSec the boss pulls the nearest
		-- letter within eatRadius studs (horizontal; height ignored) toward
		-- itself at eatPullSpeed studs a second, and eats it on coming within
		-- eatReach, healing eatHealFraction of its health. A player can pop
		-- the letter first. At these values it heals at most about 6% a
		-- minute, less in practice since a pull takes several seconds.
		-- Setting eatHealFraction to 0 keeps the pressure and drops the heal.
		eatIntervalSec   = 5,
		eatRadius        = 60,
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
