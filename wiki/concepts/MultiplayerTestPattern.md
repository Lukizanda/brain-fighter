---
type: concept
description: How to write integration tests for server-authoritative multiplayer paths using the existing TestRunner harness + a synthetic enemy
updated: 2026-09-14
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

Three test shapes are in use:

### Shape 1 — structural invariants (fast, cheap, catches placement bugs)

Pure server-side asserts on the boot-time DataModel. No `setup`/`run`/`teardown`, just `verify`. Example: [`multiplayer_invariants.luau`](../../src/shared/Tests/Suites/Multiplayer/multiplayer_invariants.luau) — asserts the GameMode remotes (`KillFeed`, `ScoreUpdate`, `GameStateChanged`) exist at their expected paths with the right class, the Health `PlayerDamaged` / `PlayerEliminated` BindableEvents exist, and at least one player is present for `ctx.player`.

It used to also assert `ShotReplication` was parented to `StarterPlayerScripts` (the dead-in-ReplicatedStorage trap, see [[concepts/LocalScriptPlacement]]). That script was deliberately deleted in `6610291`, and the stale assertion was trimmed on 2026-09-08 (`f8d9dc1`) — the canonical example of the stale-assertion pitfall in [[systems/Tests]].

These run in milliseconds and catch the kind of bug that ships unnoticed for the project's lifetime.

### Shape 3 — session-scoped tests with one real player (chunk 8, 2026-09)

Multiplayer-shaped bugs that are really "two sessions share a table" bugs do not need two clients. [[systems/GameMode]]'s `SessionRegistry` lets a test create a throwaway session/arena, move the single harness player into it with the real `transferPlayer`, assert, and move them back in `teardown`. Three tests use this:

- `registry_views_agree` — `forPlayer` / `forArena` / `rosterOf` agree for every session after a transfer; the lobby queue flag is set in the lobby and cleared on transfer out.
- `sessions_isolate_scores` — starting a round in a second session no longer zeroes the first session's `ScoreTracker` (the F12 bug).
- `transfer_moves_roster_and_attributes` — a transfer moves both the roster entry and the `ArenaId` / `PlayerState` Player attributes, in both directions.

The character genuinely pivots between arenas during these, so a following test in an `"all"` run inherits a player standing on a lobby pad, not wherever it left them.

### Shape 2 — server-authoritative path E2E (synthetic enemy) — retired

Historical: staged a `TargetDummy` clone with `BotTeam`/`BotDisplayName` attributes and called `applyDamage.process(...)` directly, relying on `BotSpawner.onPlayerEliminated` to credit the kill via `ScoreTracker.recordBotKill`. `BotSpawner` was deleted in the 2026-09 refactor (Chunk 0 — it was the only listener crediting synthetic bot kills, and it was dead dev tooling), and its test, `applydamage_credits_bot_kill.luau`, was deleted alongside the rest of the dead Multiplayer suite files in Chunk 1 (`wiki/design/refactor-plan-2026-09.md`). No replacement shape exists yet for exercising the server-authoritative damage path end-to-end without a real second client.

## What this pattern does NOT cover

- **Wire-level multiplayer.** ReplicateShot arriving on a remote client, RemoteEvent payload integrity across the network, cross-VM `os.clock()` timing — these need a real second client. Coverage waits on a harness extension that can drive two clients.
- **Client-side prediction.** Reload parity desync surfaces only on the firing client's HUD; you need the player to actually pull the trigger and watch the magazine count. Tests would either need a programmatic Tool driver or a snapshot of `FirearmController:startReload`'s computed result.
- **Real-player FF filter.** The friendly-fire block in `applyDamage` triggers only when both source and target are real `Player` instances on the same `Team`. Bots aren't Players, so they bypass it. FF coverage waits on the same two-client extension.

## Related

- [[systems/Tests]] — the harness itself: discovery rules, result attributes, suite table
- [[concepts/ServerLogicTestHarness]] — the older gated-`.server.luau` alternative for server-only logic
- [[concepts/LocalScriptPlacement]] — the class of bug Shape 1 catches
- [[concepts/ClientServerPredictionParity]] — class of bug that needs a different test shape
