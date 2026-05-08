---
type: concept
description: A `.client.luau` only auto-runs when Rojo places it in a runnable container. ReplicatedStorage is not one of them.
updated: 2026-04-30
---

# LocalScript Placement

Rojo turns `.client.luau` files into LocalScripts and places them at whatever path the project file maps. **Roblox only auto-executes LocalScripts when they're parented to one of:**

- `StarterPlayer.StarterPlayerScripts`
- `StarterPlayer.StarterCharacterScripts`
- `StarterGui` (or its descendants at runtime)
- `ReplicatedFirst`
- a Player's `Backpack`
- a Player's `Character`

**A LocalScript anywhere else — `ReplicatedStorage`, `Workspace`, `ServerScriptService` — is dead code.** It will never run, never connect handlers, never error. There is no warning at edit time and no error at runtime.

## Project mapping

`default.project.json` maps:

| Disk | Studio path | Auto-run? |
|---|---|---|
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` | ✅ |
| `src/shared/` | `ReplicatedStorage.Shared` | ❌ |
| `src/server/` | `ServerScriptService.Server` | ❌ for `.client.luau`; ✅ for `.server.luau` |

## When to use which folder

- **Top-level client handler that should run for every player on join** → `src/client/`. Examples: HUD scripts, remote-event listeners, input handlers, replication consumers.
- **Tool-specific client logic that ships with a Tool template** → `src/shared/Weapon/Templates/<Name>/Scripts/<Name>.client.luau`. These work because the Tool gets parented to `Backpack`/`Character` at runtime, which auto-runs LocalScripts inside.
- **Module of shared logic** that some other script `require`s → `src/shared/` as a `ModuleScript` (no `.client` or `.server` suffix).

The rule of thumb: **a `.client.luau` directly under `src/shared/` (not inside a Tool template) is wrong.** It will never run.

## The case study

Project setup era through 2026-04-30 — `src/shared/Weapon/Scripts/ShotReplication.client.luau` was the only consumer of the `ReplicateShot` remote (server fires it for every weapon shot to replicate muzzle flash + tracers + SFX to other clients). Rojo placed it at `ReplicatedStorage.Shared.Weapon.Scripts.ShotReplication` for the project's entire history. **Remote-client shot FX never replicated for any weapon, ever.** No error, no warning. The user noticed only when they thought to check.

Fix `18f41cc`: moved file to `src/client/`, swapped relative requires to absolute. As soon as the script started running, a latent require-time bug surfaced (`Weapon.Effects` vs `Weapon.Scripts.Effects`) — see [Dead code corollary](#dead-code-corollary).

## Diagnostic recipe

When "client-side X never happens":

1. Open Studio after a Rojo sync. Find the script in the explorer tree.
2. Confirm it lives under `StarterPlayerScripts`, `StarterCharacterScripts`, `ReplicatedFirst`, `StarterGui`, or inside a Tool that ends up in `Backpack`/`Character`.
3. If it lives anywhere else — that's the bug. Move it to `src/client/`.

For a quicker test: add `log:info("loaded")` at the top level of the script. If you don't see the log on a fresh playtest, the script isn't running.

## Dead code corollary

Code that's been dead for a long time will have **latent require-time bugs** that surface only when the code becomes live. When you finally wake up a long-dead script, expect at least one bad path that's been waiting silently. Read the file end-to-end before assuming the placement fix alone resolves the symptom.

## Related

- [[systems/Weapon]] — `ShotReplication` example
- Memory `feedback_localscript_placement.md` — same lesson in feedback form
- `CLAUDE.md` — Rojo workflow rules
