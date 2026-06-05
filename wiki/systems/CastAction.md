---
type: system
description: Phase 2 action — the cast pipeline. tapReservoir fires the highest currently-affordable tier; castSpecific fires an explicitly-picked tier. Drains the reservoir on cast, refunds on executor failure, and fires the client-local `spellResolved` signal on success.
updated: 2026-06-05
---

# CastAction

The "Cast" step of the gameplay loop (see [[design/gameplay-loop|gameplay-loop]] § "Cast (reservoir-driven)"). Wires the two cast UX gestures into actual spell fires by bridging [[systems/EnergyReservoirs]], [[systems/SpellRegistry]], and [[systems/SpellExecutor]]. The HUD calls into this module; CastAction owns no UI itself.

Phase 2 ([[design/build-plan]]) — tracker [NIM-10](tracker://NIM-10). Sequential after [[systems/SpellExecutor]] because it depends on it.

## Files

- `src/shared/CastAction/init.luau` — the module (two functions, no state).
- `src/shared/CastAction/__tests.luau` — smoke suite; exports `M.run()`.

## API

```luau
local CastAction = require(ReplicatedStorage.Shared.CastAction)

export type Color = "red" | "green" | "blue"

export type CastSummary = {
    color: Color,
    tier: number,
    name: string,
}

export type CastResult = {
    ok: boolean,
    reason: string?,        -- only on ok=false
    cast: CastSummary?,     -- only on ok=true
    drained: number?,       -- only on ok=true; energy deducted
}

-- Tap a reservoir → highest currently-affordable tier of that color.
CastAction.tapReservoir(
    color: Color,
    reservoirs: EnergyReservoirs,
    caster: Humanoid | Model,
    target: Humanoid | Model | Vector3 | nil
) -> CastResult

-- Drag → release on a specific tier entry.
CastAction.castSpecific(
    color: Color,
    tier: number,          -- 1 | 2 | 3 | 4 (T4 exists for red only — Volley)
    reservoirs: EnergyReservoirs,
    caster: Humanoid | Model,
    target: Humanoid | Model | Vector3 | nil
) -> CastResult
```

`Color` is the three-color string union shared with [[systems/EnergyReservoirs]] and [[systems/SpellRegistry]].

## The two entry points

The dual gesture model is the load-bearing decision of the cast surface (see [[design/gameplay-loop|gameplay-loop]] § "Cast (reservoir-driven)") — it has to be honored at this layer too:

- **`tapReservoir(color, ...)`** — the casual fast path. One touch fires the highest currently-affordable tier of that color. If the reservoir can't afford even T1 (cost 5), the call returns `{ ok = false, reason = "no affordable tier" }` and the HUD decides whether to surface a fizzle.
- **`castSpecific(color, tier, ...)`** — the strategic path; what the drag-from-reservoir tier menu resolves to. The player saw all affordable tiers and picked one deliberately — usually the "save big, fire small" case where the highest affordable is *not* what they want. Returns a `{ ok = false, reason = "cannot afford <Name> (cost ..., have ...)" }` if the chosen tier is above the current energy, and a `{ ok = false, reason = "invalid color/tier: ..." }` if the caller passed garbage (handled gracefully, see [Errors](#errors)).

Both gestures resolve into the same internal pipeline:

1. Look up the [[systems/SpellRegistry|Spec]].
2. Verify affordability (`canAfford` / `get`).
3. Drain the cost (`drain`).
4. Run the effect ([[systems/SpellExecutor|SpellExecutor.cast]]).
5. On success, fire `CastAction.spellResolved` (see [Signal](#signal)); on executor failure, **refund** the cost (see below).

## Signal

`CastAction.spellResolved` (`init.luau:66`) is a `BindableEvent.Event` fired with `(spec, caster, target)` after every **successful** cast (`init.luau:115`). It is the seam the VFX layer hooks: on the casting client's VM, `VfxController` connects to it to play cast VFX locally with zero RTT, then relays a payload to the server for cross-client broadcast (see [[systems/VisualEffects]]). The server VM constructs the same BindableEvent but nothing connects there. The signal does **not** fire on fizzle or refund — a `spellResolved` fire reliably means a spell actually went off.

## Refund on SpellExecutor failure

If `SpellExecutor.cast` returns `{ ok = false, ... }` — for instance because a damage spell was tapped with no target — CastAction **adds the cost back** to the reservoir via `reservoirs:add(color, spec.cost)` and propagates the executor's reason. Rationale:

- The player paid mana for an action that didn't actually happen. Losing energy to a downstream rejection would feel like a punishment for a UI/contract issue rather than a player mistake.
- The refund keeps the cast pipeline's invariant clean: **a non-`ok` `CastResult` means no observable world change AND no observable reservoir change**.
- The cost is small — one `:add` call — and the alternative (an empty try-cast handshake before the real drain) would double-call into SpellExecutor and is far more error-prone.

Pinned to a `reason` line in the resulting `CastResult` so the HUD can surface why nothing happened. The current refunding case the project actually hits is **projectile spells (Firebolt/Fireball/Volley) tapped with no resolvable target** ([[systems/SpellExecutor]] / SkillDelivery returns a `"…requires a target…"` reason); future targeting-mode work may add more.

The refund does NOT fire if the affordability check at step 2 fails — in that case `drain` was never called, so there's nothing to add back.

## Errors

- Invalid `color` / `tier` to `castSpecific`: SpellRegistry raises; CastAction catches via `pcall` and returns `{ ok = false, reason = "invalid color/tier: ..." }`. The wrap is deliberate — callers benefit from a uniform `CastResult` failure shape rather than having to wrap every `castSpecific` call in their own pcall.
- Invalid `color` to `tapReservoir`: `reservoirs:get(color)` will raise per the [[systems/EnergyReservoirs]] contract. Not pcall-wrapped — the HUD will only ever pass the three known colors here (a tap originates from a known reservoir bar), so a bad color is a programmer error rather than a user input.
- An affordability-checked drain that returns false: this is a contract violation by [[systems/EnergyReservoirs]] and raises rather than fizzling — silent fizzling here would hide a real bug.

## Logging

`Logger.new("CastAction")` emits one info line per terminal state:

- `tap fizzle — <color> reservoir below T1 (energy=<n>)`
- `castSpecific fizzle — invalid color/tier: <err>`
- `castSpecific fizzle — cannot afford <Name> (cost <n>, have <n>)`
- `cast ok — <Name> (color=<color> tier=<n> cost=<n>)`
- `cast refunded — <Name> (<reason>)`

No throttling — casts are rare-per-frame.

## Consumers

- **HUD: SpellMenu** (shipped — [[systems/HUD]]) — calls `tapReservoir` on a single-tap of a reservoir bar; calls `castSpecific(color, tier, ...)` on a drag-release over a tier menu entry. Reads `CastResult.cast` to surface the cast feedback (spell name, drain animation on the bar, placement-target hand-off for `targetingMode == "placement"` once that lands).
- **VFX: VfxController** — connects to `CastAction.spellResolved` to play cast VFX locally and relay to the server (see [Signal](#signal)).
- **Tutorial / scripted first cast** — may call either entry point directly to drive a scripted cast in an intro level.

Beyond its three dependencies and the `spellResolved` BindableEvent it owns, this module does not touch the HUD or write to attributes — the HUD reads `CastResult` from the caller. Per [[concepts/SingleOwnership]], only CastAction writes via `:drain` on the reservoirs (and only it refunds via `:add` in the failure path); MemorizeAction is the only other writer (via `:add` on Memorize success).

## Verification

Run the smoke suite from MCP `execute_luau` or the Studio command bar during a playtest:

```luau
require(game.ReplicatedStorage.Shared.CastAction.__tests).run()
```

A passing run prints `[CastAction.__tests] all scenarios passed`. A failed assertion errors with the scenario's message.

The nine scenarios (costs pinned to `TIER_COSTS = { 5, 10, 20, 40 }`, cap 60):

| # | Scenario | Pinned outcome |
|---|---|---|
| 1 | tap red, energy=0 | `ok=false, reason="no affordable tier"`, reservoir untouched |
| 2 | tap red, energy=15 | Fireball fires (T2, drain 10); red=5 — projectile, no observable damage |
| 3 | tap red, energy=30 | Inferno fires (T3, drain 20); red=10; HP 100→50 (instant delivery) |
| 4 | tap red, energy=160 (caps at 60) | Volley fires (T4, drain 40); red=20 — projectile, no observable damage |
| 5 | castSpecific(red, 1), energy=80 (caps at 60) | Firebolt fires (save-big); red=55 |
| 6 | castSpecific(red, 3), energy=15 | `ok=false, reason mentions "cannot afford Inferno"` (cost 20); red unchanged |
| 7 | castSpecific("yellow", 1) | `ok=false, reason mentions "invalid"`; red unchanged (60) |
| 8 | tap red, energy=15, target=nil | Fireball projectile has no resolvable target → executor refuses, **refund**: red back to 15, `ok=false, reason mentions "target"` |
| 9 | castSpecific(green, 1), energy=15, target=nil (heal fallback) | Mend fires on caster (self-heal), drain 5, green=10; caster HP 50→65 |

> Projectile-delivery spells (Firebolt T1, Fireball T2, Volley T4) launch a projectile that never finds a collidable target in the test rig, so the cast returns `ok=true` (delivery accepted) but no health change is observable; instant-delivery spells (Inferno T3, Mend G-T1) synchronously mutate Humanoid health and are the canonical end-to-end cases.

Tests are synchronous — CastAction itself is synchronous, and `EnergyReservoirs:get(color)` returns the post-mutation value immediately (the `.changed` signal is what's Deferred, not the underlying state write). No `task.wait()` needed.

## Cross-references

- [[design/gameplay-loop]] — § "Cast (reservoir-driven)": dual-gesture surface, tier menu, placement-mode markers.
- [[design/build-plan]] — Phase 2, gated on [[systems/SpellExecutor]].
- [[systems/EnergyReservoirs]] — drained via `:drain(color, cost)`; refunded via `:add(color, cost)` on executor failure.
- [[systems/SpellRegistry]] — spec lookup via `getSpell` (explicit) and `listAffordableSpells` (tap fast-path).
- [[systems/SpellExecutor]] — `cast(spec, caster, target)`; its `CastResult.reason` propagates through ours.
- [[systems/MemorizeAction]] — sibling action; only writer to reservoirs via `:add`. Same module style.
- [[concepts/SingleOwnership]] — `:drain` is CastAction's alone; `:add` is shared with MemorizeAction (deposits) and CastAction's own refund path.
