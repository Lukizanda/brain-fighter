---
type: status
description: Input handler that consumes a clicked/shot letter-block and appends its (letter, color) to the WordBuffer. Phase 3 — not yet implemented.
updated: 2026-05-14
---

# BlockShoot — Phase 3 (pending)

> **Status: not yet implemented.** This page is a forward declaration so the planning references resolve. Scheduled for Phase 3 per [[design/build-plan]] (after [[systems/LetterBlock]] template).

The input handler that turns "player aimed at a letter block and clicked" into a `(letter, color)` tile appended to the player's [[systems/WordBuffer]]. It owns:

- Hit detection on tagged `LetterBlock` Models (raycast or `Touched` — TBD during implementation).
- Reading `Block.Letter` and `Block.Color` attributes off the hit Model.
- Calling `:append(letter, color)` on the player's WordBuffer.
- Destroying the consumed block.
- Subscribing to [[systems/MindFullManager]]'s `mindFull` / `mindFreed` signals to gate input (no shoot when the mind is full; restored when the buffer drains).

## Inputs (planned)

- Mouse click + crosshair raycast (desktop), tap (mobile).
- The `Workspace.LetterBlock` collection — every block tags itself via `CollectionService` (see [[systems/LetterBlock]]).
- `MindFullManager` `mindFull` / `mindFreed` BindableEvents.

## Outputs (planned)

- `WordBuffer:append(letter, color)` per successful hit.
- `block:Destroy()` after a successful consume.
- Diegetic fizzle feedback when input is gated by `mindFull` (greyed crosshair, "buffer full" SFX).

## Open questions

- Hit detection model: raycast (consistent with [[systems/Weapon]] firearms) vs `ProximityPrompt` (cheaper but UX is different). Probably raycast, to match the rest of the shoot stack.
- Cooldown: per-block, per-input, or none? Likely none — `mindFull` is the natural rate-limit.

## See also

- [[design/build-plan]] — Phase 3 sequence.
- [[systems/LetterBlock]] — the entity BlockShoot consumes.
- [[systems/WordBuffer]] — the destination for consumed tiles.
- [[systems/MindFullManager]] — input gate.
