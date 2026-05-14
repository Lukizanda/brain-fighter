---
type: system
description: Pure-Luau formula module — converts a Memorized word into per-color mana. Scrabble letter values × length multiplier; mixed-color words split value-weighted with floor-reconciled rounding so per-color totals always sum exactly to whole-word energy.
updated: 2026-05-14
---

# EnergyEconomy System

Phase 1 foundation ([[design/build-plan]]). When the player Memorizes a buffered word, this module decides how much mana flows into each color reservoir. No Roblox-instance deps, no signals, no mutation — it's a pure formula library.

## Files

- `src/shared/EnergyEconomy/init.luau` — the module
- `src/shared/EnergyEconomy/__tests.luau` — smoke test; requires the module and asserts every pinned worked example. Erroring out if any assertion drifts is the test.

## API

```lua
local EnergyEconomy = require(ReplicatedStorage.Shared.EnergyEconomy)

EnergyEconomy.letterValue(c: string) -> number
EnergyEconomy.lengthMultiplier(len: number) -> number
EnergyEconomy.computeWordEnergy(word: string) -> number
EnergyEconomy.splitByColor(tiles: { Tile }) -> { [Color]: number }

export type Color = "red" | "green" | "blue"
export type Tile = { letter: string, color: Color }
```

### `letterValue(c)`

Scrabble value, case-insensitive. Looks at the first char of `c`. Unknown characters return `0` and log a warning — they should never reach this module in practice (spawner only emits valid letters).

### `lengthMultiplier(len)`

Tier table from [[design/gameplay-loop|gameplay-loop "Tuning numbers"]]:

| Word length | Multiplier |
|---|---|
| ≤ 4 | 1× |
| 5–6 | 1.5× |
| 7–8 | 2× |
| 9+ | 3× |

### `computeWordEnergy(word)`

`math.floor(Σ letter_values × length_multiplier(#word))`. The `math.floor` is required for parity with the pinned worked-example table — `FROZEN` (18 × 1.5 = 27) happens to be integer-exact, but per-color splits inside that same word are not, and we reconcile rounding in `splitByColor`.

### `splitByColor(tiles)`

Each tile contributes `letter_value × length_multiplier` to its OWN color. Length multiplier is derived from total tile count, NOT per-color count — `FLAME` is a 5-letter word for multiplier purposes whether it's all-red or mixed.

**Rounding reconciliation.** With `1.5×` words, a 50/50 split between two colors would lose 1 point of energy to `floor()` on each side. To avoid that drift, the algorithm walks colors in canonical RGB order, floors each color's raw share, and assigns the integer shortfall to the LAST present color. So:

- `Σ per-color split == computeWordEnergy(word formed from these tiles)` — exactly, every time.
- Colors with zero tiles are omitted from the result (not present as `key=0`).

## Letter values (Scrabble, pinned)

| Value | Letters |
|---|---|
| 1 | A E I O U L N S T R |
| 2 | D G |
| 3 | B C M P |
| 4 | F H V W Y |
| 5 | K |
| 8 | J X |
| 10 | Q Z |

## Pinned worked examples

Every value below is ground truth from [[design/gameplay-loop#Worked examples|gameplay-loop "Worked examples"]] and is asserted in `__tests.luau`. **If runtime drifts from these numbers, the formula is wrong — fix the implementation, not the table.**

| Word | Energy |
|---|---|
| CAT | 5 |
| FIRE | 7 |
| ROCK | 10 |
| FLAME | 15 |
| DRAGON | 12 |
| FROZEN | 27 |
| FIREBALL | 26 |
| LIGHTNING | 42 |
| EARTHQUAKES | 81 |
| CHARACTERIZE | 84 |

Color-split (from [[design/gameplay-loop#Color-split worked examples]]):

| Word | Split | Total |
|---|---|---|
| FLAME (F-L-M red, A-E green) | red=12, green=3 | 15 |
| FROZEN (F-R-Z red, O-E-N blue) | red=22, blue=5 | 27 |
| ROCK (R-O red, C-K blue) | red=2, blue=8 | 10 |

## Running the smoke test

```lua
-- In Studio (or via MCP execute_luau):
require(game.ReplicatedStorage.Shared.EnergyEconomy.__tests)
```

The require errors out if any assertion fails; otherwise it returns `{ passed = 13, failed = 0, results = ... }` and prints a `[SUITE PASS]` log line.

## Consumers

- **MemorizeAction** (Phase 2) — calls `computeWordEnergy` + `splitByColor` on a valid Memorize and feeds the result to `EnergyReservoirs:add(color, n)`.
- **HUD: BufferDisplay / SpellMenu** (Phase 4) — may preview `computeWordEnergy(buffer:asWord())` as the player composes, so the player can see what a commit would yield before pressing the button.

## Cross-references

- [[design/gameplay-loop]] — canonical "Tuning numbers" and "Worked examples" tables this module mirrors; if either drifts from the code, the code wins per [[WIKI]] (raw sources are authoritative).
- [[design/build-plan]] — Phase 1 placement; consumed by MemorizeAction in Phase 2.
- [[concepts/SingleOwnership]] — only `EnergyReservoirs` writes the color reservoirs; this module computes inputs, never mutates state.
