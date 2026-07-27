---
type: system
description: The gold ★ wildcard letter block — stands in for any letter when spelling. Covers the char/glyph split, spawn rarity, dictionary resolution, and the three-way energy spread.
updated: 2026-07-27
---

# Wildcard

A wildcard is a letter block that stands in for **any** letter. Shoot one into the buffer and `D★G` is a valid word — it resolves to DOG, DIG, or DUG. Wildcards are gold, distinct from the three reservoir colors, and spawn at roughly 4% of blocks.

`src/shared/Wildcard/init.luau` is a dependency-free constants + helpers module that every layer of the spelling chain requires. Keeping it standalone is deliberate: [[systems/Dictionary]] and [[systems/EnergyEconomy]] are pure-Luau and must not pull in [[systems/LetterBlock]] (which touches Roblox instances) just to learn what a star is.

## CHAR vs GLYPH

The single most important detail: **the internal representation is ASCII `*`, never `★`.**

| | value | where it appears |
|---|---|---|
| `Wildcard.CHAR` | `"*"` | `Block.Letter` attribute, `WordBuffer:asWord()`, log lines, Lua patterns |
| `Wildcard.GLYPH` | `"★"` | block face SurfaceGui, HUD buffer tile — **presentation only** |
| `Wildcard.COLOR` | `"wild"` | `Block.Color` attribute, `WordBuffer` tile color, HUD `TILE_COLORS` key |

`★` never round-trips back into game logic. `Wildcard.toDisplay(letter)` is the one-way door — the block face and the HUD tile both call it, so they cannot disagree about how a star looks.

## API

```lua
Wildcard.CHAR   -- "*"
Wildcard.GLYPH  -- "★"
Wildcard.COLOR  -- "wild"

Wildcard.isWildcard(c: string) -> boolean    -- c == "*"
Wildcard.hasWildcard(s: string) -> boolean   -- plain-text find, no pattern
Wildcard.toDisplay(letter: string) -> string -- "★", else uppercased letter
Wildcard.normalize(letter: string) -> string -- "*" as-is, else first char uppercased
```

## Design decisions

These were settled explicitly; each has a cheaper alternative that was rejected.

**Energy = the letter it resolves to, picking the highest-scoring match.** A star pays out whatever letter it stood in for, and `Dictionary.resolve` is handed `EnergyEconomy.computeWordEnergy` as the scorer so the player always gets the best their letters allow. Rejected: a Scrabble-blank 0, which makes wildcards pure flexibility with no upside.

> **Known consequence:** an all-wildcard buffer reliably pays out the highest-scoring word of that length — `★★★` resolves to KHZ (19 energy), and a full 12-star buffer to SQUEEZEBOXES (117, more than a real 11-letter word). This was accepted knowingly: at a 4% spawn rate, collecting even three stars at once is rare, and twelve is effectively unreachable. If it ever becomes a problem the lever is `Dictionary.resolve`'s `scoreFn`, not the spawner.

**No cap on wildcards per word.** This is what forces the matcher design below — 26<sup>k</sup> letter expansion is not viable past k≈2.

**Gold, not one of the three reservoir colors.** A player scanning a field of ~24 blocks can pick a star out at a glance. The cost is a 4th color threaded through `WordBuffer.VALID_COLORS`, `LetterBlocks.COLOR_TINTS`, and `BufferDisplayConfig.TILE_COLORS`.

**Wild energy splits evenly across all three reservoirs.** Gold is not a reservoir, so a wild tile's value has to go somewhere. Thirds keep it thematically "wild" and never waste earned energy. Rejected: routing to the word's majority color (swingy, needs a tiebreak rule).

**~4% spawn rate**, vs Scrabble's own 2/98 ≈ 2%. Blocks recycle continuously as they're consumed, so the stingier rate left too many arenas with no star at all.

## Dictionary resolution

Because wildcards are uncapped, [[systems/Dictionary]] cannot expand a pattern into concrete candidates. Instead each per-letter module is indexed by word length at load time (`byLength[letter][len]`), and matching scans only candidates that could possibly fit:

- **Concrete first letter** (`D*G`) — scan `byLength["d"][3]` only. Hundreds of candidates.
- **Leading wildcard** (`*OG`, `***`) — scan all 26 buckets at that length. Tens of thousands.

The pattern is compiled to a Lua pattern (`d*g` → `^d[a-z]g$`). Input is validated character-by-character to `[a-z]` or `*` **before** the pattern is built, so no escaping is needed and a literal `.` cannot be injected to match everything.

