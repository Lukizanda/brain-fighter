---
type: design
description: Migration plan for retiring the Spelling Staff / LetterBlaster and replacing it with direct click/tap-to-pop on letter blocks, plus a client-local hover affordance (planned as an in-range glow; see stage 5 for why it shipped as a single hover outline). Phase 5.7.
updated: 2026-08-10
---

# Tap-to-Pop migration

Retire the **Spelling Staff** Tool and the `LetterBlaster` controller. The player
clicks or taps a letter block and it pops — no weapon, no beam, no equip step.

## Why

The staff was Phase 4.6's answer to "the raw `InputBegan` handler needs a home".
It gave the input a Tool to hang off, a mesh, three sounds and a laser beam. What
it did not give was a reason for the weapon to exist: there is no aiming skill,
no reticle (by design), no ammo, no alternate fire, and nothing else in the game
is shot. The staff is a wrapper around "click the thing you want".

It also costs real complexity:

- **A boot dependency chain no other input has.** `StarterPack` → `Backpack` →
  `Tool.Equipped` → `SpellingStaff.client.luau` → `LetterBlaster:mount()`. With
  `GameConfig.SHOW_BACKPACK = false`, the hotbar is hidden, so a *dev-only*
  server script (`DevAutoEquipTool`, keyed on `GameConfig.DEV_AUTO_EQUIP_TOOL =
  "Spelling Staff"`) exists purely to equip it. Core input in a shipped build
  currently depends on a dev helper firing.
- **A muzzle position that has to agree across two VMs.** `BlockShoot.muzzlePosition`
  / `resolveHandle` and the `Handle` + `Muzzle` constants exist only so the beam
  leaves the right end of a prop.
- **A Studio-managed `Muzzle` attachment** outside the Rojo tree, and a
  duplicated fizzle `SoundId` in `.model.json` that `VfxConfig` has to carry a
  note about (see [[systems/LetterBlaster]] § Fizzle asset).

All of that goes away. What replaces it is smaller than what it replaces.

## Shape of the change

The **server contract does not change.** `ConsumeBlock` still takes one argument
(the block), `BlockShootValidation` still runs the same three checks, and the
rate limiter is still tuned off the input cooldown. This is an input-layer and
presentation-layer migration, not an authority change.

| Layer | Before | After |
|---|---|---|
| Input | `Tool.Activated` (staff equipped) | `UserInputService.InputBegan` — MouseButton1 + Touch, in a client script that is always live |
| Hit test | Camera → mouse raycast, 200 studs | Same raycast, shorter reach (see below) |
| Gate | cooldown → mind-full → raycast | unchanged |
| Prediction | append to `WordBuffer`, draw laser beam | append to `WordBuffer`, draw **pop** at the block |
| Authority | `BlockShootService` validates + destroys | unchanged |
| Presentation (others) | `VfxBroadcast.beam` from muzzle | `VfxBroadcast.playAt("block_pop", pos)` |
| Affordance | none | client-local glow on in-range blocks + hover outline |

### Why ClickDetector was rejected

It is the obvious engine answer and gives free hover cursors and distance
gating, but the server cannot be the authority for a consume: the word buffer is
**client-side**, so a server-side `MouseClick` handler would destroy a block the
client had already refused to buffer (mind full, buffer rejected mid-frame) —
block gone, letter never banked. Keeping `ConsumeBlock` as the confirm step means
the ClickDetector is doing client-only work that a raycast already does, at the
cost of one instance per block and a live risk that the **six SurfaceGui letter
faces** intercept the click before the detector sees it.

## Reach and the in-range affordance

A range limit is only fair if the player can see it. The reach becomes a real
gameplay dial, and every block inside it wears a glow.

- **`TAP_REACH_STUDS` — start at 45.** A dial, not a derived number: the spawn
  region is level-authored (`BlockSpawnVolume`-tagged parts, read by
  `BlockSpawnerService`), so the right value has to come from a playtest against
  the real volume. The bar is "from the middle of the arena most blocks are
  reachable; from a corner the far corner is not".
