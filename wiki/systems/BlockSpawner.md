---
type: system
description: Server-side letter-block populator — maintains a target count of floating LetterBlocks in the arena with Scrabble-weighted letter distribution and configurable color weights.
updated: 2026-05-14
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
type Opts = {
    targetCount: number?,        -- default 24
    boxMin: Vector3?,            -- default (-20, 8, -20)
    boxMax: Vector3?,            -- default (20, 16, 20)
    colorWeights: {              -- default uniform (1, 1, 1)
        red: number?,
        green: number?,
        blue: number?,
    }?,
    parent: Instance?,           -- default workspace
}
```

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
| Target count | 24 | gameplay-loop § Spawner |
| Arena box | 40×8×40 studs, Y 8–16 | gameplay-loop § Spawner |
| Color weights | uniform (1, 1, 1) | gameplay-loop § Spawner |

## Consumers

- **BlockSpawnerService** (`src/server/BlockSpawner/`) — the server bootstrap.
- **[[systems/BlockShoot]]** (Phase 3) — destroys blocks on hit, triggering auto-refill.

## See also

- [[systems/LetterBlock]] — the entity this spawner creates.
- [[systems/EnergyEconomy]] — letter point values (distinct from spawn frequency).
- [[design/gameplay-loop]] — the "Spawner" section that defines density and distribution targets.
