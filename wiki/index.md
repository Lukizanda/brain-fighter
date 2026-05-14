---
type: index
description: Catalog of every Brain Fighter wiki page, grouped by category. Updated on every ingest.
updated: 2026-05-14
---

# Wiki Index

Start here. See [[WIKI]] for conventions and operations.

## Design

- [[design/gameplay-loop]] — canonical core loop: aim → shoot letter blocks → buffer/arrange → cast color-typed spells; tuning, spell roster, worked examples
- [[design/build-plan]] — phased build plan with parallel/sequential dependencies; one tracker per system
- [[design/ArtDirection]] — lowpoly / chunky / oversized sci-fi proportions; greybox-first level building

## Systems

- [[systems/Weapon]] — firearm + melee pipelines, templates, state machines, hit detection
- [[systems/Health]] — damage types, hit zones, modifiers, HealthService, DeathHandler
- [[systems/Character]] — locomotion + camera (single-owner Motor6D control, AlignOrientation lock)
- [[systems/NPC]] — Perception → StateMachine → Actions, Patroller archetype, WorldDataManager
- [[systems/HUD]] — Builder + Config + LayoutManager pattern, attribute bars, WeaponRolodex
- [[systems/Loadout]] — Normal/Special slot model, RespawnPedestalManager, drop remote
- [[systems/GameMode]] — RoundManager, ScoreTracker, mode registry (FFA, TDM)
- [[systems/Tests]] — TestRunner + suites for NPC/Melee, MCP-driven harness
- [[systems/EnergyEconomy]] — Phase 1 pure-Luau module: word → per-color mana (Scrabble values × length tiers, floor-reconciled color splits)
- [[systems/EnergyReservoirs]] — Phase 1 pure-Luau state container: three per-color energy bars, cap 160, `.changed(color)` BindableEvent signal
- [[systems/Dictionary]] — Phase 1 pure-Luau word lookup; case-insensitive `isWord`, ~4.1k bootstrap K-12 entries; SCOWL upgrade path documented
- [[systems/MemorizeAction]] — Phase 2 action: validate buffered word → split per-color energy into reservoirs + clear buffer; fizzle on empty/invalid (buffer preserved)
- [[systems/SpellExecutor]] — Phase 2 effect runner; dispatches `damage`/`heal`/`freeze` (real) and `shield`/`wall`/`buff` (stubs) against caster/target
- [[systems/MindFullManager]] — Phase 2 transition watcher over WordBuffer: rising-edge `mindFull` / falling-edge `mindFreed` signals for the shoot gate + HUD indicator
- [[systems/CastAction]] — Phase 2 cast pipeline: `tapReservoir` (highest affordable) / `castSpecific` (chosen tier); drains reservoir, refunds on executor failure
- [[systems/LetterBlock]] — Phase 3 entity: floating block prefab with `Block.Letter` + `Block.Color` attributes; chunky 4×4×4 cube with 6-face SurfaceGui letter glyph + colored ParticleEmitter; CollectionService tag drives the client bob/rotation animator (6°/s, sinusoidal bob)
- [[systems/BlockSpawner]] — Phase 3 server-side populator: Scrabble-weighted letter picks, configurable color weights, auto-refill via CollectionService removed signal; maintains ~24 blocks in a 40x8x40 arena box
- [[systems/BlockShoot]] — Phase 3 input handler: left-click raycast consumes a LetterBlock, appends `(letter, color)` to WordBuffer; MindFull gate blocks input at 12/12; server validates + destroys block
- [[systems/BossAdapter]] — Phase 3 MVP Boss target: static Humanoid-bearing Model that SpellExecutor can damage; `defeated` signal for level completion; auto-respawn via BossService

## Concepts (recurring patterns)

- [[concepts/SingleOwnership]] — one system owns each Motor6D / property
- [[concepts/BuilderConfigLayout]] — HUD architecture: Builder constructs, Config tunes, LayoutManager places
- [[concepts/ModelJsonInstances]] — `.model.json` creates versioned non-script instances; `.meta.json` only modifies
- [[concepts/ClientServerPredictionParity]] — client prediction must use identical math to server validation; otherwise silent rejects produce desyncs
- [[concepts/LocalScriptPlacement]] — `.client.luau` only auto-runs from `src/client/` (or inside Tool templates); shared/ LocalScripts are dead code
- [[concepts/RojoJsonValidator]] — pre-commit linter that hard-blocks the silent-fail traps in `.meta.json` / `.model.json` files
- [[concepts/MultiplayerTestPattern]] — how to write integration tests for server-authoritative multiplayer paths against a synthetic enemy
- [[concepts/ServerLogicTestHarness]] — gated `.server.luau` drivers for testing server-only logic when MCP only gives client-side execute_luau
- [[concepts/ValidateBeforeShip]] — a fix is not done until you've observed it working; build a deterministic repro before pushing
- [[concepts/RobloxOpenCloudAuth]] — Open Cloud "Invalid API Key" 401 with a previously-working key → regenerate from the dashboard, paste new value into `.env`, move on
- [[concepts/RemoteVisualDebugging]] — 5-layer diagnostic checklist for "works for me, not for other clients" multiplayer visual bugs

## Decisions

- [[decisions/HybridMeleeHitDetection]] — client detects, server sanity-validates (2026-04-17)
