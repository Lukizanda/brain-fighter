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

local Logger     = require(ReplicatedStorage.Shared.Core.Logger)
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
	skill: SkillTypes.SkillSpec,
}

-- Pinned from gameplay-loop.md § Spell tier thresholds.
-- Cast cost equals the threshold (drain == threshold by design).
local TIER_COSTS: { number } = { 5, 10, 20, 40 }
local NUM_TIERS = #TIER_COSTS

local VALID_COLORS: { [string]: true } = {
	red   = true,
	green = true,
	blue  = true,
}

-- Per-color, tier-indexed spell table. Pinned to gameplay-loop.md
-- § Spell roster (prototype).
-- skill is pure SkillSpec data — SpellExecutor owns dispatch.
local SPELLS: { [Color]: { Spec } } = {
	red = {
		{
			name          = "Spark",
			color         = "red",
			tier          = 1,
			cost          = TIER_COSTS[1],
			targetingMode = "auto",
			skill = {
				name           = "Spark",
				delivery       = "instant",
				deliveryParams = {},
				onImpact       = { { kind = "damage", fractionOfMaxHP = 0.05 } },
			},
		},
		{
			name          = "Fireball",
			color         = "red",
			tier          = 2,
			cost          = TIER_COSTS[2],
			targetingMode = "auto",
			skill = {
				name           = "Fireball",
				delivery       = "instant",
				deliveryParams = {},
				onImpact       = { { kind = "damage", fractionOfMaxHP = 0.20 } },
			},
		},
		{
			name          = "Inferno",
			color         = "red",
			tier          = 3,
			cost          = TIER_COSTS[3],
			targetingMode = "auto",
			skill = {
				name           = "Inferno",
				delivery       = "instant",
				deliveryParams = {},
				onImpact       = { { kind = "damage", fractionOfMaxHP = 0.50 } },
			},
		},
		{
			name          = "Volley",
			color         = "red",
			tier          = 4,
			cost          = TIER_COSTS[4],
			targetingMode = "auto",
			skill = {
				name     = "FireballVolley",
				delivery = "projectile",
				deliveryParams = {
					count             = 3,
					speed             = 50,
					spreadDegrees     = 12,
					lifetimeSec       = 3,
					proximityRadius   = 3,
					size              = 0.6,
					color             = Color3.fromRGB(255, 80, 0),
					staggerSec        = 0.12,
					cosmeticEffectId  = "projectile_red_t4",
				},
				onImpact = { { kind = "damage", amount = 12 } },
			},
		},
	},
	green = {
		{
			name          = "Mend",
			color         = "green",
			tier          = 1,
			cost          = TIER_COSTS[1],
			targetingMode = "auto",
			skill = {
				name           = "Mend",
				delivery       = "instant",
				deliveryParams = {},
				onImpact       = { { kind = "heal", fractionOfMaxHP = 0.15 } },
			},
		},
		{
			name          = "Stone Wall",
			color         = "green",
			tier          = 2,
			cost          = TIER_COSTS[2],
			targetingMode = "placement",
			skill = {
				name           = "Stone Wall",
				delivery       = "world_spawn",
				deliveryParams = { durationSec = 6 },
				onImpact       = {},
			},
		},
		{
			name          = "Sanctuary",
			color         = "green",
			tier          = 3,
			cost          = TIER_COSTS[3],
			targetingMode = "auto",
			skill = {
				name           = "Sanctuary",
				delivery       = "instant",
				deliveryParams = {},
				onImpact       = {
					{ kind = "heal",   fractionOfMaxHP = 1.0 },
					{ kind = "shield", durationSec = 10 },
				},
			},
		},
	},
	blue = {
		{
			name          = "Frost Nip",
			color         = "blue",
			tier          = 1,
			cost          = TIER_COSTS[1],
			targetingMode = "auto",
			skill = {
				name           = "Frost Nip",
				delivery       = "instant",
				deliveryParams = {},
				onImpact       = { { kind = "freeze", durationSec = 1 } },
			},
		},
		{
			name          = "Shield",
			color         = "blue",
			tier          = 2,
			cost          = TIER_COSTS[2],
			targetingMode = "auto",
			skill = {
				name           = "Shield",
				delivery       = "instant",
				deliveryParams = {},
				onImpact       = { { kind = "shield", durationSec = 5 } },
			},
		},
		{
			name          = "Stasis",
			color         = "blue",
			tier          = 3,
			cost          = TIER_COSTS[3],
			targetingMode = "auto",
			skill = {
				name           = "Stasis",
				delivery       = "instant",
				deliveryParams = {},
				onImpact       = {
					{ kind = "freeze", durationSec = 5, damageAmpMultiplier = 2.0 },
				},
			},
		},
	},
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
