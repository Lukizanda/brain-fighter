---
type: design
description: Phased build plan for Brain Fighter's core gameplay systems — construction order, parallel vs sequential dependencies, parallel-session strategy
updated: 2026-05-14
---

# Build Plan

Phased construction of Brain Fighter's gameplay systems. Each phase ends with a playtestable verification milestone. Companion to [[design/gameplay-loop]] (the WHAT) — this doc is the WHEN and HOW.

Work items are tracked as Nimbalyst `task` trackers, tagged with their phase. Each system below maps to one tracker.

## Strategy

- **Pure-Luau modules with no inter-deps run in parallel sessions** (Phase 1 and parts of Phase 4).
- **Anything that wires multiple modules together runs sequentially** so the integrating session has its dependencies pinned (most of Phase 2 + Phase 3).
- **Assets that need design judgment (LetterBlock look, spell VFX, boss model) are coordinated synchronously with the user** rather than fanned out to subagents — to avoid taste drift.

The plan is a living doc — update it as systems land or discover new dependencies. Each landing system gets a wiki/systems/`<Name>`.md page and a `log.md` ingest entry. Cross-link from this plan to those pages.

## Phase 1 — Foundations (parallel)

Pure Luau modules. Zero Roblox-instance dependencies. All five built in parallel sessions.

| Module | API surface | Notes |
|---|---|---|
| **Dictionary** | `isWord(s)`, `getStats()` | Hashtable lookup. Bootstrap with ~500–1000 K-12 words; later swap to curated 10–30k SCOWL list. |
| **EnergyEconomy** | `letterValue(c)`, `lengthMultiplier(len)`, `computeWordEnergy(word)`, `splitByColor(tiles)` | Scrabble values × length tiers. Sanity-checked against the worked examples in `gameplay-loop.md`. |
| **SpellRegistry** | `getSpell(color, tier)`, `listAffordableSpells(color, energy)` | Config for 9 spells (R/G/B × T1/T2/T3) — cost, targetingMode, effectSpec. |
| **WordBuffer** | `new(cap)`, `:append(letter,color)`, `:remove(idx)`, `:reorder(from,to)`, `:clear()`, `:asWord()`, `:colorBag()`, `:isFull()`, `.changed` | 12-slot state + changed signal. |
| **EnergyReservoirs** | `new()`, `:add(color,n)`, `:get(color)`, `:canAfford(color,n)`, `:drain(color,n)`, `.changed(color)` | 3-color state with per-color signal. Cap 160 per color. |

**Milestone:** each module passes its own smoke-test asserts (e.g. `Dictionary.isWord("FIRE")` → true, `EnergyEconomy.computeWordEnergy("FLAME")` → 15). Each ships with a `wiki/systems/<Name>.md` page.

## Phase 2 — Action systems

Each depends on one or more Phase 1 modules. Some parallel-safe; sequencing noted.

| Module | Depends on | Parallel-safe? |
|---|---|---|
| **MemorizeAction** | Dictionary + EnergyEconomy + WordBuffer + EnergyReservoirs | Yes (with SpellExecutor, MindFullManager) |
| **SpellExecutor** | SpellRegistry | Yes (with MemorizeAction, MindFullManager) |
| **MindFullManager** | WordBuffer | Yes (with MemorizeAction, SpellExecutor) |
| **BlockSpawner** | Dictionary + LetterBlock template | Sequential — needs Phase 3 LetterBlock first |
| **CastAction** | EnergyReservoirs + SpellRegistry + SpellExecutor | Sequential — needs SpellExecutor first |

**Parallel strategy:** spawn MemorizeAction + SpellExecutor + MindFullManager once Phase 1 lands. BlockSpawner and CastAction wait for Phase 3 / Phase 2 prerequisites.

## Phase 3 — World instances + level integration

Mix of code + Roblox assets. Asset-heavy items need user coordination.

| Module | Notes |
|---|---|
| **LetterBlock** template | Roblox model — Part + letter glyph + color tint. Needs design coordination on look. |
| **BlockShoot** | Input handler — click on a LetterBlock → consume → append to WordBuffer. |
| **BossAdapter** | Reuses existing NPC system (Patroller archetype). Takes damage from SpellExecutor. |

## Phase 4 — HUD (parallel)

Five HUD pieces. Each builds against an already-shipped state module and runs in its own session.

| Piece | Depends on |
|---|---|
| **HUD: BufferDisplay** | WordBuffer |
| **HUD: ReservoirBars** | EnergyReservoirs |
| **HUD: MemorizeButton** | WordBuffer + MemorizeAction |
| **HUD: SpellMenu** | EnergyReservoirs + SpellRegistry + CastAction |
| **HUD: MindFullIndicator** | MindFullManager |

**Parallel strategy:** spawn five sessions once their backing modules are stable. Each session lands a builder under `src/shared/Hud/`.

## Phase 5 — Polish

Tuning passes (energy curve, spawn density, tier thresholds), audio cues, particle effects, tutorial copy, accessibility passes.

## Plan changelog

- **2026-05-14**: initial plan written; 18 trackers created; Phase 1 spawn batch (Dictionary, EnergyEconomy, SpellRegistry) kicked off.
