---
type: concept
description: How to write integration tests for server-authoritative multiplayer paths using the existing TestRunner harness + a synthetic enemy
updated: 2026-05-01
---

# Multiplayer Test Pattern

**Files:** [`src/shared/Tests/TestRunner.luau`](../../src/shared/Tests/TestRunner.luau) (the harness), [`src/server/Tests/TestAutoRunner.server.luau`](../../src/server/Tests/TestAutoRunner.server.luau) (the playtest-side driver), [`src/shared/Tests/Suites/Multiplayer/`](../../src/shared/Tests/Suites/Multiplayer/) (the suite).

## Why this pattern exists

Real two-client integration tests in Roblox need either Studio's "Start Server + 2 Players" mode or two coordinated published-game sessions. Neither is drivable from the agent's MCP tooling against a single Studio session. So the common testing path "client A fires at client B" can't be automated end-to-end.

But most multiplayer regressions on this project have been server-authoritative bugs — `applyDamage` rejecting valid hits, `ScoreTracker` not crediting kills, FF filter false-positives — and **those are reachable from a single-client playtest** if you can stage a synthetic enemy and call into the server modules directly. That's what this pattern does.

It deliberately skips wire-level multiplayer (does the ReplicateShot signal arrive on a remote client? does the cross-VM `os.clock()` drift cause issues?). Those need real two-client setup and stay deferred until a way to drive two clients from the harness exists.

## The harness

`TestRunner.luau` runs each test as `setup → run → verify → teardown`, sharing a `ctx` table. Tests are ModuleScripts under `src/shared/Tests/Suites/<SuiteName>/`. The `TestAutoRunner.server.luau` script reads `workspace:GetAttribute("RunTests")` at playtest boot and runs the named suite (or `"all"`).

After a suite finishes, the autorunner writes per-test results to `workspace.TestResult_<SuiteName>_<sanitised name>` attributes plus a `workspace.TestRunSummary` summary. **Read those instead of console output** — Studio's console truncates long playtests, drops the tail, and may hide your `[TEST PASS]` markers. The attribute readout via MCP `execute_luau` is the reliable signal.

## How to drive a suite from the agent

```
1. Set workspace.RunTests = "<SuiteName>" via MCP execute_luau
2. mcp_start_stop_play(true)
3. Wait ~25s for: 10s round countdown + 3s startup delay + test runtime
4. Read workspace.TestRunSummary + workspace.TestResult_* attributes
5. mcp_start_stop_play(false)
6. Reset workspace.RunTests = nil for future playtests
```

The autorunner waits up to 10s for at least one player; if you start the playtest in a mode where players take longer to land, raise `PLAYER_WAIT_TIMEOUT`.

## How to write a multiplayer test

Two test shapes are useful:

### Shape 1 — structural invariants (fast, cheap, catches placement bugs)

Pure server-side asserts on the boot-time DataModel. No `setup`/`run`/`teardown`, just `verify`. Example: [`multiplayer_invariants.luau`](../../src/shared/Tests/Suites/Multiplayer/multiplayer_invariants.luau) — asserts `ShotReplication` LocalScript is parented to `StarterPlayerScripts` (would have caught the dead-in-ReplicatedStorage trap), all multiplayer remotes exist at expected paths, both team SpawnLocations exist when TDM is active.

These run in milliseconds and catch the kind of bug that ships unnoticed for the project's lifetime.

### Shape 2 — server-authoritative path E2E (synthetic enemy)

Stage a `TargetDummy` clone with `BotTeam` + `BotDisplayName` attributes, call `applyDamage.process(...)` directly with the player as `sourcePlayer` and the bot's `Humanoid` as the target. The full chain runs synchronously: damage applies → `playerEliminatedEvent` fires on lethal → `BotSpawner.onPlayerEliminated` recognises the bot attributes → `ScoreTracker.recordBotKill` credits the killer.

Example: [`applydamage_credits_bot_kill.luau`](../../src/shared/Tests/Suites/Multiplayer/applydamage_credits_bot_kill.luau).

Verify side-effects via `leaderstats.Kills` (or `ScoreTracker.getScore` if you imported it). Set `respawnTime = 0` on the synthetic bot so `DeathHandler` cleans up after the explosion FX rather than templating + respawning, which races the test's teardown.

## Things to keep stable for tests

The kill-credit path runs through `BotSpawner.onPlayerEliminated`, which is registered at server boot regardless of `GameConfig.DEV_BOT_COUNT` (the spawning is gated, the listener is always-on). If you ever refactor `BotSpawner`, keep that listener split — tests depend on it. See the early-return logic at the top of `BotSpawner.server.luau`.

## What this pattern does NOT cover

- **Wire-level multiplayer.** ReplicateShot arriving on a remote client, RemoteEvent payload integrity across the network, cross-VM `os.clock()` timing — these need a real second client. Coverage waits on a harness extension that can drive two clients.
- **Client-side prediction.** Reload parity desync surfaces only on the firing client's HUD; you need the player to actually pull the trigger and watch the magazine count. Tests would either need a programmatic Tool driver or a snapshot of `FirearmController:startReload`'s computed result.
- **Real-player FF filter.** The friendly-fire block in `applyDamage` triggers only when both source and target are real `Player` instances on the same `Team`. Bots aren't Players, so they bypass it. FF coverage waits on the same two-client extension.

## Related

- [[concepts/LocalScriptPlacement]] — caught by the invariants test
- [[concepts/ClientServerPredictionParity]] — class of bug that needs a different test shape
