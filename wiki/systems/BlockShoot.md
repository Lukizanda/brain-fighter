---
type: system
description: Shared helpers and server handler for block consumption. Client input is handled by LetterBlaster (Phase 4.6) — see [[systems/LetterBlaster]]. Server-trust validation added in 5.4.
updated: 2026-08-03
---

# BlockShoot

Shared library and server handler for the letter-block consume pipeline. The client-side input wiring (Phase 3: `BlockShootBoot`) was replaced in Phase 4.6 by the [[systems/LetterBlaster]] Tool — see that page for the current input flow. This page covers the shared helpers and server handler, which are unchanged.

## Files

- `src/shared/BlockShoot/init.luau` — shared helpers: `findLetterBlock` (ancestor traversal), `readBlock` (attribute reader), `MAX_RAYCAST_DISTANCE` constant.
- `src/shared/BlockShoot/Remotes/ConsumeBlock.model.json` — RemoteEvent for client→server block destruction.
- `src/server/BlockShoot/BlockShootService.server.luau` — server handler: validates the payload, destroys the block (triggers BlockSpawner auto-refill).
- `src/server/BlockShoot/BlockShootConstants.luau` — trust thresholds, each derived from a client-side number rather than picked.
- `src/server/BlockShoot/BlockShootValidation.luau` — `checkBlock` / `checkRange` predicates, split out so the Hardening suite can drive them without a live remote fire.
- `src/server/Utility/RateLimiter.luau` — shared per-key token bucket (also used by [[systems/SpellCastService]]).
- `src/client/PlayerSession.luau` — ModuleScript: lazy-creates and caches the player's WordBuffer + MindFullManager + EnergyReservoirs.

> **Phase 4.6:** `src/client/BlockShootBoot.client.luau` was deleted. The `ConsumeBlock` remote is now fired by [[systems/LetterBlaster]].

## Flow

The input side now runs inside the [[systems/LetterBlaster]] controller (`LetterBlaster:_onActivated`); the steps below describe the end-to-end consume path. Only steps 4–8 (the helpers + server handler) live in this module.

1. Player activates the Spelling Staff Tool (`Tool.Activated`).
2. `LetterBlaster` checks `MindFullManager:isMindFull()` — blocks the shot when the buffer is at 12/12.
3. Raycast from camera through mouse position, excluding the player's character.
4. If the hit instance is inside a tagged `LetterBlock` Model (ancestor walk via `findLetterBlock`), read `Block.Letter` + `Block.Color` attributes (`readBlock`).
5. `WordBuffer:append(letter, color)` on the local session buffer.
6. Fire `ConsumeBlock` remote to the server with the block Model reference.
7. Server handler validates the payload (rate, Instance, in-workspace, tagged, in-range — see § Trust model) and calls `block:Destroy()`.
8. The `CollectionService` removed signal triggers [[systems/BlockSpawner]]'s auto-refill to maintain target count.

## MindFull gate

When the buffer hits 12/12, [[systems/MindFullManager]] fires `mindFull`. `LetterBlaster` simply polls `:isMindFull()` on each activation — no signal wiring needed because the check is cheap and the gate is checked exactly once per input event (a blocked shot plays `FizzleSound`). When the player removes tiles or memorizes a word, the buffer shrinks and `:isMindFull()` returns false, re-enabling input.

## PlayerSession

`PlayerSession.luau` is a client ModuleScript that lazy-creates and caches the player's per-session state:

| Field | Type | Notes |
|---|---|---|
| `wordBuffer` | `WordBuffer` | 12-slot buffer |
| `mindFullManager` | `MindFullManager` | Transition watcher over the buffer |
| `energyReservoirs` | `EnergyReservoirs` | 3-color energy store (consumed by MemorizeAction + CastAction) |

Any client system that needs player state calls `PlayerSession.get()` rather than constructing its own — the HUD gameplay widgets (BufferDisplay, MemorizeButton, SpellMenu) and LetterBlaster all share this one instance.

## Trust model

Hardened in Phase 5.4 for the public soft launch. Before that the handler destroyed whatever Model the client named, as fast as the client asked — enough for a client to clear the arena of every other player's blocks in one loop.

Checks run in this order, cheapest and most-abused first. Every failure drops the request and logs; nothing throws, so a malformed payload can never take the handler down for other players.

| # | Check | Rejects |
|---|---|---|
| 1 | `RateLimiter:consume(player)` | Loops with no fire cooldown |
| 2 | `validateInstance(block, "Model")` | A table wearing a Model's property names, primitives, `nil` |
| 3 | `block:IsDescendantOf(workspace)` | The `LetterBlocks.Template` in ReplicatedStorage; an already-consumed block |
| 4 | `CollectionService:HasTag(block, "LetterBlock")` | Any other world Model — griefing the boss, NPCs, scenery |
| 5 | `checkRange(character, block)` | Blocks beyond `MAX_CONSUME_DISTANCE_STUDS` of the firer |

Check 3 also makes a double-consume race a no-op for free: the first `Destroy` unparents the block, so the second request fails the check rather than needing a claimed-set.

### Tuning

`MAX_CONSUME_DISTANCE_STUDS` = `BlockShoot.MAX_RAYCAST_DISTANCE` (200) + 100. The client raycasts from the *camera*, which sits behind the character, so the camera-to-character gap has to be added back or a legitimate long shot would be rejected. The reference arena is 40×40, so the whole bound is headroom.

The rate limit is a token bucket, not a flat interval: network jitter routinely bunches two legitimately-spaced fires into one frame, so a flat interval rejects real play. Sustained rate is exactly `1 / LetterBlasterConfig.COOLDOWN`, with a 3-fire burst allowance for the jitter. Verified both ways — see [[systems/Tests]] § Hardening.

### What this does not cover

These are instance-level checks. They bound *what* a client may destroy and *how fast*; they cannot verify the letter actually reached that player's word buffer, because [[systems/WordBuffer]] and [[systems/EnergyReservoirs]] both live client-side. The same gap is what blocks server-side affordability on the cast remote — see [[systems/SpellCastService]] § Trust model.

## See also

- [[systems/LetterBlock]] — the entity BlockShoot consumes.
- [[systems/BlockSpawner]] — auto-refills when blocks are destroyed.
- [[systems/WordBuffer]] — destination for consumed tiles.
- [[systems/MindFullManager]] — input gate when buffer is full.
- [[design/gameplay-loop]] — "Buffer & input" section.
