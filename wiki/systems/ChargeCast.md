---
type: system
description: Phase 5.8 — hold-to-charge tier selection. Press a colour panel and the charge climbs through the tiers you can afford; release fires what you reached. Mana is reserved, never drained, until release, so cancelling is free. The panels are circles that fill from the centre with concentric tier rings, and a character orb makes the windup a PvP tell.
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

At `MANA_FLOW_PER_SEC = 5` (retuned down from 20 on 2026-08-12, the first pass at the feel check):

| Tier | Cost | Hold |
|---|---|---|
| T1 | 5 | 0 s — a tap |
| T2 | 10 | 1 s |
| T3 | 20 | 3 s |
| T4 | 40 | 7 s |

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
| `src/shared/Hud/SpellMenuBuilder.luau` | the gesture, the circular panel, the five charge signals |
| `src/shared/Hud/SpellMenuConfig.luau` | `PANEL_DIAMETER`, `PANEL_CORNER_RADIUS`, `FILL_RADIUS_EXPONENT`, `NOTCH_*`, `DESATURATED_*`, `CHARGE_*`, `NUMERAL_*`, `FILL_GRADIENT_*` |
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

The panels are **circles**. Mana fills each one outward from the centre; the tier thresholds are concentric rings.

The shape is not decoration. A vertical bar reads as a *meter* — status you watch — which was the right shape while a tap fired whatever you could afford. Press-and-hold needs the panel to read as something you push and keep pushing, and a disc in a column of round buttons does. It also matches the DASH button sitting directly below in the same `BottomRight` column, which was already a circle, and it echoes the charge orb rising over the caster's head.

Seven changes, all of them in service of "a whole T1 cast should not look like a nudge":

1. **Tier rings** — a ring at each `TIER_COSTS[t] / FILL_MAX` (8.3% / 16.7% / 33.3% / 66.7% of the diameter, against the cap of 60). Built as a `UIStroke` on a circular Frame, which is the cheapest true annulus the engine offers; the stroke grows *outward* from its frame, so a ring meant to sit centred on a radius is inset by its own thickness. Count comes from `SpellRegistry.tierCount(color)`, **not** `NUM_TIERS`: a fourth ring on green would mark a spell that does not exist. They are **dark**, unlike the flat bar's white notches — a ring spends most of its life on top of a lit fill disc, where white on bright is almost nothing, and a dark ring reads as a groove against both the fill and the empty base.
2. **Saturate at castable** — a panel that cannot afford T1 is drained toward grey **and faded back** (`FILL_BASE_TRANSPARENCY` 0.50 → `_DEAD` 0.72), snapping to full colour and full weight the frame it can cast. Alpha and saturation are separate channels and the eye reads them separately: grey alone still holds its ground in the layout, where grey *and* transparent falls behind the panels that matter. It is deliberately the **dead** value that moves — making castable panels more opaque would brighten all three at once on a full reservoir, which is exactly when the HUD is already loudest. Driven off the **existing** `wasAffordable` edge flag that already triggers `playAffordBounce`; a second edge detector would be one more thing to fall out of step.
3. **Ready glow** — a panel that *can* cast breathes a coloured halo at its rim (`ReadyBloom` + `ReadyGlow`). This is the positive half of (2), and it was added because the negative half is the weaker one: grey only reads as grey when there is a lit panel beside it to compare against, which is exactly the case that fails when all three are drained or all three are full. Two strokes rather than one — a single `UIStroke` is a hard line and reads as a *border*, a thing the panel has, where a crisp edge over a soft inner bloom reads as light coming off it. Both breathe on one tween each, started on the same frame with the same `TweenInfo` so they stay in phase without being driven together. Only the crisp stroke bleeds outward and only by its own 4px, so two lit neighbours keep 2px of air in the 10px `BUTTON_GAP`; the bloom is inset and faces inward.
   **Ready motes** ride the same lifecycle: six sparks orbiting just inside the rim. The halo is a static shape and the eye stops seeing it; motion is what survives peripheral vision, which is the only vision a corner-of-screen widget gets. They are **not** a `ParticleEmitter` — that is a 3D instance and does not exist in a `ScreenGui`. They are plain circular Frames parented to a transparent full-size ring whose **`Rotation`** is tweened, so the entire orbit is one tween and no per-frame code. This is a dividend of the shape change: on a circle, "orbit" and "rotate the parent" are the same operation, where the old rectangles would have needed a Heartbeat and a path. Sizes and twinkle periods are jittered per mote and the spin direction alternates per panel, because without either the three panels lit by one Memorize move in lockstep and read as one mechanism rather than three living things.
