---
title: Audio SFX
description: Sound effect inventory, wiring patterns, placeholder locations, and gap list for Brain Fighter
updated: 2026-08-10
---

# Audio SFX

Central reference for all in-game sound effects: what exists, where it's wired, what's silent, and how to add or replace sounds.

---

## Two Audio Backends

Two different Roblox audio systems are in use. Do not mix them for the same asset.

| Backend | Class | Used by |
|---------|-------|---------|
| **Old Sound** | `Instance.new("Sound")` | BlockTapController, SpellMenuGui, GameplayHudGui, `Vfx/spawnEffect` |
| **New AudioPlayer** | `AudioPlayer` + `Wire` + `AudioEmitter` | Firearm (ShotReplication), Melee (MeleeHitReplication) |

The old Sound class is simpler and fine for new work unless you need 3D positional audio or the new audio API's mixing features. The utility modules `playSoundFromSource.luau` and `playRandomSoundFromSource.luau` wrap the new system.

---

## Sound Inventory

### Block tapping (Phase 5.7)

The three Spelling Staff Sounds (`FireSound` / `HitSound` / `FizzleSound`, children of the Tool's Handle) were **deleted with the staff** in Phase 5.7 — see [[systems/LetterBlaster]].

| Event | Where it lives now | Status | Notes |
|-------|-------------------|--------|-------|
| Tap refused (mind full, or buffer rejected) | client-local `Sound` in `SoundService`, `VfxConfig.SFX.fizzle` at `PlaybackSpeed = 0.55` | ✅ wired | Same asset and pitch as `SpellMenuGui` / `GameplayHudGui`, so a refusal sounds identical wherever it was triggered |
| Block popped | `VfxConfig.EFFECTS.block_pop_{red,green,blue,wild}` → `sound` field, id `SFX.blockPop` | ✅ wired | Positional and replicated by construction, rather than a Sound on a Handle. One entry per block colour, resolved by `VfxConfig.resolveBlockPopId` |
| Tap attempt (the old `FireSound`) | — | ❌ dropped | There is no weapon to fire |
| Hit confirmation (the old `HitSound`) | folded into the block pop | ✅ wired | Was shooter-only; the pop is heard by everyone |
| Cooldown gate | — | ❌ silent | low priority — fast repeat tap |
| Raycast miss | — | ❌ silent | intentional — no target = no cue needed |

**The fizzle asset id is no longer duplicated.** It used to have a second copy in `src/StarterPack/Spelling Staff/Handle/FizzleSound.model.json`, because Rojo JSON cannot reference a Luau constant and every client needed the id on its own replicated copy of that Sound. That file is gone; `VfxConfig.SFX.fizzle` is now the only place it lives.

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

### Two traps that make a world SFX inaudible

Both of these were live bugs, found when boss fire turned out to be silent
despite being correctly wired. Check them before concluding an id is wrong.

**1. A Sound is a child of its anchor, so it dies when the anchor dies.**
`spawnEffect` parents its Sound to the anchor part. Hanging a *one-shot* cue
on `cosmeticEffectId` therefore ties it to the projectile: destroy the shot
on impact and the sound is destroyed mid-play. `cosmeticEffectId` is for
trails, which are supposed to stop when the shot stops. One-shot cues want
`launchEffectId` (fired at the muzzle on its own throwaway anchor, via
`SkillVisuals.spawnEffectAtPoint`) or `destroyEffectId`.

**2. Roblox's default 3D attenuation is tuned for effects that happen on
top of you.** Default `EmitterSize` is 10 studs with Inverse rolloff, so a
sound roughly scales by `EmitterSize / distance`. Brain engages from up to
100 studs — that is about a tenth volume, i.e. inaudible, which is exactly
what boss fire did. `SoundSpec` takes `emitterSize` and `rollOffMaxDistance`
for this; both are left at engine defaults unless a spec sets them, so
tuning a long-range cue can't quietly re-balance every close-range spell.

Current long-range entries: `projectile_boss_fireball` and
`aoe_boss_groundslam` at `emitterSize = 120` / `rollOffMaxDistance = 400`
(past Brain's 100-stud engagement range, so attenuation stays flat across
the arena); `projectile_destroy` at a more modest 40 / 300, since the wall a
player is hiding behind is right next to them anyway.

---

### Projectile death cue (`projectile_destroy`) — 2026-08-04

**Every projectile now makes a sound where it dies**, whatever killed it.
This is an audio-readability requirement, not decoration: a player in cover
with no line of sight to the boss needs to hear the volley land — and stop
landing — to know when it is safe to break out. The impact burst only ever
fired on a *direct hit*, so precisely the case where the listener can't see
the shot (it struck the wall they're hiding behind) was the silent one.

Wiring is `deliveryParams.destroyEffectId`, defaulted in `SkillDelivery` to
`DEFAULT_DESTROY_EFFECT_ID = "projectile_destroy"`, so it covers the whole
roster with no per-spell config. Two deliberate suppressions, both to avoid
double-cueing a single death:

| Case | Cue | Why |
|---|---|---|
| Splash shot (`impactRadius > 0`, e.g. Fireball) | none | `spawnShockwave` already fires on *every* detonation cause, server-side |
| Single-target direct rig hit **with** `impactEffectId` | none | the server's impact burst already covers it |
| Single-target direct rig hit **without** `impactEffectId` (player Volley) | `projectile_destroy` | previously silent |
| Stopped on world geometry | `projectile_destroy` | previously silent — **the cover case** |
| Expired mid-air | `projectile_destroy` | previously silent |
| Died on a shield shell | `shield_block` | unchanged; already had its own cue |

**Which VM plays it** matters, because both VMs run the `projectile` handler
for a player cast (the server via `SpellCastService` → `SpellExecutor`) and
double-playing is the easy mistake here:

- `SkillDelivery.detonate()` plays it **client-VM only** — that covers the
  caster's own shot, which is the one client that skips the broadcast.
- Every *other* client hears it from its own `CosmeticProjectile`, which
  reproduces the cue from `destroyEffectId` / `hasImpactCue` on the launch
  payload.
- Boss fire is server-only, so it never reaches the `detonate` branch at all
  and the cosmetic is the sole source — which is what makes the boss audible
  through a wall.

`CosmeticProjectile` distinguishes wall-from-rig with a Humanoid-ancestor
walk (`hitARig`) so a body hit stays on the server's burst while a wall
still thuds.

**Tuning note**: Brain's `FireballVolley` is `count = 30`, so this plays up
to 30 times ~0.15 s apart. Kept quiet (`volume = 0.40`) and pitched low
deliberately; if a volley reads as a machine-gun patter in playtest, drop
the volume further or add a rate cap rather than removing the cue.

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
| ~~High~~ | ~~FizzleSound SoundId in Studio (LetterBlaster)~~ — **resolved 5.7**: the Studio-side Sound is gone; the cue is built from `VfxConfig.SFX.fizzle` in code | done |
| High | Firearm empty-click (dry fire) | small — add Sound child + 2 lines in shot validation |
| Medium | `EffectSpec.light` and `.beam` are declared but still unimplemented in `spawnEffect` (only `emitters` + `sound` are consumed) | moderate |
| Medium | Projectile trails (`projectile_red_t1/t2/t4`) — 2026-08-04: now play a quiet one-shot `SFX.cast` layer at launch (no looping path in `spawnEffect`) instead of nothing; still no real continuous in-flight whoosh | needs a loopable asset |
| Medium | Boss `FireballVolley` launch (`projectile_boss_fireball`, `SFX.bossProjectileLaunch`) and impact (`impactEffectId = "impact_damage"`) — 2026-08-04: both hooks now wired in `BossConfig` (Brain + Wizard) with an audible reused-asset stand-in, no longer `UNSET`/silent | needs purpose-made launch + hit assets |
| Medium | Boss `GroundSlam` shockwave (`aoe_boss_groundslam`, reuses `SFX.impactHeavy`) — 2026-08-04: wired in `BossConfig.Brain`, was previously silent | needs a ground-thud asset |
| Low | `impact_knockup` — 2026-08-04: **correction**, `knockup` has a real gameplay handler (`SkillEffects.knockup`, used by boss GroundSlam); sound was the only stub, now reuses `SFX.impactDamage` pitched up instead of `UNSET` | needs a real "launched skyward" asset |
| ~~Low~~ **Done 2026-08-04** | Single-target projectiles that hit a wall or expired mid-air were silent — `detonate()` only played `impactEffectId` on a direct victim hit. Now every projectile death is audible via `projectile_destroy`; see "Projectile death cue" below | done |
| Medium | Memorize success chime | new Sound in GameplayHudGui |
| Medium | Spell cast success sound | new Sound in SpellMenuGui |
| Medium | Firearm reload start/complete | new Sounds + wiring in weapon state machine |
| Low | Loadout drop feedback sounds | new Sounds in LoadoutDropClient |
| Low | Death / respawn stings | CharacterSystemsLoader or DeathHandler |

---

## How to Add a New Sound

### Tool-child sound (removed pattern — do not reach for this)

The Spelling Staff hung named `Sound` children off its Handle and looked them up
via `FindFirstChild`. The pattern is recorded here because it is the obvious
thing to reinvent, and it has two traps:

- A Sound parented to anything that is **not a `BasePart`** is non-positional —
  full volume from anywhere on the map. That is why the staff's Sounds had to
  move from the Tool to the Handle before they could be replicated at all.
- The `SoundId` lives in `.model.json`, which cannot reference a Luau constant,
  so the id gets duplicated and drifts.

For a world sound, put it in a `VfxConfig.EFFECTS` entry instead (positional and
replicated by construction). For a refusal or UI cue, use a client-local Sound in
`SoundService` built from a `VfxConfig.SFX` constant.

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
