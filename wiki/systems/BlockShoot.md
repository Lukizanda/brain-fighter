---
type: system
description: Shared helpers and server handler for block consumption. Client input is BlockTapController (Phase 5.7 — click/tap a block directly). Server-trust validation added in 5.4 and unchanged by the input migration.
updated: 2026-08-10
---

# BlockShoot

Shared library and server handler for the letter-block consume pipeline. The input side has moved twice: Phase 3's `BlockShootBoot` → Phase 4.6's [[systems/LetterBlaster]] Tool → Phase 5.7's `BlockTapController`. **The server handler and its trust model have survived both moves unchanged** — that is the point worth remembering about this module.

## Files

- `src/shared/BlockShoot/init.luau` — shared helpers: `findLetterBlock` (ancestor traversal), `readBlock` (attribute reader), `MAX_RAYCAST_DISTANCE` constant.
- `src/shared/BlockShoot/BlockTapConfig.luau` — `COOLDOWN` (0.25 s), read on both VMs.
- `src/shared/BlockShoot/Remotes/ConsumeBlock.model.json` — RemoteEvent for client→server block destruction.
- `src/client/BlockTapController.client.luau` — client input: always mounted, no Tool required.
- `src/server/BlockShoot/BlockShootService.server.luau` — server handler: validates the payload, destroys the block (triggers BlockSpawner auto-refill).
- `src/server/BlockShoot/BlockShootConstants.luau` — trust thresholds, each derived from a client-side number rather than picked.
- `src/server/BlockShoot/BlockShootValidation.luau` — `checkBlock` / `checkRange` predicates, split out so the Hardening suite can drive them without a live remote fire.
- `src/server/Utility/RateLimiter.luau` — shared per-key token bucket (also used by [[systems/SpellCastService]]).
- `src/client/PlayerSession.luau` — ModuleScript: lazy-creates and caches the player's WordBuffer + MindFullManager + EnergyReservoirs.

> **Phase 5.7:** `resolveHandle` and `muzzlePosition` were deleted with the staff — they existed so both VMs could agree where a beam left a prop. `LetterBlasterConfig` became `BlockTapConfig`.

## Flow

Steps 1–3 live in `BlockTapController`; 4–8 are this module.

1. Player clicks or taps (`UserInputService.InputBegan`, `MouseButton1` or `Touch`). **Input over GUI is dropped via `gameProcessedEvent`** — see below.
2. Cooldown gate, then `MindFullManager:isMindFull()` — refuses when the buffer is at 12/12, and a living-character check.
3. Raycast from camera through the tap position, excluding the player's character.
4. If the hit instance is inside a tagged `LetterBlock` Model (ancestor walk via `findLetterBlock`), read `Block.Letter` + `Block.Color` attributes (`readBlock`).
5. `WordBuffer:append(letter, color)` on the local session buffer.
6. Fire `ConsumeBlock` remote to the server with the block Model reference.
7. Server handler validates the payload (rate, Instance, in-workspace, tagged, in-range — see § Trust model) and calls `block:Destroy()`.
8. The `CollectionService` removed signal triggers [[systems/BlockSpawner]]'s auto-refill to maintain target count.

## `gameProcessedEvent` is load-bearing

`Tool.Activated` used to suppress clicks that landed on GUI for free. A raw `InputBegan` handler does not, and this game's mouse is unlocked during play with a click-driven HUD — the spell buttons, the dash button, the buffer's tap-to-swap slots. Without the guard, **every spell cast would also pop whatever block happened to be behind the button**.

Verified by A/B with the GUI as the only variable: an input-consuming button placed over a known block gave `gameProcessed = true` and left the block standing; the identical click with the button removed gave `false` and popped it.

## Alive check

`BlockTapController` requires a character with a `Humanoid` above 0 HP. Holding the staff was an implicit gate — a corpse has no equipped Tool, so `Tool.Activated` could not fire. A global handler has no such gate, and without the check a dead player clicking would spend rate-limit budget on consumes the server can only reject.

## Showing the consume

A validated consume ends in `broadcastPop`, which fires **two** cosmetics on one round trip:

| Cosmetic | Call | What it says |
|---|---|---|
| Pop burst | `VfxBroadcast.playAt(resolveBlockPopId(color), pos)` | a block was taken, and what colour it was |
| Collect stream | `VfxBroadcast.collect(pos, userId)` | **who** took it — the ribbon terminates on their body |

Both read the block *before* `model:Destroy()`: the burst needs the position it stood at, the stream needs its colour, and neither is recoverable from a destroyed Model.

The stream is the PvP attribution cue and it replaces the blaster beam. The beam said *where a shot came from*; this says who got it and which colour they banked — deliberately leaking that read, because "red has been flowing into them for ten seconds" is a tactical tell worth having.

**The stream's destination is a `collectorUserId`, not a position.** A `Vector3` is right for `beam` (a laser is instantaneous) and wrong here, because the collector is *running* during the flight — a frozen endpoint funnels into the ground where they used to be. An Instance would hit the nil-arrival race and break on respawn. The userId is re-resolved per client per frame, and failing to resolve mid-flight simply ends the stream. Verified against a moving collector: over 25 frames while the character travelled 19.2 studs, the endpoint-to-HumanoidRootPart gap stayed at **0.00 studs**. A stationary test passes even with the bug, so test this moving.

