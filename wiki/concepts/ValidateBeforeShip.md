---
type: concept
description: A fix is not done until it has been observed working — push only after a deterministic repro confirms the bug is gone
updated: 2026-05-01
---

# Validate Before Ship

A fix that *looks* correct on the diff is not the same as a fix that *is* correct. Code that's been read but not run is one of the most reliable sources of regression on this project. The principle: **before pushing a commit that claims to fix something, run a repro that exercises the buggy path and confirm the bug is gone.**

## Why this is non-negotiable for this codebase

Two reinforcing factors make this principle especially important here:

1. **Server-side bugs invisible from client probes.** The user-visible bugs almost always have their root cause in the server VM (`LoadoutService`, `applyDamage`, `ScoreTracker`, `RespawnPedestalManager`). The agent's MCP `execute_luau` tool runs client-side; it cannot reach those paths. A "verification" via MCP that doesn't deliberately route through a server harness is testing nothing — and will look like it passed. See [[concepts/ServerLogicTestHarness]] for the gated-`.server.luau` pattern that fixes this.
2. **Roblox events fire in surprising places.** `Backpack.ChildAdded` fires on every Tab-cycle's unequip, not only on fresh pickups. `AncestryChanged` fires during atomic parent transitions while `Parent` is briefly nil. `Humanoid:EquipTool` is an unequip-then-equip pair, not a single move. A logic change that "looks idempotent" can break in ways that only the live event sequence reveals.

## Workflow checklist

Before pushing a fix:

1. **Build a deterministic repro.** Either a test under `src/shared/Tests/Suites/` (preferred — see [[concepts/MultiplayerTestPattern]]), a gated `.server.luau` harness (see [[concepts/ServerLogicTestHarness]]), or a scripted MCP probe — whichever can actually reach the buggy path.
2. **Run it twice mentally:** would the repro have shown the bug *without* the fix? Does it now show the bug *gone* with the fix?
3. **If you can't run a repro yourself**, say so explicitly: "I can't verify this from here — please reproduce and confirm." Don't soften it to "should be fixed" or "this looks right" — those phrases push the verification burden onto the user without acknowledging it.
4. **Don't conflate the existing test suite passing with this specific bug being fixed.** The suite covers what it covers. A new bug usually lives in code the suite doesn't touch.

## Anti-patterns this rule blocks

- "The diff looks right, push it." Reading is not running.
- "The MCP probe ran without errors." If the probe was client-side and the bug is server-side, it ran in a parallel universe that doesn't have the bug.
- "The multiplayer test suite still passes." That tells you the existing tests still pass; it tells you nothing about the new path you just changed.
- "I'll just run a quick playtest visually." Visual playtests can miss state that drifts slowly (eviction count climbing, stale connections accumulating). Prefer attribute-driven harnesses for state-tracking bugs.

## The case study

A debugging session on this project. The user reported "Tab-cycling makes my last weapon disappear." I:

1. Wrote a `task.defer` patch in `WeaponRolodex.client.luau:watchToolDrop` that was *partially* correct (the AncestryChanged race was real but not the only cause). Pushed without testing. Bug persisted in user's playtest. Cost the user a re-repro round-trip.
2. Wrote a fix in `LoadoutService.registerNormal` and "validated" with an MCP `execute_luau` probe that placed tools client-side. The probe reported `dots=2` across 10 cycles. Pushed. **The probe was useless** — `tool.Parent = lp.Backpack` from client doesn't replicate to server, so the actual bug path (server-side ChildAdded → registerNormal → eviction) never fired during my probe.
3. Only after writing `src/server/Dev/SimulateLoadoutCycling.server.luau` (a gated `.server.luau` harness driving real server-side parenting) did I get a deterministic trace proving the fix worked: every cycle's `registerNormal` hitting `→ already tracked, early-return` with zero `EVICT` lines.

The pattern in the harness — gated by `GameConfig.DEV_*`, writes results to `workspace.*Result`, runs once at first character spawn — is reusable for any future server-only fix validation. Use it.

## Related

- [[concepts/ServerLogicTestHarness]] — the how-to for the `.server.luau` driver pattern
- [[concepts/MultiplayerTestPattern]] — when an existing test suite test is the right tool instead
- Memory `feedback_validate_before_push.md` — the same principle in feedback form
- Memory `feedback_mcp_clone_replication.md` — why client-side probes can't substitute
