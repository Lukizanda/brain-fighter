--!strict

----------------------------------------------------------------------
-- SpellRegistry
----------------------------------------------------------------------
-- Pure-Luau config layer for the spell roster (R/G/B × T1/T2/T3 + T4).
-- Source of truth for spell name, color, tier, cost, targeting mode,
-- and the SkillSpec that SkillDelivery/SkillEffects interpret.
--
-- The roster and tier thresholds are pinned to
-- wiki/design/gameplay-loop.md § "Spell roster (prototype)" and
-- § "Spell tier thresholds". If those numbers move in the design doc,
-- this module is what changes — every other system reads through
-- getSpell/listAffordableSpells.
--
-- The skill table is pure data — delivery kind, per-kind params, and
-- onImpact effects. No behavior lives here; SpellExecutor delegates
-- to SkillDelivery which delegates to SkillEffects.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local SkillTypes = require(ReplicatedStorage.Shared.Skills.SkillTypes)

local log = Logger.new("SpellRegistry")

local SpellRegistry = {}

export type Color = "red" | "green" | "blue"
export type TargetingMode = "auto" | "placement"

export type Spec = {
	name: string,
	color: Color,
	tier: number,
	cost: number,
	targetingMode: TargetingMode,
	-- True for spells that resolve on the caster (Mend, Shield, Sanctuary).
	-- The cast UI used to infer this from color — "green means self" — which
	-- broke the moment a self-buff shipped in another school (blue Shield),
	-- since blue spells demand an enemy in range and pass that enemy as the
	-- target. Read it through needsEnemyTarget rather than branching on
	-- color anywhere.
	selfTarget: boolean?,
	skill: SkillTypes.SkillSpec,
}

-- Pinned from gameplay-loop.md § Spell tier thresholds.
-- Cast cost equals the threshold (drain == threshold by design).
local TIER_COSTS: { number } = { 5, 10, 20, 40 }
local NUM_TIERS = #TIER_COSTS

-- Red projectile tuning (Firebolt T1, Fireball T2). Inferno (T3) is
-- instant and Volley (T4) has its own params block; their tuning lives
-- in the spec literals below.
local FIREBOLT_SPEED = 80
local FIREBOLT_LIFETIME_SEC = 1.5
local FIREBOLT_PROXIMITY_RADIUS = 3
local FIREBOLT_SIZE = 0.5
local FIREBOLT_DAMAGE_FRAC = 0.05
local FIREBOLT_COLOR = Color3.fromRGB(255, 140, 40)

local FIREBALL_SPEED = 55
local FIREBALL_LIFETIME_SEC = 2.0
local FIREBALL_PROXIMITY_RADIUS = 3
local FIREBALL_SIZE = 1.0
local FIREBALL_IMPACT_RADIUS = 7
local FIREBALL_DAMAGE_FRAC = 0.20
local FIREBALL_COLOR = Color3.fromRGB(255, 90, 30)

-- Inferno (T3) tuning. The damage fraction is the spell's entire payload
-- and lands on the cast frame; the burn that follows is cosmetic — see
-- SkillConstants.BURNING_ATTRIBUTE. Three seconds was picked to outlast
-- the impact eruption (impact_damage_t3, ~1.8 s) so the flames are still
-- going when the blast clears, without lingering long enough to read as a
-- damage-over-time the spell does not have.
local INFERNO_DAMAGE_FRAC = 0.50
local INFERNO_BURN_SEC = 3.0

-- Defensive tuning (Phase 5.2). The shield is a flat absorb pool with no
-- expiry — it lasts until damage eats it or the holder dies (design call
-- 2026-08-03; add a duration here if playtest says it overstays). 40
-- absorbs roughly two boss hits (Slam 25, projectile 15). Sanctuary
-- reuses the pool size: its T3 premium over Shield is the full heal, not
-- a bigger bubble.
local SHIELD_ABSORB_POOL = 40
local SANCTUARY_HEAL_FRAC = 1.0

local STONE_WALL_DURATION_SEC = 6
local STONE_WALL_SIZE = Vector3.new(16, 10, 2)
local STONE_WALL_COLOR = Color3.fromRGB(120, 118, 110)

local STASIS_FREEZE_SEC = 5
-- Stasis's payload is the amp, not the freeze: damage dealt to the frozen
-- target is doubled for the duration. Delivered as a separate `buff`
-- effect rather than a freeze parameter so the multiplier is reusable by
-- any future spell that amplifies without freezing.
local STASIS_DAMAGE_AMP = 2.0

local VALID_COLORS: { [string]: true } = {
	red = true,
	green = true,
	blue = true,
}