`drawnLocallyBy = player.UserId` excludes the popper, who drew both on the frame they clicked. That exclusion is only safe because the client's draw sits on the same branch that fires the remote, below the buffer check — a rejected append must never draw a burst no other player can have a match for.

Cost is bounded by a concurrent-stream cap (`VfxConfig.PERF.maxBlockPops`), not by duration: flight is deliberately longer than the tap cooldown so a fast speller has two streams in the air, which is the correct read rather than a defect.

## MindFull gate

When the buffer hits 12/12, [[systems/MindFullManager]] fires `mindFull`. `BlockTapController` simply polls `:isMindFull()` on each input — no signal wiring needed because the check is cheap and the gate is checked exactly once per event (a refused tap plays the client-local fizzle cue). When the player removes tiles or memorizes a word, the buffer shrinks and `:isMindFull()` returns false, re-enabling input.

## Known gap — the optimistic append

The `WordBuffer:append` at step 5 happens **before** the remote fires, and nothing tells the client if the server rejected it. In solo play that is safe: nobody else can take your block. In PvP the loser of a same-frame race for one block keeps a **phantom letter** for the rest of the round — a letter they never got, occupying a slot and eventually paying out energy on Memorize.

The server half already handles the race correctly and for free (check 3 below). The client half does not. Closing it is Phase 5.7 stage 4.

## PlayerSession

`PlayerSession.luau` is a client ModuleScript that lazy-creates and caches the player's per-session state:

| Field | Type | Notes |
|---|---|---|
| `wordBuffer` | `WordBuffer` | 12-slot buffer |
| `mindFullManager` | `MindFullManager` | Transition watcher over the buffer |
| `energyReservoirs` | `EnergyReservoirs` | 3-color energy store (consumed by MemorizeAction + CastAction) |

Any client system that needs player state calls `PlayerSession.get()` rather than constructing its own — the HUD gameplay widgets (BufferDisplay, MemorizeButton, SpellMenu) and `BlockTapController` all share this one instance.

## Trust model

Hardened in Phase 5.4 for the public soft launch. Before that the handler destroyed whatever Model the client named, as fast as the client asked — enough for a client to clear the arena of every other player's blocks in one loop.

Checks run in this order, cheapest and most-abused first. Every failure drops the request and logs; nothing throws, so a malformed payload can never take the handler down for other players.

| # | Check | Rejects |
|---|---|---|
| 1 | `RateLimiter:consume(player)` | Loops with no tap cooldown |
| 2 | `validateInstance(block, "Model")` | A table wearing a Model's property names, primitives, `nil` |
| 3 | `block:IsDescendantOf(workspace)` | The `LetterBlocks.Template` in ReplicatedStorage; an already-consumed block |
| 4 | `CollectionService:HasTag(block, "LetterBlock")` | Any other world Model — griefing the boss, NPCs, scenery |
| 5 | `checkRange(character, block)` | Blocks beyond `MAX_CONSUME_DISTANCE_STUDS` of the tapper |

Check 3 also makes a double-consume race a no-op for free: the first `Destroy` unparents the block, so the second request fails the check rather than needing a claimed-set. This is the half of the PvP contention problem that already works — see § Known gap for the half that does not.

### Tuning

`MAX_CONSUME_DISTANCE_STUDS` = `BlockShoot.MAX_RAYCAST_DISTANCE` (200) + 100. The client raycasts from the *camera*, which sits behind the character, so the camera-to-character gap has to be added back or a legitimate long shot would be rejected. The reference arena is 40×40, so the whole bound is headroom.

The rate limit is a token bucket, not a flat interval: network jitter routinely bunches two legitimately-spaced taps into one frame, so a flat interval rejects real play. Sustained rate is exactly `1 / BlockTapConfig.COOLDOWN`, with a 3-tap burst allowance for the jitter. Verified both ways — see [[systems/Tests]] § Hardening.

`BlockTapConfig.COOLDOWN` has three consumers, which is why it is one constant and not three: this rate limiter, the Hardening suite, and `SpellCastConstants.CAST_REFILL_PER_SEC` — the spell-cast flood guard is derived from the block cooldown because energy only enters a reservoir via popped blocks.

### What this does not cover

These are instance-level checks. They bound *what* a client may destroy and *how fast*; they cannot verify the letter actually reached that player's word buffer, because [[systems/WordBuffer]] and [[systems/EnergyReservoirs]] both live client-side. The same gap is what blocks server-side affordability on the cast remote — see [[systems/SpellCastService]] § Trust model.

## See also

- [[systems/LetterBlock]] — the entity BlockShoot consumes.
- [[systems/BlockSpawner]] — auto-refills when blocks are destroyed.
- [[systems/WordBuffer]] — destination for consumed tiles.
- [[systems/MindFullManager]] — input gate when buffer is full.
- [[design/tap-to-pop]] — Phase 5.7: the input migration, the pop + collect stream, and the contested-block fix.
- [[systems/LetterBlaster]] — the removed Tool that owned input from 4.6 to 5.7.
- [[design/gameplay-loop]] — "Buffer & input" section.
