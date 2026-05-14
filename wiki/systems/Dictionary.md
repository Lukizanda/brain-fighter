---
type: system
description: Word lookup module that validates the buffered word during Memorize. O(1) hashtable, ~4.1k K-12 bootstrap entries; planned upgrade path to a curated 10–30k SCOWL list.
updated: 2026-05-14
---

# Dictionary

Pure-Luau, Roblox-instance-free word lookup. The Memorize action calls `Dictionary.isWord(buffer:asWord())` to decide whether the buffered word transmutes into per-color reservoirs or fizzles. See [[design/gameplay-loop]] for the decision context.

Phase 1 foundation module ([[design/build-plan]]) — sibling to [[systems/EnergyEconomy]], [[systems/EnergyReservoirs]], `WordBuffer`, and `SpellRegistry`.

## Files

- `src/shared/Dictionary/init.luau` — public API (isWord, getStats); requires WordList; logs `Dictionary loaded N words` on require via `Logger.new("Dictionary")`
- `src/shared/Dictionary/WordList.luau` — lowercase `{[word]=true}` hashtable; **~4.1k entries** at first commit (verified via playtest 2026-05-14)
- `src/shared/Dictionary/__tests.luau` — smoke tests; runs assertions on require, logs `[TEST PASS]` line on success

## API

```lua
local Dictionary = require(ReplicatedStorage.Shared.Dictionary)

Dictionary.isWord(s: string) -> boolean
-- Case-insensitive lookup. Lowercases input, checks hashtable.
-- Returns false for non-string input or empty string.

Dictionary.getStats() -> { wordCount: number, byLength: { [number]: number } }
-- Cached on first call. byLength[n] = number of words of length n.
```

## Bootstrap scope

The first-prototype word list was hand-curated covering K-12 vocabulary the gameplay loop assumes. Composition (length histogram from `getStats().byLength` at first commit, total ≈ 4159):

| Length | Count | What it contains |
|---|---|---|
| 2 | 25 | Most common everyday words (`am`, `at`, `be`, `to`, `it`, …) — deliberately not the Scrabble-only short words (no `qi`, `za`, `aa`). |
| 3 | 209 | Animals, body parts, actions, simple objects, weather, descriptors, numbers, food. |
| 4 | 527 | Everyday words with a step up — animals, household, common verbs, fantasy starters (`fire`, `cast`, `fang`, `rune`). |
| 5 | 525 | Nature, fantasy/spell vocab (`flame`, `frost`, `storm`), common verbs and adjectives, common nouns. |
| 6 | 568 | Same as 5, denser fantasy + verbs (`dragon`, `wizard`, `shield`, `summon`). |
| 7 | 487 | T2 payoff range; fantasy + literary + general K-12 (`lightning`, `mystery`). |
| 8 | 678 | T2/T3 payoff; fantasy + general (`fireball`, `enchanter`, `mountain`). |
| 9 | 613 | T3 payoff; fantasy + general (`character`, `archangel`). |
| 10 | 328 | T3-payoff range. |
| 11 | 133 | T3 payoff (incl. pinned `earthquakes`). |
| 12 | 39 | T3 payoff (incl. pinned `characterize`). |
| 13–14 | 27 | Showcase / occasional payoff. |

The bootstrap target in [[design/build-plan]] was 500–1000 entries; the first commit ran ~4× over because organic K-12 categorization across 14 length bins compounded faster than expected. Larger-than-target is functionally fine (Memorize fails closed only on explicitly missing words; bigger list = fewer false negatives), but the curation discipline weakens at this size — some less-common entries likely slipped in. The trade-off is logged here so the SCOWL replacement (below) can reset both the size budget and the content quality bar at once.

Curation rules in effect:

- Lowercase only — `Dictionary.isWord` lowercases input before lookup.
- No obscure / archaic / offensive entries.
- No 2-letter Scrabble-only words.
- Common K-12 fantasy / spell vocabulary is over-represented relative to a general dictionary so the spelling layer feels themed.

## Worked-example coverage

Every word from the [[design/gameplay-loop|gameplay-loop]] worked-examples table is present and recognized:

| Word | Length | Used as design example for |
|---|---|---|
| `cat`, `fire`, `rock`, `flame`, `dragon`, `frozen` | 3–6 | basic energy formula |
| `fireball`, `lightning` | 8, 9 | T2 reach via length multiplier |
| `earthquakes`, `characterize` | 11, 12 | T3 single-cast payoff |

If any of those words drops out of the list, the design's worked examples stop matching runtime — flag it.

## Verification

`__tests.luau` runs assertions on require:

- `Dictionary.isWord("FIRE" | "fire" | "Fire")` → `true` (case-insensitive)
- `Dictionary.isWord("FLAME" | "LIGHTNING" | "DRAGON" | "ROCK")` → `true`
- `Dictionary.isWord("XYZQQ")` → `false`
- `Dictionary.isWord("")` → `false`
- `Dictionary.getStats().wordCount > 500`
- `Dictionary.getStats().byLength` is a table

Run via MCP `execute_luau` during a playtest:

```lua
require(game.ReplicatedStorage.Shared.Dictionary.__tests)
```

A passing run logs `[Dictionary.tests] [TEST PASS] Dictionary smoke tests — N words loaded`.

## Upgrade path: SCOWL

The bootstrap list is intentionally small. The intended replacement is a curated subset of the [SCOWL](http://wordlist.aspell.net/) project — likely SCOWL size 35–50 (covers ~10–30k common English words). Steps:

1. Generate a candidate list from SCOWL with the chosen size threshold.
2. Filter: drop words ≤ 2 letters except a small allowlist; drop archaic/obscure; drop offensive (use a content filter list); optionally drop proper nouns.
3. Lowercase, dedupe, sort.
4. Write the result to `WordList.luau` with the same `{[word]=true}` shape.
5. The Dictionary API does not change — only the data file.

Tiering by level (e.g. easier vocabulary at lower levels) is a future direction noted in [[design/gameplay-loop]] under the Dictionary decision and is **not** baked into the API yet.

## Cross-references

- [[design/gameplay-loop]] — Memorize step (#5), dictionary decision rationale, worked examples
- [[design/build-plan]] — Phase 1 foundation module; tracker NIM-1
- [[systems/EnergyEconomy]] — sibling Phase 1 module that scores the validated word
- [[systems/EnergyReservoirs]] — sibling Phase 1 module that receives the per-color energy
- [[systems/Tests]] — TestRunner pattern (Dictionary uses a lighter "run on require" pattern because the module is pure Luau and needs no Humanoid setup)