4. **Persistent numeral** — `35/60`, in the middle of the circle. Replaces the transient `EnergyPopup` that appeared on tap and faded: a number you only see *after* committing is on the wrong side of the decision. It sat inset from the top-right corner while the panels were rectangles; on a circle the corners of the bounding box are empty space *outside* the disc, so it floated in the void — and retiring the spell name freed up the centre.
5. **Charge reserve** — an annulus eaten out of the **outer edge** of the fill: what this release will spend. Sized to the post-spend radius with a stroke thick enough to reach the pre-spend radius, so it always hugs the fill edge and eats inward. The numeral counts down in step. Both snap back on cancel, which is the whole refund story. At T4 on a full reservoir the annulus swallows the entire disc and the numeral reads `0/60`, which is the correct and rather good-looking extreme.
6. **Active ring highlight** — the ring for the tier you are at thickens and **inverts to white**, the one moment it should be the brightest thing on the panel rather than the darkest.
7. **Ceiling pulse** — a rim halo breathes when the charge tops out. A ring rather than the wash over the whole panel it used to be: the wash competed with the fill disc for the same pixels and a halo outside the largest possible fill competes with nothing. Still its own instance rather than a `UIScale` pulse, because `playAffordBounce` already owns the panel's `UIScale`, and two systems tweening one property is exactly the fight [[concepts/SingleOwnership]] exists to stop.

Two halos now want the rim, so they are **mutually exclusive by construction** rather than by z-order: the ready glow is suppressed for whichever colour is being pressed, which is also the honest reading — "you could press this" stops being information the instant you do. One predicate owns it, and both start and stop are idempotent, so every state change (`setReservoirs`, `beginPress`, `endPress`) just calls it and lets it settle rather than reasoning about which transition it is:

```lua
local function refreshReadyGlow(color: string)
    local held = press ~= nil and press.color == color
    if wasAffordable[color] and not held then startReadyGlow(color) else stopReadyGlow(color) end
end
```

They are also tuned not to compete: the ceiling pulse breathes at 0.42s and means *act now*; the ready glow at 1.2s is an idle heartbeat.

The spell name came **off the panel and onto the orb** — there is no room for "Sanctuary" inside a circle. See § The name label below.

One structural change came along with (2): the fill's `UIGradient` used to be a `ColorSequence` of the panel's own hue, so the colour lived in two multiplied places at once. `TweenService` cannot tween a `ColorSequence`, which made the desaturation inexpressible as a tween. The gradient is now a **neutral** ramp (`FILL_GRADIENT_BOTTOM_TINT` → `TOP_TINT`) and `BackgroundColor3` carries all the hue. On a disc that top-lit ramp does a second job: it stops it reading as a flat coin.

Panels are **built drained**, because every reservoir starts empty and an edge detector only fires on a change. The build now calls the same `baseColorFor(color, false)` / `baseTransparencyFor(false)` selectors the tweens use rather than restating the drained values, so there is one definition of "dead" instead of two that can drift.

The transparency split forced a fix in `playFiredFlash`, which dims the base and tweens back. It used to capture `origTransp` off the live frame when the flash *began* and restore that. A cast is exactly the event that can drop a panel below T1, so the captured value would restore the castable alpha onto a panel that had just gone dead — and it would win, because the restore lands **after** the desaturation tween `setReservoirs` started. It now resolves `baseTransparencyFor(wasAffordable[color])` when the flash ends. Sampling live state at the start of an animation and writing it back at the end is the general shape of this bug.

