---
type: design
description: Phased build plan for Brain Fighter's core gameplay systems — construction order, parallel vs sequential dependencies, parallel-session strategy
updated: 2026-05-20
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
| **Dictionary** | `isWord(s)`, `getStats()` | Hashtable lookup. 26 per-letter sub-modules from SCOWL 60 (~79.5k words); background-preloaded at game start. |
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

## Phase 4.5 — Bug Fix Sprint

Play-test all current features end-to-end. Fix bugs as found, one session per bug.
Phase complete when the current feature set (Phase 1–4) feels stable during play.

No predetermined list — issues are raised by the user after playtesting.

## Phase 4.6 — LetterBlaster Tool

Replace the bare `BlockShootBoot` click handler with a dedicated weapon Tool.

| Item | Detail |
|---|---|
| **Tool placement** | `StarterPack` via MCP — auto-equips on spawn |
| **Input** | `Tool.Activated` replaces raw `UserInputService.InputBegan` |
| **Reticle** | Reuse `ReticleBuilder.build()` in a full-screen ScreenGui |
| **Rate of fire** | 0.25s cooldown (`os.clock` gate on `Tool.Activated`) |
| **Sounds** | `FireSound` on shot, `HitSound` + hitmarker on confirmed consume |
| **Model** | Handle MeshPart in `StarterPack.LetterBlaster` (placeholder neon cyan) |
| **Server** | `BlockShootService.server.luau` unchanged |

**New files:**
- `src/shared/LetterBlaster/init.luau` — controller (mount/fire/reticle/sound)
- `src/shared/LetterBlaster/LetterBlasterConfig.luau` — tuning constants
- `src/client/LetterBlasterBoot.client.luau` — mounts controller on CharacterAdded

**Deleted:** `src/client/BlockShootBoot.client.luau`

## Phase 4.7 — Letter Slot Reorder

Add drag-to-reorder and tap-to-swap interactions to the BufferDisplay letter tiles. The backend `WordBuffer:reorder(fromIdx, toIdx)` already exists and is unit-tested — this phase is purely UI input wiring.

| Item | Detail |
|---|---|
| **Drag-to-reorder** | `DragDetector` (or `InputBegan`/`InputChanged`/`InputEnded`) on each tile cell; ghost tile follows pointer; drop calls `session.wordBuffer:reorder(fromIdx, toIdx)` |
| **Tap-to-swap** | Tap selects a source tile (highlight); second tap on a different tile swaps the two indices; tapping the same tile or an empty tile cancels selection |
| **Visual feedback** | Selected tile gets a highlight border; drag ghost is a semi-transparent copy of the tile; both modes snap-animate on drop via `TweenService` |
| **Input routing** | Works on both mouse and touch; `UserInputService.TouchEnabled` decides gesture threshold |
| **Scope** | Changes confined to `BufferDisplayBuilder.luau` (adds input handlers to each tile frame) and its boot wiring in `GameplayHudGui.client.luau` |

**Backend:** `src/shared/WordBuffer/init.luau` `:reorder(from, to)` — already implemented, no changes needed.

**Files to modify:**
- `src/shared/Hud/BufferDisplayBuilder.luau` — main input handler work
- `src/client/UI/GameplayHudGui.client.luau` (or equivalent boot script) — wire `session.wordBuffer` into tile event callbacks

## Phase 4.8 — UI Architecture Review

Before Phase 5 polish work, conduct a structured review of the client UI system for modularity, single-ownership, and software design quality. Scope: `src/client/UI/`, `src/client/PlayerHud/`, `src/shared/Hud/`.

| Question | What to check |
|---|---|
| **Single ownership** | Any two scripts writing to the same Frame, LayoutOrder, or property? |
| **Coordinator clarity** | Is `GameplayHudGui` the only BottomCenter coordinator, or do other scripts still self-register? |
| **Builder/Config/Layout compliance** | Every HUD element built via a Builder? Config values all in `*Config.luau`? No magic numbers inline? |
| **Lifecycle completeness** | Every controller/builder that holds connections have a `:destroy()` path? |
| **Dead code** | Any scaffold files or `[unused]` entries still in `shared/Hud/` that should be deleted? |
| **Coupling** | Do Builders depend on LocalScript globals (`_G`, `Players.LocalPlayer`)? Should be pure-module. |

**Deliverable:** A short findings doc or tracker entries for any issues found, with a go/no-go on Phase 5 polish starting before the fixes land.

## Phase 5 — Polish

Tuning passes (energy curve, spawn density, tier thresholds), audio cues, particle effects, tutorial copy, accessibility passes.

## Plan changelog

- **2026-05-20**: added Phase 4.8 (UI architecture review) as a gate before Phase 5 polish.
- **2026-05-20**: HUD coordinator refactor landed — `PlayerHud` is now a ModuleScript; `GameplayHudGui` is the sole BottomCenter coordinator with a single `LAYOUT` table.
- **2026-05-15**: added Phase 4.7 (letter slot drag/tap-to-swap reorder).
- **2026-05-15**: added Phase 4.5 (bug sprint) and Phase 4.6 (LetterBlaster Tool) between Phase 4 and Phase 5.
- **2026-05-14**: initial plan written; 18 trackers created; Phase 1 spawn batch (Dictionary, EnergyEconomy, SpellRegistry) kicked off.
