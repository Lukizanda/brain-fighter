---
type: system
description: Visual effects — particle effects for spell casts/impacts (shipped via VfxController + spawnEffect + cross-client broadcast), projectile bodies and trails, persistent status visuals (shield / freeze / burn / charge orb), UI feedback animations, and per-color theming. World cast/impact/projectile VFX are implemented; PERF guardrails and some lanes remain planned.
status: implemented (core); planned (PERF guardrails, collect-pop)
updated: 2026-08-12
---

# Visual Effects

> **Implementation status (2026-06-05).** The world-VFX core shipped — but with different module names than the plan below describes. Read this banner first; treat the rest of the page as the original design plan, accurate in intent but stale on specifics.
>
> **What exists on disk:**
> - `src/shared/Vfx/VfxConfig.luau` — `COLORS`, `SFX` (sound asset ids), `EFFECTS` (cast t1–t4 red, t1–t3 blue, **t1–t3 green**, `impact_damage/heal/freeze/shield/knockup/wall/buff`, **`shield_block`**, **`shield_break`**, **`impact_damage_t2`/`impact_damage_t3`**, `projectile_red_t1/t2/t4`, **`projectile_boss_fireball`**, **`projectile_boss_bolt`/`projectile_boss_arcane_bolt`**, **`aoe_boss_groundslam`**, **`projectile_destroy`**, **`wall_rise_rumble`/`wall_rise_dust`** — 2026-08-04: every `EFFECTS` entry now carries an audible placeholder `sound`, none left `UNSET`), and a `PERF` table.
> - `src/shared/Vfx/spawnEffect.luau` — **the shared spawn engine** (cast/impact/projectile), used by *both* the client `VfxController` and `SkillDelivery`. The plan's inline `VfxController.spawnCast/spawnImpact` methods were never built that way.
> - `src/client/Vfx/VfxController.client.luau` — plays cast VFX locally on `CastAction.spellResolved`, relays to server.
> - `src/server/Vfx/VfxBroadcastService.server.luau` — validates + `SpellVfxEvent:FireAllClients`.
> - `src/shared/Vfx/VfxBroadcast.luau` + `src/client/Vfx/WorldVfxController.client.luau` — **the server's only legal way to make a player see or hear something** (2026-08-04). See § "Nothing player-facing runs on the server" below.
> - `src/shared/Vfx/Remotes/*.model.json` — `BroadcastSpellVfx` / `SpellVfxEvent` / `ProjectileVfxEvent` / `WorldVfxEvent`.
> - `src/shared/Vfx/CosmeticProjectile.luau` + `src/client/Vfx/ProjectileVfxController.client.luau` — the *seen* projectile. The authoritative shot is server-simulated and invisible; each client replays the broadcast launch parameters locally so a blocked shot dies on the shield bubble rather than ~12 studs short of it. See [[systems/SkillPipeline]] § "Projectile visuals are client-local". Since 2026-08-10 it also builds the shot's *body* (sphere or stretched comet head, Trail, light) from **`VfxConfig.PROJECTILE_BODIES`** — see § "Projectiles" below.
> - `src/shared/Vfx/StatusVisuals/FreezeVfx.luau` — the freeze ice-shard status visual (see [[systems/SkillPipeline]] § VFX Layers).
> - `src/shared/Vfx/StatusVisuals/InfernoVfx.luau` + `src/client/Vfx/InfernoVfxController.client.luau` — the burning-rig flames (2026-08-08). Attribute-driven off `_burning`, like ShieldVfx. Parents `ParticleEmitter`s straight onto every limb over `MIN_PART_VOLUME` rather than welding Parts, which is what makes the fire *engulf* the rig instead of being a bonfire it stands in — a ParticleEmitter parented to a BasePart inherits that part's volume for its Sphere/Surface emission shape.
> - `src/shared/Vfx/ScreenImpact.luau` — the screen-space lane (2026-08-08): warm `ColorCorrectionEffect` + `BlurEffect` in `Lighting`, plus a camera shake via `Humanoid.CameraOffset`. Deliberately **not** `Camera.CFrame` — the default Roblox camera scripts own that and rewrite it every frame.
> - `src/shared/Vfx/StatusVisuals/ShieldVfx.luau` + `src/client/Vfx/ShieldVfxController.client.luau` — the absorb-shield bubble. Unlike FreezeVfx it is **attribute-driven**: the controller watches `_shield` on each player character rather than being called from an effect handler, which is what gets it cross-client replication without a broadcast. See [[systems/SkillPipeline]] § "Shield — the bubble reads the attribute, not the cast".
> - `src/shared/Vfx/StatusVisuals/ChargeOrbVfx.luau` + `src/client/Vfx/ChargeOrbController.client.luau` — the hold-to-charge orb (2026-08-12, [[systems/ChargeCast]]). Copies ShieldVfx's `start`/`update`/`stop` shape and its `_chargeColor` / `_chargeTier` attribute wire, and is the first persistent visual that must be *grown* while it runs. **It cannot be a `spawnEffect` entry**, and the reason is worth pinning: `spawnEffect` returns nothing, hands every instance it makes to `Debris` with a duration fixed at author time, and its only sustained branch is a `task.delay` that flips `Enabled = false`. A charge has no author-time duration and needs a handle. The mote halo's *look* still lives in `VfxConfig` as `charge_motes_<colour>` (rate-based `EmitterSpec`, resolved by `VfxConfig.resolveChargeMotesId`); only its lifetime is owned by the module. The converging mote Parts lift `collectStream`'s quadratic-Bézier flight, with the orb attachment as the destination and a ring around the caster as the source.
>
> **The only *sustained* emitter in the project.** Every other `EFFECTS` entry is a burst. `ChargeOrbVfx` therefore budgets explicitly rather than leaning on `PERF.maxEmitters = 32`: `MOTE_EMITTER_CAP = 6` concurrent halos and `MOTE_PART_CAP = 48` live mote Parts across every charging player on the client. Past either cap the orb keeps drawing and the layer degrades — flavour is lost, the tell is not. Measured 0 orphaned orbs / motes / halo attachments after 20 charge cycles.
>
> **Does NOT exist (fictional in the plan below):** `UiVfxController` (UI VFX live inline inside the HUD builders, not a standalone module), `src/shared/Vfx/init.luau` barrel, and `src/shared/Vfx/Templates/` (the `VfxTemplates` folder is Studio/MCP-managed, not Rojo `.model.json`).
>
> **Corrected contract facts:** the broadcast payload field is **`impactEffectIds: { string }`** (plural array), not `impactEffectId`; the server validates **`MAX_TIER = 4`** (not 3) and `MAX_IMPACT_EFFECT_IDS = 8`. Lifetime cleanup is **`Debris:AddItem` only** today — the §"PERF guardrails" cap/evict/throttle table and the `"VfxInstance"` Heartbeat sweep are **not implemented** (`PERF` data exists but `spawnEffect` reads none of it). The LetterBlock collect-pop is still unbuilt. Green cast entries **were** unbuilt until 2026-08-03 — `cast_green_t1..t3` now exist, and `spawnEffect` plays `EffectSpec.sound` (it previously consumed only `emitters`, so every spell was silent). **`.light` is implemented as of 2026-08-08** — a `PointLight` at full brightness on the landing frame, tweened to 0 over `durationSec` and honouring `PERF.allowLights`; `impact_damage_t3` is its first and so far only consumer. `.beam` is still ignored.

## VfxTemplates and the third-party texture trap

`ReplicatedStorage.VfxTemplates` holds seven `ParticleEmitter` templates, Studio/MCP-managed and **not** Rojo-tracked — they live only in `BrainFighter.rbxl` and must be re-created after a fresh place open.

