---
type: system
description: Floating letter-block prefab — the in-world entity the player shoots to spell words. Spawn API, color tints, and CollectionService tag for the animator.
updated: 2026-05-14
---

# LetterBlock

The in-world entity the player shoots to spell words. A small Model with a `Cube` BasePart, six SurfaceGuis (one glyph per face), and a colored ParticleEmitter. Two attributes drive everything: `Block.Letter` (the glyph) and `Block.Color` (`"red" | "green" | "blue"`). Spawned by the upcoming [[systems/BlockShoot|BlockSpawner]] / [[design/build-plan|Phase 3]] pipeline.

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
- `src/client/LetterBlockAnimator.client.luau` — CollectionService Heartbeat loop: bob 0.5 studs / 1.5 s period, Y-axis rotation 6 deg/s, per-block phase offset.
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
| `.spawn(letter, color, cframe, parent?)` | `(string, "red"\|"green"\|"blue", CFrame, Instance?) -> Model` | Clones Template, sets attributes, applies tint to `Cube`, updates SurfaceGui TextLabels + ParticleEmitter color, tags with `"LetterBlock"`, parents. |
| `.applyVisualState(block)` | `(Model) -> ()` | Re-runs the visual pass from current attributes. Idempotent. |
| `.TAG` | `string` | `"LetterBlock"` — the CollectionService tag the animator listens for. |
| `.LETTER_ATTRIBUTE` | `string` | `"Block.Letter"`. |
| `.COLOR_ATTRIBUTE` | `string` | `"Block.Color"`. |
| `.COLOR_TINTS` | `{[color]: Color3}` | red `#dc2626`, green `#16a34a`, blue `#2563eb`. |
| `.Template` | `Instance` | The Template Model under the module script. |

## Color tints

The same three values used everywhere color is rendered in the game:

| Color | Hex | Notes |
|---|---|---|
| red | `#dc2626` | matches HUD reservoir bar, spell-roster color split |
| green | `#16a34a` | same |
| blue | `#2563eb` | same |

Wired into the Cube's `Color`, every SurfaceGui-driven label tint, and the ParticleEmitter's `ColorSequence`. If you ever expand the palette, change `COLOR_TINTS` here in one place — [[systems/EnergyReservoirs]] enforces the same set on its side.

## CollectionService tag → animator

`spawn` calls `CollectionService:AddTag(block, "LetterBlock")` before parenting. The client animator (`LetterBlockAnimator.client.luau`) listens via `CollectionService:GetInstanceAddedSignal("LetterBlock")` and tracks each block in a Heartbeat loop. Per-block phase offset is derived from the block's address so a cluster of blocks doesn't bob in unison — looks more organic.

This is a one-way contract: blocks tag themselves, the animator just watches the tag. No direct require, no init-order coupling. Adding a second animator (e.g. a despawn shrink effect) means another `GetInstanceAddedSignal` — no edits to the module.

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
