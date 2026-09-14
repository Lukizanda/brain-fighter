---
type: system
description: NPC AI — three-layer Perception → Decision → Action architecture, Patroller archetype shipped (MVP). One NPC set per arena session since refactor chunk 9; Perception scans only the NPC's own arena roster via the shared Hittables definition. The three generic layers live in server/AI since chunk 11 and are shared with the boss.
updated: 2026-09-14
---

# NPC System

Three-layer architecture: perception writes facts, decision selects state, action executes. Each NPC has its own Blackboard + StateMachine instance, ticked by `NPCService` on Heartbeat.

## Architecture

```
Perception (server/AI/Scripts/Perception.luau)
  ↓ writes to Blackboard (nearestPlayer, distanceToNearest, canSeeTarget) — candidates are the roster of the arena named by the NPC's ArenaId attribute
Decision (server/AI/Scripts/StateMachine.luau)
  ↓ states under server/NPC/Scripts/States/<Archetype>States.luau
Action (server/AI/Scripts/Actions.luau)
  ↓ MoveTo / MoveToWithPath / StopMoving / FaceTarget / ReleaseFacing / Shoot
  ↓ — return Success/Failure/Running
```

**The three layers are generic and live in `server/AI` (refactor chunk 11, 2026-09-14).** The boss ticks the same Perception, the same StateMachine and the same Actions; only the state tables differ (`NPC/Scripts/States/PatrollerStates` vs `Boss/Scripts/BossStates`). `States/` deliberately stayed under `NPC/` — a Patroller's Patrol/Idle/Combat graph is archetype-specific, not part of the shared layer.

`NPCController` owns one Blackboard + one Decision instance per NPC. `NPCService` keeps one NPC set per arena session — spawned on that arena's `RoundStarted`, torn down on its `RoundEnded` — and ticks them all.

## Arena ownership (refactor chunk 9, 2026-09-10)

NPCs used to be spawned once at boot from every `NPCSpawn` marker in the place and hunted whoever was closest on the server. Now:

- **`NPCService` listens to the GameMode `RoundStarted(roster, arenaId)` / `RoundEnded(winnerId, winnerName, arenaId)` BindableEvents** (the `arenaId` argument was added by chunk 9) and keeps `sets[arenaId]`. On start it spawns every `WorldDataManager.getSpawns()` snapshot whose `attributes.ArenaId` resolves to that arena (absent = `Default`, mirroring `Arena.idOf`), stamps each Model with `ArenaId` and `Archetype`, and ticks the set after a 2 s settle. On end it destroys the set. A boot reconcile over `SessionRegistry.all()` covers the Default round, which starts before this Script's `WorldDataManager.waitForInit()` returns.
- **`NPCService.disable()` / `enable()` / `destroy()`** — pause the tick, resume it, tear everything down (bound to `game:BindToClose`).
- **Perception reads `Arena.idOf(bb.npc)`** and scans `Hittables.collect(BroadcastAudience.forArena(id), id)`, keeping only entries with a `player`. One target definition (`src/shared/Skills/Hittables.luau`) is shared with `SkillDelivery` and `CosmeticProjectile`; `grep Players:GetPlayers() src/shared/Skills src/server/NPC` is empty. A hub player is never an NPC target because nothing hostile carries `Lobby`.
- **Kill-feed cause.** `Actions.Shoot` passes `cause = <Archetype attribute>` on its `DamageRequest`, so an NPC kill reads "Patroller" instead of "Unknown" (the chunk 4 note).
- **Tests.** `Helpers/ensurePatroller.ensure(player)` clones its own `Patroller_Fixture` next to the harness player, stamped with the player's `ArenaId` and `Archetype`; `teardown` destroys it.

## Turning, pathing and speed (refactor chunk 11, 2026-09-14)

