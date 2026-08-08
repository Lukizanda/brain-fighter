---
type: system
description: Server-side letter-block populator — maintains a target count of floating LetterBlocks in the arena with Scrabble-weighted letter distribution, configurable color weights, and a per-block respawn cooldown.
updated: 2026-08-08
---

# BlockSpawner

Server-side populator that keeps a target count of [[systems/LetterBlock|LetterBlock]] Models alive in the arena. When a block is destroyed (consumed by [[systems/BlockShoot|BlockShoot]], despawned, etc.), the spawner schedules a single replacement via the CollectionService removed signal, after a `GameConfig.BLOCK_RESPAWN_DELAY` cooldown.

## Files

- `src/shared/BlockSpawner/init.luau` — module: start / stop / rerollAll / getActiveBlocks / pickers / tunables.
- `src/server/BlockSpawner/BlockSpawnerService.server.luau` — server bootstrap that calls `BlockSpawner.start()`, resolving `BlockSpawnVolume`-tagged parts and the `GameConfig` tunables.
- `src/shared/Tests/Suites/Phase3/blockspawner_respawn_delay.luau` — asserts the arena stays short mid-cooldown and returns to *exactly* target after, catching a refill-to-target regression.

## API

`require(ReplicatedStorage.Shared.BlockSpawner)` returns the module table.

| Member | Type | Notes |
|---|---|---|
| `.start(opts?)` | `(Opts?) -> ()` | Fills arena to target count **immediately** (the cooldown applies to replacements, not the initial fill), hooks CollectionService removed signal for auto-refill. No-ops if already running. |
| `.stop()` | `() -> ()` | Disconnects the refill listener. Existing blocks remain, and any in-flight respawn timers no-op on their `running` check. |
| `.rerollAll()` | `() -> ()` | Destroys all active blocks. Each queues its own replacement, so the field returns one cooldown later. **No callers** as of 2026-08-08 — it is a documented escape hatch from [[design/gameplay-loop]], not a shipped mechanic. |
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
    respawnDelay: number?,       -- seconds before a consumed block is replaced; 0 refills next frame (see GameConfig.BLOCK_RESPAWN_DELAY)
}
```

`respawnDelay` resolves with `~= nil` rather than `or`, so an explicit `0` means "next frame" instead of silently falling back to the module default. The module default is `0` — the shipped value lives in `GameConfig.BLOCK_RESPAWN_DELAY` and is threaded through by `BlockSpawnerService`.

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

When any tagged `LetterBlock` is removed from CollectionService, the spawner checks if it was one of ours (`active` set lookup, O(1)) and schedules a replacement. This means the arena self-heals regardless of what destroys the block — BlockShoot consumption, admin cleanup, or a rerollAll call.

### Respawn cooldown: one timer per block, not one refill to target

Before 2026-08-08 the refill was `task.defer(maintainCount)`, and `maintainCount` loops until the arena is back at target. Instant refill made a replacement appear in the player's face the moment they shot something, so the refill is now delayed by `respawnDelay`.

Delaying that same call would have been wrong. `maintainCount` fills *every* missing slot, so with three blocks shot a second apart, the first expiring timer would refill all three at once — two of them a full cooldown early, arriving as a burst. The delayed path therefore calls `spawnOneIfBelowTarget`, which replaces exactly one block. One destroy queues one timer which produces one spawn, so replacements stay on the clock their own destruction started.

`maintainCount` is still used, but only by `start()` for the initial fill — the cooldown is about *replacing* blocks, and an empty arena at round start should populate immediately.

The `activeCount >= targetCount` bound is what makes a stale timer harmless: one surviving a `stop()` / `start()` cycle finds the arena already full and no-ops, so it cannot push the count over target.

**Measured** (2026-08-08 playtest, `BLOCK_RESPAWN_DELAY = 3`): blocks destroyed at t = 0.00 / 1.02 / 2.02 were replaced at t = 3.08 / 4.05 / 5.06 — each 3.03–3.08 s after its own destruction, staggered rather than bursting, ending back at exactly the target count.

Raising the delay thins the arena under sustained fire: steady-state missing blocks ≈ delay × kills-per-second. At 3 s and roughly one kill per second, that is ~3 blocks short of target — barely visible against ~40. A much longer cooldown is a scarcity mechanic, not just polish, and should be tuned against [[design/gameplay-loop]]'s spellability heuristic.

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
| Respawn cooldown | 3 s per consumed block | `GameConfig.BLOCK_RESPAWN_DELAY`; `0` refills next frame |
| Wildcard frequency | `4` → 4/102 ≈ 3.9% | `WILDCARD_FREQUENCY` in `BlockSpawner/init.luau`; `0` disables |

### Wildcard rolls

The wildcard (see [[systems/Wildcard]]) is rolled as a **27th letter** against the same cumulative table as the Scrabble bag — weight `4` against the bag's total of `98`. Its color is then **fixed** to `"wild"` rather than rolled, so a star can never masquerade as a reservoir color the player is hunting for.

Scrabble's own ratio is 2 blanks per 98 tiles (≈2%), but blocks here recycle continuously as they're consumed, and that rate left too many arenas with no star visible at all.

## Consumers

- **BlockSpawnerService** (`src/server/BlockSpawner/`) — the server bootstrap.
- **[[systems/BlockShoot]]** (Phase 3) — destroys blocks on hit, triggering auto-refill.

## See also

- [[systems/LetterBlock]] — the entity this spawner creates.
- [[systems/EnergyEconomy]] — letter point values (distinct from spawn frequency).
- [[design/gameplay-loop]] — the "Spawner" section that defines density and distribution targets.