Cost: one extra array of string references per word, ~1 MB across the corpus.

### Measured performance (2026-07-27 playtest)

| call | when | cost |
|---|---|---|
| `isSpellable("D*G")` — match, early exit | per buffer change | < 0.01 ms |
| `isSpellable("*ZQXJV")` — no match, all 26 buckets | per buffer change | 0.48 ms |
| `isSpellable("***********Q")` — 12 wide, no match | per buffer change | 0.77 ms |
| `resolve("D*G", scoreFn)` | per Memorize press | < 0.01 ms |
| `resolve("******", scoreFn)` — scored, no early exit | per Memorize press | 6.8 ms |
| `resolve("************", scoreFn)` | per Memorize press | 6.9 ms |

The HUD path (`isSpellable`) early-exits on the first match, so only *unmatchable* wildcard buffers pay full scan cost — and those top out under 1 ms. The scored path cannot early-exit (it must see every candidate to pick the best), but it runs once per button press, not per frame.

## Energy split

`EnergyEconomy.splitByColor` treats a wild tile as belonging to no reservoir and divides its value three ways. One wild tile makes **all three** colors recipients, even ones with no tile of their own.

The share is computed as `floor((ownSum × 3 + wildSum) × multiplier / 3)` — scaling into thirds *before* dividing. Computing `wildSum / 3` up front introduces a repeating binary fraction whose rounding can straddle an integer boundary: `(1 + 1/3) × 1.5` lands a hair under 2 and floors to 1 instead of 2. The `FL*ME` pinned case in `EnergyEconomy/__tests.luau` exists specifically to catch that regression.

The `Σ split == computeWordEnergy` invariant is unchanged — the last present color in canonical RGB order still absorbs the remainder.

## Flow

```
BlockSpawner    rolls "*" as a 27th letter (weight 4 vs the 98-tile Scrabble bag)
                → pairs it with COLOR, never a rolled reservoir color
LetterBlocks    tints gold, paints GLYPH on all six faces
BlockShoot      reads Block.Letter="*" / Block.Color="wild" — no special-casing
WordBuffer      accepts "wild" as a 4th tile color; asWord() yields "D*G"
Hud             renders GLYPH on a gold tile; glow uses Dictionary.isSpellable
MemorizeAction  resolve("D*G", computeWordEnergy) → "DOG"
                stamps resolved letters onto tiles, KEEPS color="wild"
EnergyEconomy   splits — wild tiles' value spread across red/green/blue
```

The step that makes this work is MemorizeAction stamping the resolved letter onto each tile while leaving the color alone. That is what lets a wild tile score as a real letter *and* still spread its energy three ways.

## Tunables

| constant | file | value |
|---|---|---|
| `WILDCARD_FREQUENCY` | `BlockSpawner/init.luau` | `4` → 4/102 ≈ 3.9%; set `0` to disable wildcards entirely |
| gold tint | `LetterBlocks/init.luau` `COLOR_TINTS.wild` | `#eab308` |
| HUD tile gold | `Hud/BufferDisplayConfig.luau` `TILE_COLORS.wild` | `Color3.fromRGB(225, 180, 60)` |

## Verification

Playtest-confirmed 2026-07-27:

- Block renders gold with a white ★ on all six faces (GothamBold has the glyph — `TextBounds` 68×100, not a missing-glyph box).
- HUD tile renders ★ on `RGB(225,180,60)`.
- `D*G` → DIG (DOG/DIG/DUG all score 5; ties keep the first in corpus order, which is alphabetical and therefore deterministic).
- `FL*ME` → FLAME, split `{red=12, green=2, blue=1}`, sums to 15.
- `XQ*ZJ` → unresolvable, fizzles and clears the buffer like any invalid word.
- All three pinned pre-wildcard split cases (FLAME, FROZEN, ROCK) produce identical values to before.

Suites: `Dictionary.__tests`, `EnergyEconomy.__tests`, `WordBuffer.__tests` — all pass.

## Gotcha

A lone `*` is **not** spellable. The SCOWL-60 corpus has no single-letter entries — not even "a" or "i" — so there is nothing for it to resolve to. Pinned in `Dictionary/__tests.luau`.

## See also

- [[systems/LetterBlock]] — the block prefab and its tints
- [[systems/Dictionary]] — `resolve` / `isSpellable`
- [[systems/EnergyEconomy]] — the three-way wild split
- [[systems/MemorizeAction]] — where resolution happens
- [[systems/BlockSpawner]] — spawn weighting
- [[systems/WordBuffer]] — the 4th tile color
