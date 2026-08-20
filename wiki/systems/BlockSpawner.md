---
type: system
description: Server-side letter-block populator — one instance per arena, maintaining that arena's target count of floating LetterBlocks with Scrabble-weighted letter distribution, configurable color weights, and a per-block respawn cooldown.
updated: 2026-08-20
---

# BlockSpawner

Server-side populator that keeps a target count of [[systems/LetterBlock|LetterBlock]] Models alive in **one arena**. When a block is destroyed (consumed by [[systems/BlockShoot|BlockShoot]], despawned, etc.), the spawner schedules a single replacement via the CollectionService removed signal, after a `GameConfig.BLOCK_RESPAWN_DELAY` cooldown.

**One pool per arena since Phase 6 stage 2** (2026-08-20). It was a file-local singleton that treated every tagged `BlockSpawnVolume` in the world as one pool — see § Arena binding below. The shipped game runs exactly one pool, `Default`, so nothing about it looks different yet.

## Files

- `src/shared/BlockSpawner/init.luau` — the pool class: `new` / start / disable / destroy / rerollAll / getActiveBlocks / pickers / tunables.
- `src/server/BlockSpawner/BlockSpawnerService.server.luau` — server bootstrap that groups `BlockSpawnVolume`-tagged parts by arena and starts one pool per group, threading the `GameConfig` tunables.
- `src/shared/GameMode/Arena.luau` — the shared `ArenaId` / `Default` vocabulary, also used by [[systems/GameMode]].
- `src/shared/Tests/Suites/Phase3/blockspawner_respawn_delay.luau` — asserts the arena stays short mid-cooldown and returns to *exactly* target after, catching a refill-to-target regression.

## API

`require(ReplicatedStorage.Shared.BlockSpawner)` returns the class table; `BlockSpawner.new(opts?)` returns a pool.

| Member | Type | Notes |
|---|---|---|
| `.new(opts?)` | `(Opts?) -> BlockSpawner` | Resolves opts and the volume-weighted box table. Spawns nothing until `:start()`. |
| `:start()` | `() -> ()` | Fills this arena to target count **immediately** (the cooldown applies to replacements, not the initial fill), hooks CollectionService removed signal for auto-refill. No-ops if already running or destroyed. |
| `:disable()` | `() -> ()` | Reversible halt. Disconnects the refill listener; existing blocks remain standing and in-flight respawn timers no-op on their `_running` check. A later `:start()` tops the surviving set back up to target. |
| `:destroy()` | `() -> ()` | `:disable()`, then destroys this pool's blocks and clears its state. Permanent. |
| `:rerollAll()` | `() -> ()` | Destroys this pool's blocks. Each queues its own replacement, so the field returns one cooldown later. **No callers** as of 2026-08-08 — it is a documented escape hatch from [[design/gameplay-loop]], not a shipped mechanic. |
| `:getActiveBlocks()` | `() -> { Model }` | Snapshot of the blocks *this pool* tracks. Another arena's blocks are never included. |
| `:getArenaId()` / `:getTargetCount()` | `() -> string` / `() -> number` | Identity and resolved target, for logging and assertions. |
| `.LETTER_FREQUENCIES` | `{ [string]: number }` | Scrabble-standard 98-tile distribution used for weighted letter picks. Module-level: derived from constants, so it is built once at require rather than per pool. |

### Opts type

```luau
type BoxDef = { boxMin: Vector3, boxMax: Vector3 }

type Opts = {
    arenaId: string?,            -- which arena slot this pool is; default Arena.DEFAULT_ID

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
    minSpacing: number?,         -- minimum studs between block centers; 0 disables. BlockSpawnerService derives it from LetterBlocks.tumbleDiameter() × GameConfig.BLOCK_SPACING_CLEARANCE
    respawnDelay: number?,       -- seconds before a consumed block is replaced; 0 refills next frame (see GameConfig.BLOCK_RESPAWN_DELAY)
}
```

