---
type: system
description: In-Studio test harness — TestRunner module + Suites/{NPC,Multiplayer,Phase3,Skills,Hardening,Economy,Unit}, one Suites/Unit wrapper per pure-Luau __tests module. MCP-driven via test-runner subagent.
updated: 2026-09-08
---

# Test System

Lightweight in-Studio test harness for gameplay systems. Tests run inside Studio (not as unit tests outside the engine) so they can exercise real Humanoid / Tool / Animation behavior — including the pure-Luau modules, which could run standalone but are wired in here anyway so one `RunTests="all"` catches everything.

## Files

```
src/shared/Tests/
  TestRunner.luau               — generic test runner (declares, runs, reports)
  Helpers/
    ensurePatroller.luau         — NPC suite fixture: reuse-or-clone Patroller_1
  Suites/
    NPC/
      combat_engages.luau
      combat_disengages.luau
      npc_deals_damage.luau
    Multiplayer/
      multiplayer_invariants.luau
    Phase3/ · Skills/ · Hardening/ · Economy/
    Unit/
      wordbuffer_tests.luau · energyeconomy_tests.luau · energyreservoirs_tests.luau
      dictionary_tests.luau · spellregistry_tests.luau · memorizeaction_tests.luau
      mindfullmanager_tests.luau · hud_tests.luau

src/server/Tests/
  TestAutoRunner.server.luau    — invoked at boot when a workspace flag is set, runs a named suite, prints results
```

`Suites/Melee/` was deleted in the 2026-09 refactor (chunk 1) — the melee chain is dead code (chunk 11 removes the modules it exercised). `Helpers/restoreToSafeSpawn.luau` was deleted alongside it (its only callers were the Multiplayer suite files removed in the same pass).

## Discovery rules

`TestAutoRunner.server.luau` is a server-only Script. At boot it reads `workspace:GetAttribute("RunTests")`:

- unset / empty string → the script returns immediately, no suites run.
- a suite folder name (e.g. `"NPC"`) → requires every `ModuleScript` directly under `ReplicatedStorage.Shared.Tests.Suites.<name>` and runs them as one suite.
- `"all"` → does that for every `Folder` directly under `Suites`.