- **One owner for orientation.** Both the boss and the Patroller used to turn by
  writing `HumanoidRootPart.CFrame` every tick, which the physics solver undoes
  on the next step (the rig shudders instead of turning). `Actions.FaceTarget`
  now owns an `AlignOrientation` on the rig's HRP and switches `AutoRotate` off
  while it holds it; `Actions.ReleaseFacing` gives the Humanoid its steering
  back, which is what a *walking* rig needs. Turn rate is
  `NPCConstants.FACE_TURN_RATE_DEGREES` (180°/s), enforced by the constraint's
  `MaxAngularVelocity` rather than by a hand-rolled lerp.
- **Actions never yield their caller.** `PathfindingService:ComputeAsync` yields,
  so calling it from a state's `update` parked the whole decision tick and the
  next Heartbeat started a second one on a fresh thread — two ticks racing over
  one blackboard, and a stale Patrol update issuing `MoveTo` after the machine
  had entered Combat. `MoveToWithPath` now computes on its own thread and
  reports `Running` until the result lands. This was the NPC suite's flakiness
  (`53a43d5`).
- **A patrol route is local.** Points further than
  `NPCConstants.PATROL_ROUTE_MAX_RANGE` (200 studs) from where a rig stands are
  not its route; a rig with no local points holds its ground instead of
  path-failing toward another arena every frame.
- **`BaseWalkSpeed`.** `NPCService` (and `BossSpawner`) publish the authored
  walk speed on the rig Model under
  `SkillConstants.BASE_WALK_SPEED_ATTRIBUTE`; a freeze restores *that*, read at
  restore time. See [[systems/Boss]] for the phase-change case it fixes.

## Files

- `src/shared/NPC/NPCConstants.luau`, `NPCTypes.luau`
- `src/shared/NPC/Archetypes/Patroller.luau` — archetype definition (animations, weapons, state graph)
- `src/server/NPC/NPCService.server.luau` — entry point, one NPC set per arena session, ticks
- `src/server/AI/Scripts/Perception.luau` — arena-scoped distance scan over `Hittables` (shared with the boss)
- `src/shared/Skills/Hittables.luau` — the shared "what can be hit, in which arena" definition (chunk 9)
- `src/server/AI/Scripts/StateMachine.luau` — generic FSM (shared with the boss)
- `src/server/AI/Scripts/Actions.luau` — movement, facing and shooting primitives (shared with the boss)
- `src/server/NPC/Scripts/NPCController.luau` — per-NPC orchestrator
- `src/server/NPC/Scripts/States/PatrollerStates.luau` — Patrol + Idle + Combat states
- `src/server/AI/Scripts/WorldDataService.server.luau` — initializes WorldDataManager
- `src/server/AI/Scripts/WorldDataManager.luau` — scans tagged markers, snapshots positions, destroys runtime markers (preserves them in edit mode)

## Studio state (committed via .rbxlx)

- `ServerStorage.AIWorldData.Rigs.Patroller` — R15 dummy
- `ServerStorage.AIWorldData.Markers.SpawnMarker`, `PatrolMarker` — templates
- `Workspace.Test Area.NPCSpawns.NPCSpawn_1` — tagged `NPCSpawn`, `ArenaId = Default` (set 2026-09-09 via MCP; `.rbxl` needs saving)
- `Workspace.Test Area.PatrolPoints.PatrolPoint_1..4` — tagged `PatrolPoint`, all within ~21 studs of `NPCSpawn_1`. A rig spawned elsewhere (the Lobby fixture) takes none of them — see the patrol-route locality rule above.

## Tests

`src/shared/Tests/Suites/NPC/` — `combat_engages`, `combat_disengages`, `npc_deals_damage`. Run via [[systems/Tests]].

## Status

MVP shipped; chase, vision cones, and multiple archetypes are the next steps.

## Cross-references

- The deleted NPC melee path → [[systems/Weapon]] (`Actions.MeleeAttack` and `Weapon/Melee/*` removed in chunk 11; nothing ever wired them to an archetype)
- Boss states over the same three layers → [[systems/Boss]]
- WorldDataManager pattern (snapshot then destroy markers) → [[concepts/ModelJsonInstances]]