- **In-range glow.** A `Highlight` per in-range block, `FillTransparency` high
  and `OutlineColor` matched to the block's own tint, so a reachable block reads
  as live without repainting the arena. Client-local, driven off the same
  `CollectionService` tag the animator already tracks.
- **Hover outline.** The block under the cursor gets a stronger outline — one
  reused `Highlight` re-adorned, not one per block.
- **Mind-full state.** When `MindFullManager:isMindFull()`, glows drop to a
  muted/refused colour. The buffer being full is currently only legible on the
  HUD; putting it on the world objects the rule applies to is the point of
  having an affordance at all.
- **Cost control.** Glow membership is recomputed on a throttled tick (~6 Hz),
  not per frame, and only for blocks the animator already has tracked. The
  animator's existing distance buckets (`NEAR_THRESHOLD_STUDS` = 60,
  `FAR_THRESHOLD_STUDS` = 150) are the precedent for this being cheap.

**Ownership:** the glow writes `Highlight` instances; the animator writes pivot,
scale and transparency. Different properties, no conflict with
[[concepts/SingleOwnership]] — but they must be *one* controller if the glow ever
needs to touch scale or colour on the block itself.

## The pop

Replaces the laser beam as the thing that reads as "this happened".

- New `VfxConfig.EFFECTS.block_pop` — a short burst tinted from
  `LetterBlocks.COLOR_TINTS[color]` (the wildcard's gold included), with the
  sound in the effect entry rather than on a Handle. Positional and replicated
  by construction.
- The popping client draws it locally on the frame it clicks (prediction);
  `BlockShootService` calls `VfxBroadcast.playAt` with `drawnLocallyBy =
  player.UserId` so nobody sees it twice. Same three-layer shape the beam
  already uses — the routing is copied, not invented.
- `LetterBlockAnimator.onRemoved` already carries the placeholder comment
  *"Phase C: spawn collect-pop emitter at state.basePosition here"*. Deliberately
  **not** taking that route: it fires for every removal cause (arena reset,
  streaming, shutdown), and distinguishing them needs a flag attribute racing a
  `Destroy`. The broadcast says what happened explicitly, and the beam broadcast
  it replaces makes the traffic change net zero.

## Collect stream — the PvP attribution cue

The beam was the only thing connecting a shooter to a block for *other* players.
With PvP planned, losing that is not acceptable, and a bare pop leaves bystanders
watching blocks vanish for no visible reason. So the pop does not just burst — it
**funnels**: a cloud of block-coloured sparks converges from the block onto the
player who took it.

This is a better cue than the beam it replaces. The beam said *where a shot came
from*. The stream says *who got it, and which colour they banked* — and it says
it by pointing at a person rather than at a line of empty air.

### Payload

New `VfxBroadcast.collect(origin, collectorUserId, opts)` → `kind = "collect"`,
with a matching entry in `WorldVfxController`'s `handlers` table. Fields:
`origin: Vector3`, `collectorUserId: number`, `color: Color3?`,
`drawnLocallyBy: number?`.

**The destination is a userId, not a position and not an Instance.** All three
options are wrong in a different way and the reasoning matters:

- A **Vector3** is what `beam` uses, correctly — a laser is instantaneous and its
  endpoint is a block about to be destroyed. But a stream has a ~0.5 s flight
  during which the collector is *running*. A frozen endpoint funnels into the
  patch of ground where they used to be.
- An **Instance** re-introduces the nil-arrival race `playOn` documents, and
  additionally breaks if the collector dies or respawns mid-flight.
- A **userId** is re-resolved per client, per frame:
  `Players:GetPlayerByUserId` → `.Character` → `HumanoidRootPart`. Resolution
  failing mid-flight is not an error condition — it is the stream ending, which
  is exactly what should happen when its destination stops existing.

The origin stays a Vector3 for the same reason `beam`'s endpoint is one: the
block is already being destroyed.

### The visual, in three layers

Built cheapest-first, so the cue survives load by shedding juice rather than
disappearing.

1. **Ribbon (load-bearing).** One `Beam` between an anchor attachment at the
   block position and an attachment on the collector's `HumanoidRootPart`, with
   `TextureSpeed` flowing toward the collector and `CurveSize0/1` giving it an
   arc. A `Beam` between two live attachments **tracks the moving player with no
   per-frame code at all** — the engine does it. This is the layer that must
   never be dropped.
2. **Motes (the ask).** N small block-coloured parts spawned in a jittered shell
   around the block, each riding a quadratic Bézier to the collector with
   per-mote jitter on duration and control point, so they arrive as a stagger
   rather than a volley. Driven by **one shared `Heartbeat` loop over an array**,
   not N `TweenService` tweens — the same single-driver pattern
   `LetterBlockAnimator` already uses for the whole block field.
3. **Arrival flash.** A short burst on the collector's HRP as the stream lands.
   This is the layer that makes the eye finish on the *person*, which is the
   PvP-relevant half of the information.

### Colour language

The stream and the flash both take the **block's** colour from
`LetterBlocks.COLOR_TINTS`, wildcard gold included. Player identity is carried by
the stream *terminating on that player's body*, not by tinting it.

This is deliberate and it leaks information on purpose: watching red flow into an
opponent for ten seconds tells you a red T4 is coming. That is a real tactical
read and PvP is better for having it. If teams ever need an identity colour, it
goes on the **arrival flash only** — one variable per channel, or the stream
stops being readable as "which reservoir just got fed".

### Budget

This is the one part of the migration with a genuine performance ceiling, and
PvP is where it bites: six players popping at the 0.25 s cooldown is ~24 streams
a second, ~12 concurrent at a 0.5 s flight. At 8 motes each that is ~96 moving
parts. Degradation is staged rather than cliffed:

- Mote count scales down with concurrent stream count (8 → 3 under load).
- Over the concurrent-stream cap, **fall back to ribbon-only** — never drop the
  stream entirely. An attribution cue that vanishes exactly when the fight gets
  busy is worse than no cue, because players learn to trust it first.
- Cull by camera visibility and distance: a stream whose origin and collector are
  both far off-screen draws nothing.
- The popper's own stream is exempt from culling and from the mote scale-down.
  It is their reward and it is one stream.

## Contested blocks — what PvP breaks

Two players clicking the same block on the same tick is impossible in solo play
and routine in PvP. The server half already handles it correctly and by accident:
`BlockShootValidation.checkBlock`'s `IsDescendantOf(workspace)` test means the
first `Destroy` makes the second consume a no-op, so the loser is rejected rather
than the block being consumed twice.

**The client half does not.** The append to `WordBuffer` is optimistic — it
happens before `ConsumeBlock:FireServer` and nothing ever tells the client it
failed. In solo play that is safe because nobody can take your block. In PvP the
loser of the race keeps a **phantom letter** in their buffer for the rest of the
round: a letter they never got, occupying a slot, corrupting the word they are
spelling, and eventually paying out energy on Memorize.

This is not a tap-to-pop bug — it is latent in the current staff build too. But
tap-to-pop is the change that ships into PvP, and a rejection path is cheap now
and expensive to retrofit later. See Stage 4.

## Sounds

The three Handle sounds die with the Handle.

| Old | New home |
|---|---|
| `FireSound` | dropped — there is no weapon to fire |
| `HitSound` | folded into `block_pop`'s effect sound, heard by everyone |
| `FizzleSound` | client-local 2D cue from `VfxConfig.SFX.fizzle` at `PlaybackSpeed = 0.55`, matching the refusal cue `SpellMenuGui` and `GameplayHudGui` already play |

This resolves the duplicated fizzle asset id: `VfxConfig` becomes the only place
it lives, and its note pointing at the staff's `.model.json` can be deleted.

## Stages

Each stage is independently committable and leaves the game playable.

### Stage 1 — Input moves off the Tool

New `src/client/BlockTapController.client.luau`, carrying the body of
`LetterBlaster:_onActivated` verbatim minus the beam: cooldown → mind-full →
raycast → `readBlock` → `WordBuffer:append` → `ConsumeBlock:FireServer`.

- Bind `UserInputService.InputBegan` for `MouseButton1` **and** `Touch`.
- **`gameProcessedEvent` must be honoured.** The mouse is free during play
  (nothing sets `MouseBehavior.LockCenter`; `SettingsMenuGui` only saves and
  restores it), and the HUD is click-driven — `SpellMenuGui`, `DashButtonGui`,
  the buffer's tap-to-swap slots. `Tool.Activated` suppressed clicks over GUI for
  free; a raw `InputBegan` handler does not, and without the guard every spell
  button press also pops whatever block is behind it. **This is the single most
  likely regression in the whole migration.**
- Move tunables to `src/shared/BlockShoot/BlockTapConfig.luau` — `COOLDOWN`
  (0.25, unchanged), `TAP_REACH_STUDS`. `BlockShootConstants` and
  `blockshoot_range_and_rate` both read `LetterBlasterConfig.COOLDOWN`; this is
  a rename for them, not a retune.
- Staff still exists and still works at this point; the two input paths would
  double-fire, so `SpellingStaff.client.luau`'s `Equipped` binding is stubbed out
  in the same commit.

**Done when:** clicking a block pops it with the staff unequipped, and clicking a
spell button does not.

### Stage 2 — Delete the staff

- `src/StarterPack/Spelling Staff/` (Tool template, Handle MeshPart, three sound
  `.model.json`s, `SpellingStaff.client.luau`, `KeepAnchored.server.luau`).
- `src/shared/LetterBlaster/` (controller + config).
- From `src/shared/BlockShoot/init.luau`: `muzzlePosition`, `resolveHandle`.
- From `BlockShootService`: `broadcastShot`, the `VfxBroadcast.beam` call, the
  `LetterBlasterConfig` require.
- `GameConfig.DEV_AUTO_EQUIP_TOOL` → `""`. `DevAutoEquipTool.server.luau` stays
  (generic helper, self-disables on empty config) but is no longer load-bearing.
- **Keep** `laserBeamEffect` — `src/server/NPC/Scripts/Actions.luau` still uses it.
- **Studio-side:** the `Muzzle` attachment and the Handle mesh are Studio-managed
  and vanish with the Tool. Per the pre-sync rule, check the Rojo panel for red
  items under `StarterPack` before syncing and confirm nothing else lives there.
  The `.rbxl` will need the stale `Spelling Staff` deleted if Rojo leaves it.

**Done when:** the game boots with an empty Backpack, `grep -ri "LetterBlaster\|Spelling Staff" src/`
returns nothing, and popping still works.

### Stage 3 — The pop and the collect stream

- `VfxConfig.EFFECTS.block_pop`, tinted per block colour, sound in the entry.
- `VfxBroadcast.collect` + the `collect` handler in `WorldVfxController`.
- **Ribbon and arrival flash first** — they are the cue. Motes land in the same
  stage but as a separate commit, so the budget work has something to degrade
  *to* before there is anything to degrade.
- Local draw in `BlockTapController` on confirmed append; broadcast from
  `BlockShootService` with `drawnLocallyBy` so the popper never sees two.
- Fizzle becomes a client-local sound in the controller.

**Done when — and this is the verification standard from `CLAUDE.md`:** a
*second client* sees the pop **and** sees the stream terminate on the player who
took it, while that player is moving. Server logs and Studio's server view do not
count; three shipped bugs had clean server logs while players saw nothing. The
moving half matters — a stationary test passes with a frozen endpoint and hides
the whole reason the payload carries a userId.

### Stage 4 — Contested blocks (PvP correctness)

Close the optimistic-append hole before PvP can exercise it. The client currently
appends to `WordBuffer` and never learns if the consume was rejected.

- `BlockShootService` replies to the rejecting player — either `ConsumeBlock`
  gains a client-bound fire or a sibling `ConsumeRejected` remote carries the
  block plus a reason. Prefer reusing the existing remote: one wire object, and
  the rejection is literally the response to that request.
- `BlockTapController` keeps the pending append keyed by block, and rolls it back
  on rejection: remove that letter from the buffer, play the fizzle, and **do not
  draw the pop or the stream**. Cosmetics must be gated behind the same
  confirmation as the letter, or the loser of a race sees sparks flow into
  themselves for a letter they did not get.
- **Rollback is not "pop the last slot".** The player may have appended two more
  letters in the round-trip. Remove the specific pending entry by identity, and
  make it a no-op if the slot is already gone (the player destroyed it manually —
  `WordBuffer` supports double-tap-destroy).
- Rejections that are *not* a lost race (rate limit, out of range, malformed)
  roll back identically. The client does not need to know which it was; it needs
  to know the letter did not land.

**Done when:** two clients tap the same block on the same frame. One buffer gains
the letter, the other does not, and neither shows a stream it did not earn. This
is [[concepts/MultiplayerTestPattern]] territory — it wants a test, not just a
playtest.

### Stage 5 — Reach + glow

- `TAP_REACH_STUDS` enforced client-side in the raycast; `BlockShootConstants.MAX_CONSUME_DISTANCE_STUDS`
  re-derived from it (it currently adds a 100-stud camera-zoom allowance on top
  of `BlockShoot.MAX_RAYCAST_DISTANCE` — the allowance still applies, the base
  shrinks).
- ~~In-range `Highlight` glow~~ + hover outline + mind-full muting, in the
  controller.
- Retune `blockshoot_range_and_rate`, which asserts both directions of the range
  bound against the production constants.

**Built as: hover outline only, with state — no in-range glow.** Two reasons the
planned glow-every-reachable-block was dropped. Roblox renders a bounded number
of `Highlight` instances (guidance is under ~31) and the arena holds 40 blocks,
so the budget does not cover it and outlines would drop unpredictably. And it
answers a question nobody asks: "which of these twenty can I reach" is not how
anyone plays. The question is always about the block under the cursor, and one
highlight that changes colour answers it *and* shows where reach ends, at the
moment it is relevant. Three states: block tint + white outline (poppable),
grey and dimmer (out of reach, or mind full), off (not pointing at a block).

**Reach did not shrink after all.** This stage was written expecting reach to be
tuned down; it ended up back at LetterBlaster's original 200 by a different
route — see [[systems/BlockShoot]] § Reach and § Aiming. The hardening suite
needed no retune because its out-of-range fixture derives from
`MAX_RAYCAST_DISTANCE` rather than restating it.

**Done when:** ~~walking toward a block lights it up before you can pop it~~
pointing at a block tells you whether a click will land, and the hardening suite
is green. ✅

**PvP note:** reach plus glow turns blocks into contested positional resources —
two players can see the same block go live for both of them. That is good design
tension and Stage 4 is what makes it safe. Tune reach with contention in mind:
too generous and there is no reason to move; too tight and a fight is decided by
who spawned closer.

### Stage 6 — Wiki + tests

- `wiki/systems/LetterBlaster.md` → rewritten as a **REMOVED** historical record,
  matching the treatment [[systems/Weapon]] and [[systems/Loadout]] already got.
- `wiki/systems/BlockShoot.md` — new input path, no muzzle helpers.
- `wiki/systems/LetterBlock.md` — glow affordance + pop.
- `wiki/systems/AudioSFX.md` — staff sounds gone, pop sound added.
- [[systems/Tutorial]] — its first step is *"shoot"*; the verb is now *"tap"* and
  there is no weapon to equip. Tutorial is still in planning, so this is a copy
  edit, not a rework.
- `wiki/log.md` ingest entry; `graphify update .` before the commit.

**Done ✅.** All of the above landed, plus one the plan missed:
[[design/client-server-boundary]] carried a `LetterBlaster` row citing two
deleted files — a current-state claim, so it was corrected rather than left as
history. Plans, dated audits and changelog entries describing what was true when
written were deliberately not touched.

## Risks

| Risk | Mitigation |
|---|---|
| **HUD clicks pop blocks behind them** | `gameProcessedEvent` guard, Stage 1. Explicitly tested against `SpellMenuGui` and the buffer slots. |
| Mobile tap not delivered by `InputBegan` | Bind `UserInputType.Touch` explicitly; the buffer's tap-to-swap (Phase 4.7) already proves touch works in this codebase. |
| Rojo leaves a stale `Spelling Staff` in the `.rbxl` | Pre-sync red-item review; delete manually in Studio if it survives. |
| Glow cost with a full arena | Throttled recompute, one `Highlight` per in-range block only, reuse the animator's tracked set. |
| Reach tuned against the wrong arena | The spawn volume is level-authored — tune against the live tagged part, not the 40×8×40 figure in the wiki. |
| **Phantom letter from a lost block race** | Stage 4 rejection path. Latent in the current build too; PvP is what makes it reachable. |
| Stream cost in a 6-player fight | Staged degradation to ribbon-only, single shared Heartbeat driver, visibility culling. The cue degrades, it never disappears. |
| Stream funnels to where a player *was* | `collectorUserId` re-resolved per frame, not a baked Vector3. Verify against a **moving** target — a stationary test cannot catch this. |
| Stream drawn for a consume that was rejected | Stage 4 gates all cosmetics behind confirmation, not behind the optimistic append. |

## Status — all six stages shipped (2026-08-10)

| Stage | Commit |
|---|---|
| 1 Input | `be2b1a2` |
| 2 Delete the staff | `14881d9` |
| 3 Pop visuals | `3204b0d` |
| 4 Rejection rollback | `08a2e5a` |
| 5 Motes / hover / reach | `e5f72cc`, `1080233`, `2139661` |
| 6 Wiki | `d4bcfc3`, `4cc0ab6` |

Two things came out differently from the plan, both recorded where they happened
rather than only here: the in-range glow became a single hover outline (stage 5),
and reach ended back at LetterBlaster's 200 after a raise-and-revert that
uncovered [[systems/BlockShoot]] § Aiming — a screen/viewport coordinate
mismatch that had capped effective reach at ~30 studs and was the actual cause of
the "range is too short" report the raise was chasing.

## Milestone

Everything below is verified except the one line that needs a second client — a
stream funnelling at *another* player's character. The receive path itself is
verified single-client (see [[systems/BlockShoot]] § Stream layers), so what
remains is confirming the wire, not the logic.

Two clients in the arena. Both spawn with empty hands and no hotbar. Each taps
blocks in reach — they glow before you can take them, pop with a colour-matched
burst on both screens, and a stream of that colour funnels out of the block and
onto whoever took it, **tracking them while they run**. The letters land in the
tapper's buffer and only theirs. Neither player can pop a block outside their
reach, neither pops one by pressing a spell button, and when both tap the same
block on the same frame exactly one of them gets a letter and a stream.

## See also

- [[systems/LetterBlaster]] — the system being retired.
- [[systems/BlockShoot]] — shared helpers + the server contract that does not change.
- [[systems/LetterBlock]] — the entity, and the animator that owns its transform.
- [[design/client-server-boundary]] — the authority / prediction / presentation
  split the pop follows.
- [[systems/VisualEffects]] — `VfxBroadcast` and the effect registry.