| Template | Texture | Notes |
|---|---|---|
| `BurstSmall` / `BurstMedium` / `ImpactBurst` / `HealBurst` | `1913819781` | The original four. All share one soft round blob. |
| `FireFlame` | `17703243127` | 8×8 flipbook, `FlipbookMode = OneShot`, additive (`LightEmission` 1 / `LightInfluence` 0), `Acceleration` (0, 12, 0) + `Drag` 4, Sphere/Surface/Outward. |
| `FireSmoke` | `17703243127` | Same sheet, charcoal-tinted, `LightInfluence` 1, slower and larger. |
| `FireEmber` | `1913819781` | Keeps the blob — a spark *is* a bright round dot, and a flipbook there would only cost frames. |

**Why Inferno looked flat for so long, and the lesson.** Every template shared one round-blob texture, so no particle count could make anything read as fire — the pre-2026-08-08 `impact_damage_t3` was already the biggest entry in the table at 86 particles and still looked like a firework. The fix was the *texture*, not the count: a flipbook sheet animates each particle through a full flame birth-and-dissipate over its lifetime. Reach for `FlipbookLayout` before reaching for a bigger `emitCount`.

**The red school's impacts share one vocabulary (2026-08-09).** `impact_damage_t2` (Fireball) was rebuilt on the same three flipbook layers as `impact_damage_t3` — flame / ember / smoke, same `VfxConfig.FIRE` gradients — for the reason above: its 38-particle `ImpactBurst` splash was a firework at any count, and a fire school whose tiers draw from unrelated effects doesn't read as a ladder. **What separates the tiers is scale and how long the fire lasts**, not which templates they use. T3 is a detonation that hands off to a 3 s burn (`StatusVisuals/InfernoVfx`); T2 has no burn lane, so every lifetime is roughly halved and the smoke tail is cut hardest — `totalDurationSec` 1.25 against T3's 2.5. Fireball also lands far more often, so a long plume would leave the arena permanently hazed. The audio ladder is deliberately *not* shared: T2 keeps the pitched-down `impactDamage` hit rather than T3's `impactHeavy` boom.

**Dropping the ground disc is what forced the scale-up.** The same day, Fireball set `impactRing = false` (see [[systems/SkillPipeline]] § `impactRing`) and stopped drawing the 14-stud neon shockwave under its hit. That disc was the only thing communicating the blast's exact reach, so the fire had to grow to imply it — the growth is as much in `spreadAngle` (130°/160°/140°, against T3's 70° column) as in `size`. **Watch the tier headroom here**: the T2 flame now peaks at 7.0 against T3's 7.5, so footprint barely separates them any more and the ladder rests on duration, ember/smoke volume and the light. If Fireball starts reading as interchangeable with Inferno, scale T3 up rather than pulling T2 back down.

**Third-party Creator Store images do not load in this universe.** Every "free" fire/smoke flipbook decal found via `search_asset` on `creator_store` — sixteen of them, including all the top hits for "fire flipbook" and "smoke flipbook" — failed to load. `17703243127` works *only* because it is already in the universe inventory.

Verify before building on an asset, and verify correctly:
- `ContentProvider:PreloadAsync(ids, callback)` reports `Enum.AssetFetchStatus.Failure` for these. **Use the callback form** — the argument-less call succeeds silently either way and tells you nothing.
- The cheapest reliable probe is an `ImageLabel` in a `SurfaceGui` and a read of `IsLoaded` after a few seconds. A `Decal` on a Part plus a screenshot is *not* reliable: the project's own known-good `1913819781` rendered blank that way, and one Creator Store "fire flipbook" rendered a **shirt template**.
- Always include a known-good id as a control. Without `1913819781` in the batch there is no way to tell "this asset is unusable" from "my probe is broken".

When a needed texture has no usable owned equivalent, the path is to author one and upload it to the universe — not to ship an id that renders for nobody.

## A rate-based entry must state its `rate`

**Every template in `VfxTemplates` ships `Rate = 0`.** That is correct for the overwhelming majority of `EFFECTS`, which are one-shot bursts reaching `spawnEffect` through `emitCount`. It is a silent kill switch for the minority that use `durationSec`.

`spawnEffect`'s `durationSec` branch only sets `Enabled = true`. It does not supply a rate, and `applyEmitterOverrides` writes one only when the spec has a `rate` field. So an entry with `durationSec` and no `rate` enables an emitter that emits nothing, logs nothing, and warns nothing — it looks authored and does not exist.

This shipped in all three delivery cosmetics (`projectile_red_t1/t2/t4`) and went unnoticed for months: **every fire projectile in the game was a bare neon cube with no trail at all**, and the "make the projectiles nicer" task turned out to be mostly "make them appear". Fixed 2026-08-10; all rate-based entries now state `rate` explicitly.

If you author a `durationSec` entry, set `rate`. If a trail is invisible, check `rate` before touching anything else — count and size are the wrong place to look, because the emitter never ran.

## Projectiles (2026-08-10)

Fire projectiles were the last thing in the red school still speaking the pre-flipbook vocabulary — `BurstSmall`'s round blob, on top of the dead-`rate` bug above. They now draw from the same `FireFlame`/`FireEmber`/`FireSmoke` layers and `VfxConfig.FIRE` gradients as the impacts, so the school reads as one thing from muzzle to blast.

**`VfxConfig.PROJECTILE_BODIES` is a second table keyed by the same `cosmeticEffectId`.** It owns the *solid* of a drawn shot — shape, stretch, core colour, trail ribbon, light — while the `EFFECTS` entry under that key owns the particles. Deliberately not a field on `EffectSpec`: `spawnEffect` deals in emitters, sound and light and has no business knowing a shot has a shape, and a projectile-only field would be dead weight on every cast burst. `CosmeticProjectile` reads it; nothing else does. **A key with no entry still flies** — as the old axis-aligned neon cube — which is what keeps it optional for a future non-fire projectile.

| id | body | notes |
|---|---|---|
| `projectile_red_t1` (Firebolt) | bolt, 3.4× | short sheath; flame gone ~a body-length behind it |
| `projectile_red_t2` (Fireball) | orb | three layers, flame *grows* after birth, smoke tail, the only body with a light |
| `projectile_red_t4` (Volley) | bolt, 3.0× | wider than T1 so three at 12° spread stay three shots |
| `projectile_boss_bolt` (Brain) | bolt, 2.8× | first in-flight trail the boss has ever had |
| `projectile_boss_arcane_bolt` (Wizard) | bolt, 3.2× | violet, ember-only — the shot *freezes*, so no flame layer |

Four things that had to be found by looking, not by reading:

- **`Shape = Ball` with a non-uniform `Size` does not render an ellipsoid.** The engine draws a round sphere and ignores the other two axes. The first pass set `Size.Z` to 3.4× and every bolt still came out a circle. Elongation needs a `SpecialMesh` of `MeshType = Sphere`, whose `Scale` *is* per-axis. Caught only by stripping the flame off and looking at the bare silhouette — with a sheath on, a comet and a ball are indistinguishable.
- **Neon clips a near-white tint to pure white.** Cores were first set to `FIRE.flame`'s white-hot birth colour, reasoning the sheath should be what is hotter; on screen every shot was a flat white disc with the silhouette lost inside the blowout. The core carries the *orange* and the particles carry the white — the opposite split, and the one that reads as molten. A colour this close to clipping cannot be judged from the hex.
- **A Trail's gradient runs along its length, not over a lifetime.** Reusing `FIRE.flame` (built for a particle cooling as it ages) put the white end at the shot and dragged a wide pale band behind everything. Fire trails use their own `FIRE_TRAIL_GRADIENT`, start at the core's orange, and sit below `LightEmission` 1 so the colour survives the blend.
- **Particle density must be judged at the real speed.** Fireball at rate 95 and 3-stud sprites, moving 55 studs/s, stacked ~5 additive layers at every point of its path and saturated to white cotton (now 40). A probe at an artificially slow speed piles every particle on one spot and is worthless for this — it will tell you a correct entry is broken.

