---
type: system
description: Phase 4.6 weapon controller — wraps the block-shoot input pipeline behind the Spelling Staff Tool's Tool.Activated, with a cooldown, a laser-beam blast effect, and fire/hit/fizzle sounds. Since 2026-08-05 the beam and the fire sound both replicate via VfxBroadcast; the Sounds moved onto the Handle to make that possible.
updated: 2026-08-05
---

# LetterBlaster

The controller behind the **Spelling Staff** — the weapon Tool the player holds to shoot floating letter blocks. Replaces the raw `UserInputService.InputBegan` handler from Phase 3 with a proper Roblox `Tool` that carries its own mesh and sounds. There is **no reticle**: the player taps/clicks directly on the block they want.

## Files

- `src/shared/LetterBlaster/init.luau` — controller: `new(tool, session)`, `:mount()` (connects `Tool.Activated`), `:destroy()` (disconnects).
- `src/shared/LetterBlaster/LetterBlasterConfig.luau` — tuning constants: `COOLDOWN`, `FIRE_SOUND_NAME`, `HIT_SOUND_NAME`, `FIZZLE_SOUND_NAME`.
- `src/StarterPack/Spelling Staff/Scripts/SpellingStaff.client.luau` — the boot LocalScript: on `tool.Equipped` calls `LetterBlaster.new(tool, PlayerSession.get()):mount()`, and `:destroy()` on `Unequipped`.
- `src/StarterPack/Spelling Staff/` — the Rojo-managed Tool template: `Handle/` (MeshPart folder with a Studio-managed `Muzzle` attachment, and the `FireSound`/`HitSound`/`FizzleSound` `.model.json` children).

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

`FireSound`, `HitSound`, and `FizzleSound` are `.model.json` children of the **Handle**, resolved through `LetterBlaster:_playSound(name)` → `BlockShoot.resolveHandle(tool)`.

| Sound | Event | Heard by |
|---|---|---|
| FireSound | Every activation that passes the cooldown + mind-full gates | Shooter, plus every other player on a confirmed consume |
| HitSound | Confirmed consume only (block hit + buffer appended) | Shooter only |
| FizzleSound | Mind-full block, or buffer rejecting the append | Shooter only |

### Why the Handle and not the Tool (2026-08-05)

They used to hang directly off the Tool. A Sound parented to something that is not a BasePart is **non-positional** — it plays at full volume regardless of where the listener is standing. That made replicating them impossible without redesign: another player's blaster would have been just as loud from across the arena as from next to you.

Moving them onto the Handle (a `MeshPart`) makes them 3D, which is what lets `BlockShootService` name one in the beam broadcast and have every client play its own replicated copy at the right distance. The rolloff window is `RollOffMinDistance = 20` → `RollOffMaxDistance = 200`:

- **20** is the floor so the wielder is never attenuated. The default audio listener is the *camera*, which in this TPS sits ~12–15 studs behind the character, so a smaller floor would quietly make players' own weapons duller than before the move.
- **200** is `BlockShoot.MAX_RAYCAST_DISTANCE` — the range at which the weapon can act at all. A player standing further away than the blaster can reach has no reason to hear it.

The SoundIds, volumes and rolloff now live in the `.model.json` files rather than only in the `.rbxl`. Before this they were set in Studio and untracked, so moving the files at all would have silently created three fresh Sounds with empty ids.

### What still doesn't replicate, by choice

- **HitSound** is hit confirmation — the audio equivalent of a hit marker. Whether a shot connected is the shooter's business; the fire sound is the part that happened in the world. Same reasoning as the prediction contract on `CastAction.spellResolved`.
- **FizzleSound** is a refusal cue for an input that never reached the server at all.
- **Misses**. `FireSound` plays locally on any activation past the gates, but the server only learns about successful consumes, so bystanders hear hits and not misses. Closing that gap would mean a second remote fired on every trigger pull purely for cosmetics — not worth the traffic or the surface.

### Fizzle asset

`FizzleSound` had an **empty `SoundId`** until 2026-08-05 — silent for everyone, including the wielder. It now carries `rbxassetid://134677020800886` at `PlaybackSpeed = 0.55`, matching `VfxConfig.SFX.fizzle` and the pitch the two existing refusal cues (`SpellMenuGui`, `GameplayHudGui`) already use, so a refused action sounds the same wherever it was triggered from.

This is the one place that id is duplicated outside `VfxConfig`. Rojo JSON cannot reference a Luau constant, and setting it at runtime would not work either — every client needs the id on **its own replicated copy** of the Sound, not just the wielder's. A note in `VfxConfig.SFX.fizzle` points back here so a real asset swap updates both.

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
