---
type: system
description: Thin origin-resolver that delegates spell casting to DeliveryRegistry (delivery) and EffectRegistry (effects). All damage/heal/freeze/stub logic lives in src/shared/Skills/.
updated: 2026-05-18
---

# SpellExecutor

The runtime side of the spell roster. Given a [[systems/SpellRegistry|Spec]] plus a caster and a target, resolves the origin `CFrame` (Tip attachment → Handle → HumanoidRootPart) and delegates to `DeliveryRegistry.deliver(spec.skill, ctx)`. **All effect and delivery logic lives in `src/shared/Skills/`** — SpellExecutor is now a thin adapter. Boss attacks go through the same `DeliveryRegistry` path. See [[design/build-plan|build-plan]] Phase 2 and the Skills pipeline ingest in `wiki/log.md`.

The module is otherwise pure — the only per-cast state it keeps is a per-Humanoid freeze table so back-to-back freezes don't clobber the saved `WalkSpeed`. The caller (eventually [[systems/CastAction]]) owns cast cost, dictionary validation, and targeting UX; SpellExecutor trusts the Spec.

## Files

- `src/shared/SpellExecutor/init.luau` — thin adapter: origin resolution + `DeliveryCtx` construction
- `src/shared/SpellExecutor/__tests.luau` — pure-Luau smoke tests (`runAll() -> (passed, failed)`)
- `src/shared/Skills/SkillTypes.luau` — types: `SkillSpec`, `EffectSpec`, `DeliveryCtx`
- `src/shared/Skills/EffectRegistry.luau` — effect handlers: `damage`, `heal`, `freeze`, stubs
- `src/shared/Skills/DeliveryRegistry.luau` — delivery handlers: `instant`, `projectile`, `aoe`, `world_spawn`

## API

```lua
local SpellExecutor = require(ReplicatedStorage.Shared.SpellExecutor)

export type CastResult = {
  ok: boolean,
  reason: string?,  -- present only on failure
}

SpellExecutor.cast(
  spec: SpellRegistry.Spec,
  caster: Humanoid | Model,
  target: Humanoid | Model | Vector3 | nil
): CastResult
```

`caster` is the entity producing the spell (the wizard's character). `target` is what the spell affects — its expected shape depends on `spec.skill.onImpact[1].kind`:

| `kind` | Expected `target` | Notes |
|---|---|---|
| `damage` | `Humanoid` (or `Model` containing one) | Required. `nil` → `ok=false`. |
| `heal` | `Humanoid` / `Model` / `nil` | `nil` falls back to the caster's Humanoid (self-heal). |
| `freeze` | `Humanoid` (or `Model` containing one) | Required. `nil` → `ok=false`. |
| `shield` | (ignored — stub) | Returns `ok=true`. |
| `wall` | `Vector3` (placement) — currently ignored | Returns `ok=true`; logs the position. |
| `buff` | (ignored — stub) | Returns `ok=true`. |

`Model`-typed targets are resolved via `FindFirstChildOfClass("Humanoid")`. A `Humanoid` whose `Parent == nil` (destroyed) is treated as missing and fails the kind's target check.

## Dispatch — full table

See `EffectRegistry.luau` for the implementation. `SpellExecutor` no longer contains any dispatch logic.

| `kind` | Behaviour | Reads from `onImpact` entry |
|---|---|---|
| `damage` | `target.Health -= fraction × target.MaxHealth`; clamp to ≥ 0 | `fractionOfMaxHP` |
| `heal` | `target.Health += fraction × target.MaxHealth`; clamp to ≤ MaxHealth | `fractionOfMaxHP` |
| `freeze` | Save `target.WalkSpeed`, set to 0; restore via `task.delay(durationSec, …)`. Re-freeze extends the existing freeze. | `durationSec` |
| `shield` | **Stub.** `log:info("Shield stub — …")`. | — |
| `wall` | **Stub.** `log:info("Wall stub — … at <pos>")`. | (target Vector3 logged) |
| `buff` | **Stub.** `log:info("Buff stub — …")`. | — |
| anything else | `{ok=false, reason="unknown effect kind: <kind>"}` | — |

Effects never raise — bad inputs come back as `{ok=false, reason=…}` so the eventual cast-flow caller can surface failure to the HUD without a pcall.

## Freeze semantics — re-freeze extends

When a Humanoid is re-frozen while already frozen, the existing entry's expiry is bumped to `max(currentExpiry, now + newDuration)` and the originally-saved `WalkSpeed` is preserved. We deliberately do **not** overwrite `originalSpeed` — if we did, the second freeze would save the already-zero `WalkSpeed` and never restore the true pre-freeze value.

The chosen "extend, don't replace" semantics is slightly richer than the build-plan's allowed "last-write-wins" shortcut. Cost is ~6 lines; benefit is that a Frost Nip → Stasis chain on the same target behaves intuitively (longer expiry wins) rather than potentially shortening the freeze.

Internally the restore is a self-rescheduling `task.delay` closure: when it fires it compares `_freezeState[target]` against its captured state, and if expiry has been pushed forward, re-arms via `task.delay(remaining, …)`. If the Humanoid was destroyed in the meantime, the `Parent == nil` check skips the WalkSpeed write.

## Stub status (shield / wall / buff)

These three kinds are present in the registry today but the supporting systems aren't built:

- **Shield** (Blue T2 Shield, Sanctuary's nested buff) — needs a damage-absorb pool layered on top of [[systems/Health]]. To be implemented when the absorb layer lands.
- **Wall** (Green T2 Stone Wall) — needs the placement targeting UX from [[design/gameplay-loop|gameplay-loop]] § "Targeting" and a wall-instance lifecycle (spawn → block hits for `durationSec` → despawn). Currently the call returns `ok=true` and logs the world position so the cast-menu can be exercised end-to-end.
- **Buff** — no prototype spell currently uses `kind="buff"` at the top level (Sanctuary's `buffSpec` is a nested shield, dispatched separately when that lands). The stub branch exists so adding a buff-typed spell to the registry doesn't require an executor change to be callable.

Replacing a stub is a single-function swap — handler signature is `(spec, target) -> CastResult`, same as the real handlers. No callers need to change.

## Test

`__tests.luau` exports `runAll() -> (passed, failed)` and exercises eleven scenarios via `pcall`-wrapped cases:

- Damage 20% on 100 → 80; damage on 0-HP clamps; heal 15% on 50 → 65; heal cap at MaxHealth; heal `target=nil` falls back to caster.
- Freeze 1s → `WalkSpeed=0` immediately; after `task.wait(1.15)` → `WalkSpeed` restored.
- Shield / Wall / Buff stubs → `ok=true`.
- Unknown kind → `ok=false`, reason mentions the kind.
- Damage with `target=nil` → `ok=false`, reason mentions target.

Test dummies are `Instance.new("Model")` with a child `Humanoid` parented to `script` (the test ModuleScript), `Destroy()`ed at the end of each case.

## Cross-references

- Spec source → [[systems/SpellRegistry]]
- Pinned design → [[design/gameplay-loop]] § "Spell roster (prototype)", § "Targeting", § "Spell economy"
- Eventual caller → [[systems/CastAction]] (Phase 2 — pending; wires reservoir drain + executor invocation)
- Damage path comparison → [[systems/Health]] (uses `HealthService.applyDamage` for player/NPC hits; SpellExecutor writes `Humanoid.Health` directly for now since spells don't need hit-zone classification or damage modifiers)
- Build plan → [[design/build-plan]] (Phase 2 — action systems)