**Death no longer erases the trail.** Destroying the Part on the impact frame took its `Attachment` with it, and killing an Attachment kills every particle already emitted from it — so a shot stopped by a wall 0.2 s into a 2 s flight deleted its own streak back to the muzzle. `CosmeticProjectile.retire()` hides the core, switches the emitters and Trail off, drops the light, and lets `Debris` collect the shell ~1.6 s later. Impact cues are unaffected: they spawn on their own throwaway anchors.

**Rendered size is never gameplay size.** `girth`/`stretch` scale only the drawn body; the shield-contact padding in the flight loop reads `params.size`, the size the server launched the real shot with. Keep it that way — a 3× longer body that also padded the shell test would block where the server does not, which is the class of divergence [[systems/SkillPipeline]] § "Projectile visuals are client-local" exists to prevent.

## Nothing player-facing runs on the server

*Added 2026-08-04, after the same bug shipped three times in a row (eb0e579, a6b94b3, b14a8c2).*

The server has no screen and no speakers. Every visual and every sound a player is meant to perceive is drawn on each client.

This page has said "Server creates NO Parts/Emitters" since the design landed, and it still went wrong three times — because the engine only fails at it *partially*:

| Called on the server | Reaches players? |
|---|---|
| `ParticleEmitter:Emit()` | **No** — not replicated. This is most of `EFFECTS`. |
| Emitter with `Enabled = true` (rate-based) | Yes — it's a property write, not a method call |
| `Sound:Play()` on a workspace Part | Yes |
| Creating the anchor / cosmetic Part | Yes, a replication frame late |

A server-spawned effect therefore gives you the anchor, the ring and the audio but not the burst. It reads as ~80% correct in a playtest, 100% correct in Studio's server view, and leaves clean server logs. That combination is what let it survive three fix attempts.

**How it's prevented now — three layers:**

1. **`spawnEffect` refuses on the server** with a throttled `debug.traceback()` warning. There is no silent-degrade path left.
2. **`VfxBroadcast` gives the server a legal alternative** — the missing piece, and the actual root cause. Before it existed, `VfxBroadcastService` only relayed *client → server → clients* for spell casts, so server-owned code (boss fire, Stone Wall) had nothing correct to reach for.
   - `VfxBroadcast.playAt(effectId, position, drawnLocallyBy?)` — one-shot at a point
   - `VfxBroadcast.playOn(effectId, target, drawnLocallyBy?)` — one-shot on an existing Instance
   - `VfxBroadcast.shockwave(center, radius, opts)` — ground ring + burst
3. **The VM branch lives in `SkillVisuals`, not at call sites.** `spawnEffectAtPoint` / `spawnEffectOn` / `spawnShockwave` broadcast on the server and draw on a client. Handlers say *what* should happen; the routing is one decision in one module rather than a guard to remember twelve times.

**The one thing a caller still decides: `drawnLocallyBy`.** Delivery handlers that run on **both** VMs (`projectile`, `aoe`) pass the casting player's UserId — that player's client runs the same code and already drew the effect frame-perfectly, so the broadcast must skip them or they see two. Server-only paths (`world_spawn`, boss fire) pass nothing, so everyone receives it. Same skip `VfxController` does with `senderUserId` and `ProjectileVfxController` with `casterUserId`.

**Gameplay objects are the exception, and they split rather than move.** A Stone Wall slab is collidable — it must be one server-owned object or it blocks the boss on one machine and not another. So `spawnBarrier` creates the Part server-side as before and broadcasts only its cosmetic overlay.

That split has a limit worth naming: **moving a gameplay Part is not a cosmetic, so it stays server-side too.** The wall's rise (2026-08-08) is a per-frame `CFrame` write on the server, not a client-side animation over an already-placed slab — collision has to follow the visual, and `CFrame` writes on an anchored Part replicate as ordinary property changes anyway. Only the dust coming off the base goes over the wire, as `wall_rise_rumble` / `wall_rise_dust`. See [[systems/SkillPipeline]] § Stone Wall.

**Destroying a replicated object is itself a broadcast.** The Stone Wall's crumble (2026-08-08) adds no remote and no payload: `spawnBarrier` tags the slab, `Debris` deletes it server-side when its duration expires, and every client's `GetInstanceRemovedSignal` fires with a Part whose CFrame, Size and Color are still readable. Each client builds its own rubble from that. Worth reaching for whenever the cue *is* an object's death — it is the attribute-driven pattern (`ShieldVfx`, `FreezeVfx`) with "gone" as the state. See `client/Vfx/BarrierCrumbleController` and [[systems/SkillPipeline]] § the crumble.

**A new Part cannot move on the frame it is created.** The corollary that cost a shipped-and-rejected attempt at that rise. *Initial* instance replication is slower than the property updates that follow it, so a Part created and immediately animated has already travelled by the time any client first sees it — the client's first frame is the animation's middle, which reads exactly like a pop. Anything server-animated from birth needs a beat of stillness first (`BARRIER_TELL_SEC`). Note this is a *different* failure from the `playAt`-by-position rule below: there the Instance reference arrives `nil`, here it arrives correctly but late.

**Broadcast fresh Parts by position, not by reference.** An Instance argument the receiving client hasn't replicated yet arrives as `nil`, and the barrier overlay fires on the same frame the Part is created — squarely inside that window. `playOn` is for long-lived targets (a character's HumanoidRootPart); `playAt` is for anything just created.

**Verification standard.** A VFX/SFX change is **not** verified by server logs, `[Server]` console output, or Studio's server view. Only by what a client renders — a client-side count, a client screenshot, or the effect appearing for a second player. All three prior bugs had clean server logs while players saw nothing. a6b94b3's own commit message names it: *"the bug was only visible by measuring what the client renders."*

**The other lane is fixed too (2026-08-04).** `StatusVisuals/FreezeVfx` was never *invisible* — welded Parts and tweens do replicate — but `SkillEffects.handlers.freeze` runs on both VMs and called `FreezeVfx.start` directly, so a player-cast freeze built one set of shards on the server (replicating down) and another locally on the caster, welded to the same limbs. Two overlapping ice shells read as "slightly too opaque", which is why it went unnoticed.

It's now attribute-driven like `ShieldVfx`: `SkillEffects` writes `SkillConstants.FROZEN_ATTRIBUTE` (`_frozen`) on the character Model and draws nothing; `client/Vfx/FreezeVfxController` watches that flag and owns every Instance. `FreezeVfx.start` refuses on the server with a traceback, matching `spawnEffect`.

Both VMs deliberately still *write* the flag. The server's write is the one that replicates, so everyone sees a frozen rig; the caster's local write never leaves that machine but paints its shards on the cast frame rather than after the round trip. When the server's value lands it matches, so no second signal fires.

Unlike `ShieldVfxController` — which only binds player characters, because a shield only ever sits on a player — `FreezeVfxController` also binds every rig carrying a `SkillConstants.DAMAGEABLE_TAGS` tag. Freeze is aimed at the boss more often than at anything else. That tag list is now shared by `SkillDelivery`, `CosmeticProjectile` and the controller (it was three hand-kept copies, two of which carried comments warning they had to agree).

Measured: freezing the boss draws **15** shards on the client — one set, where the old path gave 30 — and **0** on the server. Expiry through `purgeFreeze` clears the flag, the shards, and restores WalkSpeed.

## Scope

Two categories:
1. **World VFX** — particle/beam effects for spell casts and impacts in 3D space.
2. **UI VFX** — reactive animations on HUD elements (buffer fill, energy charge, memorize feedback, spell fire).

## Color System

All VFX are themed to one of three spell colors: **Red**, **Green**, **Blue** (matching EnergyReservoirs and `LetterBlocks.COLOR_TINTS`).