-- Per-color, tier-indexed spell table. Pinned to gameplay-loop.md
-- § Spell roster (prototype).
-- skill is pure SkillSpec data — SpellExecutor owns dispatch.
local SPELLS: { [Color]: { Spec } } = {
	red = ({
		{
			name = "Firebolt",
			color = "red",
			tier = 1,
			cost = TIER_COSTS[1],
			targetingMode = "auto",
			skill = {
				name = "Firebolt",
				delivery = "projectile",
				deliveryParams = {
					count = 1,
					speed = FIREBOLT_SPEED,
					spreadDegrees = 0,
					lifetimeSec = FIREBOLT_LIFETIME_SEC,
					proximityRadius = FIREBOLT_PROXIMITY_RADIUS,
					size = FIREBOLT_SIZE,
					color = FIREBOLT_COLOR,
					staggerSec = 0,
					trackTarget = true,
					cosmeticEffectId = "projectile_red_t1",
					impactEffectId = "impact_damage",
				},
				onImpact = { { kind = "damage", fractionOfMaxHP = FIREBOLT_DAMAGE_FRAC } },
			},
		},
		{
			name = "Fireball",
			color = "red",
			tier = 2,
			cost = TIER_COSTS[2],
			targetingMode = "auto",
			skill = {
				name = "Fireball",
				delivery = "projectile",
				deliveryParams = {
					count = 1,
					speed = FIREBALL_SPEED,
					spreadDegrees = 0,
					lifetimeSec = FIREBALL_LIFETIME_SEC,
					proximityRadius = FIREBALL_PROXIMITY_RADIUS,
					size = FIREBALL_SIZE,
					color = FIREBALL_COLOR,
					staggerSec = 0,
					trackTarget = true,
					impactRadius = FIREBALL_IMPACT_RADIUS,
					-- No neon ground disc (2026-08-09). The blast reads as
					-- an explosion on its own now that it draws Inferno's
					-- fire, and the disc under it read as a separate flat
					-- decal laid on the floor rather than as part of the
					-- same event. `impactColor` is gone with it — it only
					-- ever tinted the ring. What is genuinely lost is exact
					-- radius legibility; the fire is sized to imply the
					-- 7 studs instead of drawing them.
					impactRing = false,
					cosmeticEffectId = "projectile_red_t2",
					-- Heavier splash burst than the shared impact_damage a
					-- T1 Firebolt uses, so the 7-stud blast reads as bigger
					-- than a single-target poke. Since 2026-08-09 it draws
					-- the same flipbook fire layers as Inferno's eruption,
					-- scaled down and burning out inside ~1.2 s — Fireball
					-- has no burn status to hand off to.
					impactEffectId = "impact_damage_t2",
				},
				onImpact = { { kind = "damage", fractionOfMaxHP = FIREBALL_DAMAGE_FRAC } },
			},
		},
		{
			name = "Inferno",
			color = "red",
			tier = 3,
			cost = TIER_COSTS[3],
			targetingMode = "auto",
			skill = {
				name = "Inferno",
				delivery = "instant",
				deliveryParams = {},
				-- Order matters only for readability; both land on the same
				-- frame. `burn` is the render flag that keeps the target
				-- alight after the eruption — it deals nothing.
				onImpact = {
					{ kind = "damage", fractionOfMaxHP = INFERNO_DAMAGE_FRAC },
					{ kind = "burn", durationSec = INFERNO_BURN_SEC },
				},
			},
		},
		{
			name = "Volley",
			color = "red",
			tier = 4,
			cost = TIER_COSTS[4],
			targetingMode = "auto",
			skill = {
				name = "FireballVolley",
				delivery = "projectile",
				deliveryParams = {
					count = 3,
					speed = 50,
					spreadDegrees = 12,
					lifetimeSec = 3,
					proximityRadius = 3,
					size = 0.6,
					color = Color3.fromRGB(255, 80, 0),
					staggerSec = 0.12,
					cosmeticEffectId = "projectile_red_t4",
				},
				onImpact = { { kind = "damage", amount = 12 } },
			},
		},
	} :: { Spec }),
	green = ({
		{
			name = "Mend",
			color = "green",
			tier = 1,
			cost = TIER_COSTS[1],
			targetingMode = "auto",
			selfTarget = true,
			skill = {
				name = "Mend",
				delivery = "instant",
				deliveryParams = {},
				onImpact = { { kind = "heal", fractionOfMaxHP = 0.15 } },
			},
		},
		{
			name = "Stone Wall",
			color = "green",
			tier = 2,
			cost = TIER_COSTS[2],
			targetingMode = "placement",
			skill = {
				name = "Stone Wall",
				delivery = "world_spawn",
				deliveryParams = {
					durationSec = STONE_WALL_DURATION_SEC,
					size = STONE_WALL_SIZE,
					color = STONE_WALL_COLOR,
					-- Attaches to the barrier itself. The usual impact-VFX
					-- route resolves from onImpact effect kinds, which this
					-- spell has none of.
					cosmeticEffectId = "impact_wall",
				},
				-- The barrier Part IS the effect; nothing to apply on impact.
				onImpact = {},
			},
		},
		{
			name = "Sanctuary",
			color = "green",
			tier = 3,
			cost = TIER_COSTS[3],
			targetingMode = "auto",
			selfTarget = true,
			skill = {
				name = "Sanctuary",
				delivery = "instant",
				deliveryParams = {},
				-- Full heal plus a bubble. The shield component was stripped in
				-- 5.1 because the failing stub refunded the mana while the heal
				-- still landed; restored now that `shield` is real.
				onImpact = {
					{ kind = "heal", fractionOfMaxHP = SANCTUARY_HEAL_FRAC },
					{ kind = "shield", amount = SHIELD_ABSORB_POOL },
				},
			},
		},
	} :: { Spec }),
	blue = ({
		{
			name = "Frost Nip",
			color = "blue",
			tier = 1,
			cost = TIER_COSTS[1],
			targetingMode = "auto",
			skill = {
				name = "Frost Nip",
				delivery = "instant",
				deliveryParams = {},
				onImpact = { { kind = "freeze", durationSec = 3 }, { kind = "damage", fractionOfMaxHP = 0.05 } },
			},
		},
		{
			name = "Shield",
			color = "blue",
			tier = 2,
			cost = TIER_COSTS[2],
			targetingMode = "auto",
			selfTarget = true,
			skill = {
				name = "Shield",
				delivery = "instant",
				deliveryParams = {},
				onImpact = { { kind = "shield", amount = SHIELD_ABSORB_POOL } },
			},
		},
		{
			name = "Stasis",
			color = "blue",
			tier = 3,
			cost = TIER_COSTS[3],
			targetingMode = "auto",
			skill = {
				name = "Stasis",
				delivery = "instant",
				deliveryParams = {},
				onImpact = {
					{ kind = "freeze", durationSec = STASIS_FREEZE_SEC },
					{
						kind = "buff",
						buffKind = "damageAmp",
						magnitude = STASIS_DAMAGE_AMP,
						durationSec = STASIS_FREEZE_SEC,
					},
				},
			},
		},
	} :: { Spec }),
}

