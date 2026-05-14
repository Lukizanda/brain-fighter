---
type: system
description: Phase 3 MVP Boss target — spawns a static Humanoid-bearing Model that SpellExecutor can damage. Signals defeat for level-completion logic.
updated: 2026-05-14
---

# BossAdapter

Server-side module that spawns and tracks a Boss target for spell combat. Phase 3 MVP: a static Model with a Humanoid — no AI, no movement. The player defeats it by casting spells (damage flows through [[systems/SpellExecutor]], which just needs a Humanoid target).

## Files

- `src/shared/BossAdapter/init.luau` — module: spawn / despawn / reset / getTarget / defeated signal.
- `src/server/BossAdapter/BossService.server.luau` — server bootstrap: spawns initial Boss, auto-respawns on defeat.

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
