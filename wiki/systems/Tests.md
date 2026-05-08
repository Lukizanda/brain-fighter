---
type: system
description: In-Studio test harness — TestRunner module + suites for NPC and Melee. MCP-driven via test-runner subagent.
updated: 2026-04-30
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

src/server/Tests/
  TestAutoRunner.server.luau    — invoked at boot when a workspace flag is set, runs a named suite, prints results
```

## Running tests

User-facing entry: `/run-tests` slash command, which dispatches the `test-runner` subagent. Default suite is `NPC`.

The subagent drives a real playtest via MCP, parses TestRunner output, reports pass/fail.

## Test design conventions

- **No mocks** for in-engine behavior. Tests spawn real Humanoids, Tools, etc. (see `feedback_cross_process_testing.md` in auto-memory.)
- Tests that require player input (e.g. firearm fire) cannot be MCP-driven — those are documented as "manual playtest" in their respective status pages.
- Cross-VM time uses `workspace:GetServerTimeNow()`, not `os.clock()` (different per VM). See `feedback_cross_process_testing.md`.

## Cross-references

- NPC suites cover [[systems/NPC]]
- Melee suites cover [[systems/Weapon]] melee path (`MeleeHitDetector.sweep` directly, not the remote)
- The hybrid melee refactor was validated against these suites pre/post — see [[decisions/HybridMeleeHitDetection]]
