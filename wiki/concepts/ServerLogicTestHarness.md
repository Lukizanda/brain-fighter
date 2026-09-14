---
type: concept
description: How to test server-only Roblox logic deterministically when MCP only gives you client-side execute_luau — write a gated `.server.luau` driver
updated: 2026-09-14
---

# Server-Logic Test Harness

**Files in the pattern:** `src/server/Dev/DevSmokeTestKillFeed.server.luau` (the one surviving example, gated on `GameConfig.DEV_SMOKE_KILLFEED`). `SimulateLoadoutCycling`, `DevAutoEquipTool` and `BotSpawner` — the original working examples — were deleted as dead dev tooling in refactor chunk 0 (`ba9891d`, 2026-09-08) along with their `GameConfig` flags.

> **Status (2026-09):** mostly superseded. The reason this pattern existed — server-only logic is unreachable from client-context `execute_luau` — is now solved by the in-Studio harness in [[systems/Tests]]: `TestAutoRunner` is itself a server Script, so a suite module can `require(ServerScriptService.Server.*)` and drive `applyDamage`, `EnergyLedger`, `BlockShootValidation` or `SessionRegistry` directly, with results in `workspace.TestResult_*` attributes. The Hardening, Economy and Multiplayer suites all do exactly this. **Prefer writing a suite test.** Reach for a gated dev script only when the check is a one-off visual smoke (like the kill-feed script) or needs to run outside a test suite's lifecycle. The mechanics below still apply to that case.

## The problem

Almost all the bugs that cost real time on this project live in the **server VM** — `applyDamage`, `ScoreTracker`, `EnergyLedger`, `SessionRegistry` (and, when this page was written, the since-deleted `LoadoutService` and `RespawnPedestalManager`). Their inputs are server-side: a Tool re-parented to `Backpack`, a `Humanoid:Died` event, a `BindableEvent:Fire`. Most of them are not directly user-facing — the user-facing UX is downstream, on the client.

The agent's MCP tooling only gives `execute_luau` that runs in **client / plugin context**. From there:

- Setting `tool.Parent = lp.Backpack` is a local-only edit; the server never sees it.
- `RemoteEvent:FireClient` is a server-only method; calling it from `execute_luau` errors.
- Any `require(ServerScriptService.Server.*)` fails because that service is server-only.

So a fix in `LoadoutService` cannot be validated by an MCP probe. The probe will *appear* to work — client-side state tracking will look fine — while the real server-side bug is untouched. Pushing on that "verification" produces a false positive.

## The pattern

Write a **server-side `.server.luau` script** under `src/server/Dev/` that drives the test. Gate it on a `GameConfig.DEV_*` boolean so it ships in the repo dormant and only runs when explicitly enabled for a session.

The script:

1. Waits for the first player + a settle delay (clear the round countdown).
2. Performs the bug repro using server-side APIs (real `tool.Parent = backpack`, `humanoid:EquipTool`, `playerEliminatedEvent:Fire`, etc.).
3. Writes results to a `workspace.<TestName>Result` attribute as it goes — observable from MCP `execute_luau` after the run.
4. Optionally writes a per-step diagnostic to a separate attribute (`workspace.<Test>Diag`) so you can see the call sequence, not just the final state.

To use:

```sh
1. Edit GameConfig.luau, set DEV_<FLAG> = true
2. Wait for Rojo sync
3. mcp_start_stop_play(true), wait ~25s
4. Read workspace.<Result> + <Diag> attributes via execute_luau
5. mcp_start_stop_play(false), reset the flag to false
```

The result attribute is the source of truth — Studio's console truncates the tail in long playtests and may drop your `[Logger]` lines, but workspace attributes survive cleanly until the playtest ends.

## When to use it

- **Always** before declaring a fix to server-only logic done. See [[concepts/ValidateBeforeShip]].
- For regression tests of cross-process invariants (firearm damage path, kill credit, claim uniqueness, eviction rules).
- For repro environments where coordinating a real second client is impractical (most of solo development).

## When NOT to use it

- The check can be expressed as a `setup → run → verify → teardown` module. Put it in a suite under `src/shared/Tests/Suites/` instead — same server VM, no flag to flip, results in attributes, runs under `RunTests="all"` forever after. See [[systems/Tests]].
- The bug is in client-only code (UI, input handling, animation playback, camera). Use `mcp__Roblox_Studio__execute_luau` directly — it runs in client context where the bug lives.
- The bug genuinely requires two simultaneous network-replicating clients (ReplicateShot delivery, cross-VM `os.clock()` drift). The server-driven harness can't fake the wire layer; you need real two-client setup. See [[concepts/MultiplayerTestPattern]] for what the existing test suite does and doesn't cover.

## Why a `.server.luau` instead of a server-side ModuleScript

The harness should be a top-level `.server.luau` that runs unconditionally at boot (gated by `GameConfig`), not a module that something else calls. Reasons:

1. The gating flag is one place to flip; no second consumer to wire up.
2. The harness self-cleans — when the flag is off it returns early at the top of the script.
3. The pattern parallels `DevSmokeTestKillFeed`, which is in the repo and well-understood.

## Sibling pattern (retired): kill-credit listener stays armed regardless of spawn flag

`BotSpawner.server.luau` (deleted in chunk 0) had its own variant — the `playerEliminatedEvent` listener was wired *outside* the `DEV_BOT_COUNT == 0` early-return, so test code could spawn synthetic bots and have their deaths route through the same kill-credit chain. The lesson survives the script: if you build a harness that depends on a server-side listener, gate the *spawn / drive* logic and leave the *listener* always-on so harness code can use it. See [[concepts/MultiplayerTestPattern]] for why the synthetic-bot shape itself was retired.

## Related

- [[systems/Tests]] — the in-Studio harness that now covers most of what this pattern was for
- [[concepts/MultiplayerTestPattern]] — server-authoritative test suite this harness pattern complements
- [[concepts/ValidateBeforeShip]] — when to use this pattern (always, for server-only fixes)
- Memory `feedback_mcp_clone_replication.md` — the negative version: client-context probes can't validate server logic
