---
type: system
description: Thin origin-resolver that delegates spell casting to SkillDelivery (delivery) and SkillEffects (effects). All damage/heal/freeze/shield/buff logic lives in src/shared/Skills/. Damage against server-owned targets (boss, NPCs) must run server-side — SpellCastService relays client casts via RemoteEvent, including target-less self-buffs and placements.
updated: 2026-11-14
---

# SpellExecutor

The runtime side of the spell roster. Given a [[systems/SpellRegistry|Spec]] plus a caster and a target, resolves the origin `CFrame` (Tip attachment → Handle → HumanoidRootPart) and delegates to `SkillDelivery.deliver(spec.skill, ctx)`. **All effect and delivery logic lives in `src/shared/Skills/`** — SpellExecutor is now a thin adapter. Boss attacks go through the same `SkillDelivery` path. See [[design/build-plan|build-plan]] Phase 2 and the Skills pipeline ingest in `wiki/log.md`.

The module keeps no state of its own (the per-Humanoid freeze and burn tables that stop back-to-back freezes clobbering the saved `WalkSpeed` live in `SkillEffects`). The callers ([[systems/CastAction]] on the client, [[systems/SpellCastService]] on the server) own cast cost, dictionary validation, and targeting UX; SpellExecutor trusts the Spec.

## Files

- `src/shared/SpellExecutor/init.luau` — thin adapter: origin resolution + `DeliveryCtx` construction
- `src/shared/SpellExecutor/__tests.luau` — pure-Luau smoke tests (`runAll() -> (passed, failed)`)
- `src/shared/Skills/SkillTypes.luau` — types: `SkillSpec`, `EffectSpec`, `DeliveryCtx`, `RunContext`
- `src/shared/Skills/SkillEffects.luau` — effect handlers: `damage`, `heal`, `freeze`, `burn`, `knockup`, `shield`, `buff` (plus the matching `preconditions` that back `canCast`)
- `src/shared/Skills/SkillBuffs.luau`, `SkillInterrupt.luau` — shield/buff state and cast interruption used by the handlers
- `src/shared/Skills/SkillDelivery.luau` — delivery handlers: `instant`, `projectile`, `aoe`, `world_spawn`

## API

```lua
local SpellExecutor = require(ReplicatedStorage.Shared.SpellExecutor)

export type CastResult = SkillDelivery.Result  -- { ok: boolean, reason: string? }

SpellExecutor.cast(
  spec: SpellRegistry.Spec,
  caster: Humanoid | Model,
  target: Humanoid | Model | Vector3 | nil,
  run: SkillTypes.RunContext   -- required: { mode = "authoritative" | "predicted", predictedBy = number? }
): CastResult

-- Pure "would this cast be refused?" probe; CastAction calls it BEFORE draining mana.
SpellExecutor.canCast(spec, caster, target): CastResult
```

