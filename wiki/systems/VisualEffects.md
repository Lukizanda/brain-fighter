---
type: system
description: Visual effects plan — particle effects for spell casts/impacts, UI feedback animations, and per-color theming across all VFX
status: planning
updated: 2026-05-16
---

# Visual Effects

## Scope

Two categories:
1. **World VFX** — particle/beam effects for spell casts and impacts in 3D space
2. **UI VFX** — reactive animations on HUD elements (buffer fill, energy charge, word-valid flash, spell fire)

## Color System

All VFX are themed to one of three spell colors: **Red**, **Green**, **Blue** (matching EnergyReservoirs).  
Base palette (placeholder — ArtDirection approval needed):

| Color | Particle hue | Glow | Accent |
|---|---|---|---|
| Red | #FF3030 | #FF8080 | Orange spark |
| Green | #30FF60 | #80FFB0 | White leaf |
| Blue | #3080FF | #80C0FF | Cyan arc |

## World VFX

### Spell Cast (Caster origin)

Triggered when `CastAction` drains a reservoir and calls `SpellExecutor`.

| Event | Effect | Notes |
|---|---|---|
| Cast T1 | Small burst of colored sparks from staff tip | 0.3s duration |
| Cast T2 | Medium beam surge + ring ripple | 0.5s |
| Cast T3 | Full screen-edge flash + projectile trail | 0.8s |

### Spell Impact (Target)

Triggered when `SpellExecutor` applies an effect.

| Effect type | VFX | Notes |
|---|---|---|
| `damage` | Impact burst + colored shockwave ring | Scale with damage amount |
| `heal` | Rising green sparkles on target | Looping 2s |
| `freeze` | Ice crystal lattice overlaid on model + slow particle drift | Duration = freeze time |
| `shield` | Blue dome Beam loop around target | Until shield expires |
| `wall` (stub) | Stone/energy wall Part with particle edge glow | TBD |
| `buff` (stub) | Upward-swirling color particles | TBD |

### LetterBlock (Already exists — reference)

- LetterBlock already has a colored `ParticleEmitter` (Phase 3).
- On collect: pop burst effect + letter tile fly-in animation to buffer.
- On miss/expire: grey-out dissolve.

## UI VFX

### Buffer Tile

| Event | Effect |
|---|---|
| Letter added | Tile scales up (1.2×) then snaps to size — 100ms ease-out |
| Buffer full (MindFull) | All tiles pulse gold glow |
| Reorder drag | Held tile floats with shadow + slight scale-up |
| Word accepted (Memorize) | Tiles flash white → disappear with particle pop |
| Word rejected | Tiles shake (±4px, 3 cycles) + red flash |

### Energy Bar (EnergyReservoirs)

| Event | Effect |
|---|---|
| Energy gained | Bar fills with color-sweep animation |
| Energy drained (Cast) | Bar empties with drain ripple |
| Energy full (cap 160) | Pulsing glow edge on bar |

### Spell Menu / Cast

| Event | Effect |
|---|---|
| Spell becomes affordable | Spell icon brightens + subtle bounce |
| Spell fired | Icon flashes white → brief cooldown greyscale |

## Proposed Architecture

```
VfxService (server)          — fires RemoteEvents for world VFX (authoritative events)
VfxController (client)       — listens, spawns ParticleEmitter/Beam/Part effects at world positions
VfxConfig (shared)           — effect definitions (emitter params, colors, durations) keyed by effectId
UiVfxController (client)     — purely client-side; reacts to same events that drive HUD state
```

- World effects use **Attachment + ParticleEmitter** cloned from a template folder in ReplicatedStorage.
- UI effects use **TweenService** on existing HUD instances — no separate instances spawned.
- All emitter params are in `VfxConfig` — no magic numbers in controller code.

## Open Implementation Tasks

- [ ] Finalise color palette with ArtDirection page
- [ ] Build VfxConfig table (one entry per effectId)
- [ ] World VFX: cast burst (T1/T2/T3 variants) — ParticleEmitter template + VfxService wire-up
- [ ] World VFX: impact effects per SpellExecutor type (damage, heal, freeze)
- [ ] UI VFX: buffer tile tween helpers in TileBuilder/BufferDisplay
- [ ] UI VFX: energy bar fill/drain animations in EnergyBarBuilder
- [ ] UI VFX: spell icon afford/fire state animations in SpellMenuBuilder
- [ ] LetterBlock collect pop burst (extends existing Phase 3 emitter)
- [ ] Playtest pass: check perf (ParticleEmitter count, Beam count) under 10-block spam scenario

## Related Pages

- [[systems/SpellExecutor]]
- [[systems/CastAction]]
- [[systems/LetterBlock]]
- [[systems/HUD]]
- [[systems/EnergyReservoirs]]
- [[design/ArtDirection]]
