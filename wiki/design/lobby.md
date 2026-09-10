---
type: design
description: Phase 6 plan (2026-08-20) — a welcome lobby and PvE/PvP mode selection. The finding is that mode choice is a session-container problem, not a menu problem; GameModeService and RoundManager are server-wide singletons. Decision = hub place with in-place arena zones, co-op queued PvE, 1v1 queued duels on a pad pool. Records what PvP needs that the lobby does not provide.
updated: 2026-09-10
---

# Lobby & Mode Selection

Companion to [[design/build-plan]] Phase 6. Prompted by the decision to add a PvP
mode: players need somewhere to stand, and something to choose.

## The finding

A "welcome lobby" reads like UI work. It is not. It decomposes into three
separable things, and only one of them is expensive:

1. **A place to stand** — hub geometry, portals. Greybox work, see [[design/ArtDirection]].
2. **A selection mechanism** — already covered by [[concepts/BuilderConfigLayout]].
3. **A session container** — the thing that answers *which arena am I in, and what
   round state is it running*. This does not exist.

Today `GameModeService` + `RoundManager` are a **server-wide singleton**: one
round, one mode, everybody in it. `Modes/init.luau` registers exactly `NoOp`
after `FFADeathmatch` / `TeamDeathmatch` / `TeamService` were deleted in
`6610291`. `BlockSpawner` treats every tagged `BlockSpawnVolume` in the world as
one pool. That topology has no way to express "these three players are fighting
the boss and those two are duelling."

Mode selection is therefore a refactor of code that already exists, wearing a
menu as a hat.

## The decision: hub place with in-place arena zones

One `.rbxl`. A lobby zone plus arena zones in the same server; entering a mode
moves your character between zones, it does not leave the place.

**Rejected — multi-place + `TeleportService`.** The scalable answer, and the
wrong one right now. It needs three published places, a Rojo project per place,
shared code packaged rather than required, and cross-place identity. That last
one is decisive: [[design/persistence-progression]] is **Phase 5.5 and not
built**, so a player teleported today arrives with nothing. It also splits a
pre-soft-launch population across places, which makes a 1v1 queue unfillable.

**Rejected — whole-server mode vote, no hub.** The cheapest option: the lobby
becomes `RoundManager`'s `Waiting`/`PostRound` state with a vote UI, and the
whole server plays one mode per round. No per-arena refactor at all. Rejected
because it makes PvE hostage to PvP — a solo player in an empty server can never
start anything, and the mode you want is decided by whoever else logged in.

**Why the hub survives being outgrown.** Moving to reserved servers later
changes *where a session lives*, not *what a session is*. The session
abstraction below is the part that gets reused; the zone-vs-place distinction
sits behind it.

## Session model

A **session** is one mode instance bound to one arena slot, running its own
round lifecycle.

| Concept | Meaning |
|---|---|
| **Arena slot** | A physical, tagged region of the hub place. Fixed set, authored in Studio. Has an `ArenaId` attribute. |
| **Session** | `modeDef` + `slot` + roster + `RoundManager` state. At most one per slot. |
| **Queue** | Per-mode list of players who have opted in and are waiting for a slot. |

| **Registry** | `SessionRegistry` (ModuleScript, refactor chunk 8) — owns `sessions[arenaId]`, `playerSessions[player]`, `queued`; `create` / `destroy` / `transferPlayer` / `setQueued` / `forPlayer` / `forArena` / `rosterOf`. The only writer of the `ArenaId` / `PlayerState` attributes. |
| **Scores** | One `ScoreTracker` per session, constructed and owned by its `RoundManager` (chunk 8). A round start resets that roster and nobody else. |

`RoundManager`'s existing `Waiting → Countdown → Active → PostRound` machine is
the right lifecycle — it stopped being a singleton in stage 1. The timer and the
countdown are `timeLimit` / `countdownSec` on each mode's config (chunk 8 deleted
`ROUND_TIMER_ENABLED` and `ROUND_COUNTDOWN_ENABLED`): absent means no timer / no
countdown, which is what Lobby and NoOp say; the duel mode sets both.

