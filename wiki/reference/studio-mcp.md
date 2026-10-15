---
type: reference
description: Roblox_Studio MCP as tested here — execute_luau gets its own module copies, MCP-cloned instances arrive nil over remotes, start_stop_play wedges
updated: 2026-10-15
---

# Roblox Studio MCP (`Roblox_Studio`)

**Verified against:** the `Roblox_Studio` MCP server, 2026-04 to 2026-10. **Official docs:** none we rely on; each tool's own description is the spec

How to use these tools day to day (playtest lock, waypoints, test suites) is in [`docs/agents/studio-and-playtests.md`](../../docs/agents/studio-and-playtests.md). This page records what the tools actually do.

## `execute_luau` gets its own copy of every module

Injected code runs in a **separate Luau context** from the game's scripts. `require()` there returns a *fresh* module instance, not the one the game is using. The tell: a module's init log (`[SpellRegistry] Loaded`) prints an extra time when your code requires it.

- Firing a module-local BindableEvent from injected code reaches **no** game listeners. Calling `CastAction.castSpecific` there logs `cast ok` and produces no VFX, because `VfxController` is connected to a different bindable.
- Module-level singletons (`PlayerSession`, its `energyReservoirs`) are separate objects. Filling them from injected code doesn't change what the HUD reads.

**What does cross the boundary is DataModel state:** attributes, Instances and Instance signals (`DescendantAdded`).
- **To drive gameplay,** add a self-clearing attribute hook to a dev harness. `workspace:SetAttribute("DevFillMana", 1-4)` in `DevDebug.client.luau` is the reference example. It's the same pattern as the `RunTests` auto-runner, except it clears itself so it can't re-fire on the next playtest.
- **To observe results,** arm a `DescendantAdded` observer **before** acting and record counts into attributes. Don't poll afterwards: VFX destroy themselves quickly (a 0.24 s sound is gone within 0.9 s).

**`datamodel_type`:**
- `"Client"` reads the real client VM. That makes it the direct way to verify what a client renders, as the VFX rule requires. Read *instances* there, not module state.
- `"Edit"` errors with "not available in Play mode", so clear edit-time attributes like `RunTests` before starting or after stopping.

**Stale requires in Edit mode.** `require` results are cached across `execute_luau` calls in the Edit DataModel. After a Rojo sync, a required module still runs its **old code**: constants read back pre-sync, and newly added logic silently does nothing (confirmed 2026-08-20). To check synced code, read `Instance.Source` text, or verify in a playtest, which starts a fresh VM.

**Calls in one message run one after another, not in parallel.** So "arm a Client sampler, then trigger from the Server" can't be two concurrent calls. Instead, fire a Server call that `task.spawn`s a **repeating** trigger, then issue the Client sampler. The sampler arms late but still catches one trigger. Scheduled `task.spawn`/`task.delay` work keeps running after the injected call returns.

## Simulated input

- `VirtualInput` refuses keys permanently bound to CoreGui (number keys 1–4 = hotbar), even after `SetCoreGuiEnabled(Backpack, false)`.
- Click GUI buttons with `user_mouse_input` and `instance_path`, not screen x/y; `instance_path` doesn't depend on the camera.
- The camera drifts between tool calls (about 100 studs observed), so clicking screen centre at a world object you placed doesn't work.
- **Don't orbit the camera with a synthetic right-drag.** The game uses the Classic camera, and a `user_mouse_input` right-drag locks the cursor, so both camera and cursor land somewhere unintended. Pick a target already on screen. Or skip input entirely: fire the production path from `datamodel_type: "Server"` and observe on the Client.

## Instances cloned through MCP arrive as `nil` over RemoteEvents

An Instance created or cloned with `execute_luau` (for example a Tool) arrives as `nil` in the server's `OnServerEvent` when the client passes it back, even though the client's reference is valid. Numbers, tables and server-created Instances pass through fine. MCP-created instances seem to have a restricted replication identity (first seen 2026-04-20).

For end-to-end tests that pass an Instance from client to server, spawn it from a real `.server.luau` dev script gated by a workspace attribute, and have MCP only set the attribute. Before blaming gameplay code for rejecting an Instance argument, check whether MCP spawned it.

## `start_stop_play` wedges

The first call times out, and every later call returns `"Start play hasn't finished yet"` while `get_studio_state` stays `Edit`. `execute_luau` keeps working throughout, so the plugin bridge is alive; only the play transition is stuck. Hit 2026-08-20 and 2026-08-21.

Pressing F5 in the focused Studio window cleared it once and failed the second time, so treat it as worth one try, not a fix. Reloading the plugin is the next thing to try (unverified).

- **Plan around it:** settle the verification design *before* spending a working playtest. If Studio is already in Play, use that session rather than stopping and restarting it.
- **If it wedges:** say plainly which half of the verification didn't run, and record the outstanding test in the wiki log, not just in chat.

## Only the Edit window

MCP drives the main Studio window only. Multi-client checks (Start with 2 Players) are user-driven, using paste-in Command Bar snippets kept in `nimbalyst-local/`.
