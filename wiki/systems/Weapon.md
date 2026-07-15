---
type: system
description: Weapon system (REMOVED 2026-06-22, commit 6610291) — firearm/melee TPS stack deleted; only MeleeHitDetector, MeleeConstants, and laserBeamEffect survive as NPC-facing utilities. Retained as historical record.
updated: 2026-07-15
---

# Weapon System

> **REMOVED 2026-06-22 (commit `6610291`).** The TPS weapon stack this page describes — firearm controllers, weapon templates (Pistol/Rifle/Sword/LaserPistol), the shared state machine, AimAssist, WeaponRolodex, and player-melee swing — was deleted, not gated. Brain Fighter is a spelling-combat game (the [[systems/LetterBlaster]] Spelling Staff is the only Tool). **Only three former Weapon files survive, kept for NPC combat, not player weapons:** `MeleeHitDetector` + `MeleeConstants` (NPC attacks) and `laserBeamEffect` (LetterBlaster + NPC ranged). This page is retained for historical context — do not wire new gameplay against anything below.

Weapons are Tools. Each Tool template has a per-weapon controller LocalScript that drives a generic state machine. Hit detection and damage application are split between client and server with different authority models per weapon type.

## Layout

```
src/shared/Weapon/
  Scripts/
    WeaponStateMachine/        — generic state machine reused by all weapons
    AimAssistController/       — rifle/handgun aim assist (TargetSelector, AimAdjuster, DebugVisualizer)
    FirearmController.luau     — single attribute-driven controller for all firearms (Phase B1, 2026-05-01)
    WeaponAnimationController.luau  — animation track management
    WeaponTouchInputController/ — touch input (mobile)
    Effects/                   — impactEffect, laserBeamEffect (visual)
    Utility/                   — castRays, getRayDirections, drawRayResults, sound helpers, canPlayerDamageHumanoid
  Melee/
    MeleeConstants.luau        — reach, sanity multipliers, claim limits
    MeleeTypes.luau
    MeleeHitDetector.luau      — swept GetPartBoundsInBox, Single + Cleave modes
  Templates/                   — per-weapon Tool templates (each is attributes + a per-template .client.luau wrapper that calls FirearmController.new)
    Pistol/                    — handgun (cameraModeFamily="Handgun")
    LaserPistol/               — handgun
    Rifle/                     — rifle (cameraModeFamily="Rifle")
    Sword/                     — melee reference implementation
src/server/
  Firearm/Scripts/             — per-weapon validation (validateShootArguments, validateTag, AccessoryFiltering)
  Weapon/MeleeSwingService.server.luau  — authoritative melee cooldown + sanity validation
  Loadout/RespawnPedestalManager.server.luau  — pedestal-spawner used by the greybox arena (see [[systems/Loadout]])
```

## Authority models

| Concern | Firearms | Melee |
|---|---|---|
| Hit detection | Server-side raycast on `Shoot` remote | Client sweeps `Handle.CFrame` on Heartbeat (Active state only) |
| Validation | Server validates ray origin, target, tags | Server sanity-checks distance ≤ `reach * 1.5` |
| Damage | Server (`HealthService.applyDamage`) | Server |
| Cooldown | Server | Server (authoritative) + client (responsive UI) |
| FX broadcast | Server fires `ReplicateShot` UnreliableRemote → all clients | Server fires `MeleeHitReplication` on validated hit |

Why split: firearms have a single instantaneous ray that the server can recompute; melee has an animation-driven blade trajectory the server can't accurately know. See [[decisions/HybridMeleeHitDetection]].

## Weapon templates — convention

Each template under `src/shared/Weapon/Templates/<Name>/`:

- `<Name>.client.luau` — controller LocalScript wired up by the Tool's runtime.
- `Scripts/KeepAnchored.server.luau` — keeps the Handle anchored when not equipped (consistent across all templates).
- Tool attributes carry tunable values (reach, damage, cooldowns, magazine size, reserve ammo, weapon slot).

## State machine

`src/shared/Weapon/Scripts/WeaponStateMachine/WeaponStateMachine.luau` — a generic state graph reused by:
- Firearm controllers (Idle, Firing, Reloading)
- `MeleeSwingController` (Idle, Windup, Active, Recovery)

