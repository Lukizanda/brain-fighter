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

## Aiming — screen space vs viewport space

Roblox has two mouse coordinate spaces that differ by the GUI inset, and two matching `Camera` methods. **Pairing them wrong does not fail loudly — it tilts the ray.**

| Source of the point | Space | Correct method |
|---|---|---|
| `InputObject.Position`, `Mouse.X`/`Mouse.Y` | inset-adjusted (measured below the topbar) | `Camera:ScreenPointToRay` |
| `UserInputService:GetMouseLocation()` | raw viewport | `Camera:ViewportPointToRay` |

[[systems/LetterBlaster]] used the second pair and was correct. `BlockTapController` kept its `ViewportPointToRay` line but changed where the point came from — `input.Position`, needed because touch has no cursor to read — and inherited a constant vertical offset of one GUI inset.

**Why this presented as a range limit.** The offset is in pixels at the screen, so it becomes an *angle* at the camera and the miss grows linearly with distance. Measured on a 1027×601 viewport at 70° FOV: a 58 px inset is **7.7° of aim error**, or **0.135 studs of miss per stud of range**.

| Range | Miss |
|---|---|
| 30 studs | 4.0 studs |
| 100 studs | 13.5 studs |
| 320 studs | 43.2 studs |

A letter block is about 4 studs across, so taps landed only within ~30 studs and everything past that felt like a wall. Raising `MAX_RAYCAST_DISTANCE` could not move that wall, because the ray was never pointed at the block in the first place.

Confirmed against the engine's own `Mouse.Hit` as ground truth — `ScreenPointToRay(input.Position)` agrees to **0.00 studs**, `ViewportPointToRay(input.Position)` does not — and end-to-end in a playtest: aiming at each on-screen block's true screen point, the buggy pairing hit **0 of 40** and the fixed pairing hit **18 of 40**, the remaining 22 being genuinely occluded by an opaque union in the spawn zone. A real synthetic click then popped a block at **303 studs** against a 9 px target.

**The lesson worth carrying:** an aim error that scales with distance is indistinguishable from a range cap by feel alone. When a range complaint survives a range change, stop tuning the range.

## Hover affordance

One `Highlight`, client-local, under the local player's `PlayerGui` — never replicated, so it is private to that player by construction rather than by convention. Three states, resolved every `RenderStepped`:

| State | Look | Means |
|---|---|---|
| Ready | block's tint as fill, **white** outline, opaque | a click here pops it |
| Denied | grey `#9ca3af`, dimmer in both channels | out of reach, or the mind is full |
| Off | disabled | not pointing at a block |

**Why one highlight and not one per reachable block.** Roblox renders a bounded number of `Highlight` instances — guidance is to stay under ~31 — and the arena holds 40 blocks, so glowing every reachable one exceeds the budget and drops outlines unpredictably. It is also noise. The question is only ever about the block under the cursor.

**The probe deliberately overshoots reach** (`HOVER_PROBE_MULTIPLIER`). Stopping at reach would return no hit for a too-far block, making it indistinguishable from pointing at the sky; overshooting lets the affordance say "that is a block, and it is too far" — which is its whole job now that reach is shorter than the arena. Range is judged on `result.Distance` against `MAX_RAYCAST_DISTANCE`, the same measure along the same ray the tap uses, so the outline greys out on exactly the blocks a click would fail to reach.

**The outline colour is not the block's colour, and that is deliberate.** The first build tinted both fill and outline with the block's tint; it is invisible, because an outline in the block's own colour has zero contrast against the block — and it fails on all four tints at once, since every tint is by definition the colour of the block wearing it. Every property assertion passed. Only a screenshot caught it. White is the one colour that separates from red, green, blue and gold and from the arena floor behind them. This is the same verification rule VFX is held to in `CLAUDE.md`: presentation is verified by what a client renders, not by what the code set.

Mouse only, gated on `UserInputService.MouseEnabled`. A finger has no position until it is already tapping, by which point the highlight would be reporting a decision the player has already made.

## Showing the consume

A validated consume ends in `broadcastPop`, which fires **two** cosmetics on one round trip:

| Cosmetic | Call | What it says |
|---|---|---|
| Pop burst | `VfxBroadcast.playAt(resolveBlockPopId(color), pos)` | a block was taken, and what colour it was |
| Collect stream | `VfxBroadcast.collect(pos, userId)` | **who** took it — the ribbon terminates on their body |

