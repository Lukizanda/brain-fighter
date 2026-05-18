---
type: system
description: Full boss system — 3× scaled R15 rig with AI state machine, phase scaffolding, two attack types (FireballVolley, GroundSlam), and client HUD.
updated: 2026-05-18
---

# Boss

Server-authoritative boss lifecycle: spawn → AI tick → death → respawn. The boss is a 3× scaled R15 character rig with a state machine (Idle → Patrol → AttackPrep → Attack → Cooldown), phase scaffolding, and a client health HUD.

Supersedes [[systems/BossAdapter]] (Phase 3 static Model). The `src/server/BossAdapter/BossService.server.luau` file has been renamed to `.disabled` and is no longer active.

## Files

### Shared (ReplicatedStorage)

| File | Purpose |
|---|---|
| `src/shared/Boss/BossConfig.luau` | All numeric constants + data-driven `PhaseSpec` array |
| `src/shared/Boss/BossTypes.luau` | `BossBlackboard` type (superset of `NPCTypes.Blackboard`) |
| `src/shared/Boss/BossEvents/BossHealthChanged.model.json` | RemoteEvent — fires `(currentHP, maxHP, phaseIndex)` on HP change (throttled 0.1s) |
| `src/shared/Boss/BossEvents/BossPhaseChanged.model.json` | RemoteEvent — fires `phaseIndex` (0 = defeated/no boss) |
| `src/shared/Boss/BossEvents/BossPartDestroyed.model.json` | RemoteEvent — scaffold for future destructible-part system |

### Server (ServerScriptService)

| File | Purpose |
|---|---|
| `src/server/Boss/BossService.server.luau` | Top-level lifecycle: spawn, Heartbeat tick loop, death, respawn |
| `src/server/Boss/Scripts/BossSpawner.luau` | Builds the Boss Model from the Patroller rig at 3× scale |
| `src/server/Boss/Scripts/BossController.luau` | Per-boss orchestrator: StateMachine + Perception + BossPhaseManager |
| `src/server/Boss/Scripts/BossStates.luau` | Five state definitions passed to `StateMachine.new()`; Attack dispatches via `DeliveryRegistry.deliver` |
| `src/server/Boss/Scripts/BossPhaseManager.luau` | Monitors HP thresholds; fires `onPhaseChanged` callback on transition |
| `src/shared/Skills/DeliveryRegistry.luau` | Delivery handlers (`instant`, `projectile`, `aoe`, `world_spawn`) — boss and player spells share this |
| `src/shared/Skills/EffectRegistry.luau` | Effect handlers (`damage`, `heal`, `freeze`, stubs) — all damage application lives here |
| `src/shared/Skills/SkillTypes.luau` | Pure Luau types: `SkillSpec`, `EffectSpec`, `DeliveryCtx` |

### Client (StarterPlayerScripts)

| File | Purpose |
|---|---|
| `src/client/UI/BossHudGui.client.luau` | Health bar + phase label; registered with HudLayoutManager "TopCenter" |

## Boss Model

Built by `BossSpawner` from `ServerStorage.AIWorldData.Rigs.Patroller`:

```
Model "Boss"  [tag: "Boss"]
├── HumanoidRootPart (PrimaryPart)
├── Humanoid (MaxHealth=1500, WalkSpeed from PhaseSpec)
├── Head, UpperTorso, LowerTorso, standard R15 limbs
├── ShieldPart   (8×10×0.5 Block, Neon blue, WeldConstraint to HRP)
│   └── Attribute: BossPartName = "Shield"
├── LeftArmCore  (2.5×2.5×2.5 Ball, Neon orange, WeldConstraint to HRP)
│   └── Attribute: BossPartName = "LeftArm"
└── BillboardGui (on Head, StudsOffset 0,5,0 — "BOSS" label)
```

Scale: `BodyHeightScale = BodyWidthScale = BodyDepthScale = 3` (≈ 16 studs tall).

Spawn point: `workspace.BossPoint` (BasePart). The boss is placed at Y = bossPoint.Y + bossPoint.Size.Y/2 + 12 so it stands on top of the part rather than inside it.

## Phase System

Phases are a data-driven array per boss type in `BossConfig.BOSS_TYPES[type].phases`. Each entry is:

```lua
type PhaseSpec = {
    index: number,
    hpFraction: number,        -- phase active when HP ≤ fraction of MaxHealth; 1.0 = spawn
    attackCooldown: number,
    walkSpeed: number,
    bodyColor: BrickColor,
    availableAttacks: { string },
}
```

`BossPhaseManager` scans `PHASES[2..N]` each tick and transitions the moment `currentFraction <= PHASES[i].hpFraction`. With one entry, the loop never executes — always phase 1. Add more entries to the `phases` array in `BossConfig.BOSS_TYPES[type]` to activate multi-phase behavior without changing any other file.

**Current config (single phase):**

| Index | hpFraction | Attacks | Cooldown | WalkSpeed |
|---|---|---|---|---|
| 1 | 1.0 (spawn) | FireballVolley, GroundSlam | 4 s | 6 |

## State Machine

States defined in `BossStates.luau`, instantiated via `StateMachine.new()` (shared NPC module):

