---
type: system
description: In-Studio test harness — TestRunner module + suites for NPC, Melee, Multiplayer, Phase3, Skills and Hardening. MCP-driven via test-runner subagent.
updated: 2026-08-03
---

# Test System

Lightweight in-Studio test harness for gameplay systems. Tests run inside Studio (not as unit tests outside the engine) so they can exercise real Humanoid / Tool / Animation behavior.

## Files

```
src/shared/Tests/
  TestRunner.luau               — generic test runner (declares, runs, reports)
  Suites/
    NPC/
      combat_engages.luau
      combat_disengages.luau
      npc_deals_damage.luau
    Melee/
      melee_damages_dummy.luau
      melee_misses_out_of_range.luau
      melee_cleave_hits_multiple.luau
    Multiplayer/ · Phase3/ · Skills/
    Hardening/
      blockshoot_payload_validation.luau
      blockshoot_range_and_rate.luau
      spellcast_payload_validation.luau

src/server/Tests/
  TestAutoRunner.server.luau    — invoked at boot when a workspace flag is set, runs a named suite, prints results
```

## Running tests

User-facing entry: `/run-tests` slash command, which dispatches the `test-runner` subagent. Default suite is `NPC`.

Clear `workspace:SetAttribute("RunTests", nil)` as soon as a run reports `[AUTORUN DONE]` — the attribute persists in the `.rbxl` and silently re-fires the autorunner on every later playtest.

The subagent drives a real playtest via MCP, parses TestRunner output, reports pass/fail.

## Test design conventions

- **No mocks** for in-engine behavior. Tests spawn real Humanoids, Tools, etc. (see `feedback_cross_process_testing.md` in auto-memory.)
- Tests that require player input (e.g. firearm fire) cannot be MCP-driven — those are documented as "manual playtest" in their respective status pages.
- Cross-VM time uses `workspace:GetServerTimeNow()`, not `os.clock()` (different per VM). See `feedback_cross_process_testing.md`.

## Hardening suite

Covers the Phase 5.4 server-trust validation on both client→server gameplay remotes. It drives `BlockShootValidation` / `SpellCastValidation` directly rather than firing the remotes, because the most important input — a table wearing a Model's property names — cannot be sent from a test that already runs on the server.

These modules live under `ReplicatedStorage.Shared.Tests` but reach into `ServerScriptService.Server.*`, which is valid because `TestAutoRunner` is a server Script.

Both directions are asserted, since a mis-tuned bound breaks real play as surely as a missing one: the suite checks that a player tapping at the client's own `BlockTapConfig.COOLDOWN` is *never* throttled, and that an in-range block and an in-range target are *never* rejected. `blockshoot_range_and_rate` runs its rate half in real time (~1.3s) against the production constants, because the thing worth testing is the tuning rather than the arithmetic.

## Cross-references

- Hardening suite covers [[systems/BlockShoot]] § Trust model and [[systems/SpellCastService]] § Trust model
- NPC suites cover [[systems/NPC]]
- Melee suites cover [[systems/Weapon]] melee path (`MeleeHitDetector.sweep` directly, not the remote)
- The hybrid melee refactor was validated against these suites pre/post — see [[decisions/HybridMeleeHitDetection]]
