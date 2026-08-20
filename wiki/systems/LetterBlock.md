---
type: system
description: Floating letter-block prefab — the in-world entity the player shoots to spell words. Spawn API, color tints, CollectionService tag for the animator, and the spawn-in intro.
updated: 2026-08-20
---

# LetterBlock

The in-world entity the player shoots to spell words. A small Model with a `Cube` BasePart, six SurfaceGuis (one glyph per face), and a colored ParticleEmitter. Two attributes drive everything: `Block.Letter` (the glyph) and `Block.Color` (`"red" | "green" | "blue" | "wild"`). Spawned by the upcoming [[systems/BlockShoot|BlockSpawner]] / [[design/build-plan|Phase 3]] pipeline.

`"wild"` is the gold wildcard block, whose `Block.Letter` is the ASCII `*` and whose faces render `★`. See [[systems/Wildcard]].

## Anatomy

`ReplicatedStorage.Shared.LetterBlocks.Template` is the canonical Model every block is cloned from:

```
Template (Model)         ← src/shared/LetterBlocks/Template/init.meta.json (Rojo)
└── Cube (Part)          ← MCP-managed (persisted in BrainFighter.rbxl)
    ├── Face_Front       ← SurfaceGui + TextLabel "Letter"
    ├── Face_Back        ← SurfaceGui + TextLabel "Letter"
    ├── Face_Top         ← SurfaceGui + TextLabel "Letter"
    ├── Face_Bottom      ← SurfaceGui + TextLabel "Letter"
    ├── Face_Left        ← SurfaceGui + TextLabel "Letter"
    ├── Face_Right       ← SurfaceGui + TextLabel "Letter"
    └── Mana (ParticleEmitter)
```

The Cube + its 6 SurfaceGuis + ParticleEmitter are MCP-managed: they were created via `execute_luau` in Studio, persist in `BrainFighter.rbxl`, and survive Rojo sync because `Template/init.meta.json` sets `ignoreUnknownInstances: true` (see [[concepts/ModelJsonInstances]]).