Both read the block *before* `model:Destroy()`: the burst needs the position it stood at, the stream needs its colour, and neither is recoverable from a destroyed Model.

The stream is the PvP attribution cue and it replaces the blaster beam. The beam said *where a shot came from*; this says who got it and which colour they banked — deliberately leaking that read, because "red has been flowing into them for ten seconds" is a tactical tell worth having.

**The stream's destination is a `collectorUserId`, not a position.** A `Vector3` is right for `beam` (a laser is instantaneous) and wrong here, because the collector is *running* during the flight — a frozen endpoint funnels into the ground where they used to be. An Instance would hit the nil-arrival race and break on respawn. The userId is re-resolved per client per frame, and failing to resolve mid-flight simply ends the stream. Verified against a moving collector: over 25 frames while the character travelled 19.2 studs, the endpoint-to-HumanoidRootPart gap stayed at **0.00 studs**. A stationary test passes even with the bug, so test this moving.

**The two cosmetics are broadcast differently, and the split is the point.**

The **burst** excludes the popper (`drawnLocallyBy`), who predicts it on the frame they click. Safe to predict because it stays true even when they lose the race — the block popped either way, just for somebody else.

The **stream** goes to everyone *including* the popper, who deliberately does **not** predict it. It is an attribution claim — "that letter came to me" — which is the same class of thing as a hit marker, and [[systems/CastAction]]'s prediction contract forbids this layer from asserting one. Drawing it only from the server's confirmed branch means a player who loses a race never sees a stream flow into them for a letter they did not get, with no cancellation logic needed.

Cost is bounded by a concurrent-stream cap (`VfxConfig.PERF.maxBlockPops`), not by duration: flight is deliberately longer than the tap cooldown so a fast speller has two streams in the air, which is the correct read rather than a defect.

### Stream layers, and the order they degrade in

| Layer | Role | Dropped when |
|---|---|---|
| Ribbon (`Beam`) | The cue itself. Tracks the collector for free, because a Beam between two live Attachments follows both ends with no per-frame code. | Never — only the whole-stream cap |
| Motes | The block's mana visibly coming apart and being drawn in. Flavour, not information. | Origin beyond `MOTE_VISIBLE_DISTANCE`; thinned 8 → 3 as concurrent streams approach the cap |
| Arrival shrink | Motes taper to a quarter size so the cloud enters the collector rather than piling on their chest. | With the motes |

Losing motes costs flavour; losing the ribbon costs information — hence the order. Thinning is proportional rather than a threshold: a fight that quietly loses half its sparkles still reads correctly, whereas streams that randomly do or don't have motes reads as a bug. **The local player's own stream is exempt** from both the distance cull and the thinning — it is one stream, it is the feedback for their own input, and it is the one they are looking at.

Every mote rides a quadratic Bézier whose endpoint is re-read each frame from the collector's HumanoidRootPart, for the same reason the payload carries a userId: a curve baked at spawn arcs gracefully into empty ground. Per-mote flight is jittered **shorter** only, never longer — the stream is torn down when the ribbon lands, so a longer mote would be destroyed mid-air short of its target.

All of it runs on **one** `Heartbeat` connection per stream, not one per mote — at eight motes across a dozen streams, per-mote scheduling would mean ~100 independent schedules for a 0.4 s effect. Same single-driver shape [[systems/LetterBlock]]'s animator uses for the whole block field.

Measured on a moving collector: 8 motes peak, alive across 24 frames, 34 distinct sizes in flight (stagger and shrink both live), closest approach to the HumanoidRootPart 0.27 studs, and zero instances left behind afterwards.

## MindFull gate

When the buffer hits 12/12, [[systems/MindFullManager]] fires `mindFull`. `BlockTapController` simply polls `:isMindFull()` on each input — no signal wiring needed because the check is cheap and the gate is checked exactly once per event (a refused tap plays the client-local fizzle cue). When the player removes tiles or memorizes a word, the buffer shrinks and `:isMindFull()` returns false, re-enabling input.

## Contested blocks — the optimistic append and its rollback