### Slot allocation

- **PvE — one boss arena, co-op.** `minPlayers = 1`, and everyone queued at round
  start goes in together. A solo player therefore never waits: they queue, the
  round starts, they fight. This is the resolution of "queued PvE" that keeps one
  code path with PvP without stranding lone players — the alternative, a private
  boss arena per player, needs an arena pool sized to the server.
- **PvP — a pool of duel pads, 2 authored for v1.** 1v1 means two players occupy
  a slot and everyone else waits, so the pad count is the concurrency limit.
  Queue holds when all pads are busy; the portal shows the wait.

Two pads is a guess, not a measurement. It is the cheapest number that isn't 1
(where a single duel blocks the whole server) and it is authored geometry, so
raising it later is Studio work plus a tag, not code.

## Mode selection UX

**Diegetic portals, not a menu screen.** Two physical portals in the hub, each
with a floating sign. Reasons: it matches the chunky-lowpoly read of
[[design/ArtDirection]], it costs no new UI mode in a game whose verbs are all
single taps (the same argument that reshaped [[systems/ChargeCast]]), it gives
queue counts a place to live, and walking somewhere teaches better than clicking
somewhere.

The HUD's only job is a small confirm/cancel panel on approach — built with
Builder + Config + LayoutManager like everything in `src/client/UI/`.

**Live queue counts on the PvP portal** (`2/2 duelling · 1 waiting`). A portal
with no numbers on it reads as broken when nobody else is on.

## Player state

Each player is `InLobby | Queued | InArena`. This is the gate a lot of existing
systems need and currently lack.

**Revised 2026-09-07 — the lobby teaches the full loop**, so the suppression
list is much shorter than first planned. What stays on screen is everything the
core verb touches; what hides is round and competition chrome:

- **Hidden in lobby:** health bar, `BossHudGui`, `DamageFeedbackGui`,
  `KillFeedGui`, `ScoreboardGui`, `RoundTimerGui`, `GameStateGui`,
  `DeathScreenGui`, `TeamScoreGui`
- **Live in lobby:** letter tiles, `MemorizeButton`, `SpellMenuGui`,
  `MindFullIndicatorGui`, `BuffTrayGui`, `DashButtonGui`, `SettingsMenuGui`
- `BlockTapController` — live in the lobby; lobby blocks need no special case

The mechanism is [[concepts/HudGate]]: a declared policy per element, made a
**required argument** on `HudLayoutManager:register` so a new HUD element cannot
silently leak into the lobby. Six GUIs own their own `ScreenGui` rather than
registering, and are gated on `.Enabled` through the same policy table.

## In the lobby for v1

- **Tutorial entry** — [[systems/Tutorial]] (Phase 5.3) gets a natural front door.
- **Settings access** — `SettingsMenuGui` exists; surface it.
- **Practice blocks + a target dummy** — the lobby teaches the **whole** loop:
  tap a block, buffer letters, memorize for real energy, cast at a dummy. The
  earlier "buffer but grant no energy" plan taught the setup without the payoff,
  and was specifying the wrong seam anyway — energy is granted at memorize, not
  at pop, so there was no per-block grant to suppress. Lobby blocks are just
  blocks. The dummy is a `Damageable`-tagged model; `DeathHandler` already
  clones a template and respawns it, so it is Studio work rather than code.
- **Live queue counts** — above.

**Not in v1:** the word-PB / progression board. It depends on Phase 5.5
persistence. Leave wall space for it.

## What this does *not* unblock

The lobby is worth building now — it also serves PvE, the tutorial, and later the
progression surface. It is **not** the PvP critical path, and shipping it must not
be mistaken for shipping PvP.

