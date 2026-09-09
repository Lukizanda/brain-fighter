---
type: system
description: Game mode framework — SessionRegistry (the session tables, as a module) over per-session RoundManager instances that each own a ScoreTracker; per-arena SpawnManager scored against the session roster; mode config carries allowsPvP / timeLimit / countdownSec instead of global flags; BroadcastAudience scopes the remaining screen-space remotes. Registered modes are Lobby and NoOp. Rewritten 2026-09-09 (refactor chunk 8, the Phase 6 stage-7 rewrite).
updated: 2026-09-09
---

# GameMode System

The server runs **sessions**. A session is one mode definition bound to one arena slot, with its own roster, its own round state machine and its own scores. Two exist at boot — the hub (`Lobby`, running `LobbyMode`, never starts a round) and the arena (`Default`, running the mode named by `workspace.ActiveGameMode`, `NoOp` today) — and players move between them by transfer. See [[design/lobby]] § Session model for why this shape.

> The competitive template modes (`FFADeathmatch`, `TeamDeathmatch`, `TeamService`) were deleted in `6610291` (2026-06-22). Refactor chunk 8 (2026-09-09) removed the last of the team plumbing that survived them — `TEAMS_ENABLED`, the friendly-fire branch, nametag team colour, `winnerTeamName`, `getTeamConfig`, `GameModeTypes` — and the three global round flags. Nothing about teams is left to flip.

## Ownership

| Thing | Owner | Lives in |
|---|---|---|
| Which sessions exist, which one a player is in, who is queued | `SessionRegistry` (ModuleScript) | `src/server/GameMode/Scripts/SessionRegistry.luau` |
| One session's roster, round loop and scores | `RoundManager` instance | `Scripts/GameModeService/RoundManager.luau` |
| One session's kills / deaths / assists and their broadcast | `ScoreTracker` instance, constructed by its `RoundManager` | `Scripts/GameModeService/ScoreTracker.luau` |
| The leaderstats mirror and the assist history | `ScoreTracker` module-level (server facts, not session facts) | same file |
| Which pad a player spawns on, per arena | `SpawnManager` | `Scripts/GameModeService/SpawnManager.luau` |
| Boot wiring, the player lifecycle, kill routing | `GameModeService` (Script) | `Scripts/GameModeService/init.server.luau` |
| The `ArenaId` / `PlayerState` Player attributes | `SessionRegistry` — the only writer | — |

## SessionRegistry (2026-09-09)

`GameModeService` used to hold `sessions`, `playerSessions` and `queued` as Script locals and hand them out through three untyped BindableFunctions (`TransferPlayer`, `SetPlayerQueued`, `AllowsPvP`). Those are gone from disk and from Studio. The tables live in a module every consumer requires:

```lua
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

SessionRegistry.initialize({ gameStateChangedRemote, roundStartedEvent, roundEndedEvent, fallbackMode })
SessionRegistry.create(arenaId, modeDefinition)  -- RoundManager.new + SpawnManager.registerArena; does NOT start the loop
SessionRegistry.destroy(arenaId)                 -- unassigns anyone still in it, unregisters the arena, session:destroy()

SessionRegistry.forPlayer(player)   -- Session?
SessionRegistry.forArena(arenaId)   -- Session?
SessionRegistry.rosterOf(arenaId)   -- { Player }? — nil means "no such session", distinct from an empty roster
SessionRegistry.all()

SessionRegistry.assign(player)      -- join → the Lobby session, always
SessionRegistry.unassign(player)
SessionRegistry.transferPlayer(player, targetArenaId)  -- roster move + attributes + pivot to a pad; false if no session
SessionRegistry.setQueued(player, isQueued)            -- false for a player with no session

SessionRegistry.modeFor(player) · arenaIdFor(player) · isRoundActiveFor(player) · allowsPvPFor(victim)
```

Consumers: `GameModeService` (wiring), `LobbyService` (`transferPlayer` / `setQueued` from the portals), `HealthService` (`allowsPvPFor` injected into `applyDamage`), and `BroadcastAudience`, whose resolver `initialize()` registers over these tables.

**`allowsPvPFor` before boot is false.** A hit that lands before `GameModeService.initialize()` has assigned the victim gets "no PvP", not a hang — the BindableFunction it replaced would have yielded forever if invoked unbound, which is why the old one had to be bound at file scope.

**`transferPlayer` pivots, it does not reload.** Reloading resets health, drops the Tool and rebuilds every `ResetOnSpawn` ScreenGui on a path a player crosses several times a session. A dead player is reloaded because there is nothing to pivot. The spawn pick runs *after* the roster move so threat scoring sees the target arena's roster.

## RoundManager — one session

