---
type: design
description: Phase 8 plan (2026-11-13) for the PvE boss arena layout. Three concentric value rings (premium letters inside Ground Slam range, exposed standard letters mid, common letters behind outer cover), a permanent rim, breakable cover the boss destroys when its attacks miss, regenerating gates in front of wildcard balconies, and two single-colour vaults opened by baiting the boss. Fixes the tag and attribute contract between the new BreakableWalls system, the BlockSpawner zone extension and the Studio greybox. Revised the same day into an irregular floating island with three different ways out past the ridge, two caves, and a one-way teleporter in place of the bridge. Stages 1, 2 and 5 (code) built; the Studio greybox is next.
updated: 2026-11-13
---

# Boss Arena Layout

Companion to [[systems/Boss]], [[systems/BlockSpawner]] and [[systems/SkillPipeline]].
Layout sketch: [boss-arena-layout.html](boss-arena-layout.html) (top-down, to scale).

## Why

The shipped arena is a bare 300-stud disc with eight letter volumes in a ring and no
walls at all. Two requests from the user (2026-11-13):

1. A boundary, so players can't fall off the plaza.
2. Risk/reward gameplay from the layout.

The fact that shaped everything: pop reach is 200 studs and the plaza is 300 across, so
**position carried no risk**. Any letter could be taken from nearly anywhere.

## Decisions (user, 2026-11-13)

| Question | Decision |
|---|---|
| Risk/reward ideas | Value rings, cover versus open lanes, jackpot ledges. Raised platforms and a phase-driven arena were not picked |
| How position gains risk | Keep the 200-stud reach; rely on **line of sight**. The tap raycast already stops at walls |
| Boundary | Permanent rim. The boss can destroy walls when its attack misses the player and hits the environment |
| What breaks | Inner cover and the gates in front of ledges, plus **hidden areas revealed only by getting the boss to attack their wall** |
| Regeneration | Most walls are gone for the round; some regenerate |
| Ground Slam | Also cracks cover inside its radius |