| Blocker | State |
|---|---|
| ~~**Spell damage does not respect the PvP gate**~~ | **Closed 2026-09-08** (refactor chunk 4). Every spell now goes through `applyDamage.process`, and the gate is `allowsPvP` on the mode config, resolved through the victim's session — see § PvP gate below. |
| ~~**Client-trusted affordability**~~ | **Closed 2026-09-08** (refactor chunk 6). `EnergyLedger.checkCast` prices every cast from validated memorizes, the ledger resets per round, and `EconomyConstants.ENFORCE = true` refuses casts a player provably never earned — see [[systems/SpellCastService]] § Validated memorize. |
| **Round timer / countdown off** | `ROUND_TIMER_ENABLED` and `ROUND_COUNTDOWN_ENABLED` are both `false`. A duel with no clock does not end. |
| **Contested blocks** | Closed by Phase 5.7 stage 4 — noted here because it was PvP-only and unreachable in solo play, which is the class of bug this phase will keep finding. |

**Sequencing consequence:** Phase 6 stages 1–5 (container + arenas + broadcast +
hub + PvE) are safe to build against the current trust model, because PvE co-op
cheating is self-cheating. Stage 6 (duels) should land **after** Phase 5.4.

## PvP gate (2026-09-08)

Decided as Q2 of the [[design/system-audit-2026-09]] and landed in refactor chunk 4. Whether player A may damage player B is **a property of the mode B is playing under**, so that a duel and the lobby can coexist on one server:

- `GameModeDefinition.getConfig().allowsPvP: boolean?` — absent means false. `LobbyMode` and `NoOpMode` say false; `PvPDuel` (stage 6) says true.
- `SessionRegistry.allowsPvPFor(victim)` answers from the **victim's** session — the victim is by definition in the arena the hit happened in. A player with no session yet (before boot) gets `false`. (Chunk 4 shipped this as an `AllowsPvP` BindableFunction bound by `GameModeService`; chunk 8 deleted it in favour of the module.)
- `HealthService` injects that answer into `applyDamage` as `allowsPvPFor(victim)`; `applyDamage.process` drops player-on-player damage when it is false. Self-damage, NPC-on-player and player-on-NPC are never gated.

`GameConfig.PLAYER_VS_PLAYER_ENABLED` is deleted. The round timer/countdown flags follow it onto the mode config in chunk 8 (Q7).

**Charge tier stays client-trusted (Q4(a), 2026-09-08).** `SpellCastService` takes the client's `tier` and does not check the hold duration against `chargeTimeFor(tier)`; a client that lies about charging buys itself *speed*, not mana, because it still pays `spec.cost` out of a ledger it had to earn. Accepted as a known tell-skip for now and to be revisited once duels are actually playable — see [[systems/SpellCastService]] § "Not checked: hold duration".

## Interface note

`GameModeDefinition` is kill-centric: `onPlayerKill`, `scoreLimit`,
`checkWinCondition(scores)` over kills/deaths/assists. That fits a duel almost
unchanged. It fits a boss fight badly — modelling "the boss died" as a player
kill is the kind of bend that reads fine for one mode and rots on the third.
Add an objective-shaped win condition rather than overloading kills.

## Broadcast audience

*Added 2026-08-20 after stage 1 shipped.* `RoundManager`'s `FireAllClients` was
not a one-off — it was the first of a class, and the original stage table treated
it as a detail. **Seventeen** `FireAllClients` sites remain in `src/`. They do
**not** all matter equally, and the split is by what the *consumer* does with the
payload, not by which system sends it:

| | Sites | With two arenas live |
|---|---|---|
| **Screen-space (HUD)** — 9 | `BossPhaseChanged` ×3 (`BossService` 73/84/109) + `BossHealthChanged` ×3 (85/94/108) → `BossHudGui`; `ScoreUpdate` ×1 (`ScoreTracker` 140) → `ScoreboardGui`; `KillFeed` ×2 (149/265) → `KillFeedGui` | **Broken.** A duellist gets the boss's health bar on screen and the boss room's kill feed. Position is irrelevant — it's a GUI. |
| **World-space (VFX)** — 8 | `VfxBroadcast` ×5, `VfxBroadcastService` ×1, `SkillDelivery` ×1, boss windup (`BossStates` 176) | **Costs, doesn't break.** Particles spawn at a world position, so a player in another arena never sees them — but pays to instantiate them. |

