---
type: system
description: Phase 3 MVP Boss target (REMOVED 2026-06-22, commit 6610291) — was a static Humanoid-bearing Model that SpellExecutor could damage. Superseded by the full Boss system, then deleted along with its tests. Retained as historical record.
updated: 2026-07-15
---

# BossAdapter

> **REMOVED 2026-06-22 (commit `6610291`); previously SUPERSEDED by [[systems/Boss]] (2026-05-18).** BossAdapter was the Phase 3 MVP boss — a static Humanoid Model with no AI — replaced by the full [[systems/Boss]] system (custom BossBrain rig, AI state machine, attacks, HUD health bar). As of `6610291` the shared module `src/shared/BossAdapter/init.luau`, the disabled server bootstrap `src/server/BossAdapter/BossService.server.luau.disabled`, and the Phase 3 `bossadapter_*` test suites are all deleted, and `phase3_invariants` dropped its BossAdapter check. The live boss is found in workspace as the model named/tagged `"Boss"`. This page is retained for historical context only — nothing it describes exists in `src/` anymore.

Server-side module that spawned and tracked a Boss target for spell combat. Phase 3 MVP: a static Model with a Humanoid — no AI, no movement. The player defeated it by casting spells (damage flows through [[systems/SpellExecutor]], which just needs a Humanoid target).

## Files

- `src/shared/BossAdapter/init.luau` — module: spawn / despawn / reset / getTarget / defeated signal.
- `src/server/BossAdapter/BossService.server.luau.disabled` — server bootstrap (spawned initial Boss, auto-respawned on defeat). **Disabled** — the full Boss system owns boss spawning now.

## Anatomy

The Boss is a single Model with:

```
Boss (Model)
├── HumanoidRootPart (Part)  — 6×8×6, Anchored, Neon purple (#7c3aed)
└── Humanoid                 — MaxHealth 500
```

`model.PrimaryPart = HumanoidRootPart` so `BossAdapter.getModel():GetPivot()` returns the body position. The Humanoid drives the SpellExecutor integration — `resolveHumanoid(bossModel)` finds it via `FindFirstChildOfClass`.

## API

`require(ReplicatedStorage.Shared.BossAdapter)` returns the module table.

| Member | Type | Notes |
|---|---|---|
| `.spawn(opts?)` | `(Opts?) -> Model` | Creates the Boss at `opts.position` with `opts.maxHealth`. Despawns existing boss first. |
| `.despawn()` | `() -> ()` | Destroys the current Boss immediately. |
| `.reset(opts?)` | `(Opts?) -> Model` | Despawn + spawn in one call. |
| `.getTarget()` | `() -> Humanoid?` | Returns the Boss's Humanoid for SpellExecutor targeting. nil if no boss alive. |
| `.getModel()` | `() -> Model?` | Returns the Boss Model. |
| `.isAlive()` | `() -> boolean` | true if Boss exists and Health > 0. |
| `.defeated` | `RBXScriptSignal` | Fires when the Boss's Humanoid dies. |
| `.DEFAULT_MAX_HEALTH` | `number` | 500. |
| `.DEFAULT_SPAWN_POSITION` | `Vector3` | (0, 5, -30). |

### Opts type

```luau
type Opts = {
    maxHealth: number?,    -- default 500
    position: Vector3?,    -- default (0, 5, -30)
    bodySize: Vector3?,    -- default (6, 8, 6)
    parent: Instance?,     -- default workspace
}
```

## BossService behavior

The server bootstrap:
1. Spawns the Boss on game start.
2. Listens for `.defeated` — respawns after a 5-second delay.

This loop runs indefinitely for Phase 3. Level-completion, round integration, and difficulty scaling are Phase 5 work.

## SpellExecutor integration

No special wiring needed. SpellExecutor.cast takes `(spec, caster, target)` where target can be a Model or Humanoid. Pass `BossAdapter.getTarget()` or `BossAdapter.getModel()` — `resolveHumanoid` handles both.

```luau
local target = BossAdapter.getTarget()
if target then
    SpellExecutor.cast(spec, casterHumanoid, target)
end
```

Damage, heal, and freeze all work against the Boss's Humanoid. When Health reaches 0, the Humanoid fires `Died`, BossAdapter fires `defeated`, and BossService auto-respawns.

## Future work (Phase 5+)

- Replace the placeholder Part with a proper Boss mesh/rig.
- Wire into the NPC state machine (Perception/StateMachine/Actions) for AI behavior.
- Add health phases (Phase 2 at 50% HP with different attack patterns).
- Integrate with [[systems/GameMode]] RoundManager for level-completion detection.
- Add visual effects (health bar above Boss, damage numbers, defeat explosion).

## See also

- [[systems/SpellExecutor]] — the effect runner that damages the Boss.
- [[systems/CastAction]] — the cast pipeline that triggers SpellExecutor.
- [[systems/NPC]] — the full NPC stack this will eventually integrate with.
- [[design/gameplay-loop]] — "defeat monster per level" core loop.