Base palette (placeholder — ArtDirection approval needed; the **Tile** column is the existing `BufferDisplayConfig.TILE_COLORS` value, used as the canonical UI hue so HUD tweens and world VFX agree):

| Color | World hue (ParticleEmitter) | Glow halo | Accent / spark | UI Tile (existing) |
|---|---|---|---|---|
| Red | `#FF3030` | `#FF8080` | Orange spark `#FFB060` | `Color3.fromRGB(210, 65, 65)` |
| Green | `#30FF60` | `#80FFB0` | White leaf `#FFFFFF` | `Color3.fromRGB(60, 175, 80)` |
| Blue | `#3080FF` | `#80C0FF` | Cyan arc `#80FFFF` | `Color3.fromRGB(65, 125, 220)` |

Final palette goes into `VfxConfig.COLORS` so both `VfxController` (world) and the HUD builders can pull from one source of truth. Until ArtDirection signs off, the world-hue / glow / accent column is provisional; the Tile column is locked.

---

## Architecture Overview

```
┌─── Caster Client ────────────────────────────────────────────────────────────┐
│  CastAction.spellResolved (BindableEvent, client-local only)                 │
│       │                                                                      │
│       ├──▶ VfxController — plays cast VFX locally (frame-perfect, no RTT)   │
│       │    (clones emitters from ReplicatedStorage.VfxTemplates)             │
│       │                                                                      │
│       └──▶ BroadcastSpellVfx:FireServer(payload)                             │
└──────────────────────────────────────────────────────────────────────────────┘
                              │
┌─── Server ──────────────────────────────────────────────────────────────────┐
│  VfxBroadcastService — validates + SpellVfxEvent:FireAllClients(payload)     │
│   (rate ≤ 4/s, effectId ∈ VfxConfig, impactTarget ∈ Workspace)              │
└──────────────────────────────────────────────────────────────────────────────┘
                              │
┌─── Other Clients ────────────────────────────────────────────────────────────┐
│  VfxController — receives SpellVfxEvent                                      │
│   skip if senderUserId == LocalPlayer.UserId (already played locally)        │
│   spawns cast + impact VFX from VfxTemplates                                 │
└──────────────────────────────────────────────────────────────────────────────┘

┌─── All Clients ──────────────────────────────────────────────────────────────┐
│  UI VFX — TweenService on existing HUD, inline inside each HUD Builder       │
│  (NOT a standalone UiVfxController module); no RemoteEvent needed            │
└──────────────────────────────────────────────────────────────────────────────┘

spawnEffect.luau (shared) ── the spawn engine VfxController AND SkillDelivery both call
VfxConfig (shared)  ── effect specs keyed by effectId
VfxTemplates folder (ReplicatedStorage) ── ParticleEmitter / Beam / Attachment templates (Studio/MCP-managed, not Rojo)
```

- **World VFX (R2 two-event flow)**: After a successful cast, the caster's client fires `CastAction.spellResolved` (client-local BindableEvent). `VfxController` hears it and plays cast/impact VFX immediately (frame-perfect, no network round-trip). `VfxController` also fires `BroadcastSpellVfx:FireServer(payload)`. `VfxBroadcastService.server.luau` validates and relays to all clients via `SpellVfxEvent:FireAllClients`. Each receiving client skips the event if `senderUserId == LocalPlayer.UserId` (already played). Server creates NO Parts/Emitters.
- **Client-side spawn**: `VfxController` (LocalScript) looks up `VfxConfig[effectId]`, clones the template, parents to a runtime Attachment, schedules destruction.
- **UI VFX**: pure client. Lives next to / inside existing HUD builders — uses TweenService on the same instance handles, no remote events. Triggered off the same signals the HUD already binds (`wordBuffer.changed`, `energyReservoirs.changed`, `result.ok`).
- **No magic numbers**: every duration, easing, count, lifetime, color lives in `VfxConfig` or an existing `*Config.luau`. The controller code reads it; never declares a literal in logic.

---

## 1. VfxConfig Schema

Single shared ModuleScript at `src/shared/Vfx/VfxConfig.luau`. Exports a typed table of effect entries keyed by `effectId: string`.

### Entry shape

```lua
export type Color3Triplet = { r: number, g: number, b: number } -- 0..1 floats

export type ColorPalette = {
    primary: Color3,   -- main particle hue
    glow: Color3,      -- inner halo / light tint
    accent: Color3,    -- spark / secondary
}

export type EmitterSpec = {
    -- ParticleEmitter properties (Roblox names, 1:1 with the instance)
    template: string,           -- key into VfxTemplates (e.g. "BurstSmall")
    color: ColorPalette | nil,  -- nil = use template's authored color
    rate: number?,              -- emit rate (particles/s); nil = use template
    lifetime: NumberRange?,     -- particle lifetime
    size: NumberSequence?,      -- size over lifetime
    speed: NumberRange?,
    spreadAngle: Vector2?,
    rotation: NumberRange?,
    transparency: NumberSequence?,
    -- One-shot vs duration
    emitCount: number?,         -- if set, use ParticleEmitter:Emit(emitCount)
    durationSec: number?,       -- if set, enable rate-based emit for N seconds
}

export type BeamSpec = {
    template: string,
    color: ColorPalette?,
    lifetimeSec: number,
    width0: number?,
    width1: number?,
    segments: number?,
}

export type SoundSpec = {
    soundId: string,            -- "rbxassetid://..." | "" to skip
    volume: number?,            -- 0..10
    pitchRange: NumberRange?,   -- randomize PlaybackSpeed within range
}

export type EffectSpec = {
    -- Discriminator on which lists to consume
    emitters: { EmitterSpec }?,        -- 0..N
    beam: BeamSpec?,                   -- 0..1
    light: { color: Color3, brightness: number, durationSec: number }?,
    sound: SoundSpec?,
    -- Lifetime / cleanup
    totalDurationSec: number,          -- effect-scope lifetime; cleanup at end
    -- Attachment policy
    anchor: "caster" | "targetRoot" | "targetHumanoidRootPart"
          | "targetHead" | "worldPosition",
    -- Optional gameplay-linked duration (e.g. shield/freeze): when set,
    -- VfxController re-reads totalDurationSec from the spell spec instead
    -- of this default.
    durationFromSpec: boolean?,
}

export type Config = {
    COLORS: { red: ColorPalette, green: ColorPalette, blue: ColorPalette },
    EFFECTS: { [string]: EffectSpec },   -- effectId → spec
    -- Effect id resolution: VfxController calls
    --     VfxConfig.resolveCastId(color, tier)         → "cast_red_t1" etc.
    --     VfxConfig.resolveImpactId(effectKind, tier?) → "impact_damage" etc.
    -- resolveImpactId takes an OPTIONAL tier: when an "impact_<kind>_t<N>"
    -- entry exists it wins, otherwise the shared per-kind entry is used.
    -- Authoring a tiered variant is how you say "this tier should land
    -- differently" (see Inferno, 2026-08-03).
    resolveCastId: (color: string, tier: number) -> string,
    resolveImpactId: (effectKind: string, tier: number?) -> string,
    -- "charge_motes_red" etc, the sustained halo on a hold-to-charge orb.
    -- Falls back to red for an unrecognised colour: a silently haloless orb
    -- would read as the charge having failed. Consumed by ChargeOrbVfx, which
    -- instantiates the emitter itself rather than going through spawnEffect.
    resolveChargeMotesId: (color: string?) -> string,
}
```

### Example entries

#### 1. Cast burst — Red Tier 1