**Only the HUD half is Phase 6 work** (stage 3 below). The VFX half is a
throughput problem owned by [[systems/VisualEffects]]' `PERF` guardrails, which
already exist and already budget per-effect; routing them per-roster would add a
roster lookup to the hottest path in the game to save work the distance culling
mostly saves anyway. Recorded here so the next person to grep `FireAllClients`
doesn't have to re-derive which of the eleven are load-bearing.

`DevSmokeTestKillFeed.server.luau` also has three sites. It is a dev harness —
leave it.

## Stages

| Stage | Item | Gate |
|---|---|---|
| 1 | ✅ **Done 2026-08-20 (`b38a99c`).** `RoundManager.new(deps)` with `arenaId`, a roster and `:disable()`/`:destroy()`; `GameModeService` owns `sessions[arenaId]` + `playerSessions[player]`, one `Default` session at boot. Per-roster `FireClient` landed with it, and `_waitForPlayers` gates on roster count. **Diverged from plan:** `task.cancel` was removed rather than kept — the old `stop()` never cleared `roundThread` on natural exit, so a second `stop()` would have thrown; a `_generation` counter checked at each await point covers the overlap case cancel was there for. Verified by a client-side listener plus a two-session disjoint-roster cross-talk test. | — |
| 2 | ✅ **Done 2026-08-20.** `ArenaId` attribute on `BlockSpawnVolume`; `BlockSpawner.new(opts)` is one pool per arena with `:disable()`/`:destroy()`, and `BlockSpawnerService` groups the tagged volumes by id. `SpawnManager` resolves per arena via `registerArena` + `getBestSpawn(player, arenaId)`. New shared `GameMode/Arena.luau` holds the `ArenaId` / `Default` / `SpawnTags` vocabulary. **The subtle part was density:** `count = density × volume / 1000` summed *every* tagged volume, which is the right answer for one arena and the wrong one for two — verified per-arena with two probe pools resolving to 10 and 5 rather than 15 each. **Absent `ArenaId` resolves to `Default`**, because the shipped arena's eight volumes are tagged but unattributed and requiring the attribute would have emptied it silently. The three new spawn tags are declared but nothing carries them yet. | — |
| 3 | ✅ **Done 2026-08-20.** All nine HUD sites route through a new `shared/GameMode/BroadcastAudience.luau` — a late-binding pointer at `GameModeService`'s session tables, resolved per fire. `ScoreTracker` and `BossService` both needed it because neither *holds* a roster the way `RoundManager` does. **The boss judgement call:** rather than thread a session through `BossService` (a refactor stage 5 immediately redoes), it resolves `Arena.idOf(BossPoint)` — one attribute read per boss cycle, roster resolved per fire. Fallback on an unresolved lookup is *everyone* (pre-stage-3 behaviour) plus a throttled warn, never an empty audience. **Deliberately incomplete:** ScoreTracker's scores are still server-wide, so another arena's names still appear on the scoreboard — only the audience moved, since the payload shape is frozen for `ScoreboardGui`/`KillFeedGui`. VFX lane untouched as planned. **Not fully verified:** the two-session disjoint-roster test did not run (MCP `start_stop_play` wedged); single-session boot is clean. | Before stage 6 |
| 4 | **Hub greybox + player state.** Lobby arena slot with its own session, `transferPlayer`, hub greybox, two portals, practice blocks, `InLobby/Queued/InArena` and the HUD suppression table above. Lands as 4a/4b/4c — see § Stage 4 detail. | — |
| 5 | **PvE mode.** `Modes/PvEBoss.luau` — co-op, `minPlayers = 1`, objective win condition, boss arena slot. Queue → round → back to lobby. *Prerequisites landed 2026-09-09 (refactor chunk 8): `SessionRegistry` module, per-session `ScoreTracker`, roster-scored spawns.* | — |
| 6 | **PvP duel.** `Modes/PvPDuel.luau` — exactly 2, pad pool, `allowsPvP = true` on its config, `timeLimit` + `countdownSec` set on its config (the global flags are gone). | **After Phase 5.4** |
| 7 | **Wiki + tests.** ✅ *GameMode page rewritten 2026-09-09 (chunk 8) off its NoOp-only record; session lifecycle tests landed as `Suites/Multiplayer/{sessions_isolate_scores, transfer_moves_roster_and_attributes, registry_views_agree}`.* Still open: `wiki/systems/Lobby.md`. | — |

