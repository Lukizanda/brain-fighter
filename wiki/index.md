---
type: index
description: Catalog of every Brain Fighter wiki page, grouped by category. Updated on every ingest.
updated: 2026-05-13
---

# Wiki Index

Start here. See [[WIKI]] for conventions and operations.

## Design

- [[design/gameplay-loop]] — canonical core loop: aim → shoot letter blocks → buffer/arrange → cast color-typed spells; tuning, spell roster, worked examples
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

## Decisions

- [[decisions/HybridMeleeHitDetection]] — client detects, server sanity-validates (2026-04-17)
