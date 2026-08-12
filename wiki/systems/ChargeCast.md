---
type: system
description: Phase 5.8 — hold-to-charge tier selection. Press a colour panel and the charge climbs through the tiers you can afford; release fires what you reached. Mana is reserved, never drained, until release, so cancelling is free. HUD notches + reserve band make the commitment legible, and a character orb makes it a PvP tell.
updated: 2026-08-12
---

# ChargeCast

The gesture that turns a colour panel into a **tier choice**.

Brain Fighter has four spell tiers per colour ([[systems/SpellRegistry]] `TIER_COSTS = { 5, 10, 20, 40 }`, red alone reaching T4), and until Phase 5.8 there was **no way for the player to pick one**. A tap on a spell panel fired whatever the reservoir could currently afford, so "save big, fire small" — the decision [[design/gameplay-loop]] § "Spell economy" is built around — was unreachable in-game. The design doc's answer was a drag-from-reservoir vertical tier menu; this supersedes it.

**Press the panel. The charge climbs. Release to fire what you reached.** One gesture, no menu, identical on mouse and touch.

## The charge model

Mana *flows* into the charge at a constant rate and the tier thresholds are the existing costs, so there is no second tuning table:

```
chargeTimeFor(tier) = (TIER_COSTS[tier] - TIER_COSTS[1]) / MANA_FLOW_PER_SEC
```

At `MANA_FLOW_PER_SEC = 20`:

| Tier | Cost | Hold |
|---|---|---|
| T1 | 5 | 0 s — a tap |
| T2 | 10 | 0.25 s |
| T3 | 20 | 0.75 s |
| T4 | 40 | 1.75 s |

T4 reads as a commitment for free, because it costs 8× a Firebolt and therefore takes 8× the mana to pour in. `MANA_FLOW_PER_SEC` (`SpellRegistry`) is the single lever for how a hold *feels*; moving it moves every tier together, which is the point — the ratios between tiers belong to the cost table, not to this constant.

The charge climbs only through tiers that are **both** time-reached **and** currently affordable, and **stops dead at the affordability ceiling**. You cannot charge past what you own. At the ceiling the panel pulses and the orb strains instead of growing, so "this is as big as it gets" is legible with no text cue.

## Reserve, spend on release

**Nothing is drained while the charge is held.** The counting-down numeral and the reserve band on the panel are a *promise*, not a debit. On release, [[systems/CastAction]] `castSpecific` drains exactly one tier cost, once.

This is why cancelling is free and why [[systems/EnergyReservoirs]] needed **zero changes**: there is no refund path, because nothing was ever taken. Its `:drain` is all-or-nothing by contract, and a reservation model would have meant inventing a second, partial one.

Releasing below T1 — a press on a panel that cannot afford anything, or a release before the charge started — costs nothing and fizzles.

## Cancelling

Release **outside** the panel and nothing fires. The release is watched globally (`UserInputService.InputEnded`) rather than per-button, because the whole point is that the pointer has left the button by then and the button's own `InputEnded` would never arrive.

This does **not** pop the block behind the HUD. [[systems/BlockShoot]]'s `BlockTapController` pops on `InputBegan`, not on release, and the *press* that starts a charge lands on a `TextButton` and therefore arrives there with `gameProcessedEvent = true` — the guard that Phase 5.7 flagged as load-bearing. Verified live: a cancelled charge left the reservoir untouched and popped nothing.

## Files

| File | Role |
|---|---|
| `src/shared/SpellRegistry/init.luau` | `MANA_FLOW_PER_SEC`, `chargeTimeFor(tier)`, `tierCount(color)`, exported `TIER_COSTS` / `NUM_TIERS` |
| `src/shared/CastAction/init.luau` | `resolveSpecAtCharge(color, reservoirs, heldSec)` — pure tier selection |
| `src/shared/Hud/SpellMenuBuilder.luau` | the gesture, the panel rework, the four charge signals |
| `src/shared/Hud/SpellMenuConfig.luau` | `NOTCH_*`, `DESATURATED_*`, `CHARGE_*`, `NUMERAL_*`, `FILL_GRADIENT_*` |
| `src/client/UI/SpellMenuGui.client.luau` | target resolution at release, the cast, the local orb, the `ChargeState` relay |
| `src/shared/Vfx/StatusVisuals/ChargeOrbVfx.luau` | the orb + mote layers ([[systems/VisualEffects]]) |
| `src/client/Vfx/ChargeOrbController.client.luau` | draws *other* players' orbs from the replicated attributes |
| `src/shared/SpellCast/Remotes/ChargeState.model.json` | C→S `(phase, color, tier)` |
| `src/server/SpellCast/ChargeStateService.server.luau` | validates and writes the two character attributes |
| `src/shared/Skills/SkillConstants.luau` | `CHARGE_COLOR_ATTR` / `CHARGE_TIER_ATTR` |

