---
type: system
description: Game mode framework — GameModeService as a session manager, per-session RoundManager instances, ScoreTracker, per-arena SpawnManager over the shared Arena vocabulary, mode registry, and the BroadcastAudience seam that scopes screen-space remotes to a session roster. FFA/TDM modes + TeamService DELETED (2026-06-22, commit 6610291); NoOpMode is the only registered mode.
updated: 2026-08-20
---

# GameMode System

Round-based game modes share a common scaffold: a **session** (a round state machine bound to an arena slot), a per-player score tracker, a spawn manager, and a mode-specific definition. Each mode plugs into the registry under `src/shared/GameMode/`.

> **`FFADeathmatch`, `TeamDeathmatch`, and `TeamService` REMOVED 2026-06-22 (commit `6610291`).** They were gated off since Phase 1 and are now deleted, not just disabled — `Modes/init.luau` is stripped to `NoOpMode`-only and `GameModeService`'s `TeamService` require is gone. The gating section below is retained for historical context, but the competitive modes it describes no longer exist and cannot be re-enabled by flipping a flag. What survives and runs today: `GameModeService`, `RoundManager`, `ScoreTracker`, `SpawnManager`, `NametagService`, and `NoOpMode`.

## Sessions (Phase 6 stage 1, 2026-08-20)

A **session** is one mode definition bound to one arena slot, running its own round lifecycle over its own roster of players. See [[design/lobby]] § Session model for why this shape.

`RoundManager` used to be a server-wide singleton holding its state in file-locals — one round, one mode, everybody in it. It is now **instance-per-session**:

```lua
local session = RoundManager.new({
    arenaId = "Default",
    gameStateChangedRemote = ..., roundStartedEvent = ..., roundEndedEvent = ...,
    modeDefinition = activeMode, scoreTracker = ScoreTracker,
})
session:addPlayer(player)
session:start()      -- begins the loop
session:disable()    -- reversible halt
session:destroy()    -- disable + drop all state
```

`GameModeService` is the **session manager**: it owns `sessions[arenaId]` and `playerSessions[player]`, creates exactly one session at boot (`Arena.DEFAULT_ID = "Default"`), and assigns every player to it. Behaviour is therefore identical to the singleton — the seam exists for Phase 6 stages 3–5 to hang real arenas off. Where the singleton asked `RoundManager.isActive()`, the service now asks `isPlayerRoundActive(player)`, a `playerSessions` lookup.

**Broadcast is per-roster, not `FireAllClients`.** `_broadcastState` iterates the session's roster and `FireClient`s each member. With one session this is unobservable, but with two live sessions a duellist would otherwise receive the boss arena's round state — that leak is the reason the refactor exists. The **payload shape is unchanged** (`roundState`, `timeRemaining`, `winnerId`, `winnerName`, `winnerTeamName`); `GameStateGui`, `RoundTimerGui` and `DeathScreenGui` consume it untouched. `_waitForPlayers` likewise gates on the roster count rather than `#Players:GetPlayers()`.

**`disable()` does not `task.cancel` the round thread.** The singleton's `stop()` did both, which was redundant — every await point in the machine is a `task.wait` inside an `_isLive` check, so clearing the `_running` flag unwinds the loop on its own within a second. Cancelling additionally errors on a thread that has already finished (the old `stop()` never cleared `roundThread` on natural exit) and would error if a mode callback such as `onRoundEnd` ever called back into the session from the round thread itself. The one thing cancel bought — no overlap between a winding-down loop and a `start()` issued in the same second — is covered by a `_generation` counter the loop checks at every await point.

**Still a singleton:** `ScoreTracker`. Its *audience* was scoped in stage 3 (below), but its scores remain server-wide — that is stage 5 work.

## Arena binding (Phase 6 stage 2, 2026-08-20)

A session names an arena slot; stage 2 gave that name something to resolve against. `src/shared/GameMode/Arena.luau` is the shared vocabulary — `ID_ATTRIBUTE = "ArenaId"`, `DEFAULT_ID = "Default"`, the `SpawnTags` table, and `Arena.idOf(instance)`. It exists because three scripts across two domains read those strings, and as literals they would be three copies of a coupling with nothing holding them in step. [[systems/BlockSpawner]] and [[systems/Boss]] resolve arenas through the same module.

