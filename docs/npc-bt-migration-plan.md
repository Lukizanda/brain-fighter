# NPC AI: State Machine → Behavior Tree Migration Plan

## Overview

The trick to a clean migration is designing the initial state machine so the upgrade only touches **one layer**. This document defines a three-layer architecture where Perception and Action are stable, and Decision (state machine first, BT later) is the only thing that gets swapped.

---

## Three-layer architecture (build this from day one)

```
┌─────────────────────────────────────────┐
│  PERCEPTION (stays the same forever)    │
│  - Vision (raycast + FOV + range)       │
│  - Hearing (gunshot/footstep events)    │
│  - Memory (last seen position, etc.)    │
│  → writes to Blackboard                 │
└─────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  DECISION (this is what gets swapped)   │
│  Phase 1: State Machine                 │
│  Phase 2: Behavior Tree                 │
│  → reads Blackboard, picks current goal │
└─────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  ACTION (stays the same forever)        │
│  - MoveTo(position)                     │
│  - Shoot(target)                        │
│  - PlayAnimation(name)                  │
│  Each action reports completion         │
└─────────────────────────────────────────┘
```

The **Blackboard** is the contract between layers. As long as both phases of Decision read/write the same blackboard fields, swapping them is mechanical.

---

## Phase 1: State Machine MVP

### File structure

```
src/server/NPC/
  NPCService.server.luau           -- spawns NPCs, runs tick loop
  Scripts/
    NPCController.luau             -- orchestrates perception/decision/action per NPC
    Perception.luau                -- vision/hearing → blackboard
    StateMachine.luau              -- decision layer (swappable)
    Actions.luau                   -- MoveTo, Shoot, PlayAnimation
src/shared/NPC/
  NPCConstants.luau                -- ranges, speeds, FOV angles
  NPCTypes.luau                    -- Blackboard type, NPCArchetype type
  Archetypes/
    Grunt.luau                     -- speed, weapon, behavior config
```

### Critical constraints to keep migration easy

1. **States are pure functions** of `(blackboard) → action`. No side effects in transitions, only in actions.
2. **Transition table is a config**, not hardcoded if/else. Example:
   ```lua
   {
     Idle  = { onSeeTarget = "Chase" },
     Chase = { onLoseTarget = "Search", onInRange = "Attack" },
   }
   ```
3. **Actions are idempotent and report status** (`Running`, `Success`, `Failure`). This matches BT leaf node semantics exactly — no rewrite later.
4. **Blackboard schema is locked early.** Document fields like:
   - `currentTarget`
   - `lastSeenPosition`
   - `timeSinceLastSeen`
   - `weaponEquipped`
   - `health`
   - `currentPath` (waypoints from PathfindingService)

   The BT will read the same fields.

---

## Phase 2: Behavior Tree migration (when triggered)

### What changes

- Replace `StateMachine.luau` with `BehaviorTree.luau` (the runner) + `Trees/` folder (per-archetype tree definitions)

### What stays

- `Perception.luau` — unchanged
- `Actions.luau` — unchanged (BT leaf nodes wrap these directly)
- `NPCController.luau` — unchanged (still calls `decision:tick(blackboard)`)
- `Blackboard` schema — unchanged
- Archetypes — config file format changes, but the data fields are mostly the same

### Migration steps

1. **Build the BT runner** (`BehaviorTree.luau`)
   - Composite nodes: `Sequence`, `Selector`, `Parallel`
   - Decorator nodes: `Inverter`, `Cooldown`, `Repeater`
   - Leaf base: `Action(fn)`, `Condition(fn)`
   - Each `tick(blackboard)` returns `Success | Failure | Running`

2. **Wrap existing actions as leaves** — zero refactor needed:
   ```lua
   Action(function(bb) return Actions.MoveTo(bb.npc, bb.targetPos) end)
   ```

3. **Translate one state machine into a tree** — pick the simplest archetype first to validate the runner:
   ```
   Selector
     ├─ Sequence (Combat)
     │   ├─ Condition: HasTarget
     │   ├─ Condition: TargetInRange
     │   └─ Action: Shoot
     ├─ Sequence (Chase)
     │   ├─ Condition: HasTarget
     │   └─ Action: MoveToTarget
     └─ Action: Patrol
   ```

4. **Swap the controller's decision layer** — one line change:
   ```lua
   -- before: self.decision = StateMachine.new(archetype.transitions)
   -- after:  self.decision = BehaviorTree.new(archetype.tree)
   ```

5. **Migrate other archetypes one at a time** — they can coexist. NPCController doesn't care if its decision is a state machine or a BT, as long as it has `:tick(blackboard)`.

6. **Add BT-only features**: parallel branches (e.g., shoot while moving), shared sub-trees, decorators (cooldowns, retries).

---

## When to trigger the migration

Upgrade from state machine → BT when you hit any of these signals:

| Signal | What it means |
|--------|---------------|
| 1-3 enemy types, similar behavior | State machine is fine — don't migrate |
| 5+ enemy types sharing sub-behaviors | BT starts paying off |
| Copy-pasting state transitions across types | BT |
| Designers want to author behaviors in data | BT or visual editor |
| Want emergent squad behavior | BT or HTN/GOAP |

---

## What you give up by waiting

Almost nothing. The state machine forces you to **define the blackboard schema and action interface first**, which is exactly the work you'd do anyway for a BT. You're not building throwaway code — you're building the perception and action layers that the BT will reuse.

The only "wasted" work is the state machine file itself (~200-400 lines), and even that serves as documentation of what behaviors exist when you author the BT.

---

## Red flags during Phase 1

If any of these creep in, fix them immediately or you'll regret it later:

- ❌ State transitions doing perception work (querying for targets inline) → move to Perception layer
- ❌ Actions that mutate the blackboard directly → only the controller should mutate it after the action returns
- ❌ Hardcoded state names in archetype configs → use enums/constants
- ❌ Per-state custom data structures → push into the blackboard
- ❌ Perception writing directly to action layer → must go through blackboard