There is **no `ClipsDescendants` anywhere in the panel**, deliberately. It clips to the *rectangle* and ignores `UICorner`, so it could not have masked a disc even if the layers needed masking — and they do not, because each one is sized to its own radius. The old `FillClip` did not survive the shape change.

## What the circle encodes, and what it does not

`SpellMenuConfig.FILL_RADIUS_EXPONENT` is the single lever, and the trade is real:

| N | Mapping | Reads as |
|---|---|---|
| **1** (current) | diameter ∝ mana | The rings land where the bar's notches did, so the 5/10/20/40 curve is unchanged: the first three tiers bunch near the middle and whip past, T4 is a long way out. Because area grows as the square, the disc looks **emptier than the numeral says**. |
| 0.5 | area ∝ mana | The disc leaps out of the centre on the first few points then crawls. The rings space out almost evenly, which **flatters the cost curve** by hiding that T4 costs double T3. |

Everything that has to line up with the fill edge — both tier rings, both edges of the reserve annulus — goes through one `radiusFractionFor`, so the exponent stays one lever rather than four call sites that have to agree.

A consequence of N = 1 worth knowing before tuning it: at 8.3% and 16.7% of the diameter, the **T1 and T2 rings are very small** — on a 180px panel they are 15px and 30px across, and the centred numeral sits over them. The useful rings in practice are T3 and T4. The alternative that keeps linear encoding *and* readable spacing is an arc gauge (mana travels around a 270° ring, arc length ∝ mana, centre free for the numeral); it is filed in [[ideas]] rather than built, because it needs the two-half rotation mask and the disc is nearly free.

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

## The name label

A `BillboardGui` over the orb naming the spell **this release would fire right now** — `Firebolt`, then `Fireball`, then `Volley` as the charge climbs. It pops in from zero scale on every crossing (`Back, Out`, which is the spring) and dissipates upward on release.

This is where the spell name went when the panels became circles. Putting it on the orb rather than back on the HUD does two things the panel could not: it lands where the player is already looking mid-charge instead of in the corner they are pressing, and **an opponent reads it too**. That second one is free — `ChargeOrbVfx.setTier` resolves the name from the entry's own colour, and `ChargeOrbController` already drives `setTier` off the replicated attributes, so the remote path needed no new wiring at all.

Four decisions worth keeping:

- **`AlwaysOnTop` is off.** The orb is occluded by cover and the name is occluded with it. A label that reads through a wall turns a PvP tell into a wallhack.
- **`MaxDistance = 120` studs**, well inside the orb's own visibility. At range an opponent should read *that* you are charging and roughly how big, not exactly what.
- **Parented to the head, not to the orb.** The dissipate (0.3 s) outlives the orb's release flash (`RELEASE_TIME = 0.16 s`), and a label hanging off the orb would be destroyed mid-fade. `step` rides it on the orb's *live* radius each frame so the gap under the text stays constant as the orb grows.
- **`spellNameFor` bounds the tier with `tierCount`, not `getSpell` alone.** `getSpell` validates against the roster maximum of 4 and green tops out at 3, so `getSpell("green", 4)` passes validation and returns **nil**. Reading `.name` off that is the crash the guard exists to avoid — the same off-by-one the tier rings dodge by counting from `tierCount`.

**What it does not fix.** The label only exists *during* a charge, so it tells you what you are about to fire and still cannot teach you the roster before you press. The legend that the superseded drag-menu provided is still missing and still belongs to [[systems/Tutorial]]; this closes the mid-charge half of that gap, not the learning half.

## Trust

**No new trust hole, and nothing here is authoritative.** The client already picked the tier before 5.8 and the server already validated it — [[systems/SpellCastService]] resolves the spec and debits `spec.cost` from the `EnergyLedger`. A hold-charged T4 debits 40 exactly as a tapped T4 did.