States are data — they're declared per-weapon, transitions are validated by the machine.

## Adding a new firearm

Five steps as of Phase B1 consolidation:

1. Make a new folder under `src/shared/Weapon/Templates/<Name>/`.
2. Create `init.meta.json` with `className: "Tool"`, the standard firearm attributes (`_ammo`, `magazineSize`, `damage`, `rateOfFire`, etc.) plus `cameraModeFamily` set to `"Handgun"` or `"Rifle"`.
3. Drop a `Scripts/<Name>.client.luau` that calls `FirearmController.new(tool, { cameraController = ... })` — it's the same boilerplate every other firearm uses; copy from any sibling template.
4. Drop a `Scripts/KeepAnchored.server.luau` (copy from any sibling).
5. Add the mesh + sounds. No new controller class needed; no Lua to write beyond the boilerplate.

Phase B1 (2026-05-01) collapsed the two-deep inheritance (`HandgunController` / `RifleController` → `FirearmController`) into a single attribute-driven controller. The wrapper subclasses existed solely to set 3 camera-mode strings; the camera-mode family is now read from the Tool's `cameraModeFamily` attribute and the modes table is derived as `<family>` / `<family>Aiming` / `<family>Sprinting`. Default falls back to `"Handgun"` if the attribute is unset.

## Reload + ammo contract

Reload state lives in two places that must stay in sync. Server is authoritative; client predicts.

- **Magazine** (`_ammo` Tool attribute) and **reserve** (`_reserveAmmo`) are decremented independently.
- `Ammo.performReload(tool)` (shared module) transfers `min(needed, reserve)` rounds — used both by server `validateReload`/reload handler and by the client's `FirearmController:startReload` predicted callback. Both sides MUST run the same math; otherwise an empty-reserve reload silently rejects on server while the client jumps to a full magazine, and every subsequent shot fails `validateShot(ammo<=0)` server-side. See [[concepts/ClientServerPredictionParity]].
- `WeaponController:canReload()` (client) requires `reserve > 0`, mirroring server `validateReload`. Don't kick off optimistic predictions the server is going to reject.

## Template rename order — Studio first, then disk

When renaming a weapon template (or any Rojo-synced Tool with MCP-created children), rename in Studio **first** — `Tool.Name = "NewName"` preserves all children — then update the disk folder name and `init.meta.json`. Doing the disk rename first causes Rojo to destroy the old-name Tool and create a fresh empty one, taking all MCP-only children (Handle MeshPart, Animations, Sounds, Haptics, Model) with it. `ignoreUnknownInstances: true` does not protect children when their parent is replaced by a rename.

Symptoms: the new Tool only has `Scripts` as a child while siblings have 4+; pedestals warn "Template not found" or spawn invisible/handleless weapons. Recovery: revert from `.rbxl` backup, redo in the right order.

Same logic applies to ViewModels, GUI templates, animation rigs — anything with MCP-only children needs the Studio rename to precede the disk rename.

## Important gotchas

- **`.client.luau` in `src/shared/`** is dead code — Roblox doesn't auto-run LocalScripts in ReplicatedStorage. Templates parented to Tools work because the Tool moves to the Player's Backpack/Character. But standalone shared LocalScripts must live in `src/client/`. `ShotReplication.client.luau` lived in shared from project setup until 2026-04-30 — remote shot FX never replicated until it was moved. See [[concepts/LocalScriptPlacement]].
- **Default `ToolNoneAnim` auto-plays on equip** and fights movement animations. `MeleeSwingController` suppresses it via an `Animator.AnimationPlayed` listener.
- **`LocomotionController` owns `Waist.C0`** and writes it every RenderStepped — animation-driven torso lean is muted unless locomotion is paused. See [[concepts/SingleOwnership]].

## Cross-references

- Damage application → [[systems/Health]]
- Pickup / drop / slot rules → [[systems/Loadout]]
- HUD ammo + weapon card → [[systems/HUD]]
- NPC weapon hooks → [[systems/NPC]]
- Tests → [[systems/Tests]]
