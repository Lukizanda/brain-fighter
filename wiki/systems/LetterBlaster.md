---
type: system
description: Phase 4.6 weapon Tool — wraps the block-shoot input pipeline in a dedicated Tool with Tool.Activated, reticle, cooldown, and sounds. Replaces the raw UserInputService handler in BlockShootBoot.
updated: 2026-05-15
---

# LetterBlaster

The weapon Tool the player holds to shoot floating letter blocks. Replaces the raw `UserInputService.InputBegan` handler from Phase 3 with a proper Roblox `Tool` that carries its own model, sounds, and reticle UI.

## Files

- `src/shared/LetterBlaster/init.luau` — controller: `new(tool, session)`, `:mount()` (connects `Tool.Activated`, creates reticle), `:destroy()` (disconnects, tears down reticle).
- `src/shared/LetterBlaster/LetterBlasterConfig.luau` — tuning constants: `COOLDOWN`, `FIRE_SOUND_NAME`, `HIT_SOUND_NAME`.
- `src/client/LetterBlasterBoot.client.luau` — wires the controller: scans Backpack for the Tool, calls `mount()` on `Equipped`, `destroy()` on `Unequipped`.
- `src/StarterPack/LetterBlaster/` — Rojo-managed Tool template (Handle MeshPart + FireSound + HitSound).

## Flow

1. On spawn the LetterBlaster Tool is cloned from StarterPack into the player's Backpack.
2. `LetterBlasterBoot` detects the Tool in `Backpack.ChildAdded` and wires `Equipped`/`Unequipped` listeners.
3. When the player equips the tool, `LetterBlaster.new(tool, session):mount()` is called:
   - A `ScreenGui` ("LetterBlasterReticle") is added to PlayerGui, containing the frame returned by `ReticleBuilder.build()`.
   - `Tool.Activated` is connected to `_onActivated`.
4. On each `Tool.Activated`:
   - 0.25s cooldown gate (`os.clock`).
   - `MindFullManager:isMindFull()` gate.
   - Raycast from camera through mouse position (character excluded).
   - `FireSound:Play()` on every shot attempt.
   - If a tagged LetterBlock is hit: `WordBuffer:append(letter, color)` → fire `ConsumeBlock` remote.
   - On confirmed append: `reticle:showHitmarker()` + `HitSound:Play()`.
5. On unequip, `:destroy()` disconnects listeners and removes the ScreenGui.

## Reticle

Reuses `ReticleBuilder.build()` from the HUD system. The controller parents the returned `Frame` into a dedicated `ScreenGui` ("LetterBlasterReticle") with `IgnoreGuiInset = true`. The reticle is only present while the tool is equipped — it's created on `mount()` and destroyed on `destroy()`.

## Sounds

`FireSound` and `HitSound` live as direct children of the Tool instance in StarterPack (not inside the Handle). The controller looks them up via `tool:FindFirstChild(name)` on each shot.

| Sound | Event |
|---|---|
| FireSound | Every activation (hit or miss) |
| HitSound | Confirmed consume only (block hit + buffer appended) |

## Constants

| Constant | Value | Notes |
|---|---|---|
| `COOLDOWN` | 0.25s | Minimum time between activations |
| `FIRE_SOUND_NAME` | `"FireSound"` | Tool child name |
| `HIT_SOUND_NAME` | `"HitSound"` | Tool child name |

## See also

- [[systems/BlockShoot]] — shared helpers (`findLetterBlock`, `readBlock`, `MAX_RAYCAST_DISTANCE`, `ConsumeBlock` remote) and server-side block destruction — unchanged.
- [[systems/LetterBlock]] — the entity LetterBlaster consumes.
- [[systems/WordBuffer]] — destination for consumed tiles.
- [[systems/MindFullManager]] — input gate when buffer is full.
- [[systems/HUD]] — `ReticleBuilder` lives in the HUD module family.
