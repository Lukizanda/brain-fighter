---
type: system
description: Phase 4.6 weapon controller — wraps the block-shoot input pipeline behind the Spelling Staff Tool's Tool.Activated, with a cooldown, a laser-beam blast effect, and fire/hit/fizzle sounds. Since 2026-08-05 the beam replicates to other players via VfxBroadcast; the sounds still do not.
updated: 2026-08-05
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
   - Otherwise read `letter, color` via `BlockShoot.readBlock`, and cache the block's pivot for the beam endpoint before anything can destroy it.
   - `WordBuffer:append(letter, color)`. If the buffer rejects (e.g. full mid-frame): play `FizzleSound` and bail.
   - On confirmed append: `ConsumeBlock:FireServer(block)`, then fire the **laser blast** (see below), then `HitSound:Play()`.
5. On unequip, `:destroy()` disconnects the `Tool.Activated` listener.

## Laser blast

On a confirmed consume, the controller fires `laserBeamEffect(origin, blockPosition)` (`src/shared/Weapon/Scripts/Effects/laserBeamEffect.luau`). The origin comes from `BlockShoot.muzzlePosition(tool)` — the `Muzzle` attachment's `WorldPosition` on the Tool's `Handle`, falling back to `Handle.Position` if the attachment is missing. The `Muzzle` attachment is Studio/MCP-managed on the Handle MeshPart, not a Rojo `.model.json`.

### How it reaches other players (2026-08-05)

The beam used to be drawn **only** by the client that fired it, into that client's own Workspace. Client-created instances never replicate upward, so every other player watched blocks silently vanish with nothing connecting them to the shooter. The blaster predates the Skills pipeline and never got the client/server split that [[design/client-server-boundary]] gave spells.

It now follows the same three-layer shape:

| Layer | Who | What |
|---|---|---|
| Prediction | shooter's client | draws its own beam on the frame it clicks — cosmetic only, no round trip |
| Authority | `BlockShootService` | validates the consume, destroys the block, then describes the shot |
| Presentation | every other client | `WorldVfxController`'s `beam` handler draws it from the payload |

The server resolves the muzzle itself via `BlockShoot.muzzlePosition` rather than accepting an origin from the client, so the fix adds **no new trust surface** — `ConsumeBlock`'s payload is unchanged and `BlockShootValidation` still sees exactly one argument. `VfxBroadcast.beam(origin, endPoint, shooterUserId)` passes `drawnLocallyBy` so the shooter isn't sent a second copy of a beam they already drew.

The local draw moved **below** the `WordBuffer:append` check as part of this. It used to fire on any block hit, so a shot the buffer rejected drew a beam for the shooter that no other player could ever have a matching beam for — the consume that triggers the broadcast never happened.

## Sounds

`FireSound`, `HitSound`, and `FizzleSound` live as direct `.model.json` children of the Tool instance (not inside the Handle). The controller looks them up via `tool:FindFirstChild(name)` on each shot.

| Sound | Event |
|---|---|
| FireSound | Every activation that passes the cooldown + mind-full gates |
| HitSound | Confirmed consume only (block hit + buffer appended) |
| FizzleSound | Mind-full block, or buffer rejecting the append |

**None of these are heard by other players**, and that is still true after the beam fix. `Sound:Play()` called on a client plays on that client only. Two things need deciding before it can be fixed properly, which is why it was left alone:

- The Sounds are parented to the **Tool**, not to a BasePart, so they are non-positional. Replaying them verbatim on a bystander's client would put another player's blaster at full volume anywhere on the map. Remote playback needs a positional anchor — either move the Sounds onto the `Handle` (changes the wielder's own audio from 2D to 3D) or clone them onto the shooter's Handle at playback time (leaves the wielder untouched).
- `FireSound` fires on activations that never reach the server, including clean misses. The server only learns about successful consumes, so a broadcast-on-consume design makes bystanders hear hits but not misses.

`FizzleSound` also has an **empty `SoundId`** in the place file — it is silent for everyone today, including the wielder.

## Constants

| Constant | Value | Notes |
|---|---|---|
| `COOLDOWN` | 0.25s | Minimum time between activations |
| `FIRE_SOUND_NAME` | `"FireSound"` | Tool child name |
| `HIT_SOUND_NAME` | `"HitSound"` | Tool child name |
| `FIZZLE_SOUND_NAME` | `"FizzleSound"` | Tool child name |
| `HANDLE_NAME` | `"Handle"` | Read by `BlockShoot.muzzlePosition` on both VMs |
| `MUZZLE_ATTACHMENT_NAME` | `"Muzzle"` | Read by `BlockShoot.muzzlePosition` on both VMs |

## See also

- [[systems/BlockShoot]] — shared helpers (`findLetterBlock`, `readBlock`, `muzzlePosition`, `MAX_RAYCAST_DISTANCE`, `ConsumeBlock` remote) and server-side block destruction.
- [[design/client-server-boundary]] — the authority / prediction / presentation split this beam now follows.
- [[systems/LetterBlock]] — the entity LetterBlaster consumes.
- [[systems/WordBuffer]] — destination for consumed tiles.
- [[systems/MindFullManager]] — input gate when buffer is full.
- [[systems/AudioSFX]] — Spelling Staff sound wiring.
