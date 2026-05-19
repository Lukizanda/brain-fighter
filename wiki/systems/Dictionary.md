---
type: system
description: Word lookup module that validates the buffered word during Memorize. O(1) hashtable, ~79.9k words from SCOWL size 60 + curated geographic supplement; 26 per-letter sub-modules background-preloaded at game start.
updated: 2026-05-19
---

# Dictionary

Pure-Luau, Roblox-instance-free word lookup. The Memorize action calls `Dictionary.isWord(buffer:asWord())` to decide whether the buffered word transmutes into per-color reservoirs or fizzles. See [[design/gameplay-loop]] for the decision context.

Phase 1 foundation module ([[design/build-plan]]) — sibling to [[systems/EnergyEconomy]], [[systems/EnergyReservoirs]], `WordBuffer`, and `SpellRegistry`.

## Files

- `src/shared/Dictionary/init.luau` — public API (isWord, getStats); background-preloads 26 per-letter modules via `task.defer` at game start; logs `Dictionary preload complete — N words` when done
- `src/shared/Dictionary/words/{a..z}.luau` — 26 auto-generated ModuleScripts; each returns a packed newline-delimited string of words starting with that letter (SCOWL size 60)
- `src/shared/Dictionary/__tests.luau` — smoke tests; runs assertions on require, logs `[TEST PASS]` line on success
- `tools/generate_wordlist.py` — offline parser: reads SCOWL source files, filters, writes the 26 `.luau` files

## API

```lua
local Dictionary = require(ReplicatedStorage.Shared.Dictionary)

Dictionary.isWord(s: string) -> boolean
-- Case-insensitive lookup. Lowercases input, checks per-letter hashtable.
-- Returns false for non-string input or empty string.

Dictionary.getStats() -> { wordCount: number, byLength: { [number]: number } }
-- Cached on first call. byLength[n] = number of words of length n.
-- Forces synchronous load of any letters not yet preloaded.
```

## Architecture

### Background preload

At require time, `init.luau` fires a `task.defer` that loads all 26 letter sub-modules one at a time with a `task.wait()` between each to spread the work across frames. Completes in < 1 second. By the time a player can type and submit a word via MemorizeAction (several seconds of UI interaction), all 26 buckets are cached.

`ensureLoaded(letter)` is called synchronously inside `isWord` as a safety fallback. In normal play this is always a no-op (the preload has already finished). If `isWord` is somehow called before preload reaches that letter, it loads synchronously — acceptable for the first call of a given letter, never repeated.

### Per-letter modules

Each `words/{letter}.luau` returns a Luau long-string literal with words newline-delimited:
```lua
return [[
abandon
ability
...
azure
]]
```

Parsed at load time with `packed:gmatch("[^\n]+")` into a `{[string]: boolean}` hashtable. Long-string format avoids escape-sequence overhead — measurably faster to parse than equivalent individual string literals.

### Offline parser

`tools/generate_wordlist.py` is not run at runtime. One-time setup per developer machine:

```bash
# Download SCOWL (one-time)
curl -L "https://sourceforge.net/projects/wordlist/files/SCOWL/2020.12.07/scowl-2020.12.07.tar.gz/download" -o tools/scowl/scowl.tar.gz
tar -xzf tools/scowl/scowl.tar.gz -C tools/scowl --strip-components=1

# Re-generate word files
uv run tools/generate_wordlist.py          # default: size 60 ≈ 79.5k words
uv run tools/generate_wordlist.py --size 50  # smaller list if needed
```

`tools/scowl/` and `tools/wordlists/` are gitignored. Only the generated `src/shared/Dictionary/words/*.luau` files are committed.

**Locale coverage**: English + American + British + British-z spellings (e.g. both `color` and `colour`, both `organize` and `organise`).  
**Filters applied**: contractions, proper nouns, words ≤ 2 letters (except allowlist: `am an as at be by do go he if in is it me my no of on or ok so to up us we`), offensive word blocklist (`tools/wordlists/offensive.txt`), non-alpha characters.

**Supplement**: after SCOWL filtering, words from `tools/wordlists/proper-names.txt` are merged in (minus any offensive matches). This adds ~400 single-word geographic names — countries, capitals, and major cities — that SCOWL's `-words` files omit. Multi-word names (New York, Buenos Aires) are intentionally excluded; they can't be spelled as a single play. Edit the supplement and re-run to add/remove entries.

To resize: change `--size` and commit the regenerated `words/*.luau` files. No Luau code changes needed.

## Word count (SCOWL size 60 + geographic supplement, 2026-05-19)

Total: **79,896 words**

| Letter | Count |
|---|---|
| a | 4,443 |
| b | 4,698 |
| c | 7,754 |
| d | 5,110 |
| e | 3,205 |
| f | 3,406 |
| g | 2,572 |
| h | 2,868 |
| i | 3,252 |
| j | 693 |
| k | 581 |
| l | 2,377 |
| m | 4,198 |
| n | 1,686 |
| o | 2,066 |
| p | 6,390 |
| q | 384 |
| r | 4,967 |
| s | 9,220 |
| t | 4,074 |
| u | 2,240 |
| v | 1,210 |
| w | 2,134 |
| x | 19 |
| y | 235 |
| z | 140 |

## Worked-example coverage

Every word from the [[design/gameplay-loop|gameplay-loop]] worked-examples table is present and recognized:

| Word | Length | Used as design example for |
|---|---|---|
| `cat`, `fire`, `rock`, `flame`, `dragon`, `frozen` | 3–6 | basic energy formula |
| `fireball`, `lightning` | 8, 9 | T2 reach via length multiplier |
| `earthquakes`, `characterize` | 11, 12 | T3 single-cast payoff |

## Verification

`__tests.luau` runs assertions on require:

- `Dictionary.isWord("FIRE" | "fire" | "Fire")` → `true` (case-insensitive)
- `Dictionary.isWord("FLAME" | "LIGHTNING" | "DRAGON" | "ROCK")` → `true`
- `Dictionary.isWord("tout")` → `true` (gap-regression pin, 2026-05-15)
- `Dictionary.isWord("colour")` → `true` (British spelling pin, 2026-05-15)
- `Dictionary.isWord("XYZQQ")` → `false`
- `Dictionary.isWord("")` → `false`
- `Dictionary.getStats().wordCount > 70000`
- `Dictionary.getStats().byLength` is a table

Run via MCP `execute_luau` during a playtest:

```lua
require(game.ReplicatedStorage.Shared.Dictionary.__tests)
```

A passing run logs `[Dictionary.tests] [TEST PASS] Dictionary smoke tests — N words loaded`.

## Gap log

| Date | Gap word | Root cause | Resolution |
|---|---|---|---|
| 2026-05-15 | `tout` | ~90 missing common words in 4.1k bootstrap list | Replaced bootstrap list with SCOWL 60 (79.5k words) |
| 2026-05-19 | `cairo` | SCOWL `-words` files exclude proper nouns; `cairo` lives in `english-upper.50` | Added `tools/wordlists/proper-names.txt` supplement (~400 single-word geographic names); generator merges it after SCOWL filtering |

## Cross-references

- [[design/gameplay-loop]] — Memorize step (#5), dictionary decision rationale, worked examples
- [[design/build-plan]] — Phase 1 foundation module; tracker NIM-1
- [[systems/EnergyEconomy]] — sibling Phase 1 module that scores the validated word
- [[systems/EnergyReservoirs]] — sibling Phase 1 module that receives the per-color energy
- [[systems/Tests]] — TestRunner pattern (Dictionary uses a lighter "run on require" pattern because the module is pure Luau and needs no Humanoid setup)