Why a single Part instead of a multi-part Model? The cube IS the block — no rig, no socketed accessories. One Part is the cheapest possible representation, and SurfaceGuis live on it directly (no Adornee plumbing needed when the GUI's parent is the BasePart it adorns).

The Cube properties: `Size = 4×4×4`, `Anchored = true`, `CanCollide = false`, `CanTouch = false`, `CanQuery = true` (raycasts hit it — BlockShoot relies on this), `Massless = true`, `Material = Plastic`, `TopSurface/BottomSurface = Smooth`. `Template.PrimaryPart = Cube` so `Template:PivotTo(...)` (used by `spawn`) targets the visible body.

## Files

- `src/shared/LetterBlocks/init.luau` — module: spawn / applyVisualState / constants.
- `src/shared/LetterBlocks/Template/init.meta.json` — Template Model, `ignoreUnknownInstances`, default attributes (`Block.Letter = "A"`, `Block.Color = "red"`).
- `src/client/LetterBlockAnimator.client.luau` — CollectionService Heartbeat loop: bob 0.5 studs / 1.5 s period, tumble 28 deg/s about an axis tilted 20° off vertical, per-block phase offset and tilt bearing, distance-bucketed culling, and the spawn-in intro.
- `BrainFighter.rbxl` (not under Rojo) — holds the MCP-created Cube + SurfaceGuis + ParticleEmitter children of `Template`. Saving the `.rbxl` is what persists them.

## Behavioural verification (2026-05-14 playtest — superseded)

> The yaw figures below are **historical**. The animator span the block about Y at 6 deg/s until 2026-08-20; it now tumbles at 28 deg/s about a tilted axis. See § Face treatment and tumble.


Spawned a block at `(0, 12, 0)` via MCP `execute_luau`, sampled `block:GetPivot()` at three timestamps:

| t (s) | Y position | Yaw |
|---|---|---|
| 0.0 | 12.000 | 0° |
| 0.5 | 12.046 | 3° |
| 1.0 | 12.408 | 6° |

Yaw advances at exactly **6°/s**, matching `ROTATION_DEGREES_PER_SECOND`. Y bobs sinusoidally around the spawn baseline — the first 1 s captured climbs from `12.000` toward the wave's peak at `12 + 0.5 = 12.500`. Edit-mode spot check earlier confirmed the cube tint, the 6 face SurfaceGuis with white-stroked letters, and the PrimaryPart wiring read correctly across red/green/blue colors.

## API

`require(ReplicatedStorage.Shared.LetterBlocks)` returns the module table.

| Member | Type | Notes |
|---|---|---|
| `.spawn(letter, color, cframe, parent?)` | `(string, "red"\|"green"\|"blue"\|"wild", CFrame, Instance?) -> Model` | Clones Template, sets attributes (letter via `Wildcard.normalize`), applies tint to `Cube`, updates SurfaceGui TextLabels + ParticleEmitter color, tags with `"LetterBlock"`, parents. |
| `.applyVisualState(block)` | `(Model) -> ()` | Re-runs the visual pass from current attributes. Idempotent. |
| `.TAG` | `string` | `"LetterBlock"` — the CollectionService tag the animator listens for. |
| `.LETTER_ATTRIBUTE` | `string` | `"Block.Letter"`. |
| `.COLOR_ATTRIBUTE` | `string` | `"Block.Color"`. |
| `.COLOR_TINTS` | `{[color]: Color3}` | red `#dc2626`, green `#16a34a`, blue `#2563eb`, wild `#eab308`. |
| `.Template` | `Instance` | The Template Model under the module script. |

## Color tints

The three reservoir values used everywhere color is rendered in the game, plus gold for the wildcard:

| Color | Hex | Notes |
|---|---|---|
| red | `#dc2626` | matches HUD reservoir bar, spell-roster color split |
| green | `#16a34a` | same |
| blue | `#2563eb` | same |
| wild | `#eab308` | [[systems/Wildcard]] — **not** a reservoir color; deliberately off-palette so a ★ is spottable in a field of blocks |

Wired into the Cube's `Color`, every SurfaceGui-driven label tint, and the ParticleEmitter's `ColorSequence`. If you ever expand the palette, change `COLOR_TINTS` here in one place — [[systems/EnergyReservoirs]] enforces the same set on its side (reservoir colors only; it never sees `wild`).

The face label goes through `Wildcard.toDisplay(letter)`, so a wildcard's stored `*` renders as `★` while every other letter passes through uppercased.

**These tints are not usable as an outline colour on the block itself.** The Phase 5.7 hover affordance tried it and the highlight was invisible: an outline drawn in the block's own tint has no contrast against the block, and it fails for all four tints simultaneously because each tint *is* the colour of the block wearing it. Anything that has to read *against* a block needs an off-palette colour — the hover outline uses white. See [[systems/BlockShoot]] § Hover affordance.

Refined 2026-08-20: the constraint is on *value*, not on hue. A tint driven far enough toward black (72 % for the face border, 84 % for the panel) reads fine against its own block and keeps colour identity — a red block's edge is deep maroon, not the same black as a blue one's. What is unusable is the tint at full saturation. Note the remaining budget: white and grey are spoken for by the hover and out-of-reach cues, so any *permanent* mark on a block has to be dark, or it steals the hover cue's only channel.

## Face treatment and tumble (2026-08-20)

Blocks read as flat floating swatches: a saturated cube has no silhouette against the skybox, and a white glyph on a saturated fill loses to the fill. Four changes, all driven from `applyVisualState` so they are versioned in Rojo rather than authored into the `.rbxl` Template.

**Border.** A `UIStroke` inside each face SurfaceGui, coloured with the block's tint driven 72 % to black. *Not* a `Highlight` per block — the engine renders a bounded number (~31) and the arena holds 40, the same budget that makes [[systems/BlockShoot|BlockTapController]]'s hover highlight a reused singleton. A face the camera cannot see is not drawn, so what renders is exactly the visible silhouette (confirmed by measurement — see § Costs).

Thickness is **not** a constant — see § Border thickness is distance-scaled. It shipped as one on 2026-08-20 and did not work.

**Panel + glyph inversion.** A dark plate (tint → 84 % black) inset in each face, with the glyph lightened toward white by 75 % instead of plain white — a red block's letter reads hot red, a blue one's icy blue. The cube body deliberately stays saturated: darkening it would collapse body and border to the same value, and the border cannot be lightened to compensate because white and grey are the hover and out-of-reach cues. The surviving colour ring between panel and border is what still reads once the glyph is too small to resolve.

**Value tell.** The `Mana` emitter's rate (6 → 26) and spark size (0.24 → 0.62) scale continuously with `EnergyEconomy.letterValue`, so a Q looks worth ten times an E. Continuous rather than banded into rarity tiers — the Scrabble values already are the scale, and a threshold here would invent a second one free to drift. `letterValue` returns **0** for a wildcard (it has no fixed value); `tellValueFor` pins it to the maximum instead, or the most valuable block in the arena would render as the dullest.

**Tumble.** 6 deg/s → **28 deg/s**, about an axis tilted 20° off vertical with a per-block bearing. A vertical spin sweeps the same four side faces past the camera forever and keeps top and bottom permanently hidden; a tilted one gives every face a turn. The bearing is rolled once at track time, like the bob phase, so a field does not turn as one mechanism.

### Two engine facts this depends on

`Model:ScaleTo` treats these properties differently, and the difference is load-bearing:

| Property | Scaled by `ScaleTo`? | Consequence |
|---|---|---|
| `SurfaceGui.PixelsPerStud` | yes, **inversely** (50 → 33.3 at 1.5×) | face canvas is a constant 200×200 px at any `BLOCK_SCALE` |
| `UIStroke.Thickness`, `UDim` offsets | no | border thickness needs no scale correction — and combined with the row above, `BLOCK_SCALE` cancels out of `borderThicknessFor` entirely |
| `ParticleEmitter.Size` | yes (it is a length) | spark size **must** be multiplied by the current scale |

`spawn()` applies the visual state *before* scaling, so `applyValueTell` takes `block:GetScale()`: at spawn it is 1 and `ScaleTo` multiplies afterwards; on an idempotent re-apply the block is already scaled and nothing multiplies again. Writing the bare constant would make a re-applied block's sparks shrink by `BLOCK_SCALE` against a freshly spawned one.

`LetterBlocks.tumbleDiameter()` (`edge × BLOCK_SCALE × √3` = 10.39 studs shipped) exists because [[systems/BlockSpawner]] needs the sweep radius for spacing. It lives here because it is a fact about the prefab's geometry — see that page for the overlap bug the old hand-set constant caused.

## Border thickness is distance-scaled (2026-08-20)

A canvas pixel is a fixed fraction of the face, so a constant `UIStroke.Thickness` has a width **on screen** that falls off with distance like everything else. Measured at 1536×660, FOV 70, against a 12 px stroke on the 200 px canvas:

| Camera distance | Face height | Border width |
|---|---|---|
| 40 studs | 70.7 px | 4.24 px |
| 90 studs | 31.4 px | 1.89 px |
| 130 studs | 21.8 px | 1.31 px |
| 180 studs | 15.7 px | **0.94 px** |
| 250 studs | 11.3 px | **0.68 px** |

Below ~1 px a line is sub-pixel and renders intermittently on subpixel coverage — and these blocks tumble at 28°/s, which changes each face's projected angle every frame. So the border flickered in and out on distant blocks. **That is the "one frame showed a face without its border" observation: reproducible, not a stray frame, and not a render budget.**

The severity came from the arena being 219×20×248 studs, not the 40×8×40 in the config comments (that is only the fallback; real bounds come from tagged `BlockSpawnVolume` parts). Profiled by viewer position, the fraction of blocks with a solid (≥2 px) border was **8 % from the arena centre and 0 % from the player spawn**. The border's stated job is the silhouette at distance, and distance was exactly where it stopped drawing.

**The fix.** `LetterBlocks.borderThicknessFor(distance, pixelsPerStud, fov, viewportHeight)` returns the canvas thickness that renders as `BORDER_TARGET_SCREEN_PIXELS` (5.5 — what the old 12 px measured at ~30 studs, so near blocks are unchanged). `LetterBlockAnimator` drives it per block from **camera** distance, rounded and only written on change, on the same rolling bucket as the transform but deliberately *not* behind the transform's cull gate — that gate freezes distant blocks, which are precisely the ones needing correction as the camera approaches.

The cube edge cancels out of the derivation, so neither the cube size nor `BLOCK_SCALE` appears in it: `ScaleTo` drives `PixelsPerStud` inversely to the part and the two exactly offset. That is deliberate — a hand-maintained coupling to `BLOCK_SCALE` in this very system is what produced the [[systems/BlockSpawner]] overlap bug.

**Clamped [6, 20], and the ceiling is geometry, not taste.** The stroke spans 0..T from the canvas edge and the panel starts at 26 px, so T ≥ 26 buries the panel — and the ring of block colour between border and panel is the only thing carrying red/green/blue once the glyph is too small to read, which is *which reservoir the letter feeds*. 20 keeps a 6 px ring. The cost: the target width only holds to ~51 studs, beyond which the border still thins — but from 20 px instead of 12, a 67 % wider edge at every range past it. Solid range goes **85 → 141 studs**; 180 and 250 come back out of sub-pixel. A block at 314 studs is still 0.90 px, which is only reachable from outside the arena.

`applyBorderThickness` writes thickness and the frame's inset together because they are one setting: the stroke is centred on the frame's edge, so the frame must be inset by exactly the thickness or the stroke lands half outside the canvas and gets clipped.

### Costs — measured 2026-08-20

Measured with `Stats.RenderBreakdown` and `Stats.FrameRateManager`, which report per-frame **counts** and so are immune to Studio's frame pacing. 40 blocks, all on screen, quality pinned to Level21:

| | faces on | faces off | cost |
|---|---|---|---|
| UI draw calls | 121 | 1 | **+120** |
| Batches | 233 | 113 | +120 |
| UI triangles | 7,598 | 10 | +7,590 |
| Render thread | 3.65 ms | 3.37 ms | ~0.3 ms *(below the instrument's noise)* |

**The cost metric is visible faces, not instances.** 121 draws ÷ 40 blocks = 3.0, exactly the most faces of a cube a camera can see: culling is already exact and complete, and the 1,200-instance figure is not what the renderer charges for. Hiding any *single* element (border, panel, or glyph) left draws at 121 — a face's contents batch into one draw call, so the decoration is nearly free and only the face count matters. Per visible face: ~36 triangles of border, ~22 of glyph, ~4 of panel.

Draw count is flat across camera distance out to 350 studs and flat across every quality level from Level01 to Level21. **Verdict: not a performance concern**, and the previously-proposed lever ("decorate fewer faces per block") would not have helped.

Two corrections to the record this replaces. The earlier A/B that "read 15.0 fps in every condition" was not floor-limited — 15.0 was a *ceiling*: `RenderAverage` sat at exactly 66.668 ms (1/15 s) while `RenderThreadAverage` was 2.4 ms, i.e. the renderer did 2.4 ms of work and slept for 64. All three conditions were above the cap, which is why they tied. And SurfaceGui culling is **not** quality-dependent: an apparent 88 → 119 draw jump when quality was raised turned out to be a camera move made in the same step.

**Still open:** `borderThicknessFor` is pure and would suit a `__tests` suite, but `LetterBlocks` has none and adding one means wiring a new suite into the TestRunner. The live animator path (Heartbeat driving thickness in a running game) is verified by construction and by an Edit-mode replay of the same computation, not by a playtest — Studio's play mode was wedged in the MCP proxy during the session that made the change.

## CollectionService tag → animator

`spawn` calls `CollectionService:AddTag(block, "LetterBlock")` before parenting. The client animator (`LetterBlockAnimator.client.luau`) listens via `CollectionService:GetInstanceAddedSignal("LetterBlock")` and tracks each block in a Heartbeat loop. Each block draws a random phase offset on track so a cluster doesn't bob in unison — looks more organic.

This is a one-way contract: blocks tag themselves, the animator just watches the tag. No direct require, no init-order coupling.

A *read-only* observer (analytics, an audio cue) can safely add its own `GetInstanceAddedSignal` with no edits here. Anything that **writes** a block's transform, scale, or transparency must go inside the animator instead — it already writes all three every frame, and a second writer would fight it. See [[concepts/SingleOwnership]].

## Spawn-in intro

The spawner refills the instant a block is consumed, so before 2026-08-08 a replacement snapped into existence at full size next to the one the player had just shot. It read as a pop-in glitch rather than an arrival.

The animator now plays a ~0.45 s intro on every block that arrives *after* the client has started:

| Channel | Curve | Range |
|---|---|---|
| `Model:ScaleTo` | damped spring — overshoot, dip under, settle | 8 % of final scale → final (peaks ~21 % over, dips ~4 % under) |
| `Cube.Transparency`, `TextTransparency`, `TextStrokeTransparency` | `Quad` / `Out` | 1 → the value the block replicated in with |
| `Mana` ParticleEmitter | — | `Enabled = false` for the intro, restored on settle |

### The spring curve

Scale rides an explicit damped harmonic rather than a built-in easing style:

```
y(t) = 1 - e^(-decay*t) * cos(omega*t)
omega = pi * INTRO_SPRING_HALF_CYCLES
decay = -ln(INTRO_SPRING_OVERSHOOT) * omega / pi
```

`y(0) = 0` and `y(1)` lands on ~1. Two tunables:

- **`INTRO_SPRING_OVERSHOOT`** (0.20) — how far the first peak goes past the settle point. The `decay` derivation solves the envelope at `omega*t = pi` for exactly this value, so the constant means what it says instead of being whatever the math happened to produce.
- **`INTRO_SPRING_HALF_CYCLES`** (3) — how many times the curve crosses the settle point. 1 degenerates to a single Back-style overshoot; 5+ reads as rubber rather than weight.

`Enum.EasingStyle.Back` was the first cut and does overshoot, but its magnitude is a fixed engine constant (~10 %) and it crosses once. Neither is tunable, and springiness needs both dials — hence the explicit curve.

Two consequences worth knowing:

- The realized overshoot is slightly under `INTRO_SPRING_OVERSHOOT` because scale lerps *from* `startScale`, not from zero. At the shipped constants that's 20.9 % measured against a 20 % nominal.
- `y(1)` carries a residual envelope of about +0.7 %, so the curve approaches the settle point from above. That is 0.012 studs at the shipped block scale, and `settleIntro` writes the exact final value anyway.

Details that matter:

- **Duration is jittered ±15 %.** One consumption triggers one refill, but a joining player can receive a whole arena at once; identical durations would read as a single synchronised inflate.
- **Blocks already tagged when the script starts do not intro.** They're a settled arena, not an arrival — introing them would inflate the whole field in a joining player's face.
- **Frame zero is applied synchronously in `track`**, not on the next Heartbeat. One frame at full size and full opacity is exactly the snap the intro exists to remove.
- **The intro opts out of distance culling.** Holding a pivot still for whole frames is invisible on a settled block and very visible on one mid-pop.
- **Final values are captured per instance**, not assumed zero, so the intro restores whatever the prefab authored.
- **Scale is clamped on the low end only.** The spring is *supposed* to exceed 1; `Model:ScaleTo` rejects zero and negatives.
- **Opacity resolves at 45 % of the duration**, just past the spring's first peak — the block is solid by the time it is at its biggest, so the ring-down reads as weight rather than as the block still arriving.
- **Purely cosmetic.** The server knows nothing about the intro, so a mid-intro block is shootable like any other. Gating `CanQuery` would desync client and server on a block the player can see but not hit.

### Verification (2026-08-08 playtest)

Client-VM sampling via `execute_luau` with `datamodel_type = "Client"`, destroying blocks server-side on a timer and reading the replacement's local property values each Heartbeat. Server logs cannot verify this — the scale and transparency writes happen only on the local VM (see the VFX rule in `CLAUDE.md`).

| t (s) | scale | vs. final | cube T | text T |
|---|---|---|---|---|
| 0.015 | 0.422 | −71.8 % | 0.839 | 0.839 |
| 0.132 | **1.813** | **+20.9 %** (peak) | 0.138 | 0.138 |
| 0.215 | 1.566 | +4.4 % | 0.000 | 0.000 |
| 0.299 | **1.438** | **−4.1 %** (dip) | 0.000 | 0.000 |
| 0.483 | **1.500** | 0.0 % (settled) | 0.000 | 0.000 |

Against a `GameConfig.BLOCK_SCALE` of 1.5, the measured curve peaks at +20.9 % and dips to −4.1 % before landing exactly on 1.500 — matching the offline prediction of +20.6 % / −4.1 % to within a fifth of a percent. All three transparency channels move in lockstep and reach zero at t ≈ 0.215, just past the peak. The emitter re-enables on the settle frame.

Two dials worth reaching for when tuning: `INTRO_SPRING_OVERSHOOT` for how hard it pops, `INTRO_SPRING_HALF_CYCLES` for how much it rings. Both are cheap to predict offline — the curve is 3 lines of math — so check the shape numerically before spending a playtest on it.

Two dead ends worth not repeating: MCP `execute_luau` calls issued in one message **serialize rather than run concurrently**, and a `task.delay`-scheduled trigger fires before a follow-up Client call can arm its listener. Schedule a *repeating* server-side trigger, then arm the client sampler.

## Why the animator runs on the client

Blocks are server-spawned but their motion is purely cosmetic. Animating server-side would replicate every CFrame update across the wire 60 times a second per block — pure waste. The client animator is deterministic from the block's identity, so every player sees a slightly different phase but the same wobble shape, which is fine.

## Consumers (planned)

- **[[systems/BlockShoot]]** (Phase 3 / NIM-12) — the shoot/click handler that detects a hit on a tagged block, reads `Block.Letter` + `Block.Color`, calls `:append(letter, color)` on the player's [[systems/WordBuffer]], and destroys the block.
- **BlockSpawner** (Phase 3 / NIM-9) — picks letters from [[systems/Dictionary]] and places blocks in the arena at intervals.

## See also

- `wiki/design/build-plan.md` — Phase 3 sequencing (LetterBlock template → BlockSpawner → BlockShoot).
- [[concepts/ModelJsonInstances]] — why the Template uses `init.meta.json` with `ignoreUnknownInstances` rather than declaring children in JSON.
- [[systems/WordBuffer]] — where `(letter, color)` pairs flow once a block is consumed.
- [[systems/EnergyReservoirs]] — same color vocabulary on the receiving side.
