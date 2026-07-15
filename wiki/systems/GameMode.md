---
type: system
description: Game mode framework — RoundManager, ScoreTracker, SpawnManager, mode registry. FFA/TDM modes + TeamService DELETED (2026-06-22, commit 6610291); NoOpMode is the only registered mode.
updated: 2026-07-15
---

# GameMode System

Round-based game modes share a common scaffold: a state-machine round, a per-player score tracker, a spawn manager, and a mode-specific definition. Each mode plugs into the registry under `src/shared/GameMode/`.

> **`FFADeathmatch`, `TeamDeathmatch`, and `TeamService` REMOVED 2026-06-22 (commit `6610291`).** They were gated off since Phase 1 and are now deleted, not just disabled — `Modes/init.luau` is stripped to `NoOpMode`-only and `GameModeService`'s `TeamService` require is gone. The gating section below is retained for historical context, but the competitive modes it describes no longer exist and cannot be re-enabled by flipping a flag. What survives and runs today: `GameModeService`, `RoundManager`, `ScoreTracker`, `SpawnManager`, and `NoOpMode`.

## Current gating (2026-05-13)

Brain Fighter is being repurposed as an educational shooter, so the inherited competitive modes are gated off via `GameConfig.luau`:

- `TEAMS_ENABLED = false` — `TeamDeathmatch` not registered, `TeamService` is a no-op, team UI/nametag colours fall back to neutral.
- `PLAYER_VS_PLAYER_ENABLED = false` — `FFADeathmatch` not registered, player-on-player damage rejected in `applyDamage` and `canPlayerDamageHumanoid`, aim assist ignores other players.
- `ROUND_TIMER_ENABLED = false` — active rounds have no time limit; they end on score only. `RoundTimerGui` exits early (no "0:00" overlay). Flip true to restore the 5-minute cap + timer HUD.
- `ROUND_COUNTDOWN_ENABLED = false` — `RoundManager.countdown()` returns immediately; the round goes live the moment minimum players are met. Flip true to restore the 10-second pre-round delay.

With both flags off the only registered mode is `NoOpMode` (`src/shared/GameMode/Modes/NoOpMode.luau`): a 24-hour idle round with `scoreLimit = math.huge`, no team logic, no win condition. RoundManager enters `Active` once and stays there; GameStateGui's PostRound overlay never fires.

Re-enable by flipping the flags — the FFA / TDM modules are unchanged and re-register automatically. See the inline comments in `src/shared/Core/GameConfig.luau` and `src/shared/GameMode/Modes/init.luau`.

### SpawnLocation must be Neutral while teams are off

`Workspace.Arena.SpawnZone.SpawnLocation` is currently set to `Neutral = true` (TeamColor `Bright red` is left as-is for documentation but ignored). When `TEAMS_ENABLED = false` no `Team` instances are created, so a non-Neutral team-locked SpawnLocation rejects every player — Roblox falls back to a default spawn and the player drops in the sky and falls to their death. Re-enabling teams without re-introducing per-team SpawnLocations is fine: a Neutral pad is also usable by any team via `SpawnManager.filterSpawnsForPlayer`. Re-introducing team-locked pads alongside the Neutral one is the right move if/when team spawning resumes.

## Files

```
src/shared/GameMode/
  GameModeTypes.luau              — type definitions
  Modes/init.luau                 — mode registry
  Modes/FFADeathmatch.luau
  Modes/TeamDeathmatch.luau
src/server/GameMode/Scripts/
  GameModeService/                — orchestrator
    ScoreTracker.luau             — per-player kills/deaths/assists
  RoundManager/                   — generic state machine: Waiting → Countdown → Active → PostRound
  SpawnManager/                   — picks SpawnLocation per mode, handles team-aware spawning
  TeamService/                    — team assignment, auto-balance
  NametagService/                 — team-coloured nametags above heads
src/server/Arena/
  DeathZoneService.server.luau    — fall-kill volume (CollectionService tag "DeathZone")
```

## Mode resolution

Active mode is read from `workspace:GetAttribute("ActiveGameMode")` (default: `FFADeathmatch`). Each mode exposes:

- `getConfig()` — score limit, round time, respawn time, spawn-tag, etc.
- `onPlayerJoin(player)` — hook for mode-specific player setup (team assignment, etc.)

## Round states

```
Waiting   — < min players, idle
Countdown — pre-round delay (skipped when ROUND_COUNTDOWN_ENABLED = false)
Active    — gameplay; ScoreTracker accrues; ends on score limit or time (time disabled when ROUND_TIMER_ENABLED = false)
PostRound — winner overlay, auto-restart timer
```

`RoundManager` exposes `RoundStarted` / `RoundEnded` BindableEvents. Note: these are versioned via per-file `.model.json` (the legacy `children`-array format silently failed Rojo sync — see [[concepts/ModelJsonInstances]]).

## Modes

| Mode | Status | Notes |
|---|---|---|
| FFA Deathmatch | Most of plan shipped | First mode; hardened the round/spawn/score scaffolding. Lessons from the TDM build retroactively apply. |
| Team Deathmatch (TDM) | Steps 1–4 shipped | Step 5 tuning + KillFeed UI consumer outstanding. |
| Control Points | Not built | Greybox geometry ready; `CapturePointService` is the next big build. |

## Friendly fire (TDM)

Friendly-fire block lives in `HealthService.applyDamage.process` (not in TeamService) — that way it applies to any damage path uniformly. See [[systems/Health]].

## Respawn handler ordering

In `onPlayerAdded`, `setupCharacter` (which connects `humanoid.Died` → respawn loop and adds the spawn-protection `ForceField`) is defined as a local function and **connected to `CharacterAdded` BEFORE** any `LoadCharacter()` call. Otherwise the very-first character (when team mode triggers an explicit `LoadCharacter` because `CharacterAutoLoads = false`) gets no Died handler and players appear stuck on the respawn screen after their first death. After connecting, `setupCharacter` is also applied to any already-loaded `player.Character` so non-team modes (Roblox auto-loaded) get the handler too. Fixed `dcd312d`.

## Cross-references

- Death zone wiring → `src/server/Arena/DeathZoneService.server.luau`
- Kill feed remote (consumer not yet built) → `gameModeRemotes.KillFeed`