```lua
EFFECTS["cast_red_t1"] = {
    emitters = {
        {
            template = "BurstSmall",
            color = COLORS.red,
            emitCount = 14,
            lifetime = NumberRange.new(0.20, 0.32),
            size = NumberSequence.new({
                NumberSequenceKeypoint.new(0.0, 0.35),
                NumberSequenceKeypoint.new(0.4, 0.55),
                NumberSequenceKeypoint.new(1.0, 0.0),
            }),
            speed = NumberRange.new(6, 10),
            spreadAngle = Vector2.new(35, 35),
            rotation = NumberRange.new(-180, 180),
            transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0.0, 0.0),
                NumberSequenceKeypoint.new(1.0, 1.0),
            }),
        },
    },
    sound = { soundId = "rbxassetid://0", volume = 0.8, pitchRange = NumberRange.new(0.95, 1.10) },
    totalDurationSec = 0.45,
    anchor = "caster",
}
```

#### 2. Cast burst — Blue Tier 3 (with beam)

```lua
EFFECTS["cast_blue_t3"] = {
    emitters = {
        {
            template = "BurstLarge",
            color = COLORS.blue,
            emitCount = 60,
            lifetime = NumberRange.new(0.45, 0.85),
            size = NumberSequence.new({
                NumberSequenceKeypoint.new(0.0, 0.6),
                NumberSequenceKeypoint.new(0.5, 1.4),
                NumberSequenceKeypoint.new(1.0, 0.0),
            }),
            speed = NumberRange.new(14, 22),
            spreadAngle = Vector2.new(55, 55),
        },
        {
            template = "RingRipple",
            color = COLORS.blue,
            emitCount = 1,
            lifetime = NumberRange.new(0.6, 0.6),
        },
    },
    beam = {
        template = "ChannelBeam",
        color = COLORS.blue,
        lifetimeSec = 0.55,
        width0 = 0.4,
        width1 = 0.05,
        segments = 8,
    },
    light = { color = Color3.fromHex("#80C0FF"), brightness = 6, durationSec = 0.4 },
    sound = { soundId = "rbxassetid://0", volume = 1.0 },
    totalDurationSec = 0.85,
    anchor = "caster",
}
```

#### 3. Impact — damage (target Humanoid hit)

```lua
EFFECTS["impact_damage"] = {
    emitters = {
        {
            template = "ImpactBurst",
            -- color is unset: VfxController patches it in at runtime from the
            -- caster's spell color so one impact entry serves R/G/B.
            emitCount = 22,
            lifetime = NumberRange.new(0.30, 0.55),
            size = NumberSequence.new({
                NumberSequenceKeypoint.new(0.0, 0.5),
                NumberSequenceKeypoint.new(1.0, 0.0),
            }),
            speed = NumberRange.new(10, 18),
            spreadAngle = Vector2.new(180, 180),
        },
        {
            template = "ShockwaveRing",
            emitCount = 1,
            lifetime = NumberRange.new(0.40, 0.40),
        },
    },
    sound = { soundId = "rbxassetid://0", volume = 0.85, pitchRange = NumberRange.new(0.92, 1.08) },
    totalDurationSec = 0.65,
    anchor = "targetHumanoidRootPart",
}
```

Heal / freeze / shield / wall / buff follow the same shape; `freeze` and `shield` set `durationFromSpec = true` so they survive for the full spell duration rather than a flat number.

---

## 2. World VFX — Implementation Detail

### 2.1 Cast burst anchor — ~~Spelling Staff tip~~ the caster (Phase 5.7)

> **Superseded 2026-08-10.** The staff and its `Tip` attachment were deleted in
> Phase 5.7 ([[design/tap-to-pop]]). `resolveCastAnchor` now returns the caster's
> `HumanoidRootPart` directly — the documented fallback became the only path, so
> the Tool walk was removed rather than left to miss three `FindFirstChild` calls
> per cast. **Casts now originate at the caster's chest, not a staff tip.** If the
> deferred cosmetic prop lands, give it an attachment and re-add the lookup.
>
> The original design is kept below as the record of why the fallback existed.

- **Folder-with-init layout** (implemented, now deleted): `Handle.model.json` was converted to:
  - `src/StarterPack/Spelling Staff/Handle/init.model.json` — same MeshPart props (MeshId + Size).
  - `src/StarterPack/Spelling Staff/Handle/Tip.model.json` — `Attachment` className, CFrame placeholder at `(0, 2.877, 0)` (top of staff, Y/2 of the MeshPart height).
  - See [[concepts/ModelJsonInstances]] for the folder-with-init convention (sibling `.model.json` files parent to the init instance, not to the Tool).
  - **Fallback**: if Tip CFrame iteration drags, anchor v1 cast VFX to `caster.HumanoidRootPart` and defer Tip to v1.1. *(This is what shipped, and then became permanent.)*
- `VfxController.spawnCast(playerOrCharacter, effectId)`:
  1. ~~Resolves the character → finds the equipped Tool → `Tool.Handle.Tip` Attachment.~~ Resolves the character → `HumanoidRootPart`.
  2. For each `EmitterSpec`, clones the template ParticleEmitter from `ReplicatedStorage.VfxTemplates`, applies overrides (color, rate, size, etc.), parents to the `Tip` Attachment.
  3. If `emitCount` is set: call `:Emit(emitCount)` and immediately mark for cleanup at `totalDurationSec`.
  4. If `durationSec` is set: leave `Enabled = true`, schedule `Enabled = false` at the duration, destroy at `totalDurationSec`.

### 2.2 Impact effect attachment to target

Two cases, both handled via runtime Attachments — never pre-placed:

| Anchor | How |
|---|---|
| `targetHumanoidRootPart` | Create a transient Attachment on the target's `HumanoidRootPart`. Tag with `CollectionService:AddTag(att, "VfxAttachment")` so a single sweep job can prune leftovers. |
| `targetHead` | Same, parented to `Head` (e.g. crown-style heal sparkles). |
| `worldPosition` | Spawn an invisible anchor `Part` at the position (Anchored, CanCollide=false, Transparency=1, Size 0.1), parent the emitter to it. |
| `caster` | The caster's `HumanoidRootPart`, directly. Was `casterStaffTip` — walk `caster.Character.<EquippedTool>.Handle.Tip`, falling back to the HumanoidRootPart when no tool was equipped. Phase 5.7 deleted the Spelling Staff, so the fallback became the only path and `VfxController.resolveStaffTip` collapsed into `resolveCastAnchor`. |

We **clone emitters to the target** rather than pre-placing because:
1. Targets vary (NPCs, the Boss rig, future props). Pre-placing wastes memory on every potential target.
2. NPCs respawn — pre-placed emitters would die with the original rig.

### 2.3 Choosing Roblox instance type per effect

| Need | Roblox class | When to pick |
|---|---|---|
| Sparks, smoke, dust, sparkles, debris | `ParticleEmitter` parented to `Attachment` | Default for every emitter spec. |
| Persistent beam between two points (channel ray, shield outline, beam from staff to target) | `Beam` between two `Attachment`s | When the effect's authoritative shape is a line/curve over time (cast channel, freeze tether, shield dome edge). |
| Always-readable label / damage number / "+15 HP" | `BillboardGui` parented to an Attachment | Reserved for damage numbers and gameplay-readability text — **not** general VFX. Out of scope for v1; logged in Open Tasks. |
| Brief volumetric flash | `PointLight` or `SurfaceLight` child of the cast Attachment | Sparingly — never more than 1 light per cast. Disable on low-end via `VfxConfig.PERF.allowLights`. |

### 2.4 Lifetime management

One ownership rule: **`VfxController` owns every instance it spawns**. Cleanup must not rely on `ParticleEmitter:Emit` "finishing on its own" because the parent Attachment outlives the particles.

Three combined mechanisms:

1. **`Debris:AddItem(instance, totalDurationSec)`** — primary. Both for the runtime Attachment and for any beams/lights.
2. **Local cleanup table** — `VfxController` stores `{ inst, expiresAt }` for everything it spawned; an `RBXScriptConnection` to `RunService.Heartbeat` (throttled to 10 Hz) checks the front of the queue. Backstop in case Debris service isn't available in playtest mocks.
3. **CollectionService sweep** — every active emitter / attachment is tagged `"VfxInstance"`. On `Players.PlayerRemoving` (for the caster) and on character respawn, sweep tagged items that point at the dead character and destroy them. This handles the edge case of a 4-second freeze beam outliving the caster.

### 2.5 LetterBlock collect pop

Already partly built — the block has a `ParticleEmitter` (Phase 3). For collect:

- Server destroys the block (`BlockShootService.server.luau`). Clients hear via `CollectionService:GetInstanceRemovedSignal(LetterBlocks.TAG)`.
- `LetterBlockAnimator.client.luau` is the existing client that owns block visuals (see `src/client/LetterBlockAnimator.client.luau`). **Extend it** with an `onRemoved(block)` handler that:
  1. Reads the block's spawn position from **`trackedBlocks[block].basePosition`** (already cached at track time). Do NOT call `block:GetPivot()` — the server `:Destroy()` may have propagated `Parent = nil` before the signal fires.
  2. Spawns a one-shot anchor Part at `basePosition`, clones the block's `ParticleEmitter` onto it, sets `emitCount` from `VfxConfig.EFFECTS.block_collect_pop`, calls `:Emit()`, `Debris:AddItem(anchor, 0.5)`.
  - Note: `basePosition` is the spawn position, not the live-bobbed position. For a 0.5 s pop this is visually acceptable. If pop-at-visual-position is needed later, augment the Heartbeat loop to write `state.currentPosition` each tick.

Adding this to `LetterBlockAnimator` keeps single-ownership: the block animator already owns block visuals. No new module needed.

---

## 3. UI VFX — Implementation Detail

All UI VFX are pure-client TweenService animations on existing HUD instances. They live **inside the relevant builder** (so the tween cancel/cleanup pairs naturally with `handle:destroy`) and are exposed as new methods on the existing handle interface. Spec values live in the matching `*Config.luau`.

> Note: all `TweenInfo` lines below are the spec to use; the actual `Enum` references go in `*Config.luau`.

### 3.1 BufferDisplay (`src/shared/Hud/BufferDisplayBuilder.luau` + `BufferDisplayConfig.luau`)

The builder already does a snap-flash on reorder (`snapFlash`, line 144). The new tweens slot in next to it.