## Builder signals

`SpellMenuBuilder.build()` returns a handle carrying five signals. `castRequested` **changed signature** in 5.8 — it now carries the tier the builder picked, and the coordinator no longer calls `resolveTapSpec`.

| Signal | Fires |
|---|---|
| `chargeStarted(color)` | the press, once the panel can afford T1 |
| `chargeTierChanged(color, tier)` | on each crossing, and on reaching the ceiling |
| `chargeProgress(color, tier, alpha)` | every Heartbeat while held — **local only**, never relayed |
| `castRequested(color, tier)` | release over the panel with tier ≥ 1 |
| `chargeCancelled(color)` | release outside the panel, or the charge never reached T1 |

Plus `:setChargeAffordability(color, maxTier)` so a coordinator can move the ceiling; `:setReservoirs` derives it automatically from [[systems/SpellRegistry]] `listAffordableSpells`.

Why the tier selection exists **twice** — `CastAction.resolveSpecAtCharge` and the builder's own `tierAtHold` — is deliberate: the builder cannot require `CastAction` without dragging `EnergyReservoirs` and `SpellExecutor` into the HUD layer. Both read the same two registry functions rather than one reimplementing the other's arithmetic, and `__tests` pins the registry contract (`chargeTimeFor(1) == 0`, strictly increasing) that keeps them agreeing.

## The panel

Six changes, all of them in service of "a whole T1 cast should not look like a nudge":

1. **Notches** — hard lines inside `FillClip` at `TIER_COSTS[t] / FILL_MAX` (8.3% / 16.7% / 33.3% / 66.7% against the cap of 60). Count comes from `SpellRegistry.tierCount(color)`, **not** `NUM_TIERS`: a fourth line on green would mark a spell that does not exist.
2. **Saturate at castable** — a panel that cannot afford T1 is drained toward grey and snaps to full colour the frame it can. Driven off the **existing** `wasAffordable` edge flag that already triggers `playAffordBounce`; a second edge detector would be one more thing to fall out of step.
3. **Persistent numeral** — `35/60`, top right. Replaces the transient `EnergyPopup` that appeared on tap and faded: a number you only see *after* committing is on the wrong side of the decision.
4. **Charge reserve band** — the top slice of the fill this release will spend, growing downward as the tier climbs. The numeral counts down in step. Both snap back on cancel, which is the whole refund story.
5. **Target notch highlight** — the notch for the tier you are at brightens and thickens.
6. **Ceiling pulse** — a dedicated overlay Frame breathes when the charge tops out. An overlay rather than a `UIScale` pulse because `playAffordBounce` already owns the panel's `UIScale`, and two systems tweening one property is exactly the fight [[concepts/SingleOwnership]] exists to stop.

One structural change came along with (2): the fill bar's `UIGradient` used to be a `ColorSequence` of the panel's own hue, so the bar's colour lived in two multiplied places at once. `TweenService` cannot tween a `ColorSequence`, which made the desaturation inexpressible as a tween. The gradient is now a **neutral** ramp (`FILL_GRADIENT_BOTTOM_TINT` → `TOP_TINT`) and `BackgroundColor3` carries all the hue.

Panels are **built drained**, because every reservoir starts empty and an edge detector only fires on a change.

## The orb, and why it is an attribute

The orb over the caster's head is the **PvP tell** — the point is that your opponent can see you winding up a T4. Making everyone see it is nearly free, and the reason is replication: the character Model is server-owned, so two attributes written there land on every client's copy of that rig with **no fan-out RemoteEvent**, and a late joiner sees an already-charging player because the values are simply there when they arrive. Same argument as `_shield` and `_frozen` ([[systems/SkillPipeline]]).

```
client (charging) ──ChargeState remote──► ChargeStateService ──SetAttribute──► character
                                                                                  │ replication
     ChargeOrbVfx (local, zero RTT) ◄── SpellMenuGui          ChargeOrbController ◄┘  (every other client)
```

**The local player is deliberately skipped by the controller.** `SpellMenuGui` drives `ChargeOrbVfx` directly off the same gesture that fires the remote, so the caster's own orb appears on the press frame and grows continuously off the builder's hold clock. Drawing it from the attribute as well would mean two writers for one orb, with the replicated one arriving a round trip late and stepped rather than smooth. Remote observers get the stepped version and tween between crossings; that is what `setTier`'s `alpha` argument is for — live progress locally, `0` remotely.

