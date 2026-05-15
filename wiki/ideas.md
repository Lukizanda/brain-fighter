---
title: Ideas Scrapbook
updated: 2026-05-15
---

# Ideas Scrapbook

Raw ideas, shower thoughts, and playtest observations. No commitment to build — just a place to capture before they disappear.

---

## Open Ideas

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

