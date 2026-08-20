---
type: design
description: Phase 6 plan (2026-08-20) — a welcome lobby and PvE/PvP mode selection. The finding is that mode choice is a session-container problem, not a menu problem; GameModeService and RoundManager are server-wide singletons. Decision = hub place with in-place arena zones, co-op queued PvE, 1v1 queued duels on a pad pool. Records what PvP needs that the lobby does not provide.
updated: 2026-08-20
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

`RoundManager`'s existing `Waiting → Countdown → Active → PostRound` machine is
the right lifecycle — it just has to stop being a singleton.
`ROUND_COUNTDOWN_ENABLED` and `ROUND_TIMER_ENABLED` were both set `false` for the
solo educational build and both want to come back on for PvP.

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
systems need and currently lack:

- `GameplayHudGui`, `SpellMenuGui`, `BuffTrayGui`, `BossHudGui` — suppressed in lobby
- `BlockTapController` — inert in lobby **except** on the practice blocks
- `DashButtonGui` — stays live; movement is not mode-specific
- `SettingsMenuGui` — always available

## In the lobby for v1

- **Tutorial entry** — [[systems/Tutorial]] (Phase 5.3) gets a natural front door.
- **Settings access** — `SettingsMenuGui` exists; surface it.
- **Practice blocks** — a handful of `LetterBlock`s that pop and buffer but grant
  no energy. The lobby should teach the core verb before the portal asks you to
  pick a mode built on it.
- **Live queue counts** — above.

**Not in v1:** the word-PB / progression board. It depends on Phase 5.5
persistence. Leave wall space for it.

## What this does *not* unblock

The lobby is worth building now — it also serves PvE, the tutorial, and later the
progression surface. It is **not** the PvP critical path, and shipping it must not
be mistaken for shipping PvP.

| Blocker | State |
|---|---|
| **Spell damage does not respect the PvP gate** | `GameConfig.PLAYER_VS_PLAYER_ENABLED` gates `applyDamage.process`. Spells do not go through it — they write `Humanoid.Health` directly. Documented as deferred in Phase 5.1 ("unify when 5.4 hardening moves casting server-side"). Flipping the flag changes nothing for the actual damage path. See [[systems/SkillPipeline]] § Damage paths. |
| **Client-trusted affordability** | A client can cast a spell it never earned energy for. Phase 5.4's validated memorize. The build plan already reversed its judgement on this on 2026-08-10 *for exactly this reason*. In a 1v1 it is the most visible cheat there is. |
| **Round timer / countdown off** | `ROUND_TIMER_ENABLED` and `ROUND_COUNTDOWN_ENABLED` are both `false`. A duel with no clock does not end. |
| **Contested blocks** | Closed by Phase 5.7 stage 4 — noted here because it was PvP-only and unreachable in solo play, which is the class of bug this phase will keep finding. |

**Sequencing consequence:** Phase 6 stages 1–5 (container + arenas + broadcast +
hub + PvE) are safe to build against the current trust model, because PvE co-op
cheating is self-cheating. Stage 6 (duels) should land **after** Phase 5.4.

## Interface note

`GameModeDefinition` is kill-centric: `onPlayerKill`, `scoreLimit`,
`checkWinCondition(scores)` over kills/deaths/assists. That fits a duel almost
unchanged. It fits a boss fight badly — modelling "the boss died" as a player
kill is the kind of bend that reads fine for one mode and rots on the third.
Add an objective-shaped win condition rather than overloading kills.

## Broadcast audience

*Added 2026-08-20 after stage 1 shipped.* `RoundManager`'s `FireAllClients` was
not a one-off — it was the first of a class, and the original stage table treated
it as a detail. Eleven `FireAllClients` sites remain in `src/`. They do **not**
all matter equally, and the split is by what the *consumer* does with the
payload, not by which system sends it:

| | Sites | With two arenas live |
|---|---|---|
| **Screen-space (HUD)** | `BossHealthChanged` / `BossPhaseChanged` → `BossHudGui` (`BossService` ×5); `ScoreUpdate` → `ScoreboardGui`, `KillFeed` → `KillFeedGui` (`ScoreTracker` ×3) | **Broken.** A duellist gets the boss's health bar on screen and the boss room's kill feed. Position is irrelevant — it's a GUI. |
| **World-space (VFX)** | `VfxBroadcast` ×5, `VfxBroadcastService` ×1, `SkillDelivery` ×1, boss windup (`BossStates` ×1) | **Costs, doesn't break.** Particles spawn at a world position, so a player in another arena never sees them — but pays to instantiate them. |

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
| 2 | **Arena binding.** `ArenaId` attribute on `BlockSpawnVolume`; per-arena block pools in `BlockSpawner`. New `LobbySpawn` / `PvEArenaSpawn` / `PvPArenaSpawn` tags — `SpawnManager.filterSpawnsForPlayer` already resolves spawns by tag, so this is data. | — |
| 3 | **Broadcast audience.** The six HUD sites above: `ScoreTracker`'s `ScoreUpdate` + `KillFeed` ×2, `BossService`'s `BossHealthChanged` ×3 / `BossPhaseChanged` ×2. Copy the roster pattern stage 1 established. VFX lane explicitly out — see above. | Before stage 5 |
| 4 | **Hub greybox + player state.** Lobby zone, two portals, practice blocks, `InLobby/Queued/InArena` state and the HUD suppression table above. Still `NoOp` behind the portals. | — |
| 5 | **PvE mode.** `Modes/PvEBoss.luau` — co-op, `minPlayers = 1`, objective win condition, boss arena slot. Queue → round → back to lobby. | — |
| 6 | **PvP duel.** `Modes/PvPDuel.luau` — exactly 2, pad pool, `PLAYER_VS_PLAYER_ENABLED = true`, timer + countdown back on. | **After Phase 5.4** |
| 7 | **Wiki + tests.** `wiki/systems/Lobby.md`, `GameMode` page rewritten off its NoOp-only record, session lifecycle tests. | — |

*Stage numbering changed 2026-08-20: broadcast audience inserted as the new stage
3, pushing hub/PvE/duel/wiki from 3–6 to 4–7. Stages 1 and 2 are unmoved.*

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