*Stage numbering changed 2026-08-20: broadcast audience inserted as the new stage
3, pushing hub/PvE/duel/wiki from 3–6 to 4–7. Stages 1 and 2 are unmoved.*

## Stage 4 detail

*Planned 2026-09-07.* Stage 4 is the largest stage in this phase because it is
the first one a player can see. Four decisions were taken before writing it, and
they are what make the rest of the stage mechanical.

### Decision 1 — the lobby is an arena slot with a session

Rejected: "the lobby is the absence of a session" (`playerSessions[player] ==
nil`). It looks cheaper and is not. Stages 1–3 spent their whole budget making
*arena id* the key that spawns, block pools and broadcast audiences agree on; a
lobby with no id puts a `nil` branch back into every one of them, and the
practice blocks — which are `BlockSpawner` output like any other block — would
have no pool to belong to.

So: `Arena.LOBBY_ID = "Lobby"`, a `Modes/LobbyMode.luau`, and a second session
created at boot. The lobby session is **created but never `start()`ed**, which
is how it runs no round without `RoundManager` learning what a lobby is. That
needs one new field on the mode config, `runsRounds: boolean`, because
"GameModeService should skip `start()` for this mode" is a property of the mode,
not something to special-case on an arena id.

The payoff is that the interesting primitive falls out for free:

```lua
GameModeService.transferPlayer(player, targetArenaId)
```

Remove from one roster, add to another, restamp the player's attributes, respawn
at the target arena's pads. Stage 5 (queue → boss arena → back) and stage 6
(queue → duel pad → back) are both *calls to this function*. Getting it built and
exercised in stage 4 is most of why stage 4 is worth doing before the modes
exist.

### Decision 2 — the portals really move you, against the NoOp mode

The stage table said "still `NoOp` behind the portals", which reads as: press the
portal, become `Queued`, nothing happens. That leaves `InArena` unreachable, and
`InArena` is the state the entire HUD suppression table is written against — it
would ship unverified and then be debugged in stage 5 alongside brand-new mode
code.

Instead the PvE portal transfers into the existing `Default` session. That
session runs `NoOp`, so there is no boss and nothing to win, but the player
crosses the boundary for real: roster moves, arena id changes, combat HUD comes
back, blocks in that arena become poppable and grant energy. A return pad carries
them back. The mode is still `NoOp`; the *transfer* is not.

The PvP portal enqueues honestly. Zero duel pads are authored in stage 4, so the
queue holds and the sign reads `0/0 duelling · 1 waiting`. That is a real queue
with a real answer, not a stub — stage 6 authors two pads and the same code
starts dequeuing.

### Decision 3 — player state lives on the Player instance

`PlayerState` (`InLobby` / `Queued` / `InArena`) and `ArenaId` are written by the
server as **attributes on the `Player` instance**. No remote, no handshake, no
join-order race: attributes replicate to every client automatically and are
readable the moment a client asks. `Arena.idOf` already reads an `ArenaId`
attribute off scene parts, so the same word means the same thing on a player.

This also answers the portal signs. Occupancy and queue length go on the portal
part as attributes; the sign is a client-built `BillboardGui` that reads them.
Zero remotes on the whole read path.

### Decision 4 — portal confirm is a Builder panel, not a ProximityPrompt

Per § Mode selection UX. A `ProximityPrompt` has nowhere to put
`2/2 duelling · 1 waiting`, and it is a visual language nothing else in this game
speaks. `PortalPanelBuilder` + `PortalPanelConfig` + a client coordinator, the
same triple as every other surface.

**The client does not decide anything.** The panel fires a `PortalRequest` remote
naming the portal; the server re-checks that the player is `InLobby` and actually
standing near that portal before transferring. A client-trusted portal is
precisely the class of bug § What this does *not* unblock is about.

