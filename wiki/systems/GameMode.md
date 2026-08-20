---
type: system
description: Game mode framework — GameModeService as a session manager, per-session RoundManager instances, ScoreTracker, SpawnManager, mode registry. FFA/TDM modes + TeamService DELETED (2026-06-22, commit 6610291); NoOpMode is the only registered mode.
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

`GameModeService` is the **session manager**: it owns `sessions[arenaId]` and `playerSessions[player]`, creates exactly one session at boot (`DEFAULT_ARENA_ID = "Default"`), and assigns every player to it. Behaviour is therefore identical to the singleton — the seam exists for Phase 6 stages 3–5 to hang real arenas off. Where the singleton asked `RoundManager.isActive()`, the service now asks `isPlayerRoundActive(player)`, a `playerSessions` lookup.

**Broadcast is per-roster, not `FireAllClients`.** `_broadcastState` iterates the session's roster and `FireClient`s each member. With one session this is unobservable, but with two live sessions a duellist would otherwise receive the boss arena's round state — that leak is the reason the refactor exists. The **payload shape is unchanged** (`roundState`, `timeRemaining`, `winnerId`, `winnerName`, `winnerTeamName`); `GameStateGui`, `RoundTimerGui` and `DeathScreenGui` consume it untouched. `_waitForPlayers` likewise gates on the roster count rather than `#Players:GetPlayers()`.

**`disable()` does not `task.cancel` the round thread.** The singleton's `stop()` did both, which was redundant — every await point in the machine is a `task.wait` inside an `_isLive` check, so clearing the `_running` flag unwinds the loop on its own within a second. Cancelling additionally errors on a thread that has already finished (the old `stop()` never cleared `roundThread` on natural exit) and would error if a mode callback such as `onRoundEnd` ever called back into the session from the round thread itself. The one thing cancel bought — no overlap between a winding-down loop and a `start()` issued in the same second — is covered by a `_generation` counter the loop checks at every await point.

**Still singletons:** `ScoreTracker` and `SpawnManager`. They have the same server-wide problem; instancing them is Phase 6 stage 2/4 work.

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
  GameModeConstants.luau            — MIN_PLAYERS, durations, RoundState enum
  GameModeDefinition.luau           — the interface each mode implements
  GameModeTypes.luau                — type definitions
  Modes/init.luau                   — mode registry (NoOp only; DEFAULT_MODE = "NoOp")
  Modes/NoOpMode.luau               — the only registered mode
  Remotes/                          — GameStateChanged, ScoreUpdate, KillFeed (.model.json each)
src/server/GameMode/
  Events/                           — RoundStarted, RoundEnded BindableEvents (.model.json each)
  Scripts/GameModeService/
    init.server.luau                — session manager + player/kill wiring
    RoundManager.luau               — per-session state machine: Waiting → Countdown → Active → PostRound
    ScoreTracker.luau               — per-player kills/deaths/assists (still a singleton)
    SpawnManager.luau               — picks SpawnLocation per mode (still a singleton)
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
- Kill feed remote → `gameModeRemotes.KillFeed` (`KillFeedGui` consumes it)
