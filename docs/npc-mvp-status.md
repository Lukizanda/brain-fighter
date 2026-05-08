# NPC MVP — Status & Continuation Notes

Snapshot of the NPC system state as of commit `efbaab9`. Use this to resume work from another machine.

## Where we are

The patrolling NPC MVP is **complete**. All 5 phases from [npc-build-plan.md](npc-build-plan.md) shipped and tested.

| Phase | Commit | Summary |
|-------|--------|---------|
| 0 | `4d00a63` | Scaffolding: types, constants, module stubs |
| 1 | `c9e54ec` | NPC spawning from `NPCSpawn`-tagged parts |
| 2 | `009316c` | Action layer: MoveTo, MoveToWithPath, StopMoving |
| 3 | `235c02f` | StateMachine + NPCController + Patrol state |
| 4 | `8ef25fa` | Perception layer: player distance scan |
| 5 | `efbaab9` | Idle state + Patrol↔Idle transitions (hysteresis 15/25 studs) |

## Architecture (current)

Three-layer design — see [npc-bt-migration-plan.md](npc-bt-migration-plan.md) for the rationale.

```
Perception (server/NPC/Scripts/Perception.luau)
  ↓ writes to Blackboard (nearestPlayer, distanceToNearest, canSeeTarget)
Decision (server/NPC/Scripts/StateMachine.luau)
  ↓ runs current state's update fn, evaluates transition rules
  ↓ states live in Scripts/States/<Archetype>States.luau
Action (server/NPC/Scripts/Actions.luau)
  ↓ MoveTo / MoveToWithPath / StopMoving — idempotent, returns Success/Failure/Running
```

NPCController owns one blackboard + decision instance per NPC, ticked by NPCService on Heartbeat.

## File map

```
src/shared/NPC/
  NPCConstants.luau              walk speed, ranges, tag names, state name enum
  NPCTypes.luau                  Blackboard, StateDefinition, TransitionRule, Archetype
  Archetypes/
    Patroller.luau               name + templateName + walkSpeed + initialState

src/server/AI/
  Scripts/
    WorldDataManager.luau        scans tagged AI markers, snapshots positions
    WorldDataService.server.luau entry point — initializes WorldDataManager

src/server/NPC/
  NPCService.server.luau         spawns NPCs (waits on WorldDataManager)
  Scripts/
    Actions.luau                 movement primitives
    Perception.luau              player distance scan
    StateMachine.luau            generic FSM runner
    NPCController.luau           per-NPC orchestrator
    States/
      PatrollerStates.luau       Patrol + Idle states + transitions

docs/
  npc-bt-migration-plan.md       SM → BT migration architecture
  npc-build-plan.md              Phase-by-phase build plan
  npc-mvp-status.md              this file
```

## AI World Data architecture

As of the AIWorldData refactor, spawn/patrol data flows through a central
manager instead of scattered `CollectionService:GetTagged()` calls:

```
ServerStorage.AIWorldData/
  Markers/                       templates for edit-time placement
    SpawnMarker                  green, 4x1x4, label "Spawn"
    PatrolMarker                 yellow, 2x0.2x2, label "Patrol"
  Rigs/                          NPC body templates
    Patroller                    R15 dummy
```

**Runtime flow:**
1. `WorldDataService.server.luau` runs on server startup
2. Calls `WorldDataManager.initialize()` — scans tagged markers in
   Workspace, snapshots positions/attributes, destroys the marker parts
3. `NPCService` yields on `WorldDataManager.waitForInit()`, then reads
   spawn positions via `WorldDataManager.getSpawns()`
4. `PatrollerStates` reads patrol points via `WorldDataManager.getPatrolPoints()`

Edit-time markers persist in Studio (saved in `.rbxlx`) but are destroyed
at runtime — players never see them.

## Studio state (persists via .rbxlx)

Lives in `BrainFighter.rbxlx` (committed to repo):
- `ServerStorage.AIWorldData.Rigs.Patroller` — R15 dummy (no Animate script)
- `ServerStorage.AIWorldData.Markers.SpawnMarker` — template part with billboard label
- `ServerStorage.AIWorldData.Markers.PatrolMarker` — template part with billboard label
- `Workspace.NPCSpawns.NPCSpawn_1` — tagged `NPCSpawn`, position `(40, 5, 30)`
- `Workspace.PatrolPoints.PatrolPoint_1..4` — tagged `PatrolPoint`, ring around (40, 5, 30) at radius 15

Cross-machine sync relies on committing `BrainFighter.rbxlx`. Studio's autosave
handles local persistence; just save before pushing.

## What's working

- ✅ NPC spawns at the marker on init
- ✅ Cycles 4 patrol points cleanly (60+ second test, zero errors)
- ✅ PathfindingService routes around obstacles
- ✅ Perception updates blackboard with nearest player every tick
- ✅ Patrol → Idle transition fires at <15 studs
- ✅ Idle → Patrol transition fires at >25 studs
- ✅ Hysteresis gap (15/25) prevents flicker (verified holding at 8.6 studs for 25+ seconds)
- ✅ Per-NPC memory cleanup on destroy

## What's deliberately NOT done

From [npc-build-plan.md "Out of scope for the MVP"](npc-build-plan.md#out-of-scope-for-the-mvp):
- ❌ Combat / shooting
- ❌ Vision cones / FOV (just flat distance check)
- ❌ Aggro / chase
- ❌ Death / respawn
- ❌ Multiple NPC types
- ❌ Behavior tree (still on state machine)

## Continuation ideas (next session)

Pick any of these — they all build on the existing MVP without requiring rework:

1. **Promote spawn/patrol parts to disk** — write `.model.json` files so the Studio state is version-controlled. Same pattern as `Remotes.model.json`. ~30 min.
2. **Chase state** — add `Chase` between Patrol and Idle. NPC moves toward the player when seen, falls back to Patrol when lost. New state, new transitions, no architecture changes.
3. **Combat / shooting** — give NPC a weapon Tool, hook into existing `Firearm` system. Add `Attack` state. Likely needs an `Actions.Shoot(bb, target)` primitive.
4. **Vision cones** — upgrade Perception to use raycasts + FOV check instead of flat distance. Set `bb.canSeeTarget` properly. Use `RaycastParams` to filter out terrain.
5. **Multiple archetypes** — clone the Patroller pattern for a `Sniper` (slower walk, longer detection range) or `Rusher` (faster walk, shorter range). Wire through `NPCController.stateBuilders`.
6. **NPC death + respawn** — hook into `playerEliminatedEvent` from the Health system, despawn the controller cleanly, respawn after a delay.

## Known issues / quirks

- `[PatrollerStates] patrol path failed, advancing to next waypoint` warning fires once during init while the NPC is still falling to the floor. Harmless — the next patrol point recovers cleanly.
- The Idle state currently doesn't make the NPC face the player. Easy add when wanted (set `humanoid.AutoRotate = false` and use AlignOrientation, or just `CFrame.lookAt` HRP each frame in the state's update).
- Perception's throttled log only fires when a player is **in range**, so empty patrols are silent (intentional — keeps logs readable).

## How to verify on the new machine

1. `git pull` — make sure you're at `efbaab9` or later
2. Open `BrainFighter.rbxlx` in Studio
3. Sync via Rojo (no red deletes expected — all NPC code is on disk)
4. Start a playtest, walk to the NPC, walk away
5. Output should show: spawn → patrol cycles → `Patrol -> Idle` on approach → `Idle -> Patrol` on retreat