The `WordBuffer:append` at step 5 happens **before** the remote fires. The server half of the race has always worked for free (check 3 below: the first `Destroy` unparents the block, so the second request fails validation). The client half did not — nothing told it a consume had been refused, so the loser of a same-frame race for one block kept a **phantom letter** for the rest of the round, occupying a slot and eventually paying out energy on Memorize. Unreachable in solo play, routine in PvP. Closed in Phase 5.7 stage 4.

**The reply carries a client-minted request id, not the block.** Echoing the block is the obvious design and it fails exactly where it matters: the rejection that matters most is losing a race, and by then the winner has already destroyed that block — an Instance reference to a destroyed object is the same nil-arrival trap [[systems/VisualEffects]]' `playOn` documents, so the rollback would no-op in the one case it exists for. A number always survives the trip. The id is opaque to the server: type-checked, echoed, never used for a lookup, and returned only to the player who sent it.

**Rollback removes the last tile matching (letter, colour)** via `WordBuffer:removeLastMatching`, and each part of that is load-bearing:

- Not `remove(size())` — the round trip is long enough for the player to have tapped two more blocks, and popping the newest slot would confiscate a letter they *did* earn.
- Not the remembered index either — `reorder` and `remove` shuffle indices, so a stored index goes stale the moment the player touches their buffer.
- Last-matching rather than first, because appends land at the end. Once the player has reordered, two tiles of the same letter and colour are genuinely indistinguishable (the buffer has no tile identity), so the newest match is the best available guess.
- No match is a **no-op**, not an error: the player may have destroyed the tile themselves before the rejection landed, and eating an innocent letter would be strictly worse.

Verified live end-to-end: buffer `[N,Y]`, two more taps → `[N,Y,W,T]`, reject the **W** (the older of the pair, not the newest) → `[N,Y,T]`. Plus six unit cases in `WordBuffer/__tests.luau` covering colour matching, duplicates, no-match, empty buffer, and the `changed` signal firing only on a real removal.

Unanswered entries expire after `PENDING_TTL_SEC` (10 s), since the server replies only on refusal — an ack per success would double this remote's traffic on the most frequent action in the game to carry one bit that is almost always "fine". A rejection arriving after expiry is logged rather than silent; if that ever appears in real play the TTL is too short for the round trip.

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

`MAX_CONSUME_DISTANCE_STUDS` = `BlockShoot.MAX_RAYCAST_DISTANCE` (1400) + 100. The client raycasts from the *camera*, which sits behind the character, so the camera-to-character gap has to be added back or a legitimate long tap would be rejected. The allowance does not scale with reach — it is a property of the camera rig.

### Reach

`MAX_RAYCAST_DISTANCE` is **200**. It went 200 → 1400 on 2026-08-10 and back the same day. The old value could not cross the arena: the `BlockSpawnVolume` parts span **240 × 259 studs** (floor diagonal ~353), and a live measurement put the farthest block **320 studs** from the player — past the 200-stud raycast *and* past the old 300-stud server bound. The far half of the field was out of range.

> **The raise was reverted the same day, and the reasoning is the useful part.** Reach was a real ceiling but not the binding one: the aim bug in § Aiming capped effective reach at ~30 studs regardless of this constant, so every value of it felt identical. A 7× increase producing no felt difference was the evidence that the constant was not the cause. Once aim was fixed, the reason for the raise evaporated and it went back to **200** — LetterBlaster's original value.

Reach is tuned in exactly one place; the server bound and the Hardening suite's out-of-range fixture both derive from it.

**200 is deliberately shorter than the arena.** The field is ~353 studs corner to corner and the farthest block measured 320 studs out, so the far edge is out of reach by design: you close on blocks rather than clearing the map from spawn. Two things follow from keeping reach under the arena size — the 300-stud server bound stays a real anti-grief limit (an exploiter firing the remote directly can clear blocks near themselves but not across the map), and taps stay inside the range where a block is a large enough target to hit.

**Target size is what limits any future raise.** A 4-stud block subtends about `4 / distance × (viewportY / 2tan(fov/2))` pixels — measured at **5.4 px at 320 studs**, under 3 px by ~500, roughly 1 px at 1400. So reach past a few hundred studs is not usable range without a bigger target or a hover-snap, which is the argument for the Phase 5.7 stage 5 hover highlight: its job is "let you hit something small", not "show you where the limit is".

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