### Sub-stages

Stage 4 lands in three commits, in this order, each independently verifiable.

**4a — session container (server only, no geometry).** ✅ **Done 2026-09-07.** `Arena.LOBBY_ID`,
`Arena.STATE_ATTRIBUTE`, `Arena.PlayerState`; `Modes/LobbyMode.luau` +
`runsRounds` on the mode config; `GameModeService` creates the lobby session at
boot, joins players to it instead of `Default`, and gains `transferPlayer`.
Verified by attribute reads and a scripted transfer — no world changes needed.

*Known trap:* the respawn loop in `onPlayerAdded` only fires when
`isPlayerRoundActive(player)`. A player who dies in the lobby is therefore never
respawned at all today. 4a rewrites that gate as "has a session", resolving the
arena through the existing `arenaIdForPlayer`.

*Shipped, with two consequences worth writing down.* Verified live: a joining
player reads `PlayerState=InLobby ArenaId=Lobby`, `TransferPlayer:Invoke` moves
them to `InArena`/`Default` and back, and an unknown arena id is refused rather
than silently dropping the player out of every roster.

**The arena round no longer starts on its own.** `_waitForPlayers` gates on
roster count, and the Default roster is now empty at boot, so the arena sits in
`WaitingForPlayers` until somebody transfers in. That is correct — it is what
"a round is a session, not a server" means — but it changes what three HUD
scripts see: `GameStateGui`, `RoundTimerGui` and `DeathScreenGui` all key off
`roundState`, and a lobby player now receives no `GameStateChanged` at all. They
are on 4c's suppression list anyway. Nothing in the gameplay chain — blocks,
energy, casting, boss — turned out to be coupled to round state, which is why
this was safe to land before the HUD work.

**A session left empty mid-round stays Active.** Transferring the last player
out does not end the round. Harmless for `NoOp`; stage 6 must not inherit it, or
a duel pad will never free. It belongs to the mode's win condition, not to
`transferPlayer`, so it is deliberately not fixed here.

*Also deliberate:* the transfer **pivots** the character rather than reloading
it. Reloading is the more obvious "fresh start" but it resets health, drops the
equipped Tool and rebuilds every `ResetOnSpawn` ScreenGui, on a path a player
crosses repeatedly. Restoring health belongs to a mode's round start, where it
can mean something.

**4b — the hub.** ✅ **Done 2026-09-07.** `Workspace.Lobby` greybox authored via MCP under a
`ChangeHistoryService` waypoint: floor and walls, two portal pads with arches,
`LobbySpawn` pads, a small `BlockSpawnVolume`, a `Damageable` target dummy, and
a `LobbyReturn` pad inside the existing arena. All tagged and
`ArenaId`-attributed. The existing `Arena.SpawnZone.SpawnLocation` stops being
where players land — 4a shipped with no lobby pads authored, so both arenas
currently resolve through `SpawnManager`'s misconfigured-scene fallback to the
same `SpawnLocation`, and a transfer moves a player's roster without moving
their body.

*Revised 2026-09-07, and it got smaller.* 4b was planned to stamp `ArenaId` onto
every spawned block so `BlockShootService` could refuse lobby blocks energy and
reject cross-arena pops. Both halves are now dropped. The first because
[[concepts/HudGate]] § Practice blocks established that the player-facing grant
happens at **memorize**, not at pop — there was no per-block grant to suppress,
and since the lobby grants real energy, lobby pops must reach the shadow ledger
too or the memorize they feed becomes unaffordable when `ENFORCE` flips. The
second because the hub sits hundreds of studs from the arena and
`BlockShootValidation.checkRange` already refuses a pop at that distance; an
arena-id check would be a second lock on a door that is shut. Lobby blocks are
ordinary blocks, and 4b is Studio work plus tags.