local function assertValidColor(color: string, fnName: string)
	if not VALID_COLORS[color] then
		error(
			string.format(
				"SpellRegistry.%s: invalid color %q (expected 'red', 'green', or 'blue')",
				fnName,
				tostring(color)
			),
			3
		)
	end
end

local function assertValidTier(tier: number, fnName: string)
	if tier < 1 or tier > NUM_TIERS or tier ~= math.floor(tier) then
		error(
			string.format(
				"SpellRegistry.%s: invalid tier %s (expected 1–%d)",
				fnName,
				tostring(tier),
				NUM_TIERS
			),
			3
		)
	end
end

-- Returns the Spec for the given color/tier. Errors on invalid args so
-- callers can't silently pull nil and propagate it into the executor.
function SpellRegistry.getSpell(color: Color, tier: number): Spec
	assertValidColor(color, "getSpell")
	assertValidTier(tier, "getSpell")
	return SPELLS[color][tier]
end

-- Does casting this spell require an enemy locked in range?
--
-- False for self-buffs (they resolve on the caster) and for placement
-- spells (they resolve on a spot in the world). Callers should treat a
-- false here as "cast with target = nil" — SkillEffects.heal and .shield
-- both fall back to the source, and the world_spawn delivery places
-- relative to the caster's origin.
function SpellRegistry.needsEnemyTarget(spec: Spec): boolean
	return not spec.selfTarget and spec.targetingMode ~= "placement"
end

-- Returns specs of the given color whose cost <= energy, sorted by tier
-- ascending. Used by the cast-menu HUD to render the affordable list
-- for a single color reservoir.
function SpellRegistry.listAffordableSpells(color: Color, energy: number): { Spec }
	assertValidColor(color, "listAffordableSpells")
	local affordable: { Spec } = {}
	for _, spec in SPELLS[color] do
		if spec.cost <= energy then
			table.insert(affordable, spec)
		end
	end
	-- SPELLS is declared in tier order so insertion is already ascending,
	-- but sort explicitly so the API contract doesn't rely on table layout.
	table.sort(affordable, function(a, b)
		return a.tier < b.tier
	end)
	return affordable
end

log:info(string.format("Loaded — %d colors × up to %d tiers", 3, NUM_TIERS))

return SpellRegistry