`respawnDelay` resolves with `~= nil` rather than `or`, so an explicit `0` means "next frame" instead of silently falling back to the module default. The module default is `0` — the shipped value lives in `GameConfig.BLOCK_RESPAWN_DELAY` and is threaded through by `BlockSpawnerService`.

## Studio setup

Tag any `BasePart` in Workspace with the `BlockSpawnVolume` CollectionService tag to define a spawn region, and give it an `ArenaId` string attribute to say which arena it belongs to. Volumes sharing an id are one pool; you can have as many as you want, and all are active simultaneously.

**A volume with no `ArenaId` belongs to `Default`.** The attribute is how you opt a volume *out* of the default arena, never how you opt one in — the shipped arena's eight volumes carry no attribute at all.

**Circular boss arena example**: place 4–8 rectangular parts arranged in a ring around the boss, each tagged `BlockSpawnVolume` and attributed with the same `ArenaId`. Blocks distribute across them weighted by volume, so equal-sized parts produce equal density.

Density is controlled by `GameConfig.BLOCK_SPAWN_DENSITY` and applies **per arena**: a pool's target is density × *that arena's* volume / 1000. The count auto-adjusts as you add or resize that arena's volumes, and resizing one arena never changes another's count.

## Design decisions

### Arena binding (Phase 6 stage 2, 2026-08-20)

The spawner held its state — `running`, `resolvedOpts`, `activeCount`, the box and letter tables — in file-locals, so the module *was* the arena. `BlockSpawnerService` collected every part tagged `BlockSpawnVolume` anywhere in the world into one array and called `start()` once. With the hub place of [[design/lobby]] that breaks in three ways at once: two arenas would draw spawn positions from each other's boxes, share a single target count, and refill each other's consumed blocks.

It is now one instance per arena, following the idiom [[systems/GameMode]]'s `RoundManager` established in stage 1 — `new(deps)` plus the project's `disable()` / `destroy()` pair. `BlockSpawnerService` groups the tagged volumes by `Arena.idOf(part)` and starts one pool per group.

**Density was the subtle half.** `targetCount = density × total_volume / 1000` summed *all* tagged volumes. Per-arena it has to be that arena's volume, and the difference is invisible while one arena exists — the single-arena case gives the right answer either way, so the bug would have shipped and surfaced only when the second arena over- or under-filled. Verified live by building two pools over disjoint boxes of 100k and 50k cu studs: they resolved to 10 and 5 blocks, where the summed-volume bug gives 15 each.

**Absence means default, not error.** The shipped arena's volumes are tagged but carry no `ArenaId`. Requiring the attribute — or treating unattributed parts as their own slot — would have silently stopped the shipped arena spawning while every log stayed clean. `Arena.idOf` resolves absent or blank to `Arena.DEFAULT_ID`; see the note in that module.

**Isolation is structural, not conventional.** The `LetterBlock` CollectionService tag is global, so every pool's removed handler fires for every pool's blocks. What separates them is the `_active` set lookup that was already there for O(1) "one of ours?": a pool ignores a removal it doesn't recognise, so it cannot count or refill another arena's block.

**Verified 2026-08-20** by playtest — the shipped arena boots to one `Default` pool, 8 boxes, 397,600 cu studs, target 40, spawned 40, all inside tagged volumes; a client-fired `ConsumeBlock` popped a block and the pool refilled to 40. Two probe pools then confirmed disjoint targets, independent refill, blocks confined to their own boxes, and no movement in the live arena's count.

A side effect worth knowing: the Phase 3 suites no longer have to stop the live spawner to isolate themselves. Under the singleton each fixture called `BlockSpawner.stop()` in `setup` and never restarted it, so running a block test left the real arena frozen for the rest of the playtest. They now build their own pool in their own arena id.

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

The `_activeCount >= targetCount` bound is what makes a stale timer harmless: one surviving a `disable()` / `start()` cycle finds the arena already full and no-ops, so it cannot push the count over target.