*Shipped.* Hub origin `(-600, 202, 28)`, floor top at `y = 203` to match the
arena plaza, 533 studs clear of the nearest arena block volume. 140 × 140 walled
shell with corner pillars, two portal arches (`ModePortal`-tagged pads carrying
`TargetArenaId` / `ModeLabel` / `Occupancy` / `Capacity` / `Waiting`, the last
three declared empty for 4c to write), five `LobbySpawn` pads, a 70 × 20 × 56
practice-block volume, a target dummy, and a `LobbyReturnPad` in the arena.
Verified live: `[Lobby] registered with 5 spawn points`, `[Default] registered
with 1`, `2 arena(s): Default=40, Lobby=8`, and a transfer now moves the body
— `(-650, 207, 28)` ↔ `(257, 206, 26)` — where in 4a it moved only the roster.

**The spawn change had two halves, and only one is obvious.** Disabling
`Arena.SpawnZone.SpawnLocation` is what makes Roblox's own initial spawn land a
joining player in the hub. The non-obvious half is that the arena's pad *also*
had to be tagged `FFASpawn`: `SpawnManager`'s `SpawnLocation` fallback is
deliberately **not** arena-filtered (it is the misconfigured-scene path), so
with `Default` still resolving through it, adding a `SpawnLocation` to the lobby
would have made the hub a candidate arena spawn and teleported arena players
into it. Both arenas now resolve by tag and neither reaches the fallback.

**The dummy cost no code, as predicted.** `DeathHandler` logged `Created
template for 'TargetDummy'` on sight and `HealthService` adopted it. Two notes:
`HealthService` sets it to its own 100 HP, overriding the 200 authored on the
rig — the health system owns that number, which is correct. And the
`DamageableTemplates` copy in `ServerStorage` draws its own `Damageable
initialized` line, because `HealthService` scans the tag rather than the
workspace. Cosmetic, pre-dates this stage, left alone.

**Found by screenshot, not by log:** the block volume was originally centred on
the hub and swallowed the dummy, so blocks spawned in front of the one thing
you are meant to cast at. Server logs were clean throughout. The dummy moved
north to `(-570, ., 80)` and the volume's z-extent pulled back to `[0, 56]`.

**The geometry lives in `BrainFighter.rbxl`, not in git** — Rojo maps only
`ReplicatedStorage`, `ServerScriptService`, `StarterGui` and `StarterPlayer`, so
`Workspace.Lobby` is safe from a sync deleting it, and equally is not versioned
until the place file is saved and committed. Same as the arena greybox it sits
beside.

**4c — what the player sees.** ✅ **Done 2026-09-07.** HUD suppression per [[concepts/HudGate]]: a
required policy argument on `HudLayoutManager:register` for the nine
region-registered elements, and `HudGate.bindScreenGui` for the six that own
their own `ScreenGui`. That page owns the design and the per-element policy
table; this one owns only the fact that stage 4c is when it lands.

Also 4c: `PortalPanelBuilder` + `PortalPanelConfig` + `PortalPanelGui`, the
portal sign billboards, the `BlockTapController` read of `PlayerState` (not a
`GuiObject`, so outside HudGate), and `EnergyReservoirs:reset()` cleared by the
client on the transition into `Active` — see [[concepts/HudGate]] § Resolved.
That last one is not a lobby bug: `RoundManager._activeRound` resets scores and
not energy, so round 2 of any session already inherits round 1's mana. The
lobby only makes it visible.

*Shipped, and the interesting part was a Roblox detail.* Verified client-side,
which is the only verification that counts here: in the hub the health bar,
kill feed, boss HUD, scoreboard, game state and damage feedback are all off
while the buffer, memorize button, spell menu, MindFull indicator and buff tray
stay live; walking a portal turns the first set back on. `LobbyService` logged
the whole loop — `took Boss Fight -> Default`, `took Return to Lobby -> Lobby`,
`queued for Duel (position 1)`, `left the queue`, and
`Portal refused ... out of range (80 studs)`.

