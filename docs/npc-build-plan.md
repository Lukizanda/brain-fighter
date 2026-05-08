# NPC System Build Plan: Patrolling NPC MVP

Goal: ship a single patrolling NPC that walks between waypoints. Each phase ends with something **testable** and **stable** before moving on.

See [npc-bt-migration-plan.md](npc-bt-migration-plan.md) for the architectural rationale.

---

## Phase 0 — Scaffolding (no behavior yet)

**What:** Create the file structure, type definitions, constants, and empty module stubs from the migration plan.

**Files:**
```
src/shared/NPC/
  NPCConstants.luau        -- speeds, ranges, tag names
  NPCTypes.luau            -- Blackboard, Archetype types
  Archetypes/
    Patroller.luau         -- minimal config for the test NPC
src/server/NPC/
  Scripts/
    Actions.luau           -- stubs only
    Perception.luau        -- stubs only
    StateMachine.luau      -- stubs only
    NPCController.luau     -- stubs only
  NPCService.server.luau   -- empty init log
```

**Studio setup:**
- Create an R15 NPC rig in `ServerStorage/NPCTemplates/Patroller` (Humanoid + Animator + body parts)
- Create a folder `Workspace/NPCSpawns` with one part tagged `NPCSpawn`
- Create a folder `Workspace/PatrolPoints` with 3-4 parts tagged `PatrolPoint`

**Stability test:**
- Start playtest
- Verify `[NPCService] Initialized` appears in logs
- No errors, no instances spawned yet

---

## Phase 1 — NPC spawning (just exist)

**What:** NPCService finds tagged spawn points, clones the template, parents to Workspace. NPC just stands there.

**Code:**
- `NPCService.server.luau`: on init, get all `NPCSpawn`-tagged parts, clone template, position at spawn, store reference

**Stability test:**
- Start playtest
- NPC visible in viewport at spawn point
- Stands still, doesn't fall through floor, doesn't T-pose float
- Log: `[NPCService] Spawned 1 NPC: Patroller_1`

---

## Phase 2 — Action layer (movement primitives)

**What:** Build the action functions that the decision layer will call. No decisions yet — test actions directly via `execute_luau`.

**Functions in `Actions.luau`:**
```lua
Actions.MoveTo(npc, position) -> "Running" | "Success" | "Failure"
Actions.MoveToWithPath(npc, position) -> "Running" | "Success" | "Failure"
Actions.StopMoving(npc) -> "Success"
```

- `MoveTo` uses `Humanoid:MoveTo()` + `MoveToFinished` for short distances
- `MoveToWithPath` wraps `PathfindingService:CreatePath()` for navigating around obstacles
- Each function is **idempotent** — calling it again with the same target is a no-op if already moving there

**Stability test:**
- Start playtest
- Run via `execute_luau`: `Actions.MoveToWithPath(npc, somePart.Position)`
- NPC walks to the position, navigating around obstacles
- Returns `Success` when arrived

---

## Phase 3 — State machine + Patrol state

**What:** Build the `StateMachine` module and one hardcoded `Patrol` state. Wire it to `NPCController` which ticks each NPC every frame.

**`StateMachine.luau` interface:**
```lua
StateMachine.new(transitions, initialState) -> sm
sm:tick(blackboard) -- runs current state's update fn, may transition
sm:getState() -> string
```

**`NPCController.luau`:**
- Holds blackboard for one NPC
- Calls `sm:tick(blackboard)` each Heartbeat
- Calls action functions based on the state's intent

**Patrol state logic:**
- On enter: pick the nearest patrol point, set `bb.targetPos`
- On update: call `Actions.MoveToWithPath(npc, bb.targetPos)`. If returns `Success`, pick next patrol point.
- Patrol points cycled in order (or randomly — config in Patroller archetype)

**Stability test:**
- Start playtest
- NPC walks from patrol point 1 → 2 → 3 → 4 → 1 → ... in a loop
- Doesn't get stuck on geometry
- Log shows `[NPCController] Patroller_1: arrived at PatrolPoint_2, next: PatrolPoint_3`
- **Run for 60 seconds** to confirm no leaks/errors over multiple cycles

---

## Phase 4 — Perception layer (observe only)

**What:** Build `Perception.luau` with a simple "any player in range" check. Writes to blackboard but **doesn't drive any state changes yet**. Just observation.

**Functions:**
```lua
Perception.update(npc, blackboard)
  -- Sets bb.nearestPlayer, bb.distanceToNearest, bb.canSeeTarget
```

- Check distance to all players (cheap, no raycast yet)
- Optional: raycast for line-of-sight (Phase 5+ if needed)

**`NPCController` calls** `Perception.update(npc, bb)` **before** `sm:tick(bb)` each frame.

**Stability test:**
- Start playtest, walk near the patrolling NPC
- Logs (throttled) show blackboard updates: `nearestPlayer=ZandaLuki distance=12.4`
- NPC keeps patrolling — perception is observing only, not reacting

This phase validates the **contract** between Perception and Decision layers without changing visible behavior.

---

## Phase 5 — Multi-state transitions (Idle + Patrol)

**What:** Add a second state (`Idle`) and let perception drive transitions. This validates that the state machine actually works as a state machine, not just a hardcoded loop.

**Behavior:**
- Default: `Patrol` (cycles waypoints)
- If `bb.distanceToNearest < 15`: transition `Patrol → Idle`
- In `Idle`: `Actions.StopMoving(npc)`, log "watching player"
- If `bb.distanceToNearest > 25`: transition `Idle → Patrol`

**Stability test:**
- Start playtest
- NPC patrols normally
- Walk close → NPC stops and faces you
- Walk away → NPC resumes patrol from where it stopped
- Repeat 5+ times — no stuck states, no jitter at the threshold (the 15/25 hysteresis prevents flickering)

---

## Out of scope for the MVP

These are deliberately skipped — the architecture supports them, but we want stability first:
- ❌ Combat / shooting → reuses Actions later
- ❌ Vision cones / FOV → just distance check for now
- ❌ Aggro / chase → next phase, after MVP is stable
- ❌ Death / respawn → after combat
- ❌ Multiple NPC types → architecture supports it, but only `Patroller` archetype for now
- ❌ Behavior tree → only when we hit the "5+ types" trigger from the migration plan

---

## Stability checkpoints summary

| Phase | Smoke test | Pass criteria |
|-------|-----------|---------------|
| 0 | Init log appears | No errors |
| 1 | NPC visible | Stands on floor, no fall-through |
| 2 | `execute_luau` MoveTo | NPC walks to target, returns Success |
| 3 | 60s patrol loop | Cycles waypoints without errors |
| 4 | Walk near NPC | Blackboard logs update, behavior unchanged |
| 5 | Walk close + away repeatedly | Clean Patrol↔Idle transitions |

Each phase is small enough to debug in isolation, and breakage in a later phase has a clear suspect (the layer you just added).

---

## Estimated scope per phase

| Phase | Lines of code | Complexity |
|-------|--------------|------------|
| 0 | ~100 (mostly types/stubs) | Trivial |
| 1 | ~50 | Trivial |
| 2 | ~150 | Moderate (PathfindingService API) |
| 3 | ~200 | Moderate |
| 4 | ~80 | Trivial |
| 5 | ~50 (mostly transition table) | Trivial |

**Total: ~630 LOC** to a working patrolling + reactive NPC. From here, adding combat/chase/respawn is incremental.
