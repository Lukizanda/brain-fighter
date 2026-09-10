---
type: system
description: NPC AI — three-layer Perception → Decision → Action architecture, Patroller archetype shipped (MVP). One NPC set per arena session since refactor chunk 9; Perception scans only the NPC's own arena roster via the shared Hittables definition.
updated: 2026-09-10
---

# NPC System

Three-layer architecture: perception writes facts, decision selects state, action executes. Each NPC has its own Blackboard + StateMachine instance, ticked by `NPCService` on Heartbeat.

## Architecture

```
Perception (server/NPC/Scripts/Perception.luau)
  ↓ writes to Blackboard (nearestPlayer, distanceToNearest, canSeeTarget) — candidates are the roster of the arena named by the NPC's ArenaId attribute
Decision (server/NPC/Scripts/StateMachine.luau)
  ↓ states under Scripts/States/<Archetype>States.luau
Action (server/NPC/Scripts/Actions.luau)
  ↓ MoveTo / MoveToWithPath / StopMoving / MeleeAttack — return Success/Failure/Running
```

`NPCController` owns one Blackboard + one Decision instance per NPC. `NPCService` keeps one NPC set per arena session — spawned on that arena's `RoundStarted`, torn down on its `RoundEnded` — and ticks them all.

## Arena ownership (refactor chunk 9, 2026-09-10)

NPCs used to be spawned once at boot from every `NPCSpawn` marker in the place and hunted whoever was closest on the server. Now:

- **`NPCService` listens to the GameMode `RoundStarted(roster, arenaId)` / `RoundEnded(winnerId, winnerName, arenaId)` BindableEvents** (the `arenaId` argument was added by chunk 9) and keeps `sets[arenaId]`. On start it spawns every `WorldDataManager.getSpawns()` snapshot whose `attributes.ArenaId` resolves to that arena (absent = `Default`, mirroring `Arena.idOf`), stamps each Model with `ArenaId` and `Archetype`, and ticks the set after a 2 s settle. On end it destroys the set. A boot reconcile over `SessionRegistry.all()` covers the Default round, which starts before this Script's `WorldDataManager.waitForInit()` returns.
- **`NPCService.disable()` / `enable()` / `destroy()`** — pause the tick, resume it, tear everything down (bound to `game:BindToClose`).
- **Perception reads `Arena.idOf(bb.npc)`** and scans `Hittables.collect(BroadcastAudience.forArena(id), id)`, keeping only entries with a `player`. One target definition (`src/shared/Skills/Hittables.luau`) is shared with `SkillDelivery` and `CosmeticProjectile`; `grep Players:GetPlayers() src/shared/Skills src/server/NPC` is empty. A hub player is never an NPC target because nothing hostile carries `Lobby`.
- **Kill-feed cause.** `Actions.Shoot` / `Actions.MeleeAttack` now pass `cause = <Archetype attribute>` on their `DamageRequest`, so an NPC kill reads "Patroller" instead of "Unknown" (the chunk 4 note).
- **Tests.** `Helpers/ensurePatroller.ensure(player)` moves the boot-spawned `Patroller_1` into the harness player's arena (attribute only) for the duration of an NPC suite and restores it in `teardown`; the three NPC suites pass `ctx.player`.

## Files

- `src/shared/NPC/NPCConstants.luau`, `NPCTypes.luau`
- `src/shared/NPC/Archetypes/Patroller.luau` — archetype definition (animations, weapons, state graph)
- `src/server/NPC/NPCService.server.luau` — entry point, one NPC set per arena session, ticks
- `src/server/NPC/Scripts/Perception.luau` — arena-scoped distance scan over `Hittables`
- `src/shared/Skills/Hittables.luau` — the shared "what can be hit, in which arena" definition (chunk 9)
- `src/server/NPC/Scripts/StateMachine.luau` — generic FSM
- `src/server/NPC/Scripts/NPCController.luau` — per-NPC orchestrator
- `src/server/NPC/Scripts/Actions.luau` — movement primitives + `Actions.MeleeAttack` hook
- `src/server/NPC/Scripts/States/PatrollerStates.luau` — Patrol + Idle states
- `src/server/AI/Scripts/WorldDataService.server.luau` — initializes WorldDataManager
- `src/server/AI/Scripts/WorldDataManager.luau` — scans tagged markers, snapshots positions, destroys runtime markers (preserves them in edit mode)

## Studio state (committed via .rbxlx)

- `ServerStorage.AIWorldData.Rigs.Patroller` — R15 dummy
- `ServerStorage.AIWorldData.Markers.SpawnMarker`, `PatrolMarker` — templates
- `Workspace.Test Area.NPCSpawns.NPCSpawn_1` — tagged `NPCSpawn`, `ArenaId = Default` (set 2026-09-09 via MCP; `.rbxl` needs saving)
- `Workspace.PatrolPoints.PatrolPoint_1..4` — tagged `PatrolPoint`

## Tests

`src/shared/Tests/Suites/NPC/` — `combat_engages`, `combat_disengages`, `npc_deals_damage`. Run via [[systems/Tests]].

## Status

MVP shipped; chase, vision cones, and multiple archetypes are the next steps.

## Cross-references

- Melee for NPC swing archetype → [[systems/Weapon]] (Actions.MeleeAttack hook)
- WorldDataManager pattern (snapshot then destroy markers) → [[concepts/ModelJsonInstances]]