What the server **cannot** verify is *hold duration*. There is no server-side clock on the gesture, so a client could claim to have charged instantly. That costs nothing: the tier it claims is priced by the ledger regardless, so charging instantly buys speed, not mana. Recorded explicitly in [[systems/SpellCastService]] § Trust model rather than left implied.

`ChargeStateService` is its own file rather than a branch in `SpellCastService`: different remote, different lifecycle, different trust posture. A cast changes health and mana; a charge state moves pixels. What it *does* enforce is that the payload is well-formed — a real colour, a real tier for that colour, inside a rate budget derived from the cast budget (`CHARGE_EVENTS_PER_CAST = 6`) — so a malformed fire cannot write junk onto a replicated character. Both attributes are cleared on death and on `CharacterRemoving`, so a corpse never keeps an orb.

## Verification

Everything below was run live in Studio (`start_stop_play`, session lock `charge-cast`) on 2026-08-12.

| Check | Result |
|---|---|
| `CastAction.__tests` (15 scenarios, 6 new) | `all scenarios passed` |
| Notch geometry (bar era) | red 4 notches at y-scale 0.917/0.833/0.667/0.333; green + blue 3 |
| Quick tap, green = 40 | drained 5 → **T1 Mend**, not the highest affordable |
| ~1.2 s hold, green = 35, ceiling T3 | drained 20 → **T3 Sanctuary**; attributes stepped `green\|1 → \|2 → \|3` |
| 2.5 s hold, green = 15, ceiling T2 | drained 10 → **T2 Stone Wall** — clamped at the ceiling, not the clock |
| Press red, drag off, release | red **40 → 40**, orb gone, motes gone, attributes cleared, reserve hidden |
| Grey→saturated flip | green at 0 = `(0.33, 0.44, 0.37)` muted; at 10 = `(0.196, 0.608, 0.255)` authored; fill 0.1667 sits exactly on the T2 notch |
| **Orb on another rig, from the Client datamodel** | server wrote `_chargeColor=blue/_chargeTier=3` on the Boss → client rendered 1 orb, size 2.86, tint `#80C0FF`, welded to `Boss.HumanoidRootPart`, 1 particle emitter + PointLight |
| Leak check, 20 charge cycles (10 fire / 10 cancel) | orbs 0, motes 0, halo attachments 0, halo emitters 0 |

The orb check is the one that matters and is why it was run from the **Client** datamodel against a rig the local player does not own: per [[CLAUDE.md]] § Player-Facing Output, server logs and Studio's server view do not verify a player-facing effect. Driving the Boss's attributes from the Server VM and counting instances on the Client VM exercises the exact server-write → replicate → controller-draw path a second player would, without a second client.

### Circular panels

Run live on 2026-08-12, session lock `circle-panels`.

| Check | Result |
|---|---|
| Panel structure | square 180px panels; children `FillBase / FillDisc / ChargeReserve / Ring_t1..N / ReadyBloom / ReadyGlow / ReadyMotes / CeilingPulse / Numeral / ColorLabel / PressTarget`; red 4 rings, green + blue 3; no `FillClip`, no `SpellLabel` |
| Ring geometry | ring stroke centres at diameter fractions **0.0837 / 0.1667 / 0.3337 / 0.6667** — exactly 5/10/20/40 over the cap of 60 |
| Fill at 40 mana | diameter fraction 0.667, landing exactly on the T4 ring |
| Hold to ceiling, red = 40 | reserve annulus swallowed the whole disc, numeral `0/60` in reserve gold, rim halo visible, orb + motes up |
| Release off-panel | red `40/60`, reserve thickness 0, halo hidden, orbs 0, motes 0 |
| Quick tap, green = 20 | drained 5 → **T1**, fill 0.333 → 0.250; all rings back to the resting dark |

### Ready glow and motes

Run live on 2026-08-12, session locks `ready-glow` then `ready-motes`. Verified by **client screenshot** at each state, not by reading properties — a halo is exactly the kind of thing that can exist in the tree and render as nothing.

