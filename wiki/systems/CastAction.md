---
type: system
description: Phase 2 action — the cast pipeline. castSpecific fires an explicitly-picked tier (the production path since 5.8's hold-to-charge); resolveSpecAtCharge picks that tier from a hold duration. Checks the cast can resolve, then drains the reservoir and fires the client-local `spellResolved` signal on success. (The tap-era `tapReservoir` / `resolveTapSpec` have been removed.)
updated: 2026-11-14
---

# CastAction

The "Cast" step of the gameplay loop (see [[design/gameplay-loop|gameplay-loop]] § "Cast (reservoir-driven)"). Wires the two cast UX gestures into actual spell fires by bridging [[systems/EnergyReservoirs]], [[systems/SpellRegistry]], and [[systems/SpellExecutor]]. The HUD calls into this module; CastAction owns no UI itself.

Phase 2 ([[design/build-plan]]) — tracker [NIM-10](tracker://NIM-10). Sequential after [[systems/SpellExecutor]] because it depends on it.

## Files

- `src/shared/CastAction/init.luau` — the module (`resolveSpecAtCharge` and `castSpecific`, no state).
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

-- Which tier would releasing a `heldSec`-long charge fire? Pure — reads
-- the reservoir, touches nothing. nil below T1.
CastAction.resolveSpecAtCharge(
    color: Color,
    reservoirs: EnergyReservoirs,
    heldSec: number
) -> Spec?

-- Fire a specific tier. THE production entry point since 5.8 (and the only one:
-- resolveTapSpec and tapReservoir no longer exist).
CastAction.castSpecific(
    color: Color,
    tier: number,          -- 1 | 2 | 3  (T4 parked 2026-09-23; the registry errors on it)
    reservoirs: EnergyReservoirs,
    caster: Humanoid | Model,
    target: Humanoid | Model | Vector3 | nil
) -> CastResult

CastAction.spellResolved: RBXScriptSignal   -- (spec, caster, target), see Signal
```

## Tier selection (Phase 5.8)

`resolveSpecAtCharge` is the rule behind [[systems/ChargeCast]]. It returns the highest tier that is **both** time-reached (`SpellRegistry.chargeTimeFor(tier) <= heldSec`) **and** currently affordable — so the charge stops dead at the affordability ceiling rather than climbing into a fizzle — and `nil` below T1, which the caller surfaces as a cancel rather than a failed cast.

It lives here because the HUD has to know the tier *before* the release in order to draw it, and a second copy of the selection rule in the builder would drift from the one `castSpecific` is actually handed. (`SpellMenuBuilder` does keep its own `tierAtHold` for the per-frame path — it cannot require this module without dragging `EnergyReservoirs` and `SpellExecutor` into the HUD layer — but both read the same two `SpellRegistry` functions, and scenario 15 pins that contract.)

`Color` is the three-color string union shared with [[systems/EnergyReservoirs]] and [[systems/SpellRegistry]].

## The entry point

- **`castSpecific(color, tier, ...)`** — the production path since Phase 5.8, and the only cast function. The player chose this tier deliberately, by holding the colour panel until the charge reached it (see [[systems/ChargeCast]]); the "save big, fire small" case is a short hold on a full reservoir. Returns `{ ok = false, reason = "cannot afford <Name> (cost ..., have ...)" }` if the chosen tier is above the current energy, and `{ ok = false, reason = "invalid color/tier: ..." }` if the caller passed garbage (handled gracefully, see [Errors](#errors)).
- The tap-era `tapReservoir` ("fire the highest affordable tier") and `resolveTapSpec` were retired and are gone from the module; `SpellMenuBuilder` places the charge ceiling with `listAffordableSpells` instead.

`castSpecific` resolves into this internal pipeline:

1. Look up the [[systems/SpellRegistry|Spec]].
2. Verify affordability (`canAfford` / `get`).
3. Ask `SpellExecutor.canCast(spec, caster, target)` whether the cast would resolve; if not, fail with its reason **before touching the reservoir**.
4. Drain the cost (`drain`).
5. Run the effect ([[systems/SpellExecutor|SpellExecutor.cast]], `mode = "predicted"`).
6. On success, fire `CastAction.spellResolved` (see [Signal](#signal)); on executor failure (should be unreachable after step 3), **refund** the cost (see below).

## Signal

`CastAction.spellResolved` is the `.Event` of the Rojo-versioned BindableEvent at `CastAction/Remotes/SpellResolved` (since refactor chunk 7, so `VfxController` can listen on the Instance without requiring this module and the executor chain behind it), fired with `(spec, caster, target)` after every **successful** cast (`drainAndCast` in `init.luau`). It is the seam the VFX layer hooks: on the casting client's VM, `VfxController` connects to it to draw the cast cue locally with zero RTT — and nothing at the target; every other client, and the caster's impact cue, come from the authoritative run over `VfxBroadcast` (see [[systems/VisualEffects]]). The server VM constructs the same BindableEvent but nothing connects there. The signal does **not** fire on fizzle or refund — a `spellResolved` fire reliably means a spell actually went off.

## Refuse before draining; refund as a backstop

The order is **check, then drain** (changed from drain → execute → refund): every reason a cast can be refused is knowable up front from `(spec, target)`, so `SpellExecutor.canCast` runs first and a refused cast (e.g. a damage spell with no target) returns `{ ok = false, reason }` having never touched the reservoir. Logged as `cast refused — <Name> (<reason>)`.

The refund path still exists as a backstop and should be unreachable: if `SpellExecutor.cast` returns `{ ok = false, ... }` after `canCast` said yes, CastAction **adds the cost back** via `reservoirs:add(color, spec.cost)`, propagates the executor's reason, and logs a `warn` (a precondition has drifted from its handler). Rationale for never keeping the player's mana on a failed cast:

- The player paid mana for an action that didn't actually happen. Losing energy to a downstream rejection would feel like a punishment for a UI/contract issue rather than a player mistake.
- The refund keeps the cast pipeline's invariant clean: **a non-`ok` `CastResult` means no observable world change AND no observable reservoir change**.
- A `canCast` pre-check (`SkillDelivery.canDeliver` over the same preconditions the effect handlers use) replaced the old empty-handshake idea without double-running the cast.

The `reason` is carried in the resulting `CastResult` so the HUD can surface why nothing happened. The case the project actually hits is **projectile spells (Firebolt/Fireball) with no resolvable target** ([[systems/SpellExecutor]] / SkillDelivery returns a `"…requires a target…"` reason) — now refused by the pre-check, not refunded.

Neither the refusal nor the refund touches the reservoir if the affordability check at step 2 fails — `drain` was never called.

## Errors

- Invalid `color` / `tier` to `castSpecific`: SpellRegistry raises; CastAction catches via `pcall` and returns `{ ok = false, reason = "invalid color/tier: ..." }`. The wrap is deliberate — callers benefit from a uniform `CastResult` failure shape rather than having to wrap every `castSpecific` call in their own pcall.
- An affordability-checked drain that returns false: this is a contract violation by [[systems/EnergyReservoirs]] and raises rather than fizzling — silent fizzling here would hide a real bug.

## Logging

`Logger.new("CastAction")` emits one info line per terminal state:

- `castSpecific fizzle — invalid color/tier: <err>`
- `castSpecific fizzle — cannot afford <Name> (cost <n>, have <n>)`
- `cast refused — <Name> (<reason>)` (the `canCast` pre-check; nothing drained)
- `cast ok — <Name> (color=<color> tier=<n> cost=<n>)`
- `cast refunded — <Name> (<reason>). canCast passed but the cast refused; ...` (logged at `warn`)

No throttling — casts are rare-per-frame.

## Consumers

- **HUD: SpellMenu** (shipped — [[systems/HUD]], [[systems/ChargeCast]]) — `SpellMenuBuilder` owns the press-hold-release gesture and hands `SpellMenuGui` a `castRequested(color, tier)`, which `SpellMenuGui` forwards to `SpellCastController`'s `RequestCast` BindableFunction; the controller resolves the enemy lock **at release** (a 3 s T3 charge is long enough for the world to move), calls `castSpecific`, and relays every accepted cast (reading `CastResult.cast`) to [[systems/SpellCastService]]; the GUI flashes the panel from the result. Placement-target hand-off for `targetingMode == "placement"` still pending (the controller passes `target = nil`).
- **VFX: VfxController** — listens on `Remotes/SpellResolved` and draws the caster's **cast cue only** (see [Signal](#signal)). Impact cues and the copy other players see come from the authoritative run over `VfxBroadcast`; the client-originated relay was deleted 2026-09-08 ([[design/client-server-boundary]]).
- **Tutorial / scripted first cast** — may call either entry point directly to drive a scripted cast in an intro level.

Beyond its three dependencies and the `spellResolved` BindableEvent it owns, this module does not touch the HUD or write to attributes — the HUD reads `CastResult` from the caller. Per [[concepts/SingleOwnership]], only CastAction writes via `:drain` on the reservoirs (and only it refunds via `:add` in the failure path); MemorizeAction is the only other writer (via `:add` on Memorize success).

## Verification

Run the smoke suite from MCP `execute_luau` or the Studio command bar during a playtest:

```luau
require(game.ReplicatedStorage.Shared.CastAction.__tests).run()
```

A passing run prints `[CastAction.__tests] all scenarios passed`. A failed assertion errors with the scenario's message.

The table below is the older fifteen-scenario list (costs pinned to `TIER_COSTS = { 5, 10, 20, 40 }`, cap 60); see the numbering note under it for what `__tests.luau` holds today:

| # | Scenario | Pinned outcome |
|---|---|---|
| 1 | tap red, energy=0 | `ok=false, reason="no affordable tier"`, reservoir untouched |
| 2 | tap red, energy=15 | Fireball fires (T2, drain 10); red=5 — projectile, no observable damage |
| 3 | tap red, energy=30 | Inferno fires (T3, drain 20); red=10; HP 100→50 (instant delivery) |
| 4 | tap red, energy=160 (caps at 60) | *Retired with `tapReservoir`; before T4 was parked this fired Volley (drain 40)* |
| 5 | castSpecific(red, 1), energy=80 (caps at 60) | Firebolt fires (save-big); red=55 |
| 6 | castSpecific(red, 3), energy=15 | `ok=false, reason mentions "cannot afford Inferno"` (cost 20); red unchanged |
| 7 | castSpecific("yellow", 1) | `ok=false, reason mentions "invalid"`; red unchanged (60) |
| 8 | tap red, energy=15, target=nil | Fireball projectile has no resolvable target → `canCast` refuses before the drain (this row predates that; it used to be drain-then-**refund**): red stays 15, `ok=false, reason mentions "target"` |
| 9 | castSpecific(green, 1), energy=15, target=nil (heal fallback) | Mend fires on caster (self-heal), drain 5, green=10; caster HP 50→65 |
| 10 | `resolveSpecAtCharge(red, energy=0, held=10 s)` | `nil` — a hold on an empty reservoir never reaches T1, however long |
| 11 | `resolveSpecAtCharge(red, energy=60, held=0)` | Firebolt (T1) — a tap is T1, **not** the highest affordable; the 5.8 behaviour change |
| 12 | `resolveSpecAtCharge(red, energy=12, held=17.5 s)` | Fireball (T2) — clamped at the affordability ceiling, not the clock |
| 13 | `resolveSpecAtCharge(red, energy=60)` at exactly `chargeTimeFor(3)` / midway 2→3 | T3 / T2 — the boundary is `<=`, asserted from both sides |
| 14 | `resolveSpecAtCharge(red\|green\|blue, energy=60, held=10×chargeTimeFor(NUM_TIERS))` | T3 — the roster ceiling binds before the clock; no school reaches past T3 since T4 was parked (2026-09-23), and the hold is derived from `NUM_TIERS` so parking or un-parking a tier does not reach into the test |
| 15 | `chargeTimeFor` contract | `chargeTimeFor(1) == 0` (a tap) and strictly increasing with tier |

> Scenarios 10–15 express hold durations as `SpellRegistry.chargeTimeFor(t)` rather than as literal seconds, so they survive the retune of `MANA_FLOW_PER_SEC` that the first feel-check playtest is expected to produce.

> **Numbering drift, noted 2026-09-23:** `__tests.luau` now holds ten scenarios, not fifteen — the `tapReservoir` rows went when that entry point was retired. The rows above still describe the behaviour correctly; only the indices are stale. Left rather than renumbered, since re-pinning the table to the file is a job of its own.

> Projectile-delivery spells (Firebolt T1, Fireball T2) launch a projectile that never finds a collidable target in the test rig, so the cast returns `ok=true` (delivery accepted) but no health change is observable; instant-delivery spells (Inferno T3, Mend G-T1) synchronously mutate Humanoid health and are the canonical end-to-end cases.

Tests are synchronous — CastAction itself is synchronous, and `EnergyReservoirs:get(color)` returns the post-mutation value immediately (the `.changed` signal is what's Deferred, not the underlying state write). No `task.wait()` needed.

## Cross-references

- [[design/gameplay-loop]] — § "Cast (reservoir-driven)": dual-gesture surface, tier menu, placement-mode markers.
- [[design/build-plan]] — Phase 2, gated on [[systems/SpellExecutor]].
- [[systems/EnergyReservoirs]] — drained via `:drain(color, cost)`; refunded via `:add(color, cost)` on executor failure.
- [[systems/SpellRegistry]] — spec lookup via `getSpell` (explicit) and `listAffordableSpells` (used by `resolveSpecAtCharge`).
- [[systems/SpellExecutor]] — `cast(spec, caster, target)`; its `CastResult.reason` propagates through ours.
- [[systems/MemorizeAction]] — sibling action; only writer to reservoirs via `:add`. Same module style.
- [[concepts/SingleOwnership]] — `:drain` is CastAction's alone; `:add` is shared with MemorizeAction (deposits) and CastAction's own refund path.
