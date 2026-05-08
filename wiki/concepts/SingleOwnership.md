---
type: concept
description: One controller owns each Motor6D / property. Two writers always fight.
updated: 2026-05-08
---

# Single Ownership Rule

> One system should own each Motor6D / property. If two scripts write to the same Motor6D.C0 or Humanoid.AutoRotate, they will fight. Merge them into one controller.

— `CLAUDE.md`

## Why this matters here

Roblox character control is a tug-of-war between many systems: locomotion animations, camera-yaw lock, weapon poses, hit-reaction tweens. Each writes to overlapping Motor6Ds (`Waist`, `Neck`, `LeftShoulder`, `RightShoulder`, `RightHip`). Last-write-wins is silent — there's no error, the body just snaps to whoever ran last in the RenderStep.

## Known ownership table

| Resource | Owner | Why |
|---|---|---|
| `Waist.C0` | `LocomotionController` | Camera-tracked upper body twist (lerp when idle, instant pin while firing, yields to `LocksOrientationToCamera` animations). |
| `HumanoidRootPart` orientation | `AlignOrientation` constraint (NOT a script) | Physics-stable yaw lock; see [[systems/Character]]. |
| `Humanoid.AutoRotate` | `LocomotionController` (set to `false` once) | Pair with the AlignOrientation constraint. |
| Each Tool's animation tracks | The Tool's controller LocalScript | Default `ToolNoneAnim` is suppressed by `MeleeSwingController`. |
| `_ammo` / `_reserveAmmo` Tool attributes | Server (`Ammo` module) is authoritative; client mirrors via [[systems/HUD]] adapter. | See `feedback_client_server_predict_parity.md`. |
| `_cooldownEnd` attribute on Special Tools | The Special's server runtime sets it. WeaponRolodex reads only. | See [[systems/Loadout]]. |

## Yielding the upper body to a combat animation

`LocomotionController` writes `Waist.C0` every RenderStepped to track camera direction. Most of the time this is the right call — but during a melee swing animation, fighting the Animator's Waist contributions caused two problems we couldn't cleanly solve:

1. **Animator "frozen pose":** when a non-looped Action-priority animation ends, Roblox holds the last frame's `Motor.Transform` values indefinitely. Stop+Destroy on the track doesn't clear them, lower-priority tracks can't override Action contributions, and even `Motor.Transform = CFrame.identity` direct writes get re-applied by the engine on the next frame. Continuous override (~30 frames of Heartbeat writes) flushes it, but at that point we're hammering the engine.
2. **Composition with our C0 write:** the final orientation is `parent * C0 * Transform`, so the swing's Waist `Transform` keyframes still tilted the torso even though we wrote `C0` to camera direction. We tried clearing Transform every frame, which worked visually but exacerbated (1).

**Resolution:** when a `LocksOrientationToCamera = true` animation is playing, `LocomotionController.updateUpperBodyRotation` simply early-returns. The body's pre-swing rotation (already camera-tracked by the same function) carries through; the animation plays unmolested. Cost: if the player keeps strafing during the ~0.5s swing, the torso drifts slightly with HRP. Acceptable for now — revisit if gameplay actually needs camera-locked body during swings (e.g. aim-precision melee).

- Currently tagged: `ReplicatedStorage.Shared.Weapon.Templates.Sword.SwingAnimation`.
- The attribute lives on the Animation instance (MCP-only — Animations aren't synced by Rojo). When authoring a new melee swing, set it via MCP after creating the Animation.
- **Don't** key off `AnimationPriority.Action` as a proxy — those are independent concerns. Firearm Idle is Action priority but doesn't need this yield; tagging by priority would (and did) over-trigger.

## Pinning the upper body during fire

While `isFiring`, `updateUpperBodyRotation` writes the Waist with an **instant** rotation of `(cameraYaw - characterYaw)` every frame — no lerp. This is what keeps the firing pose steady while the legs autorotate to track MoveDirection (e.g. strafing in a state without a strafe animation).

The lerp path (which still runs in non-firing states for natural look-around feel) was the original source of the visible "arms swing and spring back" while strafing-and-firing: HRP autorotated to face MoveDirection, the Waist lerp raced after the camera at ~10 rad/sec, and any change in HRP yaw (strafe start/stop, physics-step jitter between RenderStepped and the AlignOrientation step) showed up as a per-frame counter-rotation on the shoulders.

The instant write makes it mathematically impossible: `HRP_yaw + Waist_yaw == cameraYaw` every frame, so the upper body is pinned regardless of how the legs are moving. The clamp at `UPPER_BODY_FIRE_MAX_YAW (120°)` survives only as a guard against extreme camera/movement angles snapping arms through the torso.

This also means **strafe animations are not required** for a steady firing pose — the legs slide without animation in those states, but the gun stays aimed where the camera looks.

## Detection

When a property is "fighting itself" (snaps, jitters, partial application), grep for **all** writers:

```
Grep for "Waist.C0" — every match is a candidate writer.
```

Expect exactly one. If you find two, that's the bug.