**Measured** (2026-08-08 playtest, `BLOCK_RESPAWN_DELAY = 3`): blocks destroyed at t = 0.00 / 1.02 / 2.02 were replaced at t = 3.08 / 4.05 / 5.06 — each 3.03–3.08 s after its own destruction, staggered rather than bursting, ending back at exactly the target count.

Raising the delay thins the arena under sustained fire: steady-state missing blocks ≈ delay × kills-per-second. At 3 s and roughly one kill per second, that is ~3 blocks short of target — barely visible against ~40. A much longer cooldown is a scarcity mechanic, not just polish, and should be tuned against [[design/gameplay-loop]]'s spellability heuristic.

### Spacing (fixed 2026-08-20)

Blocks were visibly interpenetrating, and worsening as the arena churned. Two bugs compounded.

**The threshold was smaller than a block.** `GameConfig.BLOCK_MIN_SPACING` was a literal `4` studs while `BLOCK_SCALE = 1.5` made blocks 6 studs wide, so the check passed on pairs that were plainly overlapping. `BLOCK_SCALE`'s own comment asked whoever changed it to update the spacing by hand — a coupling that broke silently the first time it moved.

Spacing is now **derived from the prefab's geometry**: `LetterBlocks.tumbleDiameter()` returns the cube's circumsphere, `edge × BLOCK_SCALE × √3` (10.39 studs at the shipped scale). Two blocks that far apart cannot intersect at *any* orientation. `BLOCK_MIN_SPACING` is retired; `GameConfig.BLOCK_SPACING_CLEARANCE` is a **multiplier** on that diameter, which cannot drift out of step with block size the way a stud literal did.

Why the circumsphere and not the 6-stud edge: [[systems/LetterBlock]]'s animator tumbles blocks on a tilted axis, so a block sweeps a sphere rather than a cylinder. The tumble change raised the required clearance from ~8.5 studs to 10.39 and is what made the latent bug visible.

**The retry loop failed silently in the worst way.** After `MAX_SPAWN_ATTEMPTS` collisions it fell through and spawned at the *last rejected* position — an arbitrary failing candidate, not the least-bad one — with no log. A too-dense arena was indistinguishable from a healthy one until you could see the overlap. `pickSpacedCFrame` now keeps the roomiest candidate seen and warns on exhaustion, naming `BLOCK_SPAWN_DENSITY` as the lever.

Headroom was never the constraint: the shipped arena is 397,600 cu studs holding 40 blocks — 6% fill even at full tumble clearance.

**Verified 2026-08-20** on the server VM, all 780 pairs measured, then 60 blocks churned through the refill path (destroy half, wait out the 3 s cooldown, re-survey ×3):

| | blocks | pairs closer than 10.39 | closest pair |
|---|---|---|---|
| initial fill | 40 | 0 | 10.96 |
| after 20 refills | 40 | 0 | 10.63 |
| after 40 refills | 40 | 0 | 11.04 |
| after 60 refills | 40 | 0 | 11.51 |

No density warnings fired across all 60 spawns.

### Random yaw on spawn

Each block spawns with a random initial Y-axis rotation so a cluster doesn't look grid-aligned before the client animator's per-block phase offset kicks in.

## Tunables (defaults from gameplay-loop)

| Parameter | Default | Source |
|---|---|---|
| Target count | density-computed **per arena** — 40 in the shipped `Default` arena | `GameConfig.BLOCK_SPAWN_DENSITY` × that arena's volume ÷ 1000 |
| Density | 0.1 blocks per 1000 studs³ | `GameConfig.BLOCK_SPAWN_DENSITY` |
| Arena box | shipped: 8 volumes, 397,600 studs³ · module fallback: 40×8×40, Y 8–16 | `BlockSpawnVolume` tagged parts, grouped by `ArenaId` |
| Color weights | uniform (1, 1, 1) | gameplay-loop § Spawner |
| Min spacing | derived — 10.39 studs at `BLOCK_SCALE = 1.5` | `LetterBlocks.tumbleDiameter()` × `GameConfig.BLOCK_SPACING_CLEARANCE` |
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
