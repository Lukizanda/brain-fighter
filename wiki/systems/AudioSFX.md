---
title: Audio SFX
description: Sound effect inventory, wiring patterns, placeholder locations, and gap list for Brain Fighter
updated: 2026-08-03
---

# Audio SFX

Central reference for all in-game sound effects: what exists, where it's wired, what's silent, and how to add or replace sounds.

---

## Two Audio Backends

Two different Roblox audio systems are in use. Do not mix them for the same asset.

| Backend | Class | Used by |
|---------|-------|---------|
| **Old Sound** | `Instance.new("Sound")` | LetterBlaster, SpellMenuGui, GameplayHudGui, `Vfx/spawnEffect` |
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

### Spell VFX audio (`VfxConfig.SFX` → `spawnEffect`) — 2026-08-03

Every spell cast and impact burst carries a `SoundSpec` in its
`VfxConfig.EFFECTS` entry. Two things were wrong until 2026-08-03:

1. **`spawnEffect` never read `effectSpec.sound` at all.** `sound`, `light`
   and `beam` were declared in `EffectSpec` but only `emitters` was ever
   consumed, so *all 10 spells were silent* regardless of what the config
   said. `sound` is now played; `light` and `beam` are still unimplemented.
2. The early `if not effectSpec.emitters then return end` guard sat *above*
   the sound, so particle-less effects would have stayed silent anyway.
   Audio now happens before that guard.

Asset ids live in one place, `VfxConfig.SFX`, so a real SFX pack can be
dropped in one line per entry. **All current ids are interim placeholders**
— verified to load (`ContentProvider:PreloadAsync`, `IsLoaded` true,
`TimeLength > 0`) but not purpose-made. The project owns no spell SFX: the
universe inventory is the LaserTag template's gun sounds, and Creator Store
audio search returns ripped music and meme clips rather than a usable
library. See the gap table below.

`spawnEffect` skips the `rbxassetid://0` placeholder rather than playing it,
which is what stopped the `Failed to load sound` spam. Sounds are parented to
the anchor (BasePart or Attachment) for 3D positional audio — deliberately
*not* to the emitter attachment, which is destroyed on `totalDurationSec` and
is routinely shorter than the sound. A `pitchRange` jitters `PlaybackSpeed`
per play so one asset reused every cast doesn't get repetitive.

---

### SpellMenuGui (SoundService, non-positional)

A single `fizzleSound` Sound instance is created at module level and parented to `SoundService`.

**Resolved 2026-08-03** — was `rbxassetid://0`, which failed to load on every
refused cast. Now reads `VfxConfig.SFX.fizzle` and plays it at
`PlaybackSpeed = 0.55`: the fizzle deliberately shares the cast swoosh asset,
pitched down, so a refused cast is audibly a dud rather than a quiet success.

| Event | Status | Notes |
|-------|--------|-------|
| No target in range (red/blue cast) | ✅ wired | plays fizzleSound |
| CastAction failure (no mana / tier) | ✅ wired | plays fizzleSound |
| Successful cast | ❌ silent | no success chime yet |
| No character (edge case) | ❌ silent | intentional — unreachable in normal play |

---

### GameplayHudGui (SoundService, non-positional)

Same pattern as SpellMenuGui — single module-level Sound in SoundService.

**Resolved 2026-08-03** — same fix and same pitch drop as SpellMenuGui, so a
refused action sounds identical wherever it was triggered from.

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
| **High** | **Source a real spell SFX pack and replace every `VfxConfig.SFX` id.** All 6 are stand-ins; `impactFreeze` (a sword hit standing in for an ice crack) is the weakest match. Needs a purchased/commissioned pack — the free library has nothing usable. | 1 line per entry once assets exist |
| High | FizzleSound SoundId in Studio (LetterBlaster) | 1 min — just paste ID |
| High | Firearm empty-click (dry fire) | small — add Sound child + 2 lines in shot validation |
| Medium | `EffectSpec.light` and `.beam` are declared but still unimplemented in `spawnEffect` (only `emitters` + `sound` are consumed) | moderate |
| Medium | Projectile trails (`projectile_red_t1/t2/t4`) have no sound — a fireball has no whoosh in flight | needs a loopable asset |
| Low | `impact_knockup` left at `UNSET` — no asset reads as a launch, and knockup has no gameplay handler yet either | — |
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