On an `authoritative` run (the server, via [[systems/SpellCastService]]) `cast` also raises the cast cue once through `SkillVisuals.spawnCastCue(spec.color, spec.tier, casterRoot, predictedBy)`; a `predicted` run (the caster's client, via [[systems/CastAction]]) has no damage sink, so effects that need one refuse there.

`caster` is the entity producing the spell (the wizard's character). `target` is what the spell affects — its expected shape depends on `spec.skill.onImpact[1].kind`:

| `kind` | Expected `target` | Notes |
|---|---|---|
| `damage` | `Humanoid` (or `Model` containing one) | Required. `nil` → `ok=false`. |
| `heal` | `Humanoid` / `Model` / `nil` | `nil` falls back to the caster's Humanoid (self-heal). |
| `freeze` | `Humanoid` (or `Model` containing one) | Required. `nil` → `ok=false`. |
| `burn` | `Humanoid` (or `Model` containing one) | Required. `nil` → `ok=false`. |
| `knockup` | `Humanoid` (or `Model` containing one) | Required. Launches the target's HumanoidRootPart upward. |
| `shield` | `Humanoid` / `Model` / `nil` | `nil` falls back to the caster (self-shield), same as `heal`. |
| `buff` | `Humanoid` / `Model` / `nil` | `nil` falls back to the caster. |

`Model`-typed targets are resolved via `FindFirstChildOfClass("Humanoid")`. A `Humanoid` whose `Parent == nil` (destroyed) is treated as missing and fails the kind's target check.

## Dispatch — full table

See `SkillEffects.luau` for the implementation. `SpellExecutor` no longer contains any dispatch logic.

| `kind` | Behaviour | Reads from `onImpact` entry |
|---|---|---|
| `damage` | Sends `fractionOfMaxHP × target.MaxHealth` (or a flat `amount`), times any `damageAmp` buff on the target, to the `DamageSink` that `HealthService` injects (`applyDamage` on the server). Nothing here writes `Humanoid.Health`; with no sink (the client's predicted run) it returns `ok=false, reason="no damage sink on this VM"`. | `fractionOfMaxHP` (or `amount`) |
| `heal` | Sends `fraction × target.MaxHealth` to the same sink's `heal`; same no-sink refusal. | `fractionOfMaxHP` |
| `burn` | Render flag only: sets `SkillConstants.BURNING_ATTRIBUTE` on the target's character for `durationSec` (default 3.0), then clears it. No damage, no debuff — Inferno's damage is its own `damage` entry. Re-burn extends the deadline. | `durationSec` |
| `freeze` | Save `target.WalkSpeed`, set to 0, raise the frozen attribute flag; restore via `task.delay(durationSec, …)` (to the rig's published `BASE_WALK_SPEED_ATTRIBUTE` if it has one, else the saved speed; Died/HealthChanged/Destroying purge the entry too). Re-freeze extends the existing freeze. On the fresh-freeze branch: also calls `SkillInterrupt.cancelCastsBy(target)` to abort pending scheduled volley shots, and `SkillInterrupt.silence(target)` so any new casts started while frozen are born cancelled. | `durationSec` |
| `knockup` | **Real handler.** Sets the target HRP's `AssemblyLinearVelocity.Y = force` (default 50) — launches the target straight up. No registry spell uses it yet, but it's callable end-to-end. | `force` |
| `shield` | Adds `amount` to the target's `_shield` absorb pool via `SkillBuffs.grantShield`. Additive, no expiry — drained by [[systems/Health]]'s `DamageModifierRegistry` inside `applyDamage`. | `amount` |
| `buff` | Applies a timed stat modifier via `SkillBuffs.applyBuff`. Currently only `buffKind = "damageAmp"`, read by the `damage` handler. Re-applying the same kind refreshes rather than stacks. | `buffKind`, `magnitude`, `durationSec` |
| anything else | `{ok=false, reason="unknown effect kind: <kind>"}` | — |

Effects never raise — bad inputs come back as `{ok=false, reason=…}` so the eventual cast-flow caller can surface failure to the HUD without a pcall.

## Freeze semantics — re-freeze extends

When a Humanoid is re-frozen while already frozen, the existing entry's expiry is bumped to `max(currentExpiry, now + newDuration)` and the originally-saved `WalkSpeed` is preserved. We deliberately do **not** overwrite `originalSpeed` — if we did, the second freeze would save the already-zero `WalkSpeed` and never restore the true pre-freeze value.

The chosen "extend, don't replace" semantics is slightly richer than the build-plan's allowed "last-write-wins" shortcut. Cost is ~6 lines; benefit is that a Frost Nip → Stasis chain on the same target behaves intuitively (longer expiry wins) rather than potentially shortening the freeze.

Internally each extension schedules its own `task.delay` for the new deadline; every timer re-checks `_freezeState[target].restoreAt` when it fires and only purges once the deadline has passed, so a superseded earlier timer is harmless. If the Humanoid dies or is destroyed meanwhile, the Died/HealthChanged/Destroying connections purge the entry without writing `WalkSpeed`.

## Freeze interrupts in-progress casts

Freeze isn't just a movement debuff — fresh freezes interrupt the target's pending scheduled work. The mechanism lives in `src/shared/Skills/SkillInterrupt.luau`:

- Async delivery handlers (`projectile`, `aoe`) call `SkillInterrupt.begin(ctx.source)` and gate each `task.delay` callback on `token.cancelled`. A `task.delay((count-1)*staggerSec + 0.1, …)` calls `SkillInterrupt.finish(source, token)` to clean up on natural completion.
- `SkillEffects.handlers.freeze`, on the fresh-freeze branch only, calls `cancelCastsBy(target)` (flips every active token) and `silence(target)` (so any new `begin` for that humanoid returns a pre-cancelled token until the freeze expires).
- The freeze-restore `task.delay` closure unwinds the silence via `SkillInterrupt.unsilence(target)`.

In-flight projectiles already on `RunService.Heartbeat` are independent of the token — they keep flying. Only *scheduling* future work is blocked. Practical effect: a Stasis cast mid-FireballVolley stops the remaining staggered shots from launching, and any new FireballVolley the boss state machine starts during the freeze fires zero shots.

## Stub status — cleared (Phase 5.2, 2026-08-03)

All effect kinds are real. The three former stubs resolved into two implementations and one deletion:

- **Shield** (Blue T2 Shield, Green T3 Sanctuary) — implemented as a flat absorb pool on the character's `_shield` attribute, which [[systems/Health]]'s `DamageModifierRegistry` was already draining inside `applyDamage`. Skills grants, Health drains.
- **Buff** — implemented as a timed per-Humanoid modifier in `SkillBuffs`. Its first consumer is Stasis's damage amp, which the registry had been declaring while the freeze handler ignored it.
- **Wall** — **deleted.** Nothing ever dispatched it. Stone Wall is a `world_spawn` *delivery* with an empty `onImpact`; the barrier Part is the effect.

Full rationale and the ownership split: [[systems/SkillPipeline]] § Defensive layer.

Still outstanding for Stone Wall: the placement targeting UX from [[design/gameplay-loop|gameplay-loop]] § "Targeting". `world_spawn` honours an explicit `Vector3` target, but no cast UI supplies one, so the wall drops a fixed distance ahead of the caster's facing.

## Test

`__tests.luau` exports `runAll() -> (passed, failed)` and exercises eleven scenarios via `pcall`-wrapped cases:

- Damage 20% on 100 → 80; damage on 0-HP clamps; heal 15% on 50 → 65; heal cap at MaxHealth; heal `target=nil` falls back to caster.
- Freeze 1s → `WalkSpeed=0` immediately; after `task.wait(1.15)` → `WalkSpeed` restored.
- Shield grants a positive absorb pool; `world_spawn` (Stone Wall) succeeds at a placement point; `buff` applies a 2× `damageAmp`.
- Unknown kind → `ok=false`, reason mentions the kind.
- Damage with `target=nil` → `ok=false`, reason mentions target.

Test dummies are `Instance.new("Model")` with a child `Humanoid` parented to `script` (the test ModuleScript), `Destroy()`ed at the end of each case.

## Cross-references

- Spec source → [[systems/SpellRegistry]]
- Pinned design → [[design/gameplay-loop]] § "Spell roster (prototype)", § "Targeting", § "Spell economy"
- Caller → [[systems/CastAction]] (shipped; wires reservoir drain + executor invocation)
- Damage path → [[systems/Health]] (spell `damage` / `heal` effects go through the `DamageSink` that `HealthService` injects into `SkillEffects`, i.e. `applyDamage`; `damageType` defaults to Spell and hit zone to Torso)
- Server relay → `src/server/SpellCastService.server.luau` — receives `SpellCastServer` RemoteEvent from `SpellCastController`, re-executes `SpellExecutor.cast` server-side (`mode = "authoritative"`) so boss/NPC HP changes actually stick (client writes don't replicate for server-owned Humanoids)
- Build plan → [[design/build-plan]] (Phase 2 — action systems)

## Client/server boundary

`SpellExecutor.cast` runs wherever it is required — client for VFX/energy, server for real HP writes. `Humanoid.Health` writes from a LocalScript **do not replicate** for server-owned characters (boss, NPCs). `SpellCastService` closes this: `SpellCastController` (the client cast path; `SpellMenuGui` hands it the request) fires `SpellCastServer` (RemoteEvent at `ReplicatedStorage.Shared.SpellCast.Remotes.SpellCastServer`) after **every** accepted cast, including self-buffs and placements with `target = nil`; the service validates and calls `SpellExecutor.cast` server-side. No spell skips the relay — the client's predicted run has no damage sink, so heals and shields only land on the server.
