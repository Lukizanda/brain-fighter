---
type: system
description: NPC AI — three-layer Perception → Decision → Action architecture, Patroller archetype shipped (MVP)
updated: 2026-04-30
---

# NPC System

Three-layer architecture: perception writes facts, decision selects state, action executes. Each NPC has its own Blackboard + StateMachine instance, ticked by `NPCService` on Heartbeat.

## Architecture

```
Perception (server/NPC/Scripts/Perception.luau)
  ↓ writes to Blackboard (nearestPlayer, distanceToNearest, canSeeTarget)
Decision (server/NPC/Scripts/StateMachine.luau)
  ↓ states under Scripts/States/<Archetype>States.luau
Action (server/NPC/Scripts/Actions.luau)
  ↓ MoveTo / MoveToWithPath / StopMoving / MeleeAttack — return Success/Failure/Running
```

`NPCController` owns one Blackboard + one Decision instance per NPC. `NPCService` boots the world, spawns NPCs, and ticks them.

## Files

- `src/shared/NPC/NPCConstants.luau`, `NPCTypes.luau`
- `src/shared/NPC/Archetypes/Patroller.luau` — archetype definition (animations, weapons, state graph)
- `src/server/NPC/NPCService.server.luau` — entry point, spawns + ticks
- `src/server/NPC/Scripts/Perception.luau` — distance scan
- `src/server/NPC/Scripts/StateMachine.luau` — generic FSM
- `src/server/NPC/Scripts/NPCController.luau` — per-NPC orchestrator
- `src/server/NPC/Scripts/Actions.luau` — movement primitives + `Actions.MeleeAttack` hook
- `src/server/NPC/Scripts/States/PatrollerStates.luau` — Patrol + Idle states
- `src/server/AI/Scripts/WorldDataService.server.luau` — initializes WorldDataManager
- `src/server/AI/Scripts/WorldDataManager.luau` — scans tagged markers, snapshots positions, destroys runtime markers (preserves them in edit mode)

## Studio state (committed via .rbxlx)

- `ServerStorage.AIWorldData.Rigs.Patroller` — R15 dummy
- `ServerStorage.AIWorldData.Markers.SpawnMarker`, `PatrolMarker` — templates
- `Workspace.NPCSpawns.NPCSpawn_1` — tagged `NPCSpawn`
- `Workspace.PatrolPoints.PatrolPoint_1..4` — tagged `PatrolPoint`

## Tests

`src/shared/Tests/Suites/NPC/` — `combat_engages`, `combat_disengages`, `npc_deals_damage`. Run via [[systems/Tests]].

## Status

MVP shipped; chase, vision cones, and multiple archetypes are the next steps.

## Cross-references

- Melee for NPC swing archetype → [[systems/Weapon]] (Actions.MeleeAttack hook)
- WorldDataManager pattern (snapshot then destroy markers) → [[concepts/ModelJsonInstances]]
