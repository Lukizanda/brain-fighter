---
type: design
description: Phase 5.4 release-gate item "game page assets" — draft store description (short + long), icon concept, a three-shot thumbnail list with Studio camera positions, and the upload path (Creator Dashboard; no Open Cloud route for icon/thumbnails). Drafts written 2026-09-20; nothing uploaded yet.
updated: 2026-09-20
---

# Game Page — icon, thumbnails, description

Phase 5.4 ([[design/build-plan]]) lists "game page assets" as a release-gate
item with no content behind it. This page holds the drafts so the upload is a
paste, not a writing session. Nothing here is uploaded; the user picks a
description variant and shoots or approves the thumbnails.

## Description

Roblox caps the description at 1000 characters and shows the first ~150 in
search. The first sentence has to carry the premise on its own.

### Short (search snippet, ≤ 150 chars)

> Shoot letter blocks, spell words, cast the spell. Fight the boss with
> friends or duel 1v1 — the better speller wins.

### Long (≤ 1000 chars) — variant A, verb-first

> **Spell it to cast it.**
>
> Pop floating letter blocks to fill your word buffer, memorize a real word
> to turn it into energy, then cast colour-typed spells — fire, frost, heal,
> shields, stone walls. Longer and rarer words hit harder.
>
> **Boss Fight** — team up in the arena and bring down the boss before the
> clock runs out.
> **Duel** — step onto a pad, first to 3 kills wins. The pool of words is the
> same for both of you.
>
> Practice in the hub, then walk through a portal. No menus, no loadouts, no
> pay-to-win: your vocabulary is the weapon.

### Long — variant B, hook-first

> **Your vocabulary is the weapon.**
>
> Brain Fighter is a third-person spelling shooter. Letter blocks drift
> through the arena — pop them, arrange them into a word, memorize it for
> energy, and cast. Every word is a spell; every spell has a colour; the
> bigger the word, the bigger the blast.
>
> Fight the boss co-op, or queue for a 1v1 duel where the faster speller
> wins. Walk to a portal to pick — the hub is a practice range with live
> blocks and a target dummy, so you learn by doing.
>
> Made for players who like words as much as winning.

Pick one; the other's first line can become a thumbnail caption.

## Icon (512 × 512)

Concept: a single oversized letter block in the [[design/ArtDirection]]
chunky-lowpoly style — one face showing a letter, cracked, with the colour of
its spell type glowing from the crack. Reads at 64 px because it is one shape
and one accent colour. Avoid text beyond the letter; the title sits under the
icon on the page.

Two routes:

1. **Studio render.** Isolate one `LetterBlock` prefab, neutral backdrop,
   `screen_capture` at a 3/4 angle, then crop and upscale. Cheapest and on
   brand by construction.
2. **Meshy / image model** from the render as reference, the way
   `tools/weapon_icon.py` produces weapon icons. Use only if route 1 reads
   muddy at 64 px.

## Thumbnails (1920 × 1080, up to 5; three planned)

All three from Studio in Edit mode with `screen_capture(camera_position,
look_at_position)`, blocks spawned (run a playtest first if the volumes are
empty in Edit). Coordinates are the scene's authored origins.

| # | Subject | Camera → look at | Caption |
|---|---|---|---|
| 1 | **Arena, mid-cast** — player character facing the boss with a projectile or wall in flight, letter blocks in the air | from `(300, 225, 70)` → `(257, 206, 26)` (arena spawn / bridge) | "Spell it to cast it" |
| 2 | **The hub** — both portal arches with signs lit, practice blocks, target dummy | from `(-600, 240, 120)` → `(-600, 205, 28)` | "Walk to a portal. Boss fight or duel." |
| 3 | **Duel pad** — two characters at opposite spawn pads, blocks between them | from `(-1000, 235, -90)` → `(-1000, 205, -150)` (`Duel1`) | "First to 3 kills" |

Shots 1 and 3 need two characters posed; do them in a **Start (2 Players)**
local server and capture from the client window, or pose R15 dummies in Edit
mode. Server-side VFX do not render, so any spell effect in frame must be
captured from a client ([[design/client-server-boundary]]).

## Upload path

Icon, thumbnails and description are set in **Creator Dashboard → the
experience → Basic Settings**. There is no Open Cloud endpoint for the icon or
thumbnails; the Decal upload in `tools/weapon_icon.py` is for in-game assets
and does not apply here. If the dashboard rejects an image, the usual causes
are aspect ratio (thumbnails must be exactly 16:9) and text that moderation
reads as a link.

## Checklist

- [ ] Description variant chosen, pasted, saved
- [ ] Icon captured or generated, 512 × 512, uploaded
- [ ] Thumbnails 1–3 captured from a client, 1920 × 1080, uploaded with captions
- [ ] Genre set (Fighting or Shooter — Roblox has no "word game")
- [ ] Age recommendation questionnaire answered (mild fantasy violence)
- [ ] Row in [[design/build-plan]] Phase 5.4 ticked