**`Arena.idOf` treats a missing attribute as `DEFAULT_ID`**, which is the load-bearing decision. The shipped scene's parts are tagged but unattributed; requiring the attribute would have stopped the shipped arena working while every log stayed clean.

### SpawnManager is per-arena

`getSpawnPoints()` read one file-local `spawnTag` set at `initialize()`. It now keys off the arena:

| | Before | After |
|---|---|---|
| Registration | `initialize({ spawnTag })`, once | `registerArena(arenaId, spawnTag)`, called by `createSession` as each session is built |
| Candidate set | every part carrying the tag | parts carrying **that arena's** tag whose `Arena.idOf` matches |
| Lookup | `getBestSpawn(player)` | `getBestSpawn(player, arenaId)`, resolved from `playerSessions` |

Two arenas can therefore share a tag name and still keep their pads apart — which is what stage 6's pad pool needs, since both duel pads are `PvPArenaSpawn`.

`Arena.SpawnTags` declares `LobbySpawn` / `PvEArenaSpawn` / `PvPArenaSpawn` ahead of the geometry that will carry them (stages 4–6), so scene authoring and mode config cannot pick different spellings of the same idea. Nothing is tagged with them yet.

**The `SpawnLocation` fallback is deliberately *not* filtered by arena.** It is the misconfigured-scene path — nothing is tagged for this arena — and its job is to put the player somewhere rather than at origin; narrowing it by arena would make the empty case empty again. The shipped place reaches this path on every spawn: `NoOpMode`'s `spawnTag` is `FFASpawn` and nothing in the scene carries that tag, so every player lands on `Workspace.Arena.SpawnZone.SpawnLocation`. `filterSpawnsForPlayer` is unchanged — it was already tag/attribute-driven, and its `TEAMS_ENABLED` early-out still short-circuits the whole team path.

## Broadcast audience (Phase 6 stage 3, 2026-08-20)

`RoundManager` can fire at its own roster because it holds one. The other
screen-space senders cannot: `ScoreTracker` is a server-wide singleton, and
`BossService` is a top-level Script that nothing injects into. Rather than give
each of them its own answer, stage 3 added one seam.

`src/shared/GameMode/BroadcastAudience.luau` is a late-binding pointer at the
session tables — it stores **no roster of its own**. `GameModeService`
registers a resolver at the top of `initialize()`:

```lua
BroadcastAudience.setResolver({
    forPlayer = function(player) local s = playerSessions[player] return s and s:getPlayers() end,
    forArena  = function(arenaId) local s = sessions[arenaId]     return s and s:getPlayers() end,
})
```

and callers resolve **per fire**, never caching, because a roster changes under
a long-lived boss. `BroadcastAudience.fire(remote, audience, ...)` then does the
`FireClient` loop, skipping players who left since resolution.

**The fallback is everyone, not nobody.** An unresolved lookup returns
`Players:GetPlayers()` — today's pre-stage-3 behaviour — plus a warn throttled
to 30 s (the boss health path fires at 10 Hz and would otherwise bury the log).
Degrading to an empty audience would silently blank a HUD, which is the failure
mode that costs a playtest to notice. Returning an *empty table* from a resolver
is distinct and is honoured as-is: that means "a real session with nobody in it".

The nine screen-space sites now scoped:

| Remote | Sites | Audience anchor |
|---|---|---|
| `ScoreUpdate` | `ScoreTracker` ×1 | the kill's victim (or the round-starting session's roster, via `resetAll(audience)`) |
| `KillFeed` | `ScoreTracker` ×2 | victim for a player kill, killer for a bot kill |
| `BossPhaseChanged` | `BossService` ×3 | `Arena.idOf(BossPoint)` |
| `BossHealthChanged` | `BossService` ×3 | `Arena.idOf(BossPoint)` |

