---
type: design
description: Future-work plan (2026-09-20) for scaling the duel pad pool beyond the two scene-authored pads. Decision = stay on one server with fixed pads (pattern 2) for now; author more pads before writing code. Records the two switch paths — in-server dynamic instancing (~4–5 days, one factory + two boot scans become listeners) and reserved match servers (~2 weeks, second place + teleports) — with diagrams, the exact seams they use, and where the risk sits. Not scheduled.
updated: 2026-09-20
---

# Arena Instancing — scaling the duel pool

Companion to [[design/lobby]] (stage 6, the pad pool) and [[systems/GameMode]]
(sessions, `ArenaId` scoping). Prompted by the question "if the hub is busy,
should a new duel pad be created so nobody waits?" asked the day after stage 6
shipped. **Decision (user, 2026-09-20): stay single-server with scene-authored
pads for now.** This page exists so the switch, if it ever comes, is a
bounded task rather than a rediscovery.

## The three Roblox patterns

| | Pattern | Who uses it | Trade |
|---|---|---|---|
| 1 | **Reserved match servers** — hub place + `TeleportService:ReserveServer` on an arena place, one fresh server per match | Bedwars, Arsenal ranked, TDS, most big round-based games | No arena count to manage; loading screen each way, second place to publish, state travels as `TeleportData`, untestable in a Studio local server |
| 2 | **Fixed in-server arenas** — several authored arenas, one server, a queue assigns | Smaller PvP games, 1v1 pits, obby races | Simple, memory-resident state; capacity = arena count × roster |
| 3 | **In-server dynamic instancing** — clone a template arena per match, destroy after | Procedural / private-room games | Unbounded capacity on one server; every arena-scoped system gains a runtime add/remove path |

Brain Fighter is pattern 2 as of stage 6. Hosting is free in every pattern —
Roblox spins up and discards servers at no charge — so this is a design and
code decision only.

## Why pattern 2 is enough for now

A duel is two players and roughly three minutes (`DuelKillLimit` /
`DuelTimeLimitMin`). Servers have a fixed max player count set on the place,
so the worst case is *max players ÷ 2* pads — a small, bounded number. Adding
pads is a Studio task: clone `Workspace.DuelPads/Duel1`, give it a new
`ArenaId`, keep the `ArenaSlot` tag and `Mode = PvPDuel`. Blocks, spawns,
death zone and return portal come with it for free (they are all scene-gated
by tag, refactor chunks 2, 9 and 11). The queue already handles any number of
pads (`candidateSessions`, fullest-first).

**Rule to keep the switch cheap:** nothing anywhere names `Duel1` / `Duel2`
by string. The pad count is data. As long as that holds, "more pads" is
twenty minutes in Studio and "cloned pads" is the plan below.

Revisit when a real playtest shows the hub queue backing up, when duels get
long enough that two pads hold the queue for many minutes, or when a mode
with a larger roster arrives.

## What already tolerates a runtime pad

Verified 2026-09-20 against `src/`:

- **Runtime-safe already:** `DeathZoneService` listens on
  `GetInstanceAddedSignal`; `SpawnManager.getSpawnPoints`, `LobbyService.livePortals`
  and `Hittables` re-scan tags per call; `candidateSessions` reads the
  registry live; `SessionRegistry.destroy` exists (the test suites use it).
- **Boot-time only, would break:** `BlockSpawnerService.collectVolumesByArena`
  (one scan, pools built once) and `GameModeService.createSceneSlots` (one
  scan of `ArenaSlot`).

Everything arena-scoped keys off the `ArenaId` attribute via `Arena.idOf`, so
a cloned pad with a fresh id is indistinguishable from an authored one.

## Switch path A — in-server dynamic instancing

### How it would work

```mermaid
flowchart LR
    subgraph Hub["Hub"]
        Portal["PvP portal"]
        Queue["LobbyService queue"]
    end

    subgraph Storage["ServerStorage"]
        Tmpl["ArenaTemplates.DuelPad<br/>one authored pad, no ArenaId"]
    end

    subgraph Factory["ArenaSlotFactory (new)"]
        Spawn["spawn()<br/>1. Clone template<br/>2. Move to next grid cell<br/>3. Stamp ArenaId on every part<br/>4. SessionRegistry.create"]
        Despawn["despawn()<br/>1. SessionRegistry.destroy<br/>2. Destroy the Model"]
        Pool["pool: warm min, cap,<br/>idle timeout"]
    end

    subgraph World["Workspace.DuelPads (runtime)"]
        P3["Duel-3 (spawned on demand)"]
    end

    subgraph Listeners["Arena-scoped systems"]
        Blocks["BlockSpawnerService<br/>→ listen, pool per ArenaId"]
        Death["DeathZoneService (already listens)"]
        Spawns["SpawnManager (already per call)"]
    end

    Portal --> Queue
    Queue -- "queue ≥ minPlayers and no pad can take them" --> Spawn
    Tmpl -. clone .-> Spawn
    Spawn --> P3
    Spawn --> Pool
    Pool -- "empty + idle, above warm min" --> Despawn
    Despawn --> P3
    P3 -. tagged parts appear .-> Blocks
    P3 -. tagged parts appear .-> Death
    P3 -. read on transfer .-> Spawns
```