**The bug worth recording: property-changed signals are deferred.** HudGate
tells its own writes from the owner's so it can suppress without revealing. The
first implementation set an `applying` flag around the write and cleared it
immediately after — but Roblox fires `GetPropertyChangedSignal` deferred, so the
flag was already false when the handler ran. The gate read its own suppression
back as *the owner wanting the element hidden*, and nothing ever came back on
entering an arena. The first playtest showed a correct lobby and an arena with
no health bar. The fix keys off the gate's state at the time of the write
instead of a flag: with the gate open the gate never writes, so any change is
the owner's; with it closed, a value going **true** can only be the owner and is
recorded, and a value going false is assumed to be ours.

**The second bug worth recording: `Tween:Cancel()` re-fires `Completed`.**
Found in play 2026-09-10. Declining a portal with "Not now", stepping off the
pad and stepping back on showed no panel at all — and the same happened on any
second approach, dismissal or not. `PortalPanelBuilder:setShown(false)`
connected a `Completed` handler that hid the frame, and `setShown(true)`
cancelled that tween to start the fade in. Roblox fires `Completed` again on
`Cancel()` — with `Enum.PlaybackState.Cancelled`, and even for a tween that had
already finished naturally — and, being deferred, it landed just after
`Visible = true` and just before the show tween moved `BackgroundTransparency`
off 1. The stale handler's "am I fully faded?" guard therefore read true and hid
a panel on its way in. The tell is a frame at the panel's normal transparency
with `Visible = false`: the fade ran, the frame was not on screen. Fix: hide
only on `Enum.PlaybackState.Completed`, and disconnect the handler before
cancelling so a stale fade cannot speak after its turn. Sibling of the deferred
`GetPropertyChangedSignal` bug above — same lesson, different signal. The
dismissal bookkeeping in `PortalGui` (`dismissedPortal`, cleared on walking out
of range) was correct throughout.

**`LobbyOnly` has no users, and the reason is the return pad.** The policy table
assigned the portal panel `LobbyOnly`, which is wrong the moment the arena
contains a portal of its own. The panel is `Always`; **proximity** decides
whether it is on screen and the arena check decides which portals are near you.
The enum value stays for a surface that really is lobby-only.

**Two non-findings that look like findings.** `DashButtonGui` stays hidden in
both zones — it is touch-only and its owner never asked for it, which is the
"never reveals" rule doing its job rather than a gate failure. And
`RoundTimerGui` returns early on `ROUND_TIMER_ENABLED = false`, so it has no
ScreenGui at all today; its binding is correct and dead until stage 6 turns the
timer back on.

The return pad moved from 17 studs off the arena spawn to 52, onto the bridge:
arriving in the arena inside the return prompt's range greeted the player with
"Return to lobby".

### Verification

`start_stop_play` has wedged repeatedly, so stage 4 is designed to need **one**
playtest, not a loop. Everything 4a asserts is an attribute, so it is checkable
by a probe script rather than by eye. The one thing that genuinely requires a
client is HUD suppression, which is verified the way this project verifies
anything player-facing: a client-side visibility count and a client screenshot,
never a server log. Two playtests maximum before escalating.

### Deliberately not in stage 4

- **Real queue dequeuing.** No pads exist to dequeue into (stage 6).
- ~~**ScoreTracker's server-wide scores.** Still stage 5.~~ Closed 2026-09-09
  (refactor chunk 8): one tracker per session, broadcasting to its own members.
- **Tutorial entry.** Wall space is left for it; [[systems/Tutorial]] is 5.3.
- **The progression board.** Blocked on Phase 5.5 persistence.

## Milestone

Two clients join, land in the lobby with no combat HUD, pop a practice block,
and walk to different portals. One fights the boss solo while the other waits at
a full duel pad and can see why. Both return to the lobby when their round ends,
and the server never had more than one session per slot.

## Open questions

- **Does leaving mid-round forfeit?** A duel where quitting is free is a duel
  nobody loses.
- **What happens to a duel when one player disconnects?** Award, void, or
  re-queue the survivor.
- **Spectating.** Free tension-builder for waiting duellists, or a whole feature.
  Not scoped here.
*(Resolved 2026-09-07 — lobby energy carryover. Answer: reset at round start,
not at arena entry. Folded into § Stage 4 plan step 5.)*