Kill feed is anchored on the **victim, not the killer** — a victim is always a
real `Player` in a session, where an environment kill has no killer to resolve
from. `recordBotKill` inverts this of necessity: its victim is a bot.

**`ScoreTracker`'s scores are still server-wide** — only its *audience* moved.
A duellist therefore still reads the boss arena's names off their scoreboard;
what stage 3 fixes is the kill feed scrolling past for a fight they are not in.
Per-session score state is stage 5. This was a deliberate split: the payload
shape had to stay byte-identical because `ScoreboardGui` and `KillFeedGui` are
out of scope.

**Out of scope by design:** the eight world-space VFX sites keep
`FireAllClients`. Particles spawn at a world position, so another arena never
renders them — only pays to instantiate them, which is a throughput question
[[systems/VisualEffects]]' `PERF` guardrails already own. See [[design/lobby]]
§ Broadcast audience for the full inventory.

## Current gating (2026-05-13)

Brain Fighter is being repurposed as an educational shooter, so the inherited competitive modes are gated off via `GameConfig.luau`:

- `TEAMS_ENABLED = false` — `TeamDeathmatch` not registered, `TeamService` is a no-op, team UI/nametag colours fall back to neutral.
- `PLAYER_VS_PLAYER_ENABLED = false` — `FFADeathmatch` not registered, player-on-player damage rejected in `applyDamage` and `canPlayerDamageHumanoid`, aim assist ignores other players. **Note:** this flag does *not* gate the damage path spells actually use — they write `Humanoid.Health` directly. See [[design/lobby]] § What this does not unblock.
- `ROUND_TIMER_ENABLED = false` — active rounds have no time limit; they end on score only. `RoundTimerGui` exits early (no "0:00" overlay). Flip true to restore the 5-minute cap + timer HUD.
- `ROUND_COUNTDOWN_ENABLED = false` — `RoundManager:_countdown()` returns immediately; the round goes live the moment minimum players are met. Flip true to restore the 10-second pre-round delay.

All three round/PvP flags are owned by **Phase 6 stage 5**, which is gated behind Phase 5.4 — do not flip them ad hoc.

With both flags off the only registered mode is `NoOpMode` (`src/shared/GameMode/Modes/NoOpMode.luau`): a 24-hour idle round with `scoreLimit = math.huge`, no team logic, no win condition. The session enters `Active` once and stays there; GameStateGui's PostRound overlay never fires.

### SpawnLocation must be Neutral while teams are off

`Workspace.Arena.SpawnZone.SpawnLocation` is currently set to `Neutral = true` (TeamColor `Bright red` is left as-is for documentation but ignored). When `TEAMS_ENABLED = false` no `Team` instances are created, so a non-Neutral team-locked SpawnLocation rejects every player — Roblox falls back to a default spawn and the player drops in the sky and falls to their death. Re-enabling teams without re-introducing per-team SpawnLocations is fine: a Neutral pad is also usable by any team via `SpawnManager.filterSpawnsForPlayer`. Re-introducing team-locked pads alongside the Neutral one is the right move if/when team spawning resumes.

## Files

```
src/shared/GameMode/
  Arena.luau                        — arena slot vocabulary: ArenaId attribute, Default id, SpawnTags, idOf()
  GameModeConstants.luau            — MIN_PLAYERS, durations, RoundState enum
  GameModeDefinition.luau           — the interface each mode implements
  GameModeTypes.luau                — type definitions
  Modes/init.luau                   — mode registry (NoOp only; DEFAULT_MODE = "NoOp")
  Modes/NoOpMode.luau               — the only registered mode
  BroadcastAudience.luau            — who receives a screen-space remote (resolver registered by GameModeService)
  Remotes/                          — GameStateChanged, ScoreUpdate, KillFeed (.model.json each)
src/server/GameMode/
  Events/                           — RoundStarted, RoundEnded BindableEvents (.model.json each)
  Scripts/GameModeService/
    init.server.luau                — session manager + player/kill wiring
    RoundManager.luau               — per-session state machine: Waiting → Countdown → Active → PostRound
    ScoreTracker.luau               — per-player kills/deaths/assists (scores still server-wide; audience scoped stage 3)
    SpawnManager.luau               — picks a spawn per arena; SpawnLocation fallback when nothing is tagged
  Scripts/NametagService.server.luau — nametags above heads
src/server/Arena/
  DeathZoneService.server.luau      — fall-kill volume (CollectionService tag "DeathZone")
```

