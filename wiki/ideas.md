---
title: Ideas Scrapbook
updated: 2026-11-13
---

# Ideas Scrapbook

Raw ideas, shower thoughts, and playtest observations. No commitment to build — just a place to capture before they disappear.

---

## Open Ideas

### Toppling spire
*Captured: 2026-11-13, from the boss-arena mechanics ideation*

When a spire on the boss island takes enough damage it falls instead of vanishing. It falls away from the boss, crushes anyone on that side, then lies across the ground as a long low wall for the rest of the round. The tallest cover gains a late-fight cost, and the arena reshapes without boss phases.

**Design questions to answer before building:**
- Which spire? Two of the three frame the arrival view, so probably only the third.
- Is the crack readable as a warning, or does a crushed player blame the game?
- Co-op: a player can drag the boss so a spire falls on a teammate.
- A broken wall turns its collision off, so the fallen spire has to be a separate pre-placed part.

**Wait for:** the friends' playtest, to see whether players use the spires at all.

**Related systems:** `BreakableWalls`
**Wiki pages:** `wiki/design/boss-arena.md` § Mechanics ideation

---

### Riddle stone
*Captured: 2026-11-13, from the boss-arena mechanics ideation*

A carved standing stone in the open mid-field shows a short challenge: "a word with a Z", "a 6-letter word", "a word starting with B". Memorizing a qualifying word while standing near it makes the stone strike the boss, then it shows a new challenge. The strongest spelling tie of the ideation's twelve ideas, and the most educational.

**Design questions to answer before building:**
- The challenge pool must be broad enough that the field always holds the letters.
- Can a young player parse "starts with B" under fire?
- Co-op: the first player to answer takes it.
- It hands out a word-shaped reward, which overlaps the cave's ready-made word.

**Wait for:** real players' vocabularies, to tune the challenge pool.

**Related systems:** `WordMemorized` event, `Boss`
**Wiki pages:** `wiki/design/boss-arena.md` § Mechanics ideation

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

### Spell name label above the charge orb — **shipped 2026-08-12**

Captured and built the same day. The spell name came off the cast panel when it became a circle; it now lives on a `BillboardGui` over the [[systems/ChargeCast]] charge orb, popping in on each tier crossing and dissipating on release. Remote observers get it for nothing, because `ChargeOrbVfx.setTier` resolves the name from the entry's own colour and the controller already drives that off the replicated attributes.

The weakness recorded when it was filed **still stands and was not solved**: an orb only exists *during* a charge, so this tells you what you are about to fire but cannot teach you the roster before you press. The legend problem is still open and still belongs to [[systems/Tutorial]].

