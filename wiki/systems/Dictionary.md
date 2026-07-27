---
type: system
description: Word lookup module that validates the buffered word during Memorize. O(1) hashtable, ~79.9k words from SCOWL size 60 + curated supplements; 26 per-letter sub-modules background-preloaded at game start.
updated: 2026-07-27
---

# Dictionary

Pure-Luau, Roblox-instance-free word lookup. The Memorize action calls `Dictionary.resolve(buffer:asWord(), …)` to decide whether the buffered word transmutes into per-color reservoirs or fizzles. See [[design/gameplay-loop]] for the decision context.

Because the buffer may hold [[systems/Wildcard]] tiles, what it spells is a *pattern* (`D*G`) rather than a word. `resolve` collapses it to a concrete match; `isWord` remains the exact, wildcard-blind lookup. See [[systems/Wildcard#Dictionary resolution]] for the length-index matcher and its measured cost.

Phase 1 foundation module ([[design/build-plan]]) — sibling to [[systems/EnergyEconomy]], [[systems/EnergyReservoirs]], `WordBuffer`, and `SpellRegistry`.

## Files

- `src/shared/Dictionary/init.luau` — public API (isWord, isSpellable, resolve, getStats); background-preloads 26 per-letter modules via `task.defer` at game start; logs `Dictionary preload complete — N words` when done. Load also builds `byLength[letter][len]` arrays for the wildcard matcher.
- `src/shared/Dictionary/words/{a..z}.luau` — 26 auto-generated ModuleScripts; each returns a packed newline-delimited string of words starting with that letter (SCOWL size 60)
- `src/shared/Dictionary/__tests.luau` — smoke tests; runs assertions on require, logs `[TEST PASS]` line on success
- `tools/generate_wordlist.py` — offline parser: reads SCOWL source files, filters, merges supplements, writes the 26 `.luau` files
- `tools/wordlists/proper-names.txt` — curated geographic supplement (~400 single-word country/city names)
- `tools/wordlists/playtest-additions.txt` — words found missing during playtesting (see [[#Adding a missing word]])

## API

```lua
local Dictionary = require(ReplicatedStorage.Shared.Dictionary)

Dictionary.isWord(s: string) -> boolean
-- Case-insensitive EXACT lookup. Lowercases input, checks per-letter hashtable.
-- Does NOT interpret wildcards: isWord("D*G") is false.
-- Returns false for non-string input or empty string.

Dictionary.isSpellable(s: string) -> boolean
-- Wildcard-aware validity. Identical to isWord for wildcard-free input;
-- for "D*G" it is true because DOG exists. Early-exits on first match,
-- so this is the cheap per-keystroke call the HUD glow uses.

Dictionary.resolve(s: string, scoreFn: ((word: string) -> number)?) -> string?
-- Wildcard-aware resolution to a concrete UPPERCASE word, or nil.
-- Without scoreFn the first match wins (early exit).
-- With scoreFn every candidate is scored and the highest wins; ties keep
-- the first in corpus (alphabetical) order, so results are deterministic.

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

`tools/scowl/` and `tools/wordlists/` are gitignored, with hand-curated supplements as explicit `!` exceptions in `.gitignore` (`proper-names.txt`, `playtest-additions.txt`). The generated `src/shared/Dictionary/words/*.luau` files are committed. **When adding a new supplement file, add a matching `!` exception** — otherwise it stays local-only and the next clone silently regenerates without it.

**Locale coverage**: English + American + British + British-z spellings (e.g. both `color` and `colour`, both `organize` and `organise`).  
**Filters applied**: contractions, proper nouns, words ≤ 2 letters (except allowlist: `am an as at be by do go he if in is it me my no of on or ok so to up us we`), offensive word blocklist (`tools/wordlists/offensive.txt`), non-alpha characters.

**Supplements**: after SCOWL filtering, words from every file in `SUPPLEMENT_PATHS` (top of the generator) are merged in, minus any offensive matches. `--supplement` takes multiple paths and overrides the default list. Two supplements ship today:

| File | Contents |
|---|---|
| `proper-names.txt` | ~400 single-word geographic names — countries, capitals, major cities. Multi-word names (New York, Buenos Aires) intentionally excluded; they can't be spelled as a single play. |
| `playtest-additions.txt` | Words found missing during playtesting. |

Supplement words bypass the length floor and the non-alpha filter is applied at load (`^[a-z]+$`), so short entries survive but hyphens/apostrophes/spaces are silently dropped. Only the offensive blocklist still filters them.

To resize: change `--size` and commit the regenerated `words/*.luau` files. No Luau code changes needed.

## Adding a missing word

When a word that should be valid fizzles during play:

```bash
# 1. Confirm it's actually absent (exit 1 = missing)
grep -nx "zen" src/shared/Dictionary/words/z.luau

# 2. Append it to the supplement — one word per line, lowercase, a-z only
echo "zen" >> tools/wordlists/playtest-additions.txt

# 3. Regenerate
uv run tools/generate_wordlist.py --size 60

# 4. Verify the diff is only the words you added
git diff --unified=1 src/shared/Dictionary/words/
```

Regeneration is deterministic — same SCOWL + same supplements + same `--size` reproduces the committed files byte-for-byte, so step 4 should show exactly one added line per new word and nothing else. A noisy diff means `--size` or the SCOWL version drifted.

Commit the supplement edit **and** the regenerated `words/*.luau` together. Editing `words/*.luau` by hand instead works until the next regen, then silently reverts — the supplement is the durable path.

Prereq: `tools/scowl/` must be populated (see [[#Offline parser]]). Without it the generator exits with a "SCOWL final/ directory not found" error rather than writing a partial list.

## Word count (SCOWL size 60 + supplements, 2026-07-27)

Total: **79,897 words** — rows below are the generator's own per-letter report and sum to exactly this total.

> Corrected 2026-07-27: the previous table's rows were each +1 (they summed to 79,922 against a stated total of 79,896), from counting `.luau` file lines rather than words. Take counts from the generator's stderr report, not `wc -l`.

| Letter | Count |
|---|---|
| a | 4,442 |
| b | 4,697 |
| c | 7,753 |
| d | 5,109 |
| e | 3,204 |
| f | 3,405 |
| g | 2,571 |
| h | 2,867 |
| i | 3,251 |
| j | 692 |
| k | 580 |
| l | 2,376 |
| m | 4,197 |
| n | 1,685 |
| o | 2,065 |
| p | 6,389 |
| q | 383 |
| r | 4,966 |
| s | 9,219 |
| t | 4,073 |
| u | 2,239 |
| v | 1,209 |
| w | 2,133 |
| x | 18 |
| y | 234 |
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
- `Dictionary.isWord("D*G")` → `false` (isWord never interprets wildcards)
- `Dictionary.isSpellable("d*g" | "D*G" | "*og" | "***")` → `true`
- `Dictionary.isSpellable("xq*zj")` → `false`
- `Dictionary.isSpellable("*")` → `false` (no single-letter words in SCOWL-60)
- `Dictionary.isSpellable("d.g" | "d1g")` → `false` (illegal chars rejected before the pattern is built, so `.` can't match everything)
- `Dictionary.resolve("d*g", preferO)` → `"DOG"`; `resolve("d*g", preferU)` → `"DUG"` (proves scoreFn steers the result rather than corpus order)
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
| 2026-07-27 | `zen` | Same proper-noun exclusion as `cairo`, non-geographic slice — SCOWL files it capitalized, so `zenith` is present but bare `zen` is not | Added `tools/wordlists/playtest-additions.txt`; `--supplement` now takes multiple paths and both lists merge by default |

## Cross-references

- [[design/gameplay-loop]] — Memorize step (#5), dictionary decision rationale, worked examples
- [[design/build-plan]] — Phase 1 foundation module; tracker NIM-1
- [[systems/EnergyEconomy]] — sibling Phase 1 module that scores the validated word
- [[systems/EnergyReservoirs]] — sibling Phase 1 module that receives the per-color energy
- [[systems/Tests]] — TestRunner pattern (Dictionary uses a lighter "run on require" pattern because the module is pure Luau and needs no Humanoid setup)
