---
type: system
description: Per-character systems — locomotion controller, camera controller, character systems loader. Single-owner Motor6D + AlignOrientation pattern. Gated behind GameConfig.TPS_CHARACTER_ENABLED (default off for Brain Fighter).
updated: 2026-05-13
---

# Character System

Locomotion, camera, and weapon-pose are intentionally separated but coordinated through the [[concepts/SingleOwnership]] rule — exactly one controller owns each Motor6D / property.

## TPS character stack is gated off by default

Brain Fighter uses default Roblox third-person camera + `Humanoid.AutoRotate = true` character (platformer-style). The inherited TPS template's body-lock + Motor6D upper-body tracking + weapon-aim camera modes are gated behind `GameConfig.TPS_CHARACTER_ENABLED` (default `false`).

`CharacterSystemsLoader.client.luau` reads the flag at startup: when `false`, `CameraManager` and `LocomotionManager` are not initialized, so the default Roblox PlayerModule handles camera and locomotion completely. The TPS controllers stay on disk for reference (and for any future mode that wants them) but never run. Flip the flag to `true` to restore the TPS feel.

## Files

- `src/client/CharacterSystemsLoader.client.luau` — boots LocomotionController + CameraController on `LocalPlayer.CharacterAdded`
- `src/client/CameraManager.luau` — camera entry point
- `src/client/LocomotionManager.luau` — locomotion entry point
- `src/shared/Character/LocomotionController.luau` — owns `Waist.C0`, locomotion animation tracks, MovementState
- `src/shared/LocomotionAnimations/` — Animation instances (folder created via MCP; not Rojo-synced — they have AnimationIds)

## Body lock — AlignOrientation, not CFrame writes

Body yaw is locked to camera yaw via an `AlignOrientation` constraint with `RigidityEnabled = true`. **Never** set `HumanoidRootPart.CFrame` to control orientation — the physics engine overrides it. See `CLAUDE.md` for the full rule.

`AutoRotate = false` is necessary but not sufficient. Pair it with the constraint.

## Render priorities

| System | Priority | Why |
|---|---|---|
| Locomotion | `RenderPriority.Character.Value + 1` | Runs after Humanoid movement processing |
| Camera | `RenderPriority.Camera.Value + 1` | Runs after Roblox's default camera step |

Higher priority number = runs later = gets the final say.

## Movement states

`LocomotionController` reads movement direction relative to camera yaw and selects an animation by name: `Forward`, `Backward`, `StrafeLeft`, `StrafeRight`. Animation instances must be named exactly that. Priority `Movement`, `Looped = true`.

## Cross-references

- Single-owner rule → [[concepts/SingleOwnership]]
- Weapon pose vs locomotion conflict (waist write fights swing animations) → [[systems/Weapon]] gotchas
