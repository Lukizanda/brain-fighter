---
type: system
description: Pure-Luau config layer for the spell roster (R/G/B × T1–T4) — name, color, tier, cost, targeting mode, skill:SkillSpec. Single source of truth consumed by SpellExecutor and the cast-menu HUD.
updated: 2026-06-05
---

# SpellRegistry

Config-only module for the spell roster. Owns the per-spell name, color, tier, cost, targeting mode, and a `skill: SkillSpec` that `SkillDelivery` / `SkillEffects` consume. (Prior to the Skills pipeline refactor, this field was `effectSpec: EffectSpec` — the shape changed in commit `03b6080`.)

The roster is **pinned** to [[design/gameplay-loop]] § "Spell roster (prototype)" and § "Spell tier thresholds". If those numbers move in the design doc, this module is the single thing that changes — every other system reads through `getSpell` / `listAffordableSpells`.

## Files

- `src/shared/SpellRegistry/init.luau` — module: types, tier costs, spell table, public API
- `src/shared/SpellRegistry/__tests.luau` — pure-Luau smoke tests (`runAll() -> (passed, failed)`)

## API

```lua
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)

-- Spec lookup. Errors on invalid color or tier (so callers can't
-- silently pull nil and propagate into the executor).
local spec = SpellRegistry.getSpell("red", 2)
-- spec.name == "Fireball", spec.cost == 10, spec.targetingMode == "auto"

-- Affordable list for a single color reservoir, sorted by tier ascending.
local options = SpellRegistry.listAffordableSpells("red", 35)
-- → { Firebolt, Fireball, Inferno }  (Volley costs 40, filtered out)
```

## Spec shape

```lua
export type Color = "red" | "green" | "blue"
export type TargetingMode = "auto" | "placement"

export type Spec = {
  name: string,
  color: Color,
  tier: number,         -- 1 | 2 | 3 | 4
  cost: number,         -- equals TIER_COSTS[tier] by design (drain == threshold)
  targetingMode: TargetingMode,
  skill: SkillTypes.SkillSpec,  -- delivery + onImpact effects
}
```

`skill.onImpact` is a list of `EffectSpec` entries. `skill.delivery` selects a `SkillDelivery` handler (`"instant"`, `"projectile"`, `"aoe"`, `"world_spawn"`). Adding a new spell here only requires defining the `skill` shape — no executor changes needed.

## Tier thresholds

| Tier | Cost (= drain) |
|---|---|
| T1 | 5 |
| T2 | 10 |
| T3 | 20 |
| T4 | 40 |

Declared as `TIER_COSTS = { 5, 10, 20, 40 }` in `init.luau`. Cost and drain are equal by design — see [[design/gameplay-loop]] § "Spell economy".

## The 10-spell roster

| Color | Tier | Name | Targeting | Delivery | onImpact |
|---|---|---|---|---|---|
| Red | T1 | Firebolt | `auto` | `projectile` | `damage fractionOfMaxHP=0.05` |
| Red | T2 | Fireball | `auto` | `projectile` | `damage fractionOfMaxHP=0.20` |
| Red | T3 | Inferno | `auto` | `instant` | `damage fractionOfMaxHP=0.50` |
| Red | T4 | Volley | `auto` | `projectile` | `damage amount=12` (3 projectiles, `staggerSec=0.12`) |
| Green | T1 | Mend | `auto` | `instant` | `heal fractionOfMaxHP=0.15` |
| Green | T2 | Stone Wall | `placement` | `world_spawn` | _(none; `durationSec=6`)_ |
| Green | T3 | Sanctuary | `auto` | `instant` | `heal 100% + shield 10s` |
| Blue | T1 | Frost Nip | `auto` | `instant` | `freeze durationSec=1` |
| Blue | T2 | Shield | `auto` | `instant` | `shield durationSec=5` |
| Blue | T3 | Stasis | `auto` | `instant` | `freeze durationSec=5, damageAmpMultiplier=2.0` |

These numbers are first-prototype starting points. Tuning is expected — see [[design/gameplay-loop]] § "Playtest verification".

## Errors

- `getSpell(color, tier)` — `error` if `color` is not `"red"|"green"|"blue"` or `tier` is not `1|2|3|4`.
- `listAffordableSpells(color, energy)` — `error` if `color` is invalid. Any non-negative `energy` is accepted; below-T1 returns `{}`.

## Cross-references

- Pinned design source → [[design/gameplay-loop]] § "Spell roster (prototype)"
- Downstream consumer → [[systems/SpellExecutor|SpellExecutor]] (shipped) and the unified [[systems/SkillPipeline]]
- Cast UX surface → [[systems/HUD]] SpellMenu builder (shipped)
- Build plan → [[design/build-plan]] (Phase 1)
