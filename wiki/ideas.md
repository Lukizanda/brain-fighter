---
title: Ideas Scrapbook
updated: 2026-08-12
---

# Ideas Scrapbook

Raw ideas, shower thoughts, and playtest observations. No commitment to build — just a place to capture before they disappear.

---

## Open Ideas

### Spell name label above the charge orb
*Captured: 2026-08-12*

The spell name came off the cast panel when it became a circle — there is no room for "Sanctuary" inside a disc. The replacement idea: a small world-space label floating above the [[systems/ChargeCast]] charge orb, showing the name of the spell the current charge tier would fire, updating as the charge climbs.

Attractive because it puts the name where the player's eyes already are during a hold (the orb, not the HUD corner), and because it doubles as a PvP read — an opponent seeing "STONE WALL" over your head knows what is coming.

**The known weakness, and why this is filed rather than built:** an orb only exists *during* a charge. A label on it can tell you what you are about to fire, but it can never teach you the roster *before* you press. That is a different problem — a legend or a first-play tutorial beat — and this idea does not solve it. Worth building anyway if the in-charge read is valuable on its own; not worth building if it is meant to be the answer to "how does a new player learn the spells".

**Design questions:**
- BillboardGui on the orb, or reuse the [[systems/Tutorial]] overlay lane?
- Does the label show for *other* players' orbs too (it would have to come off `_chargeTier` + `_chargeColor`, which already replicate), or only your own?
- Does it show the name at the tier you are at, or the tier you are climbing toward?

**Related systems:** `ChargeCast`, `ChargeOrbVfx`, `SpellRegistry`
**Wiki pages:** `wiki/systems/ChargeCast.md`, `wiki/systems/VisualEffects.md`

---

### Arc-gauge cast panels (the alternative to the fill disc)
*Captured: 2026-08-12*

Held in reserve in case the concentric-disc panels do not work out. Instead of mana filling a disc outward from the centre, it travels **around a ring** — a 270° donut gauge with the tier thresholds as ticks along the arc.

**Why it is the technically better encoding:** arc length is linear in mana, so the 8.3 / 16.7 / 33.3 / 66.7% tier spacing survives intact and stays *visible* — on a 270° sweep the T1 tick is 22° in. The disc cannot do that: under `FILL_RADIUS_EXPONENT = 1` the T1 and T2 rings are 15px and 30px across on a 180px panel and the centred numeral sits over them, and under `0.5` the rings space out evenly but the cost curve reads flatter than it is. The donut's hole is also free real estate for the numeral.

**Why the disc was tried first:** it is nearly free — `UICorner` at 0.5 scale and a tweened `Size`. Roblox has no radial fill, so an arc needs the two-half rotation mask, roughly 60 lines of well-trodden but fiddly code.

If we go here, the pieces that carry over unchanged are `radiusFractionFor` (becomes `arcFractionFor`), the reserve-as-a-band-at-the-leading-edge idea, the active-tick highlight, and the whole charge state machine — the shape change is confined to `SpellMenuBuilder`'s layer construction and `SpellMenuConfig`.

**Related systems:** `ChargeCast`, `HUD`
**Wiki pages:** `wiki/systems/ChargeCast.md` § What the circle encodes

---

### Letter Block — Random Letter Cycling
*Captured: 2026-05-15*

Letter blocks on the field could periodically swap to a new random letter after a random delay within a configurable `[min, max]` range. Makes the board feel alive and adds pressure/opportunity — a block you were ignoring might become the letter you need, or vice versa.

**Design questions to answer before building:**
- Min/max range? (e.g. 5s–15s, 10s–30s?)
- Does the timer reset on pickup/shoot, or run independently?
- Visual tell — brief glow, spin animation, or just a swap?
- Should cycling be per-block (each has its own timer) or wave-based (all swap at once)?
- Does the letter distribution weight toward common letters or stay uniform?
- Any blocks that should never cycle (e.g. a block the player is targeting/buffering)?

**Related systems:** `LetterBlock`, `BlockSpawner`
**Wiki pages:** `wiki/systems/LetterBlock.md`, `wiki/systems/BlockSpawner.md`

---

## Shipped Ideas

*(moved here once implemented)*