`RoundManager.new(deps)` is the state machine `WaitingForPlayers → Countdown → Active → PostRound → loop`, per session:

- **Roster.** `addPlayer` / `removePlayer` / `getPlayers` / `getPlayerCount`. `_waitForPlayers` gates on the roster count, never on `#Players:GetPlayers()`, so another session's players cannot start this one's round.
- **Scores.** The constructor builds `ScoreTracker.new({}, arenaId)`; roster changes are forwarded to it; `recordKill(killer, victim, cause)` and `getScoreTracker()` expose it. A round start calls `tracker:reset()` on *this* session's members only.
- **Timer and countdown come from the mode config.** `_countdown` runs only if `getConfig().countdownSec` is a positive number; `_activeRound` counts down only if `getConfig().timeLimit` is a number, and asks the mode for a leader when it hits zero. Absent means no countdown / unlimited.
- **Broadcast is per roster.** `_broadcastState` does `FireClient` per member with `{ roundState, timeRemaining, timeLimit, winnerId, winnerName, respawnTime }`. `timeLimit` is the new field: `RoundTimerGui` shows its chrome only when it is present, so an untimed mode never puts "0:00" on screen and two sessions can differ. `winnerTeamName` is gone from the payload and from `GameStateGui`.
- **`RoundStarted` fires with the roster** (chunk 6) — `EconomyService` zeroes each member's energy ledger off it. `RoundEnded` fires `(winnerId, winnerName)`.
- `disable()` is a flag, not `task.cancel` — every await point is a `task.wait` inside an `_isLive(generation)` check, and the `_generation` counter covers the stop-then-start overlap cancel used to guard. `destroy()` disables, clears the roster and destroys the tracker.

## ScoreTracker — one per session (2026-09-09)

Audit F12: the tracker was one server-wide table, so any session's round start zeroed every player on the server and a win check in one arena read the other arena's kills. Now:

