---
type: system
description: Full boss system — custom non-humanoid rig (BossBrain) on an invisible R15 skeleton, AI state machine, phase scaffolding, two attack types, and client HUD.
updated: 2026-05-18
---

# Boss

Server-authoritative boss lifecycle: spawn → AI tick → death → respawn. Each boss type specifies its own rig template via `rigName`; the Brain boss uses `BossBrain` — an invisible R15 Patroller skeleton (for Humanoid physics) with a red sphere body and glowing yellow eyes welded on top. State machine: Idle → Patrol → AttackPrep → Attack → Cooldown. Client health HUD at TopCenter.

Supersedes [[systems/BossAdapter]] (Phase 3 static Model). The `src/server/BossAdapter/BossService.server.luau` file has been renamed to `.disabled` and is no longer active.

## Files

### Shared (ReplicatedStorage)

| File | Purpose |
|---|---|
| `src/shared/Boss/BossConfig.luau` | `BOSS_TYPES` registry + `DEFAULT_TYPE`; per-type vitals, phases, and per-skill params |
| `src/shared/Boss/BossTypes.luau` | `BossBlackboard` + `BossTypeSpec` types; `rigName` and `hipHeight` optional fields |
| `src/shared/Boss/BossEvents/BossHealthChanged.model.json` | RemoteEvent — fires `(currentHP, maxHP, phaseIndex)` on HP change (throttled 0.1s) |
| `src/shared/Boss/BossEvents/BossPhaseChanged.model.json` | RemoteEvent — fires `phaseIndex` (0 = defeated/no boss) |
| `src/shared/Boss/BossEvents/BossPartDestroyed.model.json` | RemoteEvent — scaffold for future destructible-part system |

### Server (ServerScriptService)

| File | Purpose |
|---|---|
| `src/server/Boss/BossService.server.luau` | Top-level lifecycle: spawn, Heartbeat tick loop, death, respawn |
| `src/server/Boss/Scripts/BossSpawner.luau` | Builds the Boss Model; resolves rig by `typeSpec.rigName` (default: Patroller); applies scale, `hipHeight` override, phase coloring |
| `src/server/Boss/Scripts/BossController.luau` | Per-boss orchestrator: StateMachine + Perception + BossPhaseManager |
| `src/server/Boss/Scripts/BossStates.luau` | Five state definitions passed to `StateMachine.new()`; Attack dispatches via `SkillDelivery.deliver` |
| `src/server/Boss/Scripts/BossPhaseManager.luau` | Monitors HP thresholds; fires `onPhaseChanged` callback on transition |
| `src/shared/Skills/SkillDelivery.luau` | Delivery handlers (`instant`, `projectile`, `aoe`, `world_spawn`) — boss and player spells share this |
| `src/shared/Skills/SkillEffects.luau` | Effect handlers (`damage`, `heal`, `freeze`, stubs) — all damage application lives here |
| `src/shared/Skills/SkillTypes.luau` | Pure Luau types: `SkillSpec`, `EffectSpec`, `DeliveryCtx` |

### Client (StarterPlayerScripts)

| File | Purpose |
|---|---|
| `src/client/UI/BossHudGui.client.luau` | Health bar + phase label; registered with HudLayoutManager "TopCenter" |

## Boss Model

Built by `BossSpawner` from `ServerStorage.AIWorldData.Rigs.<rigName>`. The Brain boss uses `BossBrain`:

```
Model "Boss"  [tag: "Boss"]
├── HumanoidRootPart (PrimaryPart, Transparency=1)
├── Humanoid (MaxHealth=1500, WalkSpeed from PhaseSpec, HipHeight≈2)
├── [invisible R15 limbs from Patroller clone — drive Humanoid physics]
├── BrainBody    (9×9×9 Ball, colored to phase bodyColor, WeldConstraint to HRP)
├── BrainStem    (2×3×2 Ball, colored to phase bodyColor, WeldConstraint to HRP)
├── LeftEye      (2×2×2 Ball, Neon yellow, KeepColor=true, WeldConstraint to HRP)
├── RightEye     (2×2×2 Ball, Neon yellow, KeepColor=true, WeldConstraint to HRP)
└── BillboardGui (on HRP, StudsOffset 0,9,0 — "BOSS" label)
```

**KeepColor attribute**: parts with `KeepColor=true` are skipped by BossSpawner's coloring loop and keep their template color. Used for the eyes.

**Custom rigs**: `BossSpawner` skips the ShieldPart/LeftArmCore welded accessories when `typeSpec.rigName` is set — custom rigs define their own visual parts in the template. The BossBrain model lives in `ServerStorage.AIWorldData.Rigs` (Studio-only, not on disk).

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
Idle ──(player ≤ 160 studs)─────────────→ Patrol
Patrol ──(player ≤ 100 studs)───────────→ AttackPrep
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
| `attackComplete` | boolean | Set via `ctx.onComplete` callback fired by SkillDelivery |
| `cooldownStart` | number | os.clock() stamp for cooldown check |
| `destroyedParts` | { [string]: boolean } | Scaffold for future part destruction |

