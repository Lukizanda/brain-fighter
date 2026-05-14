---
type: system
description: Pure-Luau config layer for the 9 prototype spells (R/G/B × T1/T2/T3) — name, color, tier, cost, targeting mode, effectSpec stub. Single source of truth for the spell roster.
updated: 2026-05-14
---

# SpellRegistry

Config-only module for the prototype 9-spell roster. Owns the per-spell name, color, tier, cost, targeting mode, and an `effectSpec` stub that downstream systems (SpellExecutor, the cast-menu HUD) consume.

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
-- spec.name == "Fireball", spec.cost == 30, spec.targetingMode == "auto"

-- Affordable list for a single color reservoir, sorted by tier ascending.
local options = SpellRegistry.listAffordableSpells("red", 35)
-- → { Spark, Fireball }  (Inferno costs 80, filtered out)
```

## Spec shape

```lua
export type Color = "red" | "green" | "blue"
export type TargetingMode = "auto" | "placement"

export type EffectSpec = {
  kind: string,         -- discriminator: "damage" | "heal" | "wall" | "freeze" | "shield"
  [string]: any,        -- kind-specific parameters
}

export type Spec = {
  name: string,
  color: Color,
  tier: number,         -- 1 | 2 | 3
  cost: number,         -- equals TIER_COSTS[tier] by design (drain == threshold)
  targetingMode: TargetingMode,
  effectSpec: EffectSpec,
}
```

`effectSpec` is intentionally a discriminator-keyed stub. [[systems/SpellExecutor|SpellExecutor]] (Phase 2) owns interpretation; extra fields are passed through as-is so adding a new spell here doesn't require executor changes for shape, only for behavior.

## Tier thresholds

| Tier | Cost (= drain) |
|---|---|
| T1 | 10 |
| T2 | 30 |
| T3 | 80 |

Declared as `TIER_COSTS = { 10, 30, 80 }` in `init.luau`. Cost and drain are equal by design — see [[design/gameplay-loop]] § "Spell economy".

## The 9-spell roster

| Color | Tier | Name | Targeting | effectSpec |
|---|---|---|---|---|
| Red | T1 | Spark | `auto` | `{ kind = "damage", fractionOfMaxHP = 0.05 }` |
| Red | T2 | Fireball | `auto` | `{ kind = "damage", fractionOfMaxHP = 0.20 }` |
| Red | T3 | Inferno | `auto` | `{ kind = "damage", fractionOfMaxHP = 0.50 }` |
| Green | T1 | Mend | `auto` | `{ kind = "heal", fractionOfMaxHP = 0.15 }` |
| Green | T2 | Stone Wall | `placement` | `{ kind = "wall", durationSec = 6 }` |
| Green | T3 | Sanctuary | `auto` | `{ kind = "heal", fractionOfMaxHP = 1.0, buffSpec = { kind = "shield", durationSec = 10 } }` |
| Blue | T1 | Frost Nip | `auto` | `{ kind = "freeze", durationSec = 1 }` |
| Blue | T2 | Shield | `auto` | `{ kind = "shield", durationSec = 5 }` |
| Blue | T3 | Stasis | `auto` | `{ kind = "freeze", durationSec = 5, damageAmpMultiplier = 2.0 }` |

These numbers are first-prototype starting points. Tuning is expected — see [[design/gameplay-loop]] § "Playtest verification".

## Errors

- `getSpell(color, tier)` — `error` if `color` is not `"red"|"green"|"blue"` or `tier` is not `1|2|3`.
- `listAffordableSpells(color, energy)` — `error` if `color` is invalid. Any non-negative `energy` is accepted; below-T1 returns `{}`.

## Cross-references

- Pinned design source → [[design/gameplay-loop]] § "Spell roster (prototype)"
- Downstream consumer → [[systems/SpellExecutor|SpellExecutor]] (Phase 2 — pending)
- Cast UX surface → [[systems/HUD]] cast-menu builder (Phase 4 — pending)
- Build plan → [[design/build-plan]] (Phase 1)