```
Idle ──(player ≤ 80 studs)──────────────→ Patrol
Patrol ──(player ≤ 30 studs)────────────→ AttackPrep
Patrol ──(no player in range)────────────→ Idle
AttackPrep ──(0.5 s windup elapsed)──────→ Attack
Attack ──(attackComplete = true)─────────→ Cooldown
Cooldown ──(timer + player in range)─────→ AttackPrep
Cooldown ──(timer + player out of range)─→ Patrol
Cooldown ──(timer + no player)───────────→ Idle
```

**Key BossBlackboard fields** (beyond NPCTypes.Blackboard):

| Field | Type | Purpose |
|---|---|---|
| `currentPhaseIndex` | number | Active PHASES index |
| `currentPhaseSpec` | PhaseSpec | Resolved spec for active phase |
| `selectedAttack` | string? | Chosen in AttackPrep.onEnter |
| `attackWindupStart` | number? | os.clock() stamp for windup check |
| `attackComplete` | boolean | Set via `ctx.onComplete` callback fired by DeliveryRegistry |
| `cooldownStart` | number | os.clock() stamp for cooldown check |
| `destroyedParts` | { [string]: boolean } | Scaffold for future part destruction |

## Attack Types

All server-authoritative (`applyDamage.process` with `sourcePlayer = nil`):

### FireballVolley

3 Part projectiles in spread. Each is `CanCollide = false` with a `LinearVelocity` constraint — Touched doesn't fire so hit detection is a per-Heartbeat proximity check (`≤ 3 studs`). 0.15 s stagger between projectiles; `attackComplete` set after all are in flight. Damage: **15 HP**.

### GroundSlam

0.8 s windup delay, then AOE within 12 studs. Spawns a flat Cylinder shockwave visual (Neon yellow, Debris 0.5 s). All players in radius take damage and receive an upward `ApplyImpulse`. `attackComplete` set after 1.2 s total. Damage: **25 HP**.

## Client HUD

`BossHudGui` registered to HudLayoutManager **TopCenter** region. Hidden until a boss spawns.

- **Health bar** — red fill, TweenService 0.25 s Quad animation on `BossHealthChanged`
- **Phase label** — Roman numeral ("Phase I", "Phase II" …) on `BossPhaseChanged`
- **Late-join** — on load reads `workspace.Boss` humanoid directly; defaults to phase 1 if no `BossPhaseChanged` has fired

## Integration Points

No changes needed in other systems:

- **SpellExecutor** — damages any Humanoid; Boss is `workspace.Boss` so SpellMenuGui auto-targets it
- **applyDamage.process()** — `sourcePlayer = nil` bypasses the PvP gate; firearm hits damage the boss normally
- **DeathHandler** — only handles `DAMAGEABLE_TAG` models; Boss is tagged `"Boss"`, not `DAMAGEABLE_TAG`, so BossService owns the full death/respawn cycle

## Lifecycle

1. `BossService` finds `workspace.BossPoint` at startup.
2. `BossSpawner.spawn(bossPoint)` clones the Patroller rig, scales it 3×, places it.
3. `BossController.new(boss, onPhaseChanged)` wires Perception + StateMachine + BossPhaseManager.
4. `RunService.Heartbeat` drives `controller:tick(dt)` each frame.
5. `humanoid.HealthChanged` fires `BossHealthChanged` (throttled 0.1 s).
6. `humanoid.Died` → disconnect Heartbeat, destroy controller, fire defeat events (phaseIndex=0), destroy Model after 1 s, respawn after `BossConfig.RESPAWN_DELAY_SEC` (5 s).

## Key Constants (BossConfig)

| Constant | Value |
|---|---|
| MAX_HEALTH | 1500 |
| BODY_SCALE | 3 |
| RESPAWN_DELAY_SEC | 5 |
| DETECTION_RANGE | 80 studs |
| ATTACK_RANGE | 30 studs |
| ATTACK_WINDUP_SEC | 0.5 s |
| FIREBALL_DAMAGE | 15 HP |
| FIREBALL_SPEED | 30 studs/s |
| FIREBALL_SPREAD_COUNT | 3 |
| FIREBALL_PROXIMITY_RADIUS | 3 studs |
| GROUNDSLAM_DAMAGE | 25 HP |
| GROUNDSLAM_RADIUS | 12 studs |
| GROUNDSLAM_KNOCKUP | (config value × mass) |

## Future Work

- **Destructible parts** (separate planning session) — ShieldPart and LeftArmCore are present on the model but have no health pools or interaction yet; `destroyedParts` blackboard field is the scaffold.
- **Multi-phase behavior** — add entries to `BossConfig.PHASES`; BossPhaseManager and BossController handle the rest without code changes.
- **Additional attacks** — `LetterThrow` (Phase 2+), `SummonMinions` (Phase 3+) planned; add to `BossAttacks.luau` and list in the relevant `PhaseSpec.availableAttacks`.
- **Round integration** — wire `BossPhaseChanged(0)` into [[systems/GameMode]] RoundManager for level-completion detection.

## See also

- [[systems/NPC]] — shared StateMachine, Perception, Actions modules reused verbatim
- [[systems/HUD]] — HudLayoutManager region system; BossHudGui uses TopCenter
- [[systems/SpellExecutor]] — effect runner; damages Boss Humanoid directly
- [[systems/Health]] — applyDamage pipeline; boss receives firearm hits the same as any NPC
- [[systems/BossAdapter]] — superseded Phase 3 MVP (static Model, no AI)