| Check | Result |
|---|---|
| All three at 10 mana (T2 affordable) | all three panels carry a coloured rim halo, in phase, each with orbiting motes |
| Two captures 1.5 s apart | motes at different angles and different brightnesses — the spin tween and the per-mote twinkle jitter are both live, not a static ring of dots |
| Hold green | green's halo and motes **both gone**, replaced by the white ceiling ring; red + blue unaffected — the handoff is clean and only the pressed colour changes |
| Release green, casting T2 Stone Wall (cost 10 → drained to 0) | green grey with **no halo and no motes**; red + blue at `10/60` still lit and orbiting |
| Console | no errors across either cycle |

### Dead-panel transparency

Run live on 2026-08-12, session lock `dead-alpha`.

| Check | Result |
|---|---|
| All three at `0/60` on spawn | panels recede to near-invisible — numeral and a faint rim only. The build-time path uses the dead selectors, so this is right without waiting for an edge |
| Fill to 10 | all three snap forward to solid discs with halo + motes; the two states are now unmistakable at a glance |
| Cast green dry (T2 Stone Wall, 10 → 0) | green settles at the **dead** alpha after the fired flash, not the castable one — the `origTransp` capture bug does not reproduce. Red + blue unchanged |

Those captures were taken at **0.72 / 0.88**, where a dead panel was near-invisible. Retuned immediately after to **0.50 / 0.72**, which keeps the familiar 0.72 as the *dead* value and makes the castable state heavier instead — so the split widens (0.22, against 0.16) while nothing is ever fainter than it was before the split existed. Only the two constants moved; the behaviour above is unchanged.

### The name label

| Check | Result |
|---|---|
| Hold red = 40 to ceiling | `"Volley"`, GothamBlack, TextScaled, `UIScale` settled at 1.0, `MaxDistance` 120, `AlwaysOnTop` false; **1** label in the world |
| Label tracks the orb's growth | `StudsOffsetWorldSpace.Y` = 5.196 = `ORB_HEIGHT_STUDS` 2.6 + live radius 1.70 + `LABEL_GAP_STUDS` 0.9 |
| Release over the panel | red **40 → 0** (T4 Volley), label / orb / motes all 0 after the dissipate |
| Hold red = 10, ceiling T2 | `"Fireball"` — the name follows the *reached* tier, not the roster maximum |
| Release off-panel | red **10 → 10**, label gone, nothing cast |
| Leak sweep, 12 start→tier→release/stop cycles | labels 0, orbs 0, motes 0, emitters 0 |

**Feel check, first pass (2026-08-12):** `MANA_FLOW_PER_SEC` moved **20 → 5**, taking T4 from a 1.75 s hold to a 7 s one and T2 from 0.25 s to a full second. The lever did exactly what it exists for — no code, no test and no HUD constant had to move with it, because everything derives from `chargeTimeFor`. Whether 7 s is where it lands is a further play question; a hold that long makes the orb's PvP tell much easier to react to, which is a design consequence and not only a tuning one.

**Still owed:** the other axis — does a disc that looks emptier than its numeral read as tension or as a bug (`FILL_RADIUS_EXPONENT`)?

## Cross-references

- [[design/gameplay-loop]] § "Cast (reservoir-driven)" — the gesture this supersedes.
- [[design/build-plan]] — Phase 5.8.
- [[systems/CastAction]] — `resolveSpecAtCharge`, `castSpecific`.
- [[systems/SpellRegistry]] — `TIER_COSTS`, `chargeTimeFor`, `tierCount`.
- [[systems/HUD]] — the SpellMenu panel.
- [[systems/VisualEffects]] — `ChargeOrbVfx` and the `charge_motes_*` entries.
- [[systems/SpellCastService]] — trust model; the cast relay is unchanged.
- [[concepts/SingleOwnership]] — the ceiling pulse overlay vs `playAffordBounce`'s `UIScale`.