- **Instance state** is `scores[Player]` for the session's members. `recordKill` credits the victim's death, the killer's kill and any assistants *that are members*; a killer in another session earns nothing here (cross-session damage is PvP-gated anyway). `reset()` zeroes members and forgets the assist history on their own characters only.
- **Broadcasts go to members.** `ScoreUpdate` is serialized from the instance's members alone, so the scoreboard a player sees lists exactly their session's roster; `KillFeed` lands only on the session the kill happened in. `ScoreTracker` no longer needs `BroadcastAudience`. Payload shapes are unchanged — `ScoreboardGui` and `KillFeedGui` are untouched.
- **Module-level, deliberately:** the leaderstats mirror (`ensureLeaderstats` / `forgetPlayer`, one folder per Player for the life of their connection — a transfer must not rebuild it) and the assist history (`PlayerDamaged` carries no session, and a victim's Humanoid is the same object whichever tracker later asks). The mirror follows whichever session the player is currently scored in: observed Deaths going 1 → 0 on a transfer out of the lobby into a fresh Default round.
- `recordBotKill` is deleted. `victimTeamColor` is therefore never sent; `KillFeedGui` still tolerates its absence.

## SpawnManager — per arena, scored against the roster

`registerArena(arenaId, spawnTag)` binds a slot to the tag its mode authors pads with; a candidate is a `BasePart` carrying that tag whose `Arena.idOf` matches. Nothing tagged → any `SpawnLocation` in the workspace, deliberately unfiltered by arena (the misconfigured-scene path's job is to put the player *somewhere*).

`getBestSpawn(player, arenaId, roster)` scores each candidate by distance to the nearest living enemy **on the roster it is handed** — audit F13: it used to iterate `Players:GetPlayers()`, so a hub player near the arena boundary counted as a threat. Callers pass `session:getPlayers()` / `SessionRegistry.rosterOf(arenaId)`. The team filter (`filterSpawnsForPlayer`, `teamFilter`) is deleted.

`Arena.SpawnTags` now has a `Default` key for the shipped arena's pad. The tag *name* is still `FFASpawn` — that is what `Workspace.Arena.SpawnZone.SpawnLocation` carries (with `ArenaId = Default`), and retagging the pad is a Studio change, not a code change. The old wiki claim that nothing carried `FFASpawn` was stale: the Default arena registers with 1 spawn point.

## Mode config (Q7, 2026-09-09)

`GameModeDefinition.getConfig()` returns a `ModeConfig`:

| Field | Meaning | Lobby | NoOp |
|---|---|---|---|
| `scoreLimit` | kills that end the round | 0 | `math.huge` |
| `timeLimit?` | seconds of Active before a time-out; **absent = unlimited** | absent | absent |
| `countdownSec?` | pre-round countdown; **absent or 0 = skipped** | absent | absent |
| `respawnTime` | `GameModeConstants.RESPAWN_TIME` | 4 | 4 |
| `spawnTag` | one of `Arena.SpawnTags` | `Lobby` | `Default` |
| `runsRounds?` | whether the session's loop is started; absent = true | false | true |
| `allowsPvP?` | player-on-player damage, resolved through the **victim's** session; absent = false | false | false |

`TEAMS_ENABLED`, `ROUND_TIMER_ENABLED` and `ROUND_COUNTDOWN_ENABLED` are deleted from `GameConfig` (`PLAYER_VS_PLAYER_ENABLED` went in chunk 4). A global flag could only ever be right for one session at a time; a duel mode that wants a timer sets `timeLimit` and `countdownSec = GameModeConstants.COUNTDOWN_DURATION` on its own config. `teamBased` is gone; `checkWinCondition` returns `(shouldEnd, winnerUserId)` and `getRoundLeader` returns a user id — no team name anywhere. `onPlayerKill(killer: Player?, victim, cause)` — the third argument is the kill-feed cause id, not a weapon name.

**NoOp's `timeLimit` is deliberately still unlimited.** Chunk 6 noted that the Default round therefore starts exactly once per session and nothing downstream of `RoundStarted` fires twice in a playtest. A finite limit would fix that at the cost of re-firing `RoundStarted` — and the energy-ledger reset that listens to it — every few minutes in the shipped arena, which is a gameplay decision nobody has taken. Round-start isolation is proven by the suite and by a real transfer instead (§ Verification).

## Modes

| Mode | Status | Notes |
|---|---|---|
| Lobby | Live (hub) | `runsRounds = false`; the session holds a roster and pads but its loop is never started, so `RoundManager` needs no notion of a lobby. |
| NoOp | Live (Default arena) | `scoreLimit = math.huge`, no timer, no countdown: the session enters Active once and stays there, which is what spawn protection and the respawn loop key on. |
| PvE Boss | Planned — Phase 6 stage 5 | Co-op, `minPlayers = 1`, objective win condition, boss arena slot. Per-session scores are no longer a prerequisite — done here. |
| PvP Duel | Planned — Phase 6 stage 6, gated behind Phase 5.4 | Exactly 2, pad pool, `allowsPvP = true`, `timeLimit` + `countdownSec` set on its config. |
| FFA Deathmatch / Team Deathmatch | **Deleted** `6610291` | Not recoverable by a flag flip; the modules and now the team plumbing are gone. |

Mode resolution: `workspace:GetAttribute("ActiveGameMode")` looked up in `Modes/init.luau`; unset or unknown falls back to `DEFAULT_MODE = "NoOp"`. The `.rbxl` still says `TeamDeathmatch`, hence the boot line `mode: No-Op (key=NoOp, requested=TeamDeathmatch)`. `LobbyMode` is required directly by `GameModeService` — whether there is a hub is not a configurable question.

## Broadcast audience

`shared/GameMode/BroadcastAudience.luau` is the seam for a screen-space sender that does not hold a roster. After chunk 8 that is **`BossService` only** — `RoundManager` and `ScoreTracker` fire at their own members. `SessionRegistry.initialize()` registers the resolver (`forPlayer` → `playerSessions`, `forArena` → `sessions`); callers resolve per fire, never caching. An unresolved lookup falls back to *everyone* plus a throttled warn, never to an empty audience — a blank HUD is the failure that costs a playtest to notice. World-space VFX keep `FireAllClients` by design ([[systems/VisualEffects]]).

## Player state

`SessionRegistry` publishes two attributes on the Player instance — `ArenaId` and `PlayerState` (`InLobby` / `Queued` / `InArena`) — because attributes replicate on their own and a late-starting LocalScript reads them the moment it asks. The arena half is derived from the session's mode (`runsRounds` → `InArena`); `Queued` is pushed in by `LobbyService` through `setQueued`, since a queued player is standing in the lobby like everybody else. Entering an arena clears the queue flag. `HudGate` and `LobbyService`'s occupancy counts read these.

## Respawn (2026-09-08)

**GameModeService is the only thing that gives a player a character** (chunk 5):

- `Players.CharacterAutoLoads = false` is the first statement of `initialize()`.
- `onPlayerAdded` connects `setupCharacter` to `CharacterAdded` **before** the bare `LoadCharacter()` that gives a joiner their first body (the engine's SpawnLocation pick lands in the lobby, which has no threat scoring to do). Adopts an already-loaded character for a player who was in the server before the Script initialized.
- Every later character comes from the `humanoid.Died` handler: wait `SessionRegistry.modeFor(player).getConfig().respawnTime`, then `SpawnManager.getBestSpawn(player, arenaId, SessionRegistry.rosterOf(arenaId))`, `LoadCharacter`, `PivotTo`. Gated on "has a session", not "round active", so a player who falls off the hub comes back.
- Spawn protection (`ForceField` for `SPAWN_PROTECTION_DURATION`) uses `SessionRegistry.isRoundActiveFor(player)` — the player's own session, not a global round state.

Measured (chunk 5): one `CharacterAdded` per death, in the hub and in the arena.

## Kill routing

`PlayerEliminated` → `GameModeService.onPlayerEliminated` → `SessionRegistry.forPlayer(victim)` → `session:getMode().onPlayerKill(killer, victim, cause)` then `session:recordKill(killer, victim, cause)`. The **victim's** session, because the victim is by definition in the arena the kill happened in. `cause` is `DamageResult.cause` (a skill name, a `DamageTypes.Cause`), which is what the kill feed prints. NPC/dummy victims are not tracked.

## Files

```
src/shared/GameMode/
  Arena.luau                        — arena slot vocabulary: ArenaId attribute, Default/Lobby ids, SpawnTags (Default, Lobby, PvEArena, PvPArena), idOf()
  GameModeConstants.luau            — MIN_PLAYERS, COUNTDOWN_DURATION, INTERMISSION_DURATION, RESPAWN_TIME, spawn offsets, RoundState enum
  GameModeDefinition.luau           — the interface each mode implements; exports ModeConfig, PlayerScore, Scores
  Modes/init.luau                   — mode registry (NoOp + Lobby; DEFAULT_MODE = "NoOp")
  Modes/NoOpMode.luau               — the arena's idle mode
  Modes/LobbyMode.luau              — the hub; runsRounds = false
  BroadcastAudience.luau            — who receives a screen-space remote (resolver registered by SessionRegistry)
  Remotes/                          — GameStateChanged, ScoreUpdate, KillFeed (.model.json each)
src/server/GameMode/
  Events/                           — RoundStarted, RoundEnded BindableEvents (.model.json each). No BindableFunctions.
  Scripts/SessionRegistry.luau      — the session tables (module)
  Scripts/GameModeService/
    init.server.luau                — boot wiring, player lifecycle, kill routing
    RoundManager.luau               — per-session state machine + roster + its ScoreTracker
    ScoreTracker.luau               — per-session scores; module-level leaderstats mirror + assist history
    SpawnManager.luau               — pad pick per arena, scored against a roster
  Scripts/NametagService.server.luau — neutral-coloured nametags above heads
src/shared/Tests/Suites/Multiplayer/
  sessions_isolate_scores · transfer_moves_roster_and_attributes · registry_views_agree · multiplayer_invariants
```

## Verification (2026-09-09, chunk 8)

- **Suite** (`RunTests = all`): 33 tests. `sessions_isolate_scores` seeds a death on the lobby tracker, starts a round in a second session whose roster also holds the one harness player, and asserts the lobby's deaths survive and `RoundStarted` carried exactly the test roster. `transfer_moves_roster_and_attributes` and `registry_views_agree` round-trip the real `transferPlayer` into a throwaway arena and back.
- **Single-client playtest, real portal path:** death-zone kill while in the lobby → client received `KillFeed` + a **1-row** `ScoreUpdate` (`d1`, `ArenaId=Lobby`). `PortalRequest(join)` on the PvE pad → `Transferred Lobby → Default`, attributes flipped to `Default` / `InArena`, `[Default] Scores reset` + `Round started! Timer: none`, client received a **1-row** `ScoreUpdate` (`d0`, `ArenaId=Default`) and `GameStateChanged Active timeLimit=nil`; **no** `[Lobby] Scores reset` or `[Lobby] Round started` followed; `RoundTimerGui`'s container stayed `Visible = false` on the client; leaderstats mirror went Deaths 1 → 0 with the session.
- **Two-client half** (each scoreboard lists only its own session's roster; a Default round start leaves the *other* player's lobby scores alone) is user-driven with `nimbalyst-local/chunk8-client-scoreboard.lua` — see the chunk's divergence note in [[design/refactor-plan-2026-09]] for whether it ran.

## Cross-references

- Phase 6 session/lobby plan → [[design/lobby]], [[design/build-plan]] § Phase 6; the audit findings this page closes → [[design/system-audit-2026-09]] F12, F13, F16, F34, Q6, Q7
- PvP gate mechanism → [[systems/Health]] § PvP gate
- Death zone wiring → `src/server/Arena/DeathZoneService.server.luau`
- Boss HUD remotes use the broadcast seam → [[systems/Boss]] § Broadcast audience