## Mode resolution

Active mode is read from `workspace:GetAttribute("ActiveGameMode")` and looked up in `Modes/init.luau`; unset or unknown keys fall back to `DEFAULT_MODE = "NoOp"`. (The attribute in the current `.rbxl` is still `TeamDeathmatch`, a mode that no longer exists — it resolves to `NoOp`, which is why the boot log reads `mode: No-Op (key=NoOp, requested=TeamDeathmatch)`.) Each mode exposes:

- `getConfig()` — score limit, round time, respawn time, spawn-tag, etc.
- `onPlayerJoin(player)` — hook for mode-specific player setup
- `onRoundStart()` / `onRoundEnd()` / `onPlayerKill(...)`
- `checkWinCondition(scores)` / `getRoundLeader(scores)`

`GameModeDefinition` is kill-centric, which fits a duel nearly unchanged and a boss fight badly — [[design/lobby]] § Interface note records the decision to add an objective-shaped win condition rather than model "the boss died" as a player kill.

## Round states

```
Waiting   — roster below MIN_PLAYERS, idle
Countdown — pre-round delay (skipped when ROUND_COUNTDOWN_ENABLED = false)
Active    — gameplay; ScoreTracker accrues; ends on score limit or time (time disabled when ROUND_TIMER_ENABLED = false)
PostRound — winner overlay, auto-restart timer
```

`RoundStarted` / `RoundEnded` BindableEvents are fired by each session. Note: these are versioned via per-file `.model.json` (the legacy `children`-array format silently failed Rojo sync — see [[concepts/ModelJsonInstances]]).

## Modes

| Mode | Status | Notes |
|---|---|---|
| NoOp | Live | The only registered mode. 24-hour idle round, `scoreLimit = math.huge`; the session parks in `Active`. |
| PvE Boss | Planned — Phase 6 stage 4 | Co-op, `minPlayers = 1`, objective win condition, boss arena slot. |
| PvP Duel | Planned — Phase 6 stage 5, gated behind Phase 5.4 | Exactly 2 players, pad pool, timer + countdown back on. |
| FFA Deathmatch / Team Deathmatch | **Deleted** `6610291` | Not recoverable by a flag flip; the modules are gone. |

## Friendly fire

The friendly-fire block lives in `HealthService.applyDamage.process` (not in the deleted `TeamService`) — that way it applies to any damage path uniformly. See [[systems/Health]]. Dormant while `TEAMS_ENABLED = false`.

## Respawn handler ordering

In `onPlayerAdded`, `setupCharacter` (which connects `humanoid.Died` → respawn loop and adds the spawn-protection `ForceField`) is defined as a local function and **connected to `CharacterAdded` BEFORE** any `LoadCharacter()` call. Otherwise the very-first character (when team mode triggers an explicit `LoadCharacter` because `CharacterAutoLoads = false`) gets no Died handler and players appear stuck on the respawn screen after their first death. After connecting, `setupCharacter` is also applied to any already-loaded `player.Character` so non-team modes (Roblox auto-loaded) get the handler too. Fixed `dcd312d`.

Both the ForceField and the respawn use `isPlayerRoundActive(player)` — the player's own session — rather than a global round state.

## Cross-references

- Phase 6 session/lobby plan → [[design/lobby]], [[design/build-plan]] § Phase 6
- Death zone wiring → `src/server/Arena/DeathZoneService.server.luau`
- Kill feed remote → `gameModeRemotes.KillFeed` (`KillFeedGui` consumes it), scoped per session — see § Broadcast audience
- Boss HUD remotes use the same seam → [[systems/Boss]] § Broadcast audience