| Event | Spec | Handle method to add |
|---|---|---|
| Letter added to slot `i` | Scale `cell.Size` from `1.20×` of TILE_SIZE back to base over **100 ms**, `EasingStyle.Back, EasingDirection.Out`. Implement via `UIScale` child (avoid mutating `Size` UDim2 which lays out neighbors). | `:popTile(idx)` — call from inside `:setTiles` when comparing old vs new tile count. |
| Buffer full (MindFull) | Loop pulse on **every** tile: `UIStroke.Transparency` 0 ↔ 0.5 over **600 ms** each way (`Sine, InOut`), repeat ∞, reversing. Stroke color = `Color3.fromRGB(255, 215, 0)` (gold). | `:setMindFullPulse(active: boolean)` — wires through to `MindFullIndicatorBuilder`'s existing setActive; the indicator and the tile pulse share one source of truth. |
| Word accepted (Memorize ok) | All tiles: `BackgroundTransparency` 0 → 1 + `TextTransparency` 0 → 1 over **220 ms** (`Quad, Out`). Then call `:setTiles({})` to clear. Tied to MemorizeButton green flash already at `flashResult(true)`. | `:playMemorizeOk()` — invoked from `GameplayHudGui` on `result.ok`. |
| Word rejected | Horizontal shake on container: `Position.X.Offset` ±4 px, 3 cycles, **180 ms** total (manual interpolation in a coroutine — TweenService doesn't loop position oscillation cleanly). + tile background tween to `Color3.fromRGB(220, 60, 60)` and back, **160 ms** (`Quad, Out`). | `:playMemorizeFail()` — invoked from `GameplayHudGui` on `result.ok == false`. |

Add to `BufferDisplayConfig.luau`:
```lua
POP_TWEEN          = TweenInfo.new(0.10, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
POP_SCALE          = 1.20,
PULSE_TWEEN        = TweenInfo.new(0.60, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
PULSE_STROKE_COLOR = Color3.fromRGB(255, 215, 0),
MEMORIZE_FADE      = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
SHAKE_OFFSET_PX    = 4,
SHAKE_CYCLES       = 3,
SHAKE_DURATION_SEC = 0.18,
REJECT_COLOR       = Color3.fromRGB(220, 60, 60),
REJECT_TWEEN       = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
```

### 3.2 Energy bars (`src/shared/Hud/AttributeBarBuilder.luau` + `AttributeBarConfig.luau`)

> **Stale — do not build as written.** Every trigger below hangs off `ReservoirBarsBuilder:setEnergy`, and `ReservoirBarsBuilder` / `ReservoirBarsConfig` were **deleted** in Phase 4.8 R-2. The mana fill has belonged to [[systems/ChargeCast]]'s circular spell panels since; a gain sweep and a drain ripple on a disc that fills from the centre are different effects, not the same ones re-pointed. Kept for the timings and the delta thresholds.

The builder **already tweens fill width** on `:setValue` (line 162) using `Defaults.FILL_TWEEN`. Two additions:

| Event | Spec | Where |
|---|---|---|
| Fill sweep on big gain (≥ 8 energy delta) | One-shot bright overlay frame (sibling of `Fill`, transparency 0.5, child of `Track`) tweens `Position.X.Scale` from `0` → `1` over **350 ms** while widening to current fill fraction. Then fades to transparency 1 over **200 ms**. | New child instance in `AttributeBarBuilder.build`; new method `:playGainSweep()`. Triggered from `ReservoirBarsBuilder:setEnergy` when a per-color delta crosses the threshold. |
| Drain ripple on Cast (decrease ≥ 10 energy) | Three radial rings emitted from the right edge of the live fill: tiny `Frame` (8×8 px, UICorner.CornerRadius 0.5 of size) that tweens `Size` ×3 + transparency 0→1 over **300 ms**, then destroys. Stagger by 80 ms. | New method `:playDrainRipple()`. `ReservoirBarsBuilder` detects the drop and invokes per affected color. |
| Full cap (60) reached | Endless edge glow: `UIStroke.Thickness` 1 ↔ 3 over **800 ms** (`Sine, InOut`, repeat ∞, reversing). Stroke color = bar's `config.color`. | New method `:setCapGlow(active)`. `ReservoirBarsBuilder:setEnergy` watches `energy >= MAX_ENERGY`. (Note: ReservoirBars is currently unused — SpellMenu owns the mana fill.) |

Add to `AttributeBarConfig.luau`:
```lua
GAIN_SWEEP_TWEEN     = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
GAIN_SWEEP_FADE      = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
GAIN_SWEEP_DELTA_MIN = 8,
DRAIN_RIPPLE_TWEEN   = TweenInfo.new(0.30, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
DRAIN_RIPPLE_COUNT   = 3,
DRAIN_RIPPLE_STAGGER = 0.08,
DRAIN_DELTA_MIN      = 10,
CAP_GLOW_TWEEN       = TweenInfo.new(0.80, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
CAP_STROKE_MIN       = 1,
CAP_STROKE_MAX       = 3,
```

Delta detection: `ReservoirBarsBuilder` keeps a `lastEnergy: { red, green, blue }` snapshot. On every `setEnergy`, compute deltas, route to the matching bar's new methods.

**Single-subscription invariant**: `:setEnergy` must be called from exactly one `changed` subscription per bar handle. The `lastEnergy` cache lives on the handle instance (not the builder module) so multiple bar instances in tests don't share state. Currently satisfied: one `changed` subscription drives the reservoir bars. If a second subscriber is added, it will compute incorrect deltas.

### 3.3 Spell menu (`src/shared/Hud/SpellMenuBuilder.luau` + `SpellMenuConfig.luau`)

> **Shipped**, with two drifts from this spec. `playFiredFlash` is called after `CastAction.castSpecific`, not `tapReservoir` (retired in 5.8), and the affordability treatment became a full grey-blend (`DESATURATED_*`) rather than a transparency swap — the panel now drains toward grey below T1 instead of dimming. The flash overlay is a disc, since the panels are circles.

Already does affordability via transparency. Add two micro-tweens:

| Event | Spec | Where |
|---|---|---|
| Spell becomes affordable (transition `disabled → active`) | One-shot `UIScale.Scale` 1.0 → 1.08 → 1.0 over **220 ms** total (`Back, Out`). Brighten panel background by tweening transparency: `Defaults.DISABLED_TRANSPARENCY → Defaults.ACTIVE_TRANSPARENCY` instead of an instant swap. | `:playAffordBounce(color)`; called from `setReservoirs` when `canCast` transitions from false to true for that color. |
| Spell fired | Flash overlay `Frame` (same size as panel, BackgroundColor3 = white, BackgroundTransparency 0) tweens transparency 0 → 1 over **140 ms** (`Quad, Out`). Plus apply a brief grayscale stub: drop `panel.BackgroundColor3` saturation by mixing 60 % with `Color3.fromRGB(80,80,90)` and tween back over **400 ms**. | `:playFiredFlash(color)`; called from `SpellMenuGui.client.luau` after `CastAction.tapReservoir` returns `ok = true`. |

Add to `SpellMenuConfig.luau`:
```lua
AFFORD_BOUNCE_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
AFFORD_BOUNCE_SCALE = 1.08,
FIRED_FLASH_TWEEN   = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
FIRED_DIM_COLOR     = Color3.fromRGB(80, 80, 90),
FIRED_DIM_TWEEN     = TweenInfo.new(0.40, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
```

Track affordability transitions per-color in `SpellMenuBuilder` via a local `wasAffordable: { [color]: boolean }` map updated at the bottom of `:setReservoirs`.

### 3.4 MemorizeButton (`src/shared/Hud/MemorizeButtonBuilder.luau`)

Existing `flashResult(ok)` already tweens to ACTIVE/DISABLED color. Keep it; no new method needed. The BufferDisplay's `:playMemorizeOk` / `:playMemorizeFail` already pair with this in `GameplayHudGui`.

### 3.5 MindFullIndicator

Existing `:setActive` already tweens transparency in/out. Wire it to also call `BufferDisplay:setMindFullPulse(active)` from `GameplayHudGui` so the two indicators feel like one effect. No builder change.

### 3.6 Cleanup contract

Every new method that creates Instances or Tweens must:
- Track them in a local list on the handle.
- Cancel tweens / destroy instances inside `:destroy()` (and a new `:disable()` where the system follows the project's `disable/destroy` convention — currently the HUD builders don't have `:disable`, so just `:destroy` is required, matching their existing pattern).

---

## 4. RemoteEvent Contract

Two new RemoteEvents (R2 two-event design). Everything else stays client-local.

### `BroadcastSpellVfx` (RemoteEvent, client → server)

- **Location**: `ReplicatedStorage.Shared.Vfx.Remotes.BroadcastSpellVfx`
- **Created via**: `src/shared/Vfx/Remotes/BroadcastSpellVfx.model.json` — Rojo-versioned.
- **Fired by**: the casting client's `VfxController`, immediately after `CastAction.spellResolved` fires.
- **Received by**: `VfxBroadcastService.server.luau`.
- **Validation** (server-side, in VfxBroadcastService):
  - Rate ≤ 4 casts/sec/player (sliding 1-second window per UserId).
  - `castEffectId` ∈ `VfxConfig.EFFECTS` (skip while EFFECTS is empty during Phase A).
  - `color` ∈ `{red, green, blue}`.
  - `tier` ∈ `{1, 2, 3}`.
  - `impactTarget` (if present) is a `Workspace` descendant.
- **Payload shape**: same as `SpellVfxPayload` below, without `senderUserId`.

### `SpellVfxEvent` (RemoteEvent, server → all clients)

- **Location**: `ReplicatedStorage.Shared.Vfx.Remotes.SpellVfxEvent`
- **Created via**: `src/shared/Vfx/Remotes/SpellVfxEvent.model.json` — Rojo-versioned.
- **Fired by**: `VfxBroadcastService.server.luau` after validation passes — `FireAllClients(payload)`.
- **Listened by**: every client's `VfxController`. The casting client skips the event when `senderUserId == LocalPlayer.UserId` (it already played VFX locally from `spellResolved`, without waiting for the network round-trip).
- **Payload shape**:

```lua
type SpellVfxPayload = {
    senderUserId: number,              -- Player.UserId; receiving client resolves to Character
    castEffectId: string,              -- VfxConfig.resolveCastId(color, tier)
    impactEffectId: string?,           -- VfxConfig.resolveImpactId(kind); nil if no impact
    impactAnchor: ("worldPosition"     -- discriminator for how to read impactTarget
                 | "targetHumanoidRootPart"
                 | "targetHead"
                 | "targetRoot")?,
    impactTarget: Instance?,           -- Model | BasePart; client validates IsDescendantOf(workspace)
    impactPosition: Vector3?,          -- used when impactAnchor == "worldPosition"
    color: "red" | "green" | "blue",   -- for runtime emitter color patches
    tier: number,                      -- 1/2/3, for tier-scoped overrides
    durationSec: number?,              -- forwarded from spec for durationFromSpec effects
    serverNow: number,                 -- workspace:GetServerTimeNow() for late-join lag estimate
}
```

- Client trust model: payload is rendering-only. Worst case of a malicious client (bypassing `BroadcastSpellVfx`) is wrong visuals; no gameplay state changes. Receiving clients also validate `castEffectId` ∈ `VfxConfig.EFFECTS` and `impactTarget` IsDescendantOf(workspace) before spawning.

### Why the casting client plays locally (not from SpellVfxEvent)

`spellResolved` fires synchronously at the end of `CastAction.drainAndCast` — the VFX plays in the same frame as the cast. If we waited for the server round-trip, the player would see a 100–300 ms stutter between pressing cast and seeing the burst. The `senderUserId` filter on `SpellVfxEvent` prevents the double-play.

### Why not a RemoteFunction

No round-trip needed. Client doesn't return anything to the server about VFX.

### Why not split per-color or per-effect

One channel keeps the contract small. Every payload is < 200 bytes; we expect < 4 casts/sec/player worst case → bandwidth is negligible.

---

## 5. Performance Guardrails

Conservative defaults; tunable in `VfxConfig.PERF`.

| Guardrail | Cap | Behaviour at cap |
|---|---|---|
| Concurrent ParticleEmitters per client | 32 | New spawns evict oldest non-`durationFromSpec` emitter. |
| Concurrent Beams per client | 6 | New spawns evict oldest. |
| Concurrent PointLights from VFX | 2 | Drop the light from the new spawn (emitters still play). |
| Concurrent total `VfxInstance`-tagged Instances | 80 | Hard cap; over budget logs once per 5 s. |
| Letter block collect pops in flight | 16 | New collects skip the pop emitter (block still destroys); avoids the 10-block spam scenario from the wiki test plan. |

Throttle policy when the client falls behind:
- `VfxController` reads `RunService.Heartbeat` dt → maintains an EMA. If dt EMA > 1/45 s (i.e. < 45 FPS) for 2 s continuously, switch to **"reduced" mode**: cut `emitCount` in half on incoming specs, skip Beam spawn entirely (`beam = nil` override), and skip PointLight. Restore after dt EMA recovers below 1/55 s for 2 s.
- All thresholds in `VfxConfig.PERF`. No magic numbers in controller logic.

Sound throttling: the same `SpellVfxEvent` triggers cast sound. If two casts within 100 ms fire the same sound id, only the first plays (prevents stacking on rapid alt-fire).

---

## 6. Updated Task List

Ordered so each step is independently testable; **bold** items are blocking for the next step.

### Phase A — Foundation
1. ~~**Create `src/shared/Vfx/VfxConfig.luau`**~~ **Done** — config stub with full `COLORS` palette (R/G/B), `PERF` guardrails, and empty `EFFECTS` table.
2. ~~**Create `src/shared/Vfx/Remotes/SpellVfxEvent.model.json`**~~ **Done** — Rojo-versioned RemoteEvent stub exists at `src/shared/Vfx/Remotes/`. (Also covered by Phase B B0.)
3. **Create `src/shared/Vfx/init.luau`** — module barrel exporting `Config = VfxConfig`, `resolveCastId`, `resolveImpactId`, and a typed `getRemote()` helper.
4. **Create `ReplicatedStorage.VfxTemplates`** Folder + the initial templates (`BurstSmall`, `BurstLarge`, `RingRipple`, `ImpactBurst`, `ShockwaveRing`, `ChannelBeam`). Templates live on disk under `src/shared/Vfx/Templates/` as `.model.json` (`ParticleEmitter`, `Beam`). Color/rate set to "neutral white"; runtime patches the color.

### Phase B — World VFX infrastructure
**B0.** ~~Add `BroadcastSpellVfx.model.json` + `SpellVfxEvent.model.json`~~ **Done** — both files exist at `src/shared/Vfx/Remotes/`.

**B1.** ~~Create `VfxBroadcastService.server.luau`~~ **Done** — `src/server/Vfx/VfxBroadcastService.server.luau` validates rate + type + target then relays via `SpellVfxEvent:FireAllClients`.

5. **Edit `src/shared/CastAction/init.luau`** **Done** — `CastAction.spellResolved: RBXScriptSignal` is a module-level BindableEvent. Fired in `drainAndCast` after `SpellExecutor.cast` succeeds. **Client-side-only meaningful**: server VM creates the same BindableEvent but `VfxBroadcastService` does NOT connect to it — the broadcast is triggered by the client's `BroadcastSpellVfx:FireServer` call, not by the server-side signal.

### Phase C — World VFX client-side
6. ~~**Create `src/client/Vfx/VfxController.client.luau`**~~ **Done** — local-player path implemented: listens to `CastAction.spellResolved`, spawns cast emitters at `Handle.Tip` (fallback HRP), spawns impact emitters at target HRP. Remote-player path (`SpellVfxEvent.OnClientEvent` + `BroadcastSpellVfx:FireServer`) and `_G.PlayerVfx` debug handle deferred to Phase C step 2.
7. ~~**`Tip` Attachment**~~ **Done, then deleted (Phase 5.7)** — was `src/StarterPack/Spelling Staff/Handle/Tip.model.json` (CFrame Y=2.877, half of Handle height 5.7549). Went with the staff; cast bursts anchor to the HumanoidRootPart. See §2.1.
8. **Populate `VfxConfig.EFFECTS`** — **Partial**: `cast_red_t1`, `cast_red_t2`, `impact_damage` implemented. Remaining: green/blue tiers, `impact_heal`, `impact_freeze`, `impact_shield`, `impact_wall`, `impact_buff`. Sound IDs `"rbxassetid://0"` — replaced by ArtDirection pass. VfxTemplates (`BurstSmall`, `BurstMedium`, `ImpactBurst`) created in Studio via MCP (not Rojo-tracked; re-create after fresh place open).
9. **Extend `src/client/LetterBlockAnimator.client.luau`** with the collect-pop emitter spawn (§2.5). The `onRemoved` handler already reads `state.basePosition` from cache — Phase C only needs to add the emitter clone + Debris call there.

### Phase D — UI VFX (parallelizable; each is independent of the other)
10. ~~**Edit `src/shared/Hud/BufferDisplayBuilder.luau`** + `BufferDisplayConfig.luau`~~ **Done** — `popTile`, `setMindFullPulse`, `playMemorizeOk`, `playMemorizeFail` implemented; constants in `BufferDisplayConfig.luau`.
11. ~~**Edit `src/shared/Hud/AttributeBarBuilder.luau`** + `AttributeBarConfig.luau`~~ **Done** — `playGainSweep`, `playDrainRipple`, `setCapGlow` implemented; constants in `AttributeBarConfig.luau`.
12. ~~**Edit `src/shared/Hud/ReservoirBarsBuilder.luau`**~~ **Done** — per-color delta tracking + bar routing implemented; `lastEnergy` cache on handle.
13. ~~**Edit `src/shared/Hud/SpellMenuBuilder.luau`** + `SpellMenuConfig.luau`~~ **Done** — `playAffordBounce`, `playFiredFlash`, `wasAffordable` map implemented; constants in `SpellMenuConfig.luau`.
14. **Edit `src/client/UI/GameplayHudGui.client.luau`** to wire `:playMemorizeOk/Fail` and `:setMindFullPulse` into the existing memorize / MindFull listeners.
15. **Edit `src/client/UI/SpellMenuGui.client.luau`** to call `menu:playFiredFlash(color)` on `result.ok`.

### Phase E — Validation
17. **Playtest pass — 10-block spam**: spawn 10 blocks, shoot all in 2 s. Verify collect pops respect the per-frame cap and FPS stays > 50.
18. **Playtest pass — back-to-back T3 casts**: 5 T3 casts in 3 s, confirm no orphan emitters via a `print(#CollectionService:GetTagged("VfxInstance"))` debug dump.
19. **Playtest pass — freeze + shield overlap**: target is frozen and shielded; both `durationFromSpec` effects coexist without one cleanup nuking the other (each owns its own runtime Attachment).
20. **Wiki ingest**: update `wiki/log.md`, mark `status: implemented` here, append entries to relevant system pages (`SpellExecutor`, `CastAction`, `LetterBlock`, `HUD`).

### Phase F — Polish (out of v1 scope; deferred)
- Damage number BillboardGui (separate system in §2.3 table).
- ArtDirection palette finalization → swap placeholder hues.
- Per-spell-name overrides (some T3 spells may want unique signatures).
- Locale-aware sound packs.

---

## 7. Open Questions / Decisions Needed

- **Q1**: Should fizzle (failed cast / no target) get its own minimal client-only VFX? Currently scoped out — `SpellMenuGui` already plays `fizzleSound`. Recommend adding a small grey poof at the staff tip in v2.
- **Q2**: Tip Attachment CFrame — should the artist authored value live in `Tip.model.json` (versioned) or in `init.meta.json` props (locked to Handle's local space)? Default to `Tip.model.json`.
- **Q3**: Confirmation that `CastAction.spellResolved` as a module-level BindableEvent is acceptable (introduces side-channel state in an otherwise stateless module). Alternative: callback registration API. Default to BindableEvent — it's the lightest seam.
- **Q4**: Final ArtDirection sign-off on the palette. Until then, `VfxConfig.COLORS` holds the placeholder hues; UI tile colors are locked.

---

## Related Pages

- [[systems/SpellExecutor]]
- [[systems/CastAction]]
- [[systems/LetterBlock]]
- [[systems/HUD]]
- [[systems/EnergyReservoirs]]
- [[design/ArtDirection]]
- [[concepts/SingleOwnership]] — VfxController owns world VFX; each HUD builder owns its UI tweens.
- [[concepts/RojoJsonValidator]] — applies to new `.model.json` template files in `src/shared/Vfx/Templates/`.
