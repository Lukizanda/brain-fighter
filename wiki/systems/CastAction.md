---
type: system
description: Phase 2 action — the cast pipeline. tapReservoir fires the highest currently-affordable tier; castSpecific fires an explicitly-picked tier. Drains the reservoir on cast and refunds on executor failure.
updated: 2026-05-14
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
    tier: number,          -- 1 | 2 | 3
    reservoirs: EnergyReservoirs,
    caster: Humanoid | Model,
    target: Humanoid | Model | Vector3 | nil
) -> CastResult
```

`Color` is the three-color string union shared with [[systems/EnergyReservoirs]] and [[systems/SpellRegistry]].

## The two entry points

The dual gesture model is the load-bearing decision of the cast surface (see [[design/gameplay-loop|gameplay-loop]] § "Cast (reservoir-driven)") — it has to be honored at this layer too:

- **`tapReservoir(color, ...)`** — the casual fast path. One touch fires the highest currently-affordable tier of that color. If the reservoir can't afford even T1 (cost 10), the call returns `{ ok = false, reason = "no affordable tier" }` and the HUD decides whether to surface a fizzle.
- **`castSpecific(color, tier, ...)`** — the strategic path; what the drag-from-reservoir tier menu resolves to. The player saw all affordable tiers and picked one deliberately — usually the "save big, fire small" case where the highest affordable is *not* what they want. Returns a `{ ok = false, reason = "cannot afford <Name> (cost ..., have ...)" }` if the chosen tier is above the current energy, and a `{ ok = false, reason = "invalid color/tier: ..." }` if the caller passed garbage (handled gracefully, see [Errors](#errors)).

Both gestures resolve into the same internal pipeline:

1. Look up the [[systems/SpellRegistry|Spec]].
2. Verify affordability (`canAfford` / `get`).
3. Drain the cost (`drain`).
4. Run the effect ([[systems/SpellExecutor|SpellExecutor.cast]]).
5. On executor failure, **refund** the cost (see below).

## Refund on SpellExecutor failure

If `SpellExecutor.cast` returns `{ ok = false, ... }` — for instance because a damage spell was tapped with no target — CastAction **adds the cost back** to the reservoir via `reservoirs:add(color, spec.cost)` and propagates the executor's reason. Rationale:

- The player paid mana for an action that didn't actually happen. Losing energy to a downstream rejection would feel like a punishment for a UI/contract issue rather than a player mistake.
- The refund keeps the cast pipeline's invariant clean: **a non-`ok` `CastResult` means no observable world change AND no observable reservoir change**.
- The cost is small — one `:add` call — and the alternative (an empty try-cast handshake before the real drain) would double-call into SpellExecutor and is far more error-prone.

Pinned to a `reason` line in the resulting `CastResult` so the HUD can surface why nothing happened. The current refunding case the project actually hits is **damage spells with no target** ([[systems/SpellExecutor]] returns `"damage requires a Humanoid target"`); future targeting-mode work may add more.

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

## Consumers (planned)

- **HUD: SpellMenu** ([[design/build-plan]] Phase 4) — calls `tapReservoir` on a single-tap of a reservoir bar; calls `castSpecific(color, tier, ...)` on a drag-release over a tier menu entry. Reads `CastResult.cast` to surface the cast feedback (spell name in a kill-ticker, drain animation on the bar, placement-target hand-off for `targetingMode == "placement"` once that lands).
- **Tutorial / scripted first cast** — may call either entry point directly to drive a scripted cast in an intro level.

This module deliberately does **not** call any other system beyond its three dependencies. It does not emit signals, does not touch the HUD, does not write to attributes — the HUD reads `CastResult` from the caller. Per [[concepts/SingleOwnership]], only CastAction writes via `:drain` on the reservoirs (and only it refunds via `:add` in the failure path); MemorizeAction is the only other writer (via `:add` on Memorize success).

## Verification

Run the smoke suite from MCP `execute_luau` or the Studio command bar during a playtest:

```luau
require(game.ReplicatedStorage.Shared.CastAction.__tests).run()
```

A passing run prints `[CastAction.__tests] all scenarios passed`. A failed assertion errors with the scenario's message.

The nine scenarios mirror the NIM-10 brief:

| # | Scenario | Pinned outcome |
|---|---|---|
| 1 | tap red, energy=0 | `ok=false, reason="no affordable tier"`, reservoir untouched |
| 2 | tap red, energy=15 | Spark fires (T1, drain 10); red=5; HP 100→95 |
| 3 | tap red, energy=50 | Fireball fires (T2, drain 30); red=20; HP 100→80 |
| 4 | tap red, energy=160 | Inferno fires (T3, drain 80); red=80; HP 100→50 |
| 5 | castSpecific(red, 1), energy=80 | Spark fires (save-big); red=70; HP 100→95 |
| 6 | castSpecific(red, 3), energy=50 | `ok=false, reason mentions "cannot afford Inferno"`; red unchanged |
| 7 | castSpecific("yellow", 1) | `ok=false, reason mentions "invalid"`; red unchanged |
| 8 | tap red, energy=15, target=nil | executor refuses, **refund**: red back to 15, `ok=false, reason mentions "target"` |
| 9 | tap green, energy=15, target=nil (heal fallback) | Mend fires on caster (self-heal), green=5; caster HP 50→65 |

Tests are synchronous — CastAction itself is synchronous, and `EnergyReservoirs:get(color)` returns the post-mutation value immediately (the `.changed` signal is what's Deferred, not the underlying state write). No `task.wait()` needed.

## Cross-references

- [[design/gameplay-loop]] — § "Cast (reservoir-driven)": dual-gesture surface, tier menu, placement-mode markers.
- [[design/build-plan]] — Phase 2, gated on [[systems/SpellExecutor]].
- [[systems/EnergyReservoirs]] — drained via `:drain(color, cost)`; refunded via `:add(color, cost)` on executor failure.
- [[systems/SpellRegistry]] — spec lookup via `getSpell` (explicit) and `listAffordableSpells` (tap fast-path).
- [[systems/SpellExecutor]] — `cast(spec, caster, target)`; its `CastResult.reason` propagates through ours.
- [[systems/MemorizeAction]] — sibling action; only writer to reservoirs via `:add`. Same module style.
- [[concepts/SingleOwnership]] — `:drain` is CastAction's alone; `:add` is shared with MemorizeAction (deposits) and CastAction's own refund path.
