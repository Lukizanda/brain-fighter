---
type: system
description: Server-side letter-block populator — maintains a target count of floating LetterBlocks in the arena with Scrabble-weighted letter distribution and configurable color weights.
updated: 2026-05-16
---

# BlockSpawner

Server-side populator that keeps a target count of [[systems/LetterBlock|LetterBlock]] Models alive in the arena. When a block is destroyed (consumed by [[systems/BlockShoot|BlockShoot]], despawned, etc.), the spawner auto-refills to target via the CollectionService removed signal.

## Files

- `src/shared/BlockSpawner/init.luau` — module: start / stop / rerollAll / getActiveBlocks / pickers / tunables.
- `src/server/BlockSpawner/BlockSpawnerService.server.luau` — server bootstrap that calls `BlockSpawner.start()`.

## API

`require(ReplicatedStorage.Shared.BlockSpawner)` returns the module table.

| Member | Type | Notes |
|---|---|---|
| `.start(opts?)` | `(Opts?) -> ()` | Fills arena to target count, hooks CollectionService removed signal for auto-refill. No-ops if already running. |
| `.stop()` | `() -> ()` | Disconnects the refill listener. Existing blocks remain. |
| `.rerollAll()` | `() -> ()` | Destroys all active blocks. The removed-signal handler auto-refills to target. |
| `.getActiveBlocks()` | `() -> { Model }` | Snapshot of currently tracked blocks. |
| `.LETTER_FREQUENCIES` | `{ [string]: number }` | Scrabble-standard 98-tile distribution used for weighted letter picks. |

### Opts type

```luau
type BoxDef = { boxMin: Vector3, boxMax: Vector3 }

type Opts = {
    -- Target count: explicit > density-computed > hardcoded default (24)
    targetCount: number?,        -- explicit override; ignores density
    density: number?,            -- blocks per 1000 cubic studs (see GameConfig.BLOCK_SPAWN_DENSITY)

    -- Spawn volumes: prefer boxes array; fall back to single-box shorthand
    boxes: { BoxDef }?,          -- multiple regions; volume-weighted distribution
    boxMin: Vector3?,            -- single-box shorthand, default (-20, 8, -20)
    boxMax: Vector3?,            -- single-box shorthand, default (20, 16, 20)

    colorWeights: {              -- default uniform (1, 1, 1)
        red: number?,
        green: number?,
        blue: number?,
    }?,
    parent: Instance?,           -- default workspace
    minSpacing: number?,         -- minimum studs between block centers; 0 disables (see GameConfig.BLOCK_MIN_SPACING)
}
```

## Studio setup

Tag any `BasePart` in Workspace with the `BlockSpawnVolume` CollectionService tag to define a spawn region. You can have as many tagged parts as you want — all are active simultaneously.

**Circular boss arena example**: place 4–8 rectangular parts arranged in a ring around the boss, each tagged `BlockSpawnVolume`. Blocks will distribute across them weighted by volume, so equal-sized parts produce equal density.

Density is controlled by `GameConfig.BLOCK_SPAWN_DENSITY` (default 2 = ~26 blocks in the 40×8×40 reference arena). The total block count auto-adjusts as you add or resize volumes.

## Design decisions

### Letter distribution: Scrabble-frequency soft heuristic

Letters are picked from the standard English Scrabble bag (98 tiles). Vowels and common consonants dominate, so a random sample of ~24 blocks will almost always contain spellable words without an explicit "must be spellable" guarantee. This avoids the complexity of a dictionary-bag scan while keeping the arena feel natural.

The frequency table is intentionally separate from `EnergyEconomy.letterValue` — frequency is "how often does this letter appear" while value is "how many points is it worth." They correlate inversely (common letters = low value) but are distinct concepts.

### Color distribution: independently weighted

Color is picked independently from letter, defaulting to uniform 33/33/33. A per-level designer can bias a color scarce (e.g. `{ red = 1, green = 1, blue = 0.3 }`) to make blue spells harder to charge — without touching letter frequencies.

### Auto-refill via CollectionService removed signal

When any tagged `LetterBlock` is removed from CollectionService, the spawner checks if it was one of ours (`active` set lookup, O(1)) and schedules a deferred refill. This means the arena self-heals regardless of what destroys the block — BlockShoot consumption, admin cleanup, or a rerollAll call.

### Random yaw on spawn

Each block spawns with a random initial Y-axis rotation so a cluster doesn't look grid-aligned before the client animator's per-block phase offset kicks in.

## Tunables (defaults from gameplay-loop)

| Parameter | Default | Source |
|---|---|---|
| Target count | density-computed (≈26 at default density) | `GameConfig.BLOCK_SPAWN_DENSITY` |
| Density | 2 blocks per 1000 studs³ | `GameConfig.BLOCK_SPAWN_DENSITY` |
| Arena box | 40×8×40 studs, Y 8–16 (reference) | `BlockSpawnVolume` tagged parts |
| Color weights | uniform (1, 1, 1) | gameplay-loop § Spawner |
| Min spacing | 4 studs between block centers | `GameConfig.BLOCK_MIN_SPACING` |

## Consumers

- **BlockSpawnerService** (`src/server/BlockSpawner/`) — the server bootstrap.
- **[[systems/BlockShoot]]** (Phase 3) — destroys blocks on hit, triggering auto-refill.

## See also

- [[systems/LetterBlock]] — the entity this spawner creates.
- [[systems/EnergyEconomy]] — letter point values (distinct from spawn frequency).
- [[design/gameplay-loop]] — the "Spawner" section that defines density and distribution targets.
