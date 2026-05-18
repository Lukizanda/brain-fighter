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

local BossTypes = require(ReplicatedStorage.Shared.Boss.BossTypes)

type BossTypeSpec = BossTypes.BossTypeSpec

local BossConfig = {}

BossConfig.DEFAULT_TYPE = "Brain"

local bossTypes: { [string]: BossTypeSpec } = {
	Brain = {
		name            = "Brain",
		maxHealth       = 1500,
		bodyScale       = 3,
		respawnDelaySec = 5,
		detectionRange  = 80,
		attackRange     = 30,
		attackWindupSec = 0.5,
		skills = {
			FireballVolley = {
				name      = "FireballVolley",
				delivery  = "projectile",
				windupVfx = "charge_glow",
				deliveryParams = {
					count           = 3,
					speed           = 30,
					spreadDegrees   = 15,
					lifetimeSec     = 3,
					proximityRadius = 3,
					size            = 1.5,
					color           = Color3.fromRGB(255, 120, 0),
					staggerSec      = 0.15,
				},
				onImpact = {
					{ kind = "damage", amount = 15, useApplyDamage = true },
				},
			},
			GroundSlam = {
				name      = "GroundSlam",
				delivery  = "aoe",
				minRange  = 18,
				windupVfx = "aoe_indicator",
				deliveryParams = {
					radius      = 22,
					windupSec   = 0.8,
					completeSec = 1.2,
				},
				onImpact = {
					{ kind = "damage", amount = 25, useApplyDamage = true },
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
					count           = 5,
					speed           = 60,
					spreadDegrees   = 25,
					lifetimeSec     = 4,
					proximityRadius = 3,
					size            = 0.8,
					color           = Color3.fromRGB(120, 80, 255),
					staggerSec      = 0.1,
				},
				onImpact = {
					{ kind = "damage", amount = 10, useApplyDamage = true },
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
