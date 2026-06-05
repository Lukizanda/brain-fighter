---
type: system
description: Phase 4.6 weapon controller — wraps the block-shoot input pipeline behind the Spelling Staff Tool's Tool.Activated, with a cooldown, a laser-beam blast effect, and fire/hit/fizzle sounds. Replaces the raw UserInputService handler from Phase 3.
updated: 2026-06-05
---

# LetterBlaster

The controller behind the **Spelling Staff** — the weapon Tool the player holds to shoot floating letter blocks. Replaces the raw `UserInputService.InputBegan` handler from Phase 3 with a proper Roblox `Tool` that carries its own mesh and sounds. There is **no reticle**: the player taps/clicks directly on the block they want.

## Files

- `src/shared/LetterBlaster/init.luau` — controller: `new(tool, session)`, `:mount()` (connects `Tool.Activated`), `:destroy()` (disconnects).
- `src/shared/LetterBlaster/LetterBlasterConfig.luau` — tuning constants: `COOLDOWN`, `FIRE_SOUND_NAME`, `HIT_SOUND_NAME`, `FIZZLE_SOUND_NAME`.
- `src/StarterPack/Spelling Staff/Scripts/SpellingStaff.client.luau` — the boot LocalScript: on `tool.Equipped` calls `LetterBlaster.new(tool, PlayerSession.get()):mount()`, and `:destroy()` on `Unequipped`.
- `src/StarterPack/Spelling Staff/` — the Rojo-managed Tool template: `Handle/` (MeshPart folder with a Studio-managed `Muzzle` attachment) + `FireSound`/`HitSound`/`FizzleSound` `.model.json` children directly under the Tool.

## Flow

1. On spawn the Spelling Staff Tool is in the player's StarterPack/Backpack.
2. `SpellingStaff.client.luau` wires `Equipped`/`Unequipped`; on equip it constructs `LetterBlaster.new(tool, session)` and calls `:mount()`.
3. `:mount()` connects `Tool.Activated` to `_onActivated`. No UI is created.
4. On each `Tool.Activated` (`_onActivated`):
   - `COOLDOWN` (0.25s) gate via `os.clock`.
   - `MindFullManager:isMindFull()` gate — if full, play `FizzleSound` and bail (no shot).
   - Raycast from camera through mouse position (character excluded), out to `BlockShoot.MAX_RAYCAST_DISTANCE`.
   - `FireSound:Play()` on every shot attempt (after the raycast).
   - On a miss, or a hit with no `LetterBlock` ancestor / missing attributes: bail.
   - Otherwise read `letter, color` via `BlockShoot.readBlock`, then fire a **laser blast** (see below).
   - `WordBuffer:append(letter, color)`. If the buffer rejects (e.g. full mid-frame): play `FizzleSound` and bail.
   - On confirmed append: `ConsumeBlock:FireServer(block)` then `HitSound:Play()`.
5. On unequip, `:destroy()` disconnects the `Tool.Activated` listener.

## Laser blast

On a confirmed hit, the controller fires `laserBeamEffect(origin, blockPosition)` (`src/shared/Weapon/Scripts/Effects/laserBeamEffect.luau`). The origin is the `Muzzle` attachment's `WorldPosition` on the Tool's `Handle` (falling back to `Handle.Position` if the attachment is missing); the endpoint is the consumed block's pivot. The `Muzzle` attachment is Studio/MCP-managed on the Handle MeshPart, not a Rojo `.model.json`.

## Sounds

`FireSound`, `HitSound`, and `FizzleSound` live as direct `.model.json` children of the Tool instance (not inside the Handle). The controller looks them up via `tool:FindFirstChild(name)` on each shot.

| Sound | Event |
|---|---|
| FireSound | Every activation that passes the cooldown + mind-full gates |
| HitSound | Confirmed consume only (block hit + buffer appended) |
| FizzleSound | Mind-full block, or buffer rejecting the append |

## Constants

| Constant | Value | Notes |
|---|---|---|
| `COOLDOWN` | 0.25s | Minimum time between activations |
| `FIRE_SOUND_NAME` | `"FireSound"` | Tool child name |
| `HIT_SOUND_NAME` | `"HitSound"` | Tool child name |
| `FIZZLE_SOUND_NAME` | `"FizzleSound"` | Tool child name |

## See also

- [[systems/BlockShoot]] — shared helpers (`findLetterBlock`, `readBlock`, `MAX_RAYCAST_DISTANCE`, `ConsumeBlock` remote) and server-side block destruction.
- [[systems/LetterBlock]] — the entity LetterBlaster consumes.
- [[systems/WordBuffer]] — destination for consumed tiles.
- [[systems/MindFullManager]] — input gate when buffer is full.
- [[systems/AudioSFX]] — Spelling Staff sound wiring.