## Attack Types

Implementations live in [[systems/SkillPipeline|SkillDelivery]] (`handlers.projectile`, `handlers.aoe`); boss-specific tuning lives in `BossConfig.BOSS_TYPES[type].skills`. All damage flows through `applyDamage.process` with `sourcePlayer = nil` (set via `EffectSpec.useApplyDamage = true`).

### FireballVolley (`delivery = "projectile"`)

3 Part projectiles in spread. Each is `CanCollide = false` with a `LinearVelocity` constraint — Touched doesn't fire so hit detection is a per-Heartbeat proximity check (`≤ 3 studs`). 0.15 s stagger between projectiles; `attackComplete` set via `ctx.onComplete` after all are in flight. Brain's tuning: `count=3`, `speed=40`, damage `15 HP` (`onImpact = [{kind="damage", amount=15, useApplyDamage=true}]`).

### GroundSlam (`delivery = "aoe"`)

0.8 s windup delay, then AOE within 12 studs. Spawns a flat Cylinder shockwave visual (Neon yellow, Debris 0.5 s). All humanoids in radius take damage and receive a knockup. `attackComplete` set via `ctx.onComplete` after total cycle. Brain's tuning: `radius=12`, `onImpact = [{kind="damage", amount=25, useApplyDamage=true}, {kind="knockup", force=...}]` — multi-effect composition.

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

## Key Tuning (BossConfig.BOSS_TYPES.Brain)

All boss constants are now per-type in `BossConfig.BOSS_TYPES[<name>]`. Brain's defaults:

| Field | Value | Path |
|---|---|---|
| maxHealth | 1500 | `BOSS_TYPES.Brain.maxHealth` |
| bodyScale | 1 | `BOSS_TYPES.Brain.bodyScale` (BossBrain parts are pre-sized; no R15 scaling needed) |
| rigName | "BossBrain" | `BOSS_TYPES.Brain.rigName` |
| hipHeight | 6 (config intent) | `BOSS_TYPES.Brain.hipHeight` (currently overridden by Roblox rig physics to ~2) |
| respawnDelaySec | 5 | `BOSS_TYPES.Brain.respawnDelaySec` |
| detectionRange | 160 studs | `BOSS_TYPES.Brain.detectionRange` |
| attackRange | 100 studs | `BOSS_TYPES.Brain.attackRange` |
| attackWindupSec | 0.5 s | `BOSS_TYPES.Brain.attackWindupSec` |
| FireballVolley count / speed / damage | 3 / 30 / 15 HP | `BOSS_TYPES.Brain.skills.FireballVolley.deliveryParams` + `.onImpact[1].amount` |
| GroundSlam radius / damage / knockup | 22 / 25 HP / 60 | `BOSS_TYPES.Brain.skills.GroundSlam.deliveryParams` + `.onImpact[*]` |

Add a new boss type by adding another entry to `BOSS_TYPES`; switch the active boss by setting `workspace.BossPoint:SetAttribute("BossType", "<name>")`. Falls back to `BossConfig.DEFAULT_TYPE` when unset.

## Future Work

- **BossBrain visual iteration** — sphere + eyes is a first pass; the model lives in Studio (ServerStorage.AIWorldData.Rigs.BossBrain) and can be reshaped without any code changes.
- **hipHeight hover** — `hipHeight=6` in BossConfig is the intent but Roblox's Humanoid continuously recalculates HipHeight from R15 leg geometry (settles at ~2). To achieve a higher hover: resize the hidden Patroller legs in the BossBrain template, or replace the skeleton with a minimal custom joint structure.
- **Destructible parts** — `destroyedParts` blackboard field is the scaffold; no health pools yet.
- **Multi-phase behavior** — add entries to `BossConfig.BOSS_TYPES[<name>].phases`; BossPhaseManager and BossController handle the rest without code changes.
- **Additional attacks** — `LetterThrow`, `SummonMinions` planned; add a new entry to `BOSS_TYPES[<name>].skills` (referencing an existing `delivery` handler in [[systems/SkillPipeline|SkillDelivery]] or adding a new one) and list it in the relevant `PhaseSpec.availableAttacks`.
- **Round integration** — wire `BossPhaseChanged(0)` into [[systems/GameMode]] RoundManager for level-completion detection.

## See also

- [[systems/NPC]] — shared StateMachine, Perception, Actions modules reused verbatim
- [[systems/HUD]] — HudLayoutManager region system; BossHudGui uses TopCenter
- [[systems/SpellExecutor]] — effect runner; damages Boss Humanoid directly
- [[systems/Health]] — applyDamage pipeline; boss receives firearm hits the same as any NPC
- [[systems/BossAdapter]] — superseded Phase 3 MVP (static Model, no AI)