```mermaid
sequenceDiagram
    autonumber
    actor P5 as Player 5
    actor P6 as Player 6
    participant L as LobbyService
    participant F as ArenaSlotFactory
    participant R as SessionRegistry
    participant B as BlockSpawnerService
    participant RM as RoundManager (Duel-3)

    Note over L: Duel-1 and Duel-2 mid-round, freeSeats = 0
    P5->>L: Join queue
    P6->>L: Join queue
    L->>L: flushPortal: 2 waiting, no seats
    L->>F: request pad for PvPDuel
    F->>F: clone → grid cell → stamp ArenaId "Duel-3"
    F->>R: create("Duel-3", PvPDuel)
    F-->>B: BlockSpawnVolume appears → start pool
    Note over L: 1 s heartbeat
    L->>R: transferPlayer(P5), transferPlayer(P6)
    RM->>RM: Countdown → Active → PostRound → roster home
    Note over F: idle timer, pool above warm min
    F->>R: destroy("Duel-3")
    F->>B: volume removed → stop pool
    F->>F: Destroy Model
```

### Plan

| Step | Work | Size |
|---|---|---|
| 1 Template | Move one pad to `ServerStorage.ArenaTemplates.DuelPad`; duel pads stop being `ArenaSlot`s and become factory output. Lobby and Default stay code-created. | ½ day, Studio |
| 2 Factory | New `ArenaSlotFactory` in `server/GameMode`: clone, place on a grid stride far from the hub, rewrite `ArenaId` on every descendant carrying the attribute, `SessionRegistry.create`. `despawn` reverses it, registry first. Warm pool of two at boot. | 1 day |
| 3 Blocks | `BlockSpawnerService` → `GetInstanceAddedSignal` / `RemovedSignal` on `BlockSpawnVolume`, lazy pool per arena, `pool:destroy()` on removal clearing in-flight blocks. | ½ day |
| 4 Queue | In `flushPortal`, after the candidate loop: if the queue still holds ≥ the mode's `minPlayers` and the pool is under its cap, request a pad. Heartbeat flushes it next tick. Sign copy: `Capacity` is no longer fixed. | ½ day |
| 5 Teardown | Pad empty and `WaitingForPlayers` longer than the idle timeout, pool above warm minimum → despawn. | ½ day code, most of the risk |
| 6 Tests | Factory spawn/despawn round-trip; lazy block pool; pure "pads needed" rule; `scene_slots_have_sessions` accepts zero duel slots. | ½ day |
| 7 Docs | This page → decision; [[systems/GameMode]], [[systems/Tests]], two-client doc gains spawn/teardown cases. | ½ day |

**Total ≈ 4–5 focused days**, about four stage-6s. New constants: grid
stride, warm minimum, pool cap, idle timeout (a `GameModeConstants` block).
Untouched: `PvPDuel` rules, `RoundManager`, `ScoreTracker`, `RoundOutcomeCopy`,
HUD, round-start heal, portal UI.

### Where the risk sits

```mermaid
flowchart TD
    A["Pad empty + idle"] --> B{"Teardown starts"}
    B --> C["1. SessionRegistry.destroy first<br/>so candidateSessions stops offering it"]
    C --> D["2. Destroy the Model"]

    X["Same second: flushPortal picks this pad"] -. race .-> B
    X --> Y{"transferPlayer returns false"}
    Y -- must --> Z["Player returns to the queue,<br/>PlayerState stays Queued"]
    Y -- bug if --> W["Player dropped from queue,<br/>stuck Queued"]

    style W fill:#f8d7da,stroke:#c00
    style Z fill:#d4edda,stroke:#080
```

Everything keyed by `ArenaId` that can be in flight when the pad vanishes
needs the same care: blocks mid-respawn, a dead player's respawn timer, VFX
anchors, the kill feed's arena filter. This class of bug only shows with real
players, which is the reason not to pay for it before a playtest demands it.

**Ongoing tax:** every future arena-scoped system must handle add *and*
remove, and every suite gains runtime-spawn cases — a few hours per system,
forever.

## Switch path B — reserved match servers

```mermaid
flowchart LR
    subgraph HubServer["Hub place (server A)"]
        Q["Queue fills to minPlayers"]
        RS["TeleportService:ReserveServer(arenaPlaceId)"]
        TP["TeleportAsync(players, code, teleportData)"]
    end

    subgraph ArenaServer["Arena place (fresh server B per match)"]
        One["One session, one RoundManager"]
        Back["Round over → teleport back"]
    end

    Q --> RS --> TP --> One --> Back --> HubServer
```

Shape: a new *destination kind* in `LobbyService` — the queue is already
separate from "where they go" (`candidateSessions` is the only function that
knows) — that teleports instead of `transferPlayer`. A second place holding
one session; `RoundManager` and the modes run unchanged there. Loadout and
score state cross as `TeleportData` or DataStore.

**≈ 2 weeks**, mostly because teleports cannot run in a Studio local server,
so every verification cycle goes through a published place. Worth it only for
cross-server ranked matchmaking, rosters bigger than one server seats, or a
boss raid that should not share a server with the hub. A hybrid is common:
local pads for casual duels, a "ranked" portal that teleports.

## What carries to later games

The reusable asset is the session model — `SessionRegistry`, `RoundManager`,
`ArenaId` scoping, the `ArenaSlot` convention and the `LobbyService` queue —
and it is pattern-agnostic. The instancing *policy* is per-game: it depends
on server size, match length and whether cross-server matchmaking is wanted,
so choose it per game against those numbers rather than building it in.
