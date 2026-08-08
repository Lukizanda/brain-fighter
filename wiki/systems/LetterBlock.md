---
type: system
description: Floating letter-block prefab — the in-world entity the player shoots to spell words. Spawn API, color tints, CollectionService tag for the animator, and the spawn-in intro.
updated: 2026-08-08
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
- `src/client/LetterBlockAnimator.client.luau` — CollectionService Heartbeat loop: bob 0.5 studs / 1.5 s period, Y-axis rotation 6 deg/s, per-block phase offset, distance-bucketed culling, and the spawn-in intro.
- `BrainFighter.rbxl` (not under Rojo) — holds the MCP-created Cube + SurfaceGuis + ParticleEmitter children of `Template`. Saving the `.rbxl` is what persists them.

## Behavioural verification (2026-05-14 playtest)

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