Rule adopted for which walls regenerate (assistant's proposal, not yet challenged):
**walls that guard a reward heal; walls that protect the player don't.** Gates and vault
doors re-seal, so the reward is re-earned and holes in the boundary close. Ordinary
cover is permanent loss, apart from a few indestructible stumps so the late fight is
not a bare floor.

Boss attacks only. A player spell does not damage a wall, because opening a vault with
your own Fireball removes the baiting.

## What already works (verified in code 2026-11-13)

- **Taps stop at walls.** `BlockTapController` raycasts from the camera and the hover
  outline is `Occluded` to match. Client-side only; the server checks range, not sight.
- **Fireballs stop at walls.** `SkillDelivery`'s projectile handler sweeps each step
  with `RespectCanCollide` and calls `detonate(part, pos, nil, "impact")` when the ray
  stops on something that is not a rig. That branch is the wall-damage hook.
- **The boss fires without line of sight.** `BossStates` never reads `canSeeTarget`,
  so a player behind cover still draws fire and the cover takes it.
- **Ground Slam is a plain radius**, players only, no occlusion (`handlers.aoe`).
- Brain's volley is `count = 20`, `speed = 90`, `lifetimeSec = 3` in `BossConfig`
  (270 studs of travel, further than the plaza is wide). [[systems/Boss]] quotes both
  30 and 3; the config is the truth.

## Measured arena (Studio, 2026-11-13)

| Thing | Value |
|---|---|
| Plaza | `Workspace.Arena.LevelGreybox.Plaza`, cylinder radius 150, centre X 53.4 / Z 28.2, floor top Y 202.5 |
| BossPoint | (54, 204, 27), the plaza centre |
| Bridge | East side, 49 x 36, to the spawn zone at X 264; glass railings. Carries the `LobbyReturnPad`. Removed in stage 3 |
| Letter volumes | 8 untagged-arena boxes at 75–100 studs from centre, Y 213–233 (10–30 above the floor) |
| DeathZone | 600 x 50 x 300 at Y 100 |
| Walls | None |

## Layout

**Revised 2026-11-13 (v2).** The first sketch was a disc with cover on a regular
angular grid and three identical square balconies. The user found it static and gamey
and asked for something more organic. v2 keeps every rule and changes the shapes.

Angles are degrees clockwise on the sketch from east (the bridge). Radii are studs from
the plaza centre. All numbers are greybox starting points.

| Element | Where | Behaviour |
|---|---|---|
| Island | Irregular outline, radius 138–163 | Replaces the 150-radius disc, so the floor is rebuilt in the greybox |
| Ridge | A rock lip just inside the outline, uneven height, plus an invisible collider | Permanent, closed all the way round (see § Entry) |
| Weak ridge sections ×3 | About 68°, 170°, 285° (deliberately uneven) | Breakable, **regenerate** |
| The Spit | Beyond the 170° section: a tongue about 60 long narrowing from 25 wide to a point | Wildcards at the tip. No railing; a knock-up is a ring-out |
| The Stones | Beyond the 68° section: three islets across open gaps | A jump each way. Some wildcards on the second, most on the last |
| The Overhang | Beyond the 285° section: a broad cracked slab | The slab is itself a regenerating `BreakableWall`. Boss fire that lands on it drops it for a while |
| Ridge cave | Hollow in the ridge at about 228° | Permanent shell, **regenerating** rock plug facing the boss. Single-colour letters. Dead end |
| Hollow boulder | Free-standing at about 118°, r 100 | Same, but mid-field, so not every reward is at the rim |
| Rock clusters ×10 | Irregular: five around r 60, five around r 105 | Two to four boulders of mixed size. Most are breakable and gone for the round; six clusters have one permanent bedrock core, so a cluster erodes to a stump |
| Common letters | Patches on the far side of the outer clusters | Safest spot |
| Standard letters | Patches on open ground between clusters | Exposed |
| Premium letters | A patch around the boss spawn, out to about r 30 | Inside Ground Slam's 22 studs |

What stays fixed from v1:

- Value falls with distance from the boss.
- The line from the boss spawn to each weak ridge section and each cave plug is free
  of cover, so a boss near the middle can always be baited into them.
- Walls that guard a reward regenerate; cover does not.

The three ways out differ on purpose. The Spit punishes a knock-up, the Stones punish a
missed jump, and the Overhang punishes staying too long. The Overhang needs no new
code: a floor part tagged `BreakableWall` with `RegenSec` is handled by stage 1 as it
is, to be confirmed in the greybox playtest.

Greybox note: organic shapes are built from rotated and overlapping blocks, wedges and
balls under `Workspace.Arena.LevelGreybox`. Each breakable boulder must stay a single
`BasePart` to fit the contract.

## Entry: teleporter, no bridge

**Decided by the user 2026-11-13.** The bridge goes. Players enter by a teleporter and
cannot walk back to the ready room; the only ways off the island are dying or quitting.

How that maps onto what exists:

- The **ready room** is today's `Workspace.Arena.SpawnZone`: the arena session's one
  spawn pad, where a player lands on transfer from the hub and on every respawn. Dying
  already returns you there, so "die" needs no new code.
- **Quit** is the `LobbyReturnPad`, which sits on the bridge today and moves into the
  ready room. Leaving mid-fight therefore means dying first (or leaving the game).
  Confirmed by the user 2026-11-13: the return pad in the ready room, no in-fight
  "return to lobby" button.
- **New:** a one-way pad in the ready room that puts the player on the island's
  arrival pad. Contract: a `BasePart` tagged **`ArenaEntryPad`**, and a `BasePart`
  tagged **`ArenaArrivalPoint`**, matched by `ArenaId`. Server-owned; stepping on the
  pad teleports that player's character. With several arrival points one is picked at
  random.
- With no bridge the ridge has no gap, which is the full boundary the user first asked
  for.

Greybox consequences:

- The arrival pad sits on the east side behind one permanent rock, so a player does not
  appear in the boss's line of fire.
- **The ready room has to be out of reach of the fight.** It is 210 studs from the
  plaza centre today, pop reach is 200 and spell auto-target is 150, so from its edge a
  player could pop outer letters in safety. Since walking distance no longer matters,
  move it further out or seal its view; then it can still be a place to watch from.

**Letter height.** Blocks float 10–30 studs above the floor today. A third-person
camera sees over low cover, so cover only hides letters if the letter band is lowered
(proposal: 6–18 above the floor) and cover is about 20 tall. Thin pillars will hide
little either way; wall segments and the roofed vaults do the real occluding. To be
judged in the greybox playtest.

## Contract between the three pieces

Fixed here so the code and the greybox can be built separately.

### Breakable walls

A wall is one anchored `BasePart` tagged **`BreakableWall`**.

| Attribute | Type | Meaning |
|---|---|---|
| `MaxHealth` | number | Hit points. Absent means `BreakableWallConstants.DEFAULT_MAX_HEALTH` |
| `RegenSec` | number | Seconds after breaking before it re-seals. Absent or 0 means gone for the round |
| `ArenaId` | string | Same vocabulary as everything else. Absent means `Default` |

Published by the server on the part, read by the client:

| Attribute | Meaning |
|---|---|
| `WallHealth` | Current hit points |
| `WallState` | `"intact"`, `"cracked"`, `"critical"`, `"broken"` |

Ownership: the server owns `CanCollide`, `CanQuery`, `CanTouch` and the two published
attributes. The client owns everything the player sees and hears (crack look, break
burst, regen telegraph), driven by `WallState` changes. A broken wall stays in the
DataModel, non-colliding and non-queryable, so it can re-seal and so taps and fireballs
pass through it.

Damage arrives through two server-side BindableEvents fired by `SkillDelivery` on the
authoritative run, in the same shape [[systems/Analytics]] uses (the domain announces,
one listener reacts):

- `WorldImpact(hitInstance, hitPosition, skillName, source)` when a projectile stops on
  world geometry.
- `AoeImpact(center, radius, skillName, source)` when an aoe lands.

`BreakableWallService` listens, ignores any source that is not `Boss`-tagged, and
applies `FIREBALL_WALL_DAMAGE` or `SLAM_WALL_DAMAGE`. Walls reset to intact on their
arena's `RoundStarted`. A regenerating wall does not re-seal while a character stands
inside it.

### Letter zones

A `BlockSpawnVolume` part gains three optional attributes. A volume with none of them
behaves exactly as today.

| Attribute | Type | Meaning |
|---|---|---|
| `LetterTable` | string | Named table in the spawner: `Standard` (default, the Scrabble bag), `Common`, `Premium`, `Wildcard` |
| `ColorOnly` | string | `red`, `green` or `blue`: every block in the volume is that colour |
| `BlockQuota` | number | This volume holds exactly this many blocks and refills itself. It is left out of the density pool |

`BlockQuota` exists because distribution is volume-weighted: a small vault or balcony
would otherwise receive almost nothing, and blocks sealed in a vault would thin the
open arena. Quota volumes are counted separately; the arena's density target is
computed from the remaining volumes only.

## Stages

| Stage | Item | Owner | Status |
|---|---|---|---|
| 1 | `BreakableWalls` system: service, constants, client visuals, the two `SkillDelivery` events, suite | build session (Sonnet) | **built 2026-11-13**, suite 7/7 — [[systems/BreakableWalls]]. Real boss fire not yet verified |
| 2 | `BlockSpawner` letter zones: per-volume table, colour and quota, suite | build session (Sonnet) | **built 2026-11-13**, 5 new tests — [[systems/BlockSpawner]] § Letter zones |
| 3 | Greybox the layout in Studio: rim, cover, gates, balconies, vaults, retagged volumes | with the user, after the sketch is approved and 1–2 land | waiting |
| 4 | Playtest and tune: wall health against a 20-shot volley, letter height, quotas, boss reach to the outer ring | with the user | waiting |
| 5 | Arena entry teleporter: `ArenaEntryPad` → `ArenaArrivalPoint`, suite | build session (Sonnet) | **built 2026-11-13**, 3 tests — [[systems/ArenaEntry]]. Physical touch not yet verified |

Stage 3 is not fanned out. The build plan's rule is that work needing design judgment
is done with the user, and it needs the Studio place, which the two build sessions also
playtest in.

## Open questions

- ~~**Scope against the soft launch.**~~ Decided by the user 2026-11-13: the arena
  ships **before** the unlisted publish. [[design/build-plan]] § Current focus now lists
  Phase 8 stages 3–4 ahead of the publish.
- **Outer ring safety.** Boss `attackRange` is 100 and it walks at 6. A player at r 120
  may sit outside its reach for long stretches. Tune in stage 4.
- **Wall health.** One volley is 20 shots. Health has to be set so a segment survives
  more than one volley but not a whole round.
- **Tutorial.** Baiting is not discoverable without a tell on gates and vault doors
  (cracks, light leaking through). The tell is part of stage 3.
