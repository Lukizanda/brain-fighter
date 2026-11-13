---
type: system
description: Walls the boss destroys (Phase 8 stage 1, 2026-11-13). A BasePart tagged BreakableWall has health; boss fireballs that stop on it and Ground Slams that reach it wear it through intact / cracked / critical / broken. The server owns health and collision and publishes WallHealth / WallState; the client owns the look. RegenSec walls re-seal, the rest stay broken until the arena's next round. Fed by two new SkillDelivery Bindables, WorldImpact and AoeImpact. Suite 7/7; real boss fire against a wall is not yet verified.
updated: 2026-11-13
---

# BreakableWalls

Cover and gates in the boss arena that the boss's own attacks destroy. Built for
[[design/boss-arena]], which holds the layout and the reason: hiding behind cover spends
the cover, and reward areas are opened by baiting the boss into hitting their wall.

No wall exists in the place yet. The greybox is Phase 8 stage 3.

## Files

| File | Purpose |
|---|---|
| `src/shared/Arena/BreakableWallConstants.luau` | Tag, attribute and state names, damage and regen numbers, the client's greybox look. Shared because the client reads the names |
| `src/server/Arena/BreakableWallService.server.luau` | Health, state, collision, regeneration, round reset. `enable()` / `disable()` / `destroy()` |
| `src/client/Arena/BreakableWallVisuals.client.luau` | Crack tint, break burst, regen ghost, re-seal fade |
| `src/shared/Skills/SkillEvents/WorldImpact.model.json`, `AoeImpact.model.json` | The two server-side BindableEvents `SkillDelivery` fires |
| `src/shared/Tests/Suites/Arena/wall_*.luau`, `Tests/Helpers/breakableWallFixture.luau` | Suite and fixture |

## Authoring a wall

Tag one anchored `BasePart` with `BreakableWall`. Optional attributes:

| Attribute | Meaning |
|---|---|
| `MaxHealth` | Hit points, in boss fireballs. Absent means `DEFAULT_MAX_HEALTH` (30) |
| `RegenSec` | Seconds after breaking before it re-seals. Absent or 0 means gone for the round |
| `ArenaId` | Absent means `Default`, as everywhere else |

The authored attributes are read at use, so a designer can retune a wall during a
playtest. A wall must stay a single part; a boulder made of several parts is several
walls.

## Ownership

| Owner | Writes |
|---|---|
| Server (`BreakableWallService`) | `CanCollide`, `CanQuery`, `CanTouch`, and the published attributes `WallHealth` and `WallState` |
| Client (`BreakableWallVisuals`) | `Color` and `Transparency`, plus every sound and burst |

The server never touches the look and the client never touches collision
([[concepts/SingleOwnership]]). A broken wall stays in the DataModel with all three
collision flags off, so it can re-seal and so taps and fireballs pass through it. A
re-seal restores the flags the part was registered with, not `true`.

## Damage

`SkillDelivery` announces where a delivery landed; the service decides what that means.
Same shape as [[systems/Analytics]]: the domain fires, one listener reacts.

| Event | Fired | Effect |
|---|---|---|
| `WorldImpact(hitInstance, hitPosition, skillName, source)` | Projectile handler, when the swept ray stops on something that is not a rig. Not on expiry or fuze | The hit wall takes `FIREBALL_WALL_DAMAGE` (1) |
| `AoeImpact(center, radius, skillName, source)` | `handlers.aoe`, with the shockwave | Every wall whose nearest point is inside the radius takes `SLAM_WALL_DAMAGE` (10) |

Both fire on the authoritative run only. **Boss sources only**: anything not carrying
`BossSpawner.BOSS_TAG` is ignored, so a player cannot open a vault with their own
Fireball.

State follows health: at or below two thirds is `cracked`, at or below one third is
`critical`, zero is `broken`.

**Why 30.** Brain's volley is 20 shots. A wall that cannot outlast one volley is no
cover, so the default is a volley and a half: it survives a full volley even if every
shot lands, and the second volley finishes it. `VOLLEY_SHOTS` mirrors
`BossConfig`'s `FireballVolley.count`, and the suite asserts they match, so retuning
the volley fails a test instead of quietly thinning every wall.

## Regeneration and reset

- `RegenSec > 0`: re-seals that long after breaking, unless a character overlaps the
  part, in which case it asks again every `REGEN_RETRY_SEC` (0.5 s).
- Otherwise it stays broken.
- Every wall of an arena returns to intact on that arena's `RoundStarted`.

## Client look (greybox)

A tint toward dark stone at `cracked` (30%) and `critical` (60%, plus 0.15
transparency), a `wall_break` burst and hide at `broken`, then a faint pulsing ghost
before the re-seal and a short fade back. Effects are `VfxConfig.EFFECTS` entries
(`wall_crack` and `wall_rise_dust` reused from the Stone Wall, `wall_break` new), so an
art pass is a config change. A wall first seen in a damaged state is drawn silently.
Reduced effects drops the ghost pulse and the fade.

The regen ghost is a client estimate: the server publishes no timestamp, so the client
counts `RegenSec` minus 2 s from when it saw the break. A late joiner sees no ghost,
and a wall held open by an overlapping character keeps its ghost until the server
re-seals.

## Verification (2026-11-13)

`RunTests=all` gave 55/55 with `Arena` 7/7 and `Skills` 5/5; a second bare boot was
clean. A probe wall watched on the client went cracked, critical, broken, ghost and
re-sealed with the expected tint and transparency.

Not verified:

- **Real boss fire against a wall.** The tests fire the Bindables directly. The two
  hook sites in `SkillDelivery` are confirmed by reading and by `Skills` still passing,
  not by a boss shot. First real check is the greybox playtest.
- The break burst, crack sound and dust were never seen or heard, and Reduced effects
  was not exercised.
- Streaming and two clients.

Known side effect: `wall_round_start_resets_arena_walls` fires the real `RoundStarted`
for two made-up arena ids, and `NPCService` keeps an empty NPC set for each until the
server stops.

## See also

- [[design/boss-arena]] — layout, decisions and the contract this implements
- [[systems/SkillPipeline]] — the projectile and aoe handlers that fire the events
- [[systems/Boss]] — the only source that damages a wall
- [[systems/BlockShoot]] — the tap raycast that a standing wall blocks
