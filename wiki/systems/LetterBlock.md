---
type: system
description: Floating letter-block prefab — the in-world entity the player shoots to spell words. Spawn API, color tints, and CollectionService tag for the animator.
updated: 2026-05-14
---

# LetterBlock

The in-world entity the player shoots to spell words. A small Model with a `Cube` BasePart, six SurfaceGuis (one glyph per face), and a colored ParticleEmitter. Two attributes drive everything: `Block.Letter` (the glyph) and `Block.Color` (`"red" | "green" | "blue"`). Spawned by the upcoming [[systems/BlockShoot|BlockSpawner]] / [[design/build-plan|Phase 3]] pipeline.

## Status (2026-05-14)

NIM-11 is **in progress**. The disk side shipped in commit `606bd5c`:

- Spawn API + visual-state pipeline (`src/shared/LetterBlocks/init.luau`)
- Template Model declaration with `ignoreUnknownInstances = true` (`src/shared/LetterBlocks/Template/init.meta.json`)
- Client-side bob + Y-rotation animator (`src/client/LetterBlockAnimator.client.luau`)

The MCP-managed children of the Template — the `Cube` BasePart, six SurfaceGuis with TextLabels (one per cube face), and the colored ParticleEmitter — **are not yet attached**. They will be added in Studio with `ignoreUnknownInstances` keeping them safe through Rojo sync. NIM-11 stays in-progress until those children land and a playtest confirms a spawned block reads correctly.

## Files

- `src/shared/LetterBlocks/init.luau` — module: spawn / applyVisualState / constants.
- `src/shared/LetterBlocks/Template/init.meta.json` — Template Model, `ignoreUnknownInstances`, default attributes.
- `src/client/LetterBlockAnimator.client.luau` — CollectionService Heartbeat loop: bob 0.5 studs / 1.5 s period, Y-axis rotation 6 deg/s, per-block phase offset.

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