**Wire cost:** discrete events only. One write on start, one per tier crossing, one on end — at most ~6 attribute writes per charge, never per frame.

**Attribute write order on `end` is load-bearing.** `ChargeStateService` writes the final tier *first*, then clears the colour. `ChargeOrbController` reads the tier on the frame the colour clears to choose between the release flash (tier > 0, the spell went out) and a quiet collapse (tier 0, a cancel). Clearing the colour first would make every cast look like a cancel. A residual `_chargeTier` number stays on the character after a charge ends; it is meaningless while `_chargeColor` is nil and the next `start` overwrites it.

`ChargeOrbController` also watches `SkillConstants.DAMAGEABLE_TAGS`, so a future boss windup can reuse this lane instead of `BossWindupClient`'s bespoke per-frame glow. Nothing writes those attributes on a boss today.

## Trust

**No new trust hole, and nothing here is authoritative.** The client already picked the tier before 5.8 and the server already validated it — [[systems/SpellCastService]] resolves the spec and debits `spec.cost` from the `EnergyLedger`. A hold-charged T4 debits 40 exactly as a tapped T4 did.

What the server **cannot** verify is *hold duration*. There is no server-side clock on the gesture, so a client could claim to have charged instantly. That costs nothing: the tier it claims is priced by the ledger regardless, so charging instantly buys speed, not mana. Recorded explicitly in [[systems/SpellCastService]] § Trust model rather than left implied.

`ChargeStateService` is its own file rather than a branch in `SpellCastService`: different remote, different lifecycle, different trust posture. A cast changes health and mana; a charge state moves pixels. What it *does* enforce is that the payload is well-formed — a real colour, a real tier for that colour, inside a rate budget derived from the cast budget (`CHARGE_EVENTS_PER_CAST = 6`) — so a malformed fire cannot write junk onto a replicated character. Both attributes are cleared on death and on `CharacterRemoving`, so a corpse never keeps an orb.

## Verification

Everything below was run live in Studio (`start_stop_play`, session lock `charge-cast`) on 2026-08-12.

| Check | Result |
|---|---|
| `CastAction.__tests` (15 scenarios, 6 new) | `all scenarios passed` |
| Notch geometry | red 4 notches at y-scale 0.917/0.833/0.667/0.333; green + blue 3 |
| Quick tap, green = 40 | drained 5 → **T1 Mend**, not the highest affordable |
| ~1.2 s hold, green = 35, ceiling T3 | drained 20 → **T3 Sanctuary**; attributes stepped `green\|1 → \|2 → \|3` |
| 2.5 s hold, green = 15, ceiling T2 | drained 10 → **T2 Stone Wall** — clamped at the ceiling, not the clock |
| Press red, drag off, release | red **40 → 40**, orb gone, motes gone, attributes cleared, reserve hidden |
| Grey→saturated flip | green at 0 = `(0.33, 0.44, 0.37)` muted; at 10 = `(0.196, 0.608, 0.255)` authored; fill 0.1667 sits exactly on the T2 notch |
| **Orb on another rig, from the Client datamodel** | server wrote `_chargeColor=blue/_chargeTier=3` on the Boss → client rendered 1 orb, size 2.86, tint `#80C0FF`, welded to `Boss.HumanoidRootPart`, 1 particle emitter + PointLight |
| Leak check, 20 charge cycles (10 fire / 10 cancel) | orbs 0, motes 0, halo attachments 0, halo emitters 0 |

The orb check is the one that matters and is why it was run from the **Client** datamodel against a rig the local player does not own: per [[CLAUDE.md]] § Player-Facing Output, server logs and Studio's server view do not verify a player-facing effect. Driving the Boss's attributes from the Server VM and counting instances on the Client VM exercises the exact server-write → replicate → controller-draw path a second player would, without a second client.

**Still owed:** the feel check. Does a 1.75 s T4 hold read as a commitment or as lag? `MANA_FLOW_PER_SEC` is expected to move after real play.

## Cross-references

- [[design/gameplay-loop]] § "Cast (reservoir-driven)" — the gesture this supersedes.
- [[design/build-plan]] — Phase 5.8.
- [[systems/CastAction]] — `resolveSpecAtCharge`, `castSpecific`.
- [[systems/SpellRegistry]] — `TIER_COSTS`, `chargeTimeFor`, `tierCount`.
- [[systems/HUD]] — the SpellMenu panel.
- [[systems/VisualEffects]] — `ChargeOrbVfx` and the `charge_motes_*` entries.
- [[systems/SpellCastService]] — trust model; the cast relay is unchanged.
- [[concepts/SingleOwnership]] — the ceiling pulse overlay vs `playAffordBounce`'s `UIScale`.