A child is only counted as a test if `require`ing it succeeds AND the result is a table with a `.name` field. Anything else (a stray non-ModuleScript, or a ModuleScript that doesn't return the right shape) logs `[AUTORUN WARN] Skipped <name>: ...` and is dropped from the suite silently — **this chunk's whole point was to get that WARN count to zero**, because a silently-skipped test used to read as a passing suite. A `RunTests="all"` run with any `[AUTORUN WARN] Skipped` line means something in `Suites/` isn't wired right, not that everything is fine.

Because the autorunner only ever runs server-side, **any suite requiring `Players.LocalPlayer` cannot execute through it** — see `hud_tests` below.

## `__tests.luau` wiring — two idioms

Every gameplay module with its own `src/shared/<Module>/__tests.luau` gets a thin wrapper ModuleScript under `Suites/Skills/` or `Suites/Unit/` with this shape:

```lua
return {
	name = "some_tests",
	run = function(_ctx) require(ReplicatedStorage.Shared.<Module>:FindFirstChild("__tests")).run() end,
}
```

`TestRunner.run` treats a wrapper with no `verify` as "passed unless `run` throws" — so the `__tests` module itself must throw (via `error`/`assert`) on any failed case, and simply return normally on success. This is the idiom `CastAction`, `Dictionary`, `EnergyEconomy`, `EnergyReservoirs`, `MemorizeAction`, `MindFullManager`, `Skills` and `WordBuffer`'s `__tests.luau` all use — exposing `M.run()` (or, for `WordBuffer`, `{ run = runTests }`).

`SpellExecutor` and `SpellRegistry` use the other idiom: their `__tests.luau` exposes `.runAll()` returning `(passed, failed)` counts instead of throwing, because their case tables run every case even after one fails (so one bad case doesn't hide the rest). Their wrappers (`spellexecutor_tests.luau`, `spellregistry_tests.luau`) capture the tuple into `ctx` in `run` and check `failed == 0` in `verify`. **Don't force these into the throw-on-fail idiom** — the tuple form is deliberate (see `SpellExecutor.__tests.luau`'s own header comment).

Requiring any `__tests.luau` must be side-effect-free — the assertions only run inside `.run()`/`.runAll()`. Two modules got this wrong before the 2026-09 refactor (chunk 1): `Dictionary` and `EnergyEconomy` executed their asserts at the top level, so merely `require`ing them (e.g. from another script, or Rojo's own instantiation) would throw. Both are now wrapped. `WordBuffer.__tests` returned a bare function instead of a table — also fixed, since the autorunner's `collectTestsInFolder` only accepts a table with `.name`.

## Fixture requirements

- **NPC suites** need a live, ticking `workspace.Patroller_1` with a real `NPCController` behind it — not just the raw rig Model. `NPCService.server.luau` boot-spawns one from `ServerStorage.AIWorldData` spawn points before `TestAutoRunner`'s startup delay elapses, which is the fixture in the common case. `Helpers/ensurePatroller.luau` is the fallback: if no `Patroller_1` exists, it clones `ServerStorage.AIWorldData.Rigs.Patroller`, constructs an `NPCController` directly (the same module `NPCService` uses — it's a requireable ModuleScript, not locked inside the Script), and ticks it on `Heartbeat` for the test's duration. `teardown` only tears down what it created; a boot-spawned `Patroller_1` is never touched, since it's shared state other systems (and other tests in the same `"all"` run) depend on.
- **Hardening suite** drives `BlockShootValidation` / `SpellCastValidation` directly rather than firing the remotes, because the most important input — a table wearing a Model's property names — cannot be sent from a test that already runs on the server. These modules live under `ReplicatedStorage.Shared.Tests` but reach into `ServerScriptService.Server.*`, which is valid because `TestAutoRunner` is a server Script.
- **`hud_tests` (Unit)** is VM-gated, not fixture-gated: `Hud/__tests.luau` requires `Players.LocalPlayer` and errors immediately on a server VM (see its own "Client only" header). Since there is no client-side autorunner, `Suites/Unit/hud_tests.luau` checks `RunService:IsServer()` and reports an explicit pass with a `"skipped — client-only ..."` message instead of a false `[TEST FAIL]` for a harness gap. On an actual client VM it runs the real `HudGate` suite.

## Suite table

| Suite | Status | Covers |
|---|---|---|
| NPC | LIVE (fixture-gated via `ensurePatroller`) | Combat engage/disengage state transitions, NPC-deals-damage — [[systems/NPC]] |
| Multiplayer | LIVE (1 test — `multiplayer_invariants`) | Boot-time structural invariants: ShotReplication placement, GameMode remotes, PlayerDamaged/PlayerEliminated events |
| Phase3 | LIVE (7 tests) | BlockSpawner pool/refill/bounds/respawn-delay, BlockShoot helpers/remote — [[systems/BlockShoot]] |
| Skills | LIVE (5 tests) | SkillInterrupt lifecycle, SpellExecutor case table, CastAction scenarios, cast-rejection, predicted-vs-authoritative |
| Hardening | LIVE (3 tests) | [[systems/BlockShoot]] § Trust model, [[systems/SpellCastService]] § Trust model |
| Economy | LIVE (1 test) | Ledger pricing |
| Unit | LIVE (8 tests) | WordBuffer, EnergyEconomy, EnergyReservoirs, Dictionary, SpellRegistry, MemorizeAction, MindFullManager (all real runs) + Hud (server-VM skip, real on client) |
| Melee | **deleted** (chunk 1, 2026-09-08) | Was: MeleeHitDetector sweep. Dead code — [[systems/Weapon]] melee path is unused; chunk 11 removes the modules |

Deleted alongside Melee: `Suites/Multiplayer/{drop_request_zone_gated,respawnzone_tracks_hrp_presence,applydamage_credits_bot_kill}.luau` (their C1/C2 deliverables and the bot-spawner they exercised are gone — see `wiki/design/refactor-plan-2026-09.md` Chunk 0/1) and `Helpers/restoreToSafeSpawn.luau` (only caller was `respawnzone_tracks_hrp_presence`).

## Known failing tests (real bugs, not harness bugs)

As of the 2026-09-08 `RunTests="all"` run (26/28 passed):

- **`Suites/NPC/npc_deals_damage`** — intermittent: fails "Player took no damage" when the preceding `combat_disengages` test leaves the player mid-fall/respawn (`DeathZoneService` → `HealthService` reset) right as this test snapshots `ctx.initialHealth`. Cross-test interference in the existing suite bodies, not something chunk 1 introduced or is scoped to fix.
- **`Suites/Multiplayer/multiplayer_invariants`** — fails "ShotReplication LocalScript missing from StarterPlayerScripts". This is the placement bug the test exists to catch (see `wiki/concepts/LocalScriptPlacement.md`), currently regressed.

## Running tests

User-facing entry: `/run-tests` slash command, which dispatches the `test-runner` subagent. Default suite is `NPC`.

**Clear `workspace:SetAttribute("RunTests", nil)` as soon as a run reports `[AUTORUN DONE]`** — the attribute persists in the `.rbxl` and silently re-fires the autorunner on every later playtest, contaminating non-test sessions with test fixtures. `TestResult_*` and `TestRunSummary` attributes are runtime-only and clear on play-stop; only `RunTests` needs the explicit nil.

The subagent drives a real playtest via MCP, parses TestRunner output, reports pass/fail.

## Test design conventions

- **No mocks** for in-engine behavior. Tests spawn real Humanoids, Tools, etc. (see `feedback_cross_process_testing.md` in auto-memory.)
- Tests that require player input (e.g. firearm fire) cannot be MCP-driven — those are documented as "manual playtest" in their respective status pages.
- Cross-VM time uses `workspace:GetServerTimeNow()`, not `os.clock()` (different per VM). See `feedback_cross_process_testing.md`.
- `__tests.luau` files may change their **return shape** freely (wrap in a function, expose `.run`/`.runAll`) without it counting as touching "the module under test" — the assertions inside are still off-limits unless they're demonstrably stale against documented behavior (see the MemorizeAction case in `wiki/design/refactor-plan-2026-09.md` Chunk 1).

## Cross-references

- Hardening suite covers [[systems/BlockShoot]] § Trust model and [[systems/SpellCastService]] § Trust model
- NPC suites cover [[systems/NPC]]
- [[systems/MemorizeAction]] — the invalid-word-clears-the-buffer behavior the Unit suite's `memorizeaction_tests` now asserts correctly
- `wiki/design/refactor-plan-2026-09.md` Chunk 1 — the 2026-09-08 harness rewrite this page describes
