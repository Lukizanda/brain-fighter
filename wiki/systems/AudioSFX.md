---
title: Audio SFX
description: Sound effect inventory, wiring patterns, placeholder locations, and gap list for Brain Fighter
updated: 2026-05-16
---

# Audio SFX

Central reference for all in-game sound effects: what exists, where it's wired, what's silent, and how to add or replace sounds.

---

## Two Audio Backends

Two different Roblox audio systems are in use. Do not mix them for the same asset.

| Backend | Class | Used by |
|---------|-------|---------|
| **Old Sound** | `Instance.new("Sound")` | LetterBlaster, SpellMenuGui, GameplayHudGui |
| **New AudioPlayer** | `AudioPlayer` + `Wire` + `AudioEmitter` | Firearm (ShotReplication), Melee (MeleeHitReplication) |

The old Sound class is simpler and fine for new work unless you need 3D positional audio or the new audio API's mixing features. The utility modules `playSoundFromSource.luau` and `playRandomSoundFromSource.luau` wrap the new system.

---

## Sound Inventory

### LetterBlaster (Spelling Staff tool children)

Sounds live as named children of the Tool instance, looked up via `FindFirstChild`. Names come from `LetterBlasterConfig.luau`.

| Event | Asset constant | Status | Notes |
|-------|---------------|--------|-------|
| Shoot attempt (every activation) | `FIRE_SOUND_NAME = "FireSound"` | ✅ wired | SoundId set in Studio |
| Block consumed (success) | `HIT_SOUND_NAME = "HitSound"` | ✅ wired | SoundId set in Studio |
| Mind full block | `FIZZLE_SOUND_NAME = "FizzleSound"` | ✅ wired | **SoundId not yet set in Studio** |
| Buffer rejected | `FIZZLE_SOUND_NAME = "FizzleSound"` | ✅ wired | same FizzleSound instance |
| Cooldown gate | — | ❌ silent | low priority — fast repeat tap |
| Raycast miss | — | ❌ silent | intentional — no target = no cue needed |

**Model file**: `src/StarterPack/Spelling Staff/FizzleSound.model.json`
**To set SoundId**: open Studio, expand Spelling Staff in Explorer, select FizzleSound, paste asset ID into SoundId property.

---

### SpellMenuGui (SoundService, non-positional)

A single `fizzleSound` Sound instance is created at module level and parented to `SoundService`.

**Placeholder location**: `src/client/UI/SpellMenuGui.client.luau` line 67
```lua
fizzleSound.SoundId = "rbxassetid://0" -- TODO: replace with fizzle SFX asset ID
```

| Event | Status | Notes |
|-------|--------|-------|
| No target in range (red/blue cast) | ✅ wired | plays fizzleSound |
| CastAction failure (no mana / tier) | ✅ wired | plays fizzleSound |
| Successful cast | ❌ silent | no success chime yet |
| No character (edge case) | ❌ silent | intentional — unreachable in normal play |

---

### GameplayHudGui (SoundService, non-positional)

Same pattern as SpellMenuGui — single module-level Sound in SoundService.

**Placeholder location**: `src/client/UI/GameplayHudGui.client.luau` line 23
```lua
fizzleSound.SoundId = "rbxassetid://0" -- TODO: replace with fizzle SFX asset ID
```

| Event | Status | Notes |
|-------|--------|-------|
| Memorize failure (empty buffer / invalid word) | ✅ wired | plays fizzleSound |
| Memorize success | ❌ silent | no success chime yet |

---

### Firearm (AudioPlayer + Wire system)

Sounds live in a `Sounds` folder on the weapon model. `ShotReplication.client.luau` also expects an `AudioEmitter` on the Handle.

| Event | Status | Notes |
|-------|--------|-------|
| Fire | ✅ wired | `Sounds/Shoot` AudioPlayer |
| Hit on target | ❌ silent | no client-side impact sound |
| Reload | ❌ silent | |
| Empty / out of ammo | ❌ silent | dry-fire click is standard feedback |

---

### Melee (AudioPlayer + Wire system)

`MeleeHitReplication.client.luau` looks for `weapon:FindFirstChild("Sounds"):FindFirstChild("Hit")`.

| Event | Status | Notes |
|-------|--------|-------|
| Hit confirmed | ✅ wired | random variant supported if Hit is a Folder |
| Swing / miss | ❌ silent | common to omit for melee |

---

### Player State

No sounds wired for any player lifecycle event. `CharacterSystemsLoader.client.luau` has no audio logic.

| Event | Status |
|-------|--------|
| Death | ❌ silent |
| Respawn | ❌ silent |
| Loadout drop request | ❌ silent |
| Loadout drop rejected (toast shown) | ❌ silent |
| Loadout drop success | ❌ silent |

---

## Gap Priority

| Priority | Gap | Effort |
|----------|-----|--------|
| High | FizzleSound SoundId in Studio (LetterBlaster) | 1 min — just paste ID |
| High | fizzleSound placeholder IDs in SpellMenuGui + GameplayHudGui | 2 lines |
| High | Firearm empty-click (dry fire) | small — add Sound child + 2 lines in shot validation |
| Medium | Memorize success chime | new Sound in GameplayHudGui |
| Medium | Spell cast success sound | new Sound in SpellMenuGui |
| Medium | Firearm reload start/complete | new Sounds + wiring in weapon state machine |
| Low | Loadout drop feedback sounds | new Sounds in LoadoutDropClient |
| Low | Death / respawn stings | CharacterSystemsLoader or DeathHandler |

---

## How to Add a New Sound

### Spelling Staff tool sound (old Sound class)

1. Add `<Name>.model.json` to `src/StarterPack/Spelling Staff/` with `{ "className": "Sound" }`.
2. Add `Config.<NAME>_SOUND_NAME = "<Name>"` to `LetterBlasterConfig.luau`.
3. In `LetterBlaster/init.luau`, look up and play:
   ```lua
   local snd = self._tool:FindFirstChild(LetterBlasterConfig.<NAME>_SOUND_NAME) :: Sound?
   if snd then snd:Play() end
   ```
4. After Rojo sync, set the SoundId in Studio.

### UI sound in SoundService (old Sound class)

```lua
local SoundService = game:GetService("SoundService")
local mySound = Instance.new("Sound")
mySound.SoundId = "rbxassetid://<ID>"
mySound.Volume = 1
mySound.Parent = SoundService
-- play it:
mySound:Play()
```

Create once at module level; call `:Play()` at every event site.

### Firearm / melee weapon sound (new AudioPlayer system)

Use `playSoundFromSource(templateAudioPlayer, targetPart)` from
`src/shared/Weapon/Scripts/Utility/playSoundFromSource.luau`.
The template AudioPlayer must be an instance accessible to the caller (usually a child of the weapon model).
