---
type: design
description: Phase 8 plan (2026-11-13) for the PvE boss arena layout. Three concentric value rings (premium letters inside Ground Slam range, exposed standard letters mid, common letters behind outer cover), a permanent rim, breakable cover the boss destroys when its attacks miss, regenerating gates in front of wildcard balconies, and two single-colour vaults opened by baiting the boss. Fixes the tag and attribute contract between the new BreakableWalls system, the BlockSpawner zone extension and the Studio greybox. Revised the same day into an irregular floating island with three different ways out past the ridge, two caves, and a one-way teleporter in place of the bridge. Stages 1, 2 and 5 (code) built; the Studio greybox is next.
updated: 2026-11-18
---

# Boss Arena Layout

Companion to [[systems/Boss]], [[systems/BlockSpawner]] and [[systems/SkillPipeline]].
Current layout, drawn from the review copy's measured geometry:
[boss-arena-review-layout.html](boss-arena-review-layout.html). The original concept
sketch is [boss-arena-layout.html](boss-arena-layout.html) (v3, out of date).

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
  (270 studs of travel, further than the plaza is wide). [[systems/Boss]] once quoted
  both 30 and 3 for the count; it was corrected, and the config is the truth. Each
  fireball does 5 damage, so a full volley is 100.

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

### Word kits (the cave's reward, decided 2026-11-13)

The user asked what carrot the cave should hold and chose the assistant's
recommendation: **a ready-made word**. The cave holds five or six letters of one colour
that are guaranteed to anagram into a real word, so the reward is something the open
arena cannot give and it pays out as one big cast. The colour changes each time the
plug regenerates, so players can read from outside what is on offer. Rejected: the
three random red letters built first (may not spell, not worth being cornered for), a
generic power-up (outside the spelling loop) and a safe room (hiding is the opposite of
risk for reward).

Contract, as an extension of letter zones:

| Attribute | On | Meaning |
|---|---|---|
| `WordKit` | a `BlockSpawnVolume` | number: the word length. The volume holds the letters of one word of that length from a curated list, shuffled |
| `KitGate` | the same volume | string: re-roll the kit when a `BreakableWall` with the same `GateId` re-seals |
| `GateId` | a `BreakableWall` | string: names the wall for `KitGate` |

- A kit is laid out as a **row along the volume part's local X axis**, evenly spaced
  across `Size.X`, at the part's position. This is the one case where a volume's
  rotation is honoured; ordinary zones stay axis-aligned boxes.
- **Amended 2026-11-13 after the build:** letters need about 10.4 studs between
  centres, so a straight 5-letter row is 52 studs and the cave chamber is 32 wide. A
  row too short to be straight **zig-zags** across the part's local Z. The cave holds
  a 5-letter kit in a 26.5 x 10 zig-zag; a 6-letter word does not fit that chamber.
- A kit is one colour. `ColorOnly` fixes it; without it the pool picks a colour each
  time the kit is rolled.
- A kit does not refill letter by letter. It is replaced whole: when its gate re-seals,
  or, with no `KitGate`, once it has been emptied.
- `WordKit` implies the block count, so `BlockQuota` and `LetterTable` are ignored on
  a kit volume, with a warning if set.
- Words come from a short curated list of common words, not a random dictionary pick:
  the dictionary holds about 80k words including obscure and geographic ones, and an
  anagram nobody can find is not a reward.

### Fossil letters (decided 2026-11-13)

Picked by the user from the mechanics ideation (see § Mechanics ideation). Each
breakable rock hides a letter. The crack shows it and the break frees it, so losing
cover pays out in the game's own language and cover becomes a spelling choice.

| Attribute | On | Meaning |
|---|---|---|
| `FossilTable` | a `BreakableWall` | string: a letter-table name (`Standard`, `Common`, `Premium`, `Wildcard`). The wall holds one letter rolled from that table. Absent means no fossil |
| `FossilLetter`, `FossilColor` | the same wall | published by the server each `RoundStarted`; read by the client |

- **Opt-in per wall.** Greybox authoring: low cover `Standard`, tall cover `Premium`,
  spires `Wildcard`. Gates and the cave plug carry none.
- A wall with `RegenSec > 0` cannot hold a fossil; setting both warns and the fossil is
  ignored. A regenerating wall would otherwise pay out every time it breaks.
- **The glyph is hidden while the wall is intact.** The wall-visuals client draws it
  when `WallState` becomes `cracked` or `critical`. A letter painted on every rock from
  the start would read as gamey.
- When the wall breaks, one ordinary letter block of that letter and colour appears
  where the wall stood, at a fixed height above the wall's base, and is removed after
  `FOSSIL_LIFETIME_SEC` (start at 20) with a fade tell in its last seconds.
- The freed block is outside the density pool and outside every quota. It is not
  refilled.
- Ownership: the letter roll and the freed block belong to [[systems/BlockSpawner]]
  (it owns letter tables and blocks) in a watcher beside the word-kit one. The wall
  service is not changed; the watcher reads `WallState`. The glyph belongs to the
  wall-visuals client.

### Hungry brain (decided 2026-11-13)

Also picked by the user. The boss eats letters near it and heals a little, so the
letters around the boss are urgent instead of merely valuable.

- Every `eatIntervalSec` (start at 5) the living boss takes the nearest letter block
  within `eatRadius` (start at 25 studs), and heals `eatHealFraction` of its maximum
  health (start at 0.01). At most 12% a minute at these values.
- It does not eat during the entrance, while frozen (the code has no stun status), or when no block is in
  range. It never eats a word-kit letter or a freed fossil letter: both are rewards a
  player earned.
- The block is removed through the spawner's normal removal path, so its zone refills
  as it would after a pop.
- The player sees a stream from the block to the boss and a heal cue on the boss, both
  sent with `VfxBroadcast`.
- Ownership: the behaviour and its numbers belong to [[systems/Boss]] (`BossConfig`).
  The boss asks [[systems/BlockSpawner]] for the block; it does not touch blocks
  itself. The heal goes through the Health system's existing heal path.
- Risks named by the ideation session, to watch in stage 4: "why is the boss healing?"
  confusion for a first-time player, and a co-op player at range paying for a fight
  they did not choose. The three numbers are the tuning levers; `eatHealFraction = 0`
  switches the heal off while keeping the pressure on the letters.

## Stages

| Stage | Item | Owner | Status |
|---|---|---|---|
| 1 | `BreakableWalls` system: service, constants, client visuals, the two `SkillDelivery` events, suite | build session (Sonnet) | **built 2026-11-13**, suite 7/7 — [[systems/BreakableWalls]]. Real boss fire not yet verified |
| 2 | `BlockSpawner` letter zones: per-volume table, colour and quota, suite | build session (Sonnet) | **built 2026-11-13**, 5 new tests — [[systems/BlockSpawner]] § Letter zones |
| 3 | Greybox the layout in Studio: rim, cover, gates, balconies, vaults, retagged volumes | with the user, after the sketch is approved and 1–2 land | **staged 2026-11-13** beside the old arena (see § Greybox staging); the swap waits on the user's walk-through |
| 4 | Playtest and tune: wall health against a 20-shot volley, letter height, quotas, boss reach to the outer ring | with the user | waiting |
| 7 | Word kits: a spawn volume that holds one ready-made word, re-rolled when its gate re-seals; the cave's reward | build session (Sonnet) | **built 2026-11-13**, 10 tests — [[systems/BlockSpawner]] § Word kits. Cave tagged on the staged island (`WordKit = 5`, `KitGate` / `GateId = CaveRidge`); re-roll seen live with the wall state set by hand, not yet under boss fire |
| 8 | Fossil letters: `FossilTable` on a wall, glyph on crack, freed timed letter on break, suite | build session (Sonnet) | **built 2026-11-13**, 7 tests — [[systems/BlockSpawner]] § Fossil letters. Island rocks tagged (15 `Standard`, 2 `Premium`, 3 `Wildcard`). The fade tell on the freed block is not built; not yet seen under boss fire |
| 9 | Hungry brain: boss eats the nearest letter on a timer and heals, suite | build session (Sonnet) | **built 2026-11-13**, 9 tests — [[systems/Boss]] § Hunger. Never seen on a real Brain: nothing is in reach in the old arena |
| 6 | Arrival beat: timed boss entrance keyed on the first arrival, brief arrival protection, suite | build session (Sonnet) | **built 2026-11-13**, 6 tests — [[systems/Boss]] § Entrance, [[systems/Health]] § Protection. Not yet seen end to end on the island |
| 5 | Arena entry teleporter: `ArenaEntryPad` → `ArenaArrivalPoint`, suite | build session (Sonnet) | **built 2026-11-13**, 5 `entry_*` tests since `EntryLink` — [[systems/ArenaEntry]]. Physical touch verified with a walking character |

Stage 3 is not fanned out. The build plan's rule is that work needing design judgment
is done with the user, and it needs the Studio place, which the two build sessions also
playtest in.

## Greybox staging (2026-11-13)

The user chose to build the island **beside** the old arena and swap only after walking
it. It lives in the place file, not in git, and the place has to be saved to keep it.

- **Where:** `Workspace.Arena.IslandGreybox` (a Model, 259 parts), centred 500 studs +Z
  of the old plaza at X 53.4 / Z 528.2, floor top Y 202.5. The centre is stored on the
  Model as `CenterX` / `FloorY` / `CenterZ`. Built by script through MCP with one undo
  waypoint per pass.
- **Staging arena id:** everything tagged carries `ArenaId = IslandStaging`, so nothing
  joins the shipped `Default` arena. There is no session for that id: letters spawn and
  walls register, but no boss spawns there and a player cannot pop its blocks.
- **Name prefixes:** `Floor_`, `Ridge_`, `Gate_` (regenerating), `Cover_` (breakable),
  `Core_` (permanent), `Cave_`, `Ledge_`, `Zone_` (letter volumes), plus
  `BossPoint_Island`, `ArrivalPoint` and its own `DeathZone`.
- **Counts:** 26 breakable walls (20 cover, 3 ridge gates at `RegenSec` 25, 2 cave
  plugs at 25, the Overhang slab at 15). 17 letter zones, all on quotas, 59 blocks:
  premium 6, standard 5×4, common 5×4, wildcards 7, caves 2×3.
- **Differences from the sketch:** gates sit on ridge segments, so the ways out are at
  71°, 169° and 289°. Ledges step down 4–5 studs below the floor so the ridge lip hides
  their letters from deep inside. Caves grew to 32 x 28 inside so their letters clear
  the walls. Three common-letter zones slid sideways along the outer band to find room
  between cover and ridge. Letter zones are axis-aligned boxes, because the spawner
  reads `Position ± Size/2` and ignores rotation.

Checked in Edit mode by raycast: from the boss spawn the first thing hit toward each
ridge gate and each cave plug is that gate or plug, and toward the arrival pad it is
the permanent rock. No letter zone, grown by a block's half-size, touches solid rock.

Checked in one playtest boot: `IslandStaging` resolved to 61 quota blocks (before the
cave quota dropped from 4 to 3), every block inside its zone, common zones rolled only
common letters, premium rolled `QFV*FF`, wildcard zones only wildcards, 26 walls intact
at 30 health, and the shipped arenas unchanged at 40/5/5/8. That is the first time the
zone attributes were read off real Studio volumes. Three zones logged the one-time
spacing warning; they were resized afterwards and not re-run.

**Temporary walk-through pad (2026-11-13, remove at the swap).**
`Workspace.TEMP_IslandWalkthrough` holds a teal `ArenaEntryPad` in the lobby at
(-715, 203, 28), in front of the spawn pads, and a second `ArenaArrivalPoint` on the
island. Both carry `ArenaId = Lobby`, so a lobby player matches them with no code
change. The player stays in the Lobby session on the island: no boss, no popping. To
get back, reset the character or jump off. Verified in a playtest by walking the
character onto the pad with `Humanoid:MoveTo`: it arrived on the island at full health.
That is also the first physical-touch check of [[systems/ArenaEntry]].

**Not done:** nobody has walked it; no boss has fought on it. The ready room, the entry
pad, the `LobbyReturnPad` move and the bridge removal belong to the swap.

**The swap must give the ready-room pad `ArenaId = Default`**, or the boss entrance
never engages and the boss spawns at once.

**The swap**, once approved: move the Model onto the old centre, retag `IslandStaging`
to `Default` (or strip the attribute), rename `BossPoint_Island` over the old
`BossPoint`, delete the old `Plaza`, bridge and the eight old volumes, place the
`ArenaEntryPad` and return pad in the ready room, and move or seal the ready room.

## After the first walk-through (2026-11-13)

The user walked the staged island and reported two things: the first view on arrival
was the back of the shielding rock, and from player height the level felt crowded and
claustrophobic. Screenshots at player height agreed. The causes were tall, wide rocks
(15–22 studs against a 5-stud character), letters lowered into the gaps between them
(6–18 studs), and a ridge closing the horizon. All three came from asking cover to hide
letters.

The assistant proposed switching the risk from line of sight to a shorter pop reach,
with head-high cover and a low ridge. **The user did not take that.** Decision: cover
does not need to block letters all the time; raise the letters and see how it plays.
Reach stays 200 and the rocks and ridge stay as built for now.

Decided and applied to the staged greybox:

- **Letters higher.** Open-ground zones now sit 18–28 studs above the floor and the
  premium zone 14–22. Cave and ledge zones are unchanged, so those still hide.
- **Overlook arrival.** The shielding rock is gone. `Overlook_Shelf`, a 16-stud-high
  shelf against the east ridge, carries the arrival point; a raycast from eye height on
  it to the boss spot is clear. Dropping off it is the way in and there is no way back
  up.

- **Mixed cover heights** (the user's idea, same day). Height follows role. The five
  inner clusters are all low, 6–8 studs, so the middle stays readable and you can watch
  the boss from behind cover. Each of the five outer clusters keeps one tall piece,
  16–20 studs and at most 12 wide, as a landmark and a place to hide fully; its
  companions are low. That is 5 tall and 23 low pieces, down from 20 tall. Each piece
  carries a `CoverHeight` attribute. Low cover still stops fireballs: the boss fires
  from `ATTACK_ORIGIN_HEIGHT = 2`, close to ground level.

- **Spires, and one cave fewer** (the user, same day). Three of the five tall rocks are
  now spires at 36, 40 and 44 studs (`Cover_06`, `Cover_10`, `Cover_02`,
  `CoverHeight = "spire"`); two of them flank the overlook and frame the arrival view.
  They are still breakable at the default health, which may want raising for something
  that size. The user asked for one of the two caves to go; the assistant removed the
  mid-field hollow boulder and kept the ridge cave, because the boulder was a 40 x 36
  box in open ground and the ridge cave sits against the rim. The island now has 25
  breakable walls and 56 letter blocks.

- **Ridge cave as an outcrop** (the user, same day: the rectangle hid the real shape
  of the level). The box shell stays inside as the sealed chamber, recoloured to the
  ridge's colour, and 21 tilted `Cave_Ridge_Rock` blocks clad it: leaning jambs and a
  lintel at the mouth, flanks, a back that climbs into the ridge, skirts thinning out
  along it and a mound on top. A script pushed any rock clear of the chamber and of the
  lane in front of the plug. Raycasts from the boss spot still reach the plug across its
  whole face. The skirts step up in jumpable heights, so players can probably climb
  onto the mound; not yet tried.

Decided, in build as stage 6:

- **Timed boss entrance.** The countdown starts when the first player arrives for the
  round, and the boss appears `entranceDelaySec` later. It cannot be measured from
  round start: the round goes Active while the first player is still in the ready
  room. (First recorded here as "starts at server boot", which was a misreading of the
  boot log; the build session corrected it.)
- **Brief spawn protection on arrival**, for players re-entering mid-fight.

Still open from this pass: whether raising the letters is enough to fix the crowding,
or whether the rocks and ridge also need to come down.

## Mechanics ideation (2026-11-13)

The user asked for a session to propose level mechanics, interactable objects and
hazards. A read-only Opus session returned twelve ideas. The user's picks:

| Idea | Outcome |
|---|---|
| Fossil letters | **build now** (stage 8) |
| Hungry brain | **build now** (stage 9) |
| Toppling spire, riddle stone | filed in [[ideas]] |
| Boss sheds premium letters on a slam; heavy letters (premium reach 50–60 studs); brain fog; resonant crystal | not picked |
| Scorched ground, crosswind on the Spit, ridge rockfall, crumbling edge | not picked; the session itself advised against them for launch |

Two findings from that session stay open and are **not yet checked in a fight**:

- **The value rings may carry little risk now.** With letters at 18–28 studs and low
  cover at 6–8, the premium patch is probably visible from the rim, about 150 studs
  out and inside the 200-stud reach. Hungry brain adds urgency to those letters but
  does not make a player walk in for them.
- **The premium patch is fixed at the boss's spawn point and the boss walks away from
  it.** Hungry brain only bites while the boss stands near letters.

The session's view, which the assistant shares: the island's geometry is at the limit
of what a first-time player can read on arrival, so new rules on existing objects are
preferable to new props.

## Review copy (2026-11-14)

The user asked for a senior-level-designer review of the island, carried out on a copy
so the staged island stays as the comparison.

- `Workspace.Arena.IslandReview` is a clone of `IslandGreybox`, 700 studs along +X
  (`CenterX = 753.4`, `CenterZ = 528.2`), every `ArenaId` set to `IslandReview`. It has
  its own letter pool (58 blocks), cave word and fossils. Like the staged island it has
  no session, so no boss fights there.
- Lobby pads, side by side under `Workspace.TEMP_IslandWalkthrough`: `TempIslandPad`
  (base island, untouched) and the orange `TempReviewPad` (review copy), told apart
  with `EntryLink` ([[systems/ArenaEntry]]).
- A review session works on the copy only. Its findings and the changes it made are
  recorded here when it reports.

## Senior review of the copy (2026-11-14)

A senior-level-designer session (Opus) reviewed `IslandReview` against the Brain's
numbers and ran four designer sessions in two rounds. `IslandGreybox` is unchanged.
The figures below are the reviewer's calculations from the config and code; none has
been checked in a fight, and the parent session did not re-derive them.

**Its main finding is about the boss, not the level.** The Brain stops walking as soon
as its target is within `attackRange` (100) and fires from there. With a 10 degree
spread the reviewer calculates that 52% of a volley hits a standing player at 30
studs, 17% at 60 and 6% at 100, so a volley at the boss's chosen distance does about 6
damage. With the boss at the centre, the rim, all three ways out, the cave mouth and
the overlook (131 studs) are beyond 100 studs. A player is close to safe anywhere
unless they choose to close in, and geometry cannot change that.

Also found: fireballs leave about 9 studs up, not 2 (`hipHeight` 6 plus the origin
offset), and still dip to torso height, so rocks of 6 studs or more block them. The
boss sphere does not collide with rocks and pathfinds with a thin body. Hunger reaches
about 4 of the 6 premium letters at the drop point and no ordinary letter along the
boss's usual paths.

Changed in the copy:

| Area | Change |
|---|---|
| Ways out | Stone gaps were 9 to 10.3 studs with no way back; a player could be stranded behind a re-sealed gate. Now 7.0 with 1-stud drops, and each exit has a one-way rock stair back in. Jumps tested in a playtest |
| Rim | 45 identical slabs became 34 merged leaning masses; about 45% is a low lip open to the sky. The invisible wall still stops falls |
| Cover | Two even rings of five became 10 formations, 3 standalone rocks and open fields; two "brave" breakable rocks at 35 to 38 studs from the boss point. Floor within 15 studs of cover rose from 41% to 52% |
| Spires | Flattened and leaning, health 60, one moved so they no longer frame the arrival like gateposts |
| Boss spot | A plum dais of radius 22, the slam's reach |
| Cave | Rises into a 30-stud spur on one side and breaks down to the lip on the other |

Recommendations that need code or a decision, **none decided**:

1. Make the boss threaten at its fighting range: a 4 degree spread (calculated 68% at
   60 studs, 35% at 100) or an `attackRange` near 60.
2. Shorter pop reach for premium letters (50 to 60 studs).
3. Lower the letter band where the boss walks to 12 to 20 studs, if hunger should bite.
4. Gates that do not re-seal while a player is beyond them, in place of the stairs.
5. Widen the cave plug to 16 to 18 studs so it opens as fast as a gate.

## Decisions after the senior review (user, 2026-11-14)

| # | Recommendation | Decision |
|---|---|---|
| 1 | Make the boss dangerous at its fighting range | **Tighten the spread.** `FireballVolley.spreadDegrees` 10 to 4 in `BossConfig`. `attackRange` stays 100 |
| 2 | Shorter pop reach for premium letters | **Deferred** to the balancing pass, once there is real play time |
| 3 | Lower the letters so hunger bites | **Replaced by the user's idea: the boss sucks letters to it.** See § Letter pull. **Built 2026-11-14**, 13 tests; not yet watched on a client |
| 4 | Gates do not re-seal while a player is beyond them | **Built 2026-11-14**, 7 tests, and placed on the review copy: `Hold_Stones`, `Hold_Spit`, `Hold_Overhang`, `Hold_CaveRidge`. Seen working live on the Spit. The stairs back in are still there |
| 5 | Widen the cave plug | **Done on the review copy**: `Gate_CaveRidge` 12 to 17 studs wide, jambs narrowed to match; 5 of 5 rays from the boss point at muzzle height hit the plug first |

Known side effect of 1, not yet measured: gates open only when shots miss the player
in front of them, and a tighter spread misses less, so baiting a gate from range will
be slower than the reviewer's "about 3 volleys".

### Letter pull (replaces the hunger reach rule)

The hungry brain could reach almost nothing, because letters float well above it. The
boss now draws a letter to itself, so height stops mattering and the player can see
the meal coming and take it away.

- Every `eatIntervalSec` the living, unfrozen boss with no letter already in tow picks
  the nearest eligible letter within `eatRadius`, measured **horizontally**, and starts
  pulling it. `eatRadius` starts at 60.
- The letter travels toward the boss at `eatPullSpeed` (start 12 studs a second),
  following the boss as it moves, with a visible tether.
- **A letter in tow can still be popped.** The player who pops it gets it and the boss
  goes hungry; the interval starts again.
- When it comes within `eatReach` of the boss (start 8 studs) it is eaten: removed,
  and the boss heals `eatHealFraction` as before.
- One letter at a time. While the boss is frozen the letter hangs where it is. If the
  boss dies or the round ends, a letter in tow is removed.
- However a towed letter ends, its zone refills as after a pop. Word-kit letters and
  freed fossil letters are never pulled.
- Ownership as before: the Boss system decides when and whom; BlockSpawner owns the
  block, including its position while in tow.

### Gate hold zones

A player beyond a gate could be sealed out when it regenerated. The review copy got
stairs back in; the rule below is the cleaner fix and is being tried alongside them.

| Thing | Meaning |
|---|---|
| tag `GateHoldZone` | on an invisible, non-colliding part that covers the ground beyond a gate |
| `GateId` | string on the zone and on the `BreakableWall`; they pair when equal and in the same arena |

A regenerating wall that is due to re-seal waits while a living player's character is
inside any hold zone paired with it, and asks again on the existing retry interval,
exactly as it already waits for a character standing in the wall itself. `GateId` is
the attribute word kits already use, so the cave plug's kit still re-rolls when the
plug finally re-seals.

## Boss fight on the review copy (2026-11-17)

The user asked to playtest the review island with the boss. No code was needed: the
island became a real arena in the place file.

- `IslandReview` carries the `ArenaSlot` tag and `Mode = PvEBoss`, so it gets its own
  session at boot. Its boss point was renamed `BossPoint_Island` to `BossPoint`, the
  name `BossService` looks for.
- `Workspace.Arena.IslandReviewReadyRoom` (360 studs east of the island centre): a
  spawn pad tagged `FFASpawn`, an `ArenaEntryPad` to the overlook, and a
  `LobbyReturnPad`. All `ArenaId = IslandReview`.
- The orange lobby pad `TempReviewPad` is now a `ModePortal` with
  `TargetArenaId = IslandReview`; `TempReviewArrival` was removed. The baseline island
  is unchanged and still has no boss.

First run, driven by the assistant with a scripted character: portal join moved the
player into the session, the entry pad landed them on the overlook, the countdown ran
and the boss dropped in 8.2 s later. In 45 s it put six letters in tow, and a tether
beam was present on the client. A player standing in the open 76 studs out went from
100 health to 0 in 14 s, and one rock cracked.

**Found: the overlook is a permanent safe spot.** The boss never moved while the
player stood there. `PathfindingService` returns `NoPath` from the boss to the
overlook (a shelf 16 studs up with no ramp), and at 131 studs the player is beyond
`attackRange`, so the boss stands in `Patrol` unable to walk or fire. A path to the
open floor computes fine. Not fixed; a decision for the user.

## Level art (2026-11-18)

The user asked for the greybox to be made pretty with level art built from **native
Roblox shapes and built-in materials only**, by a team of artist agents, shown in a
separate space for review. **The greybox is not replaced.** Both islands are untouched.

**Where.** `Workspace.LevelArtShowcase`, centred at (400, 200, 1250): about 700 studs
from the nearest island. Three dark strips, one per kit (`Kit_Rocks`, `Kit_Terrain`,
`Kit_SetPieces`), each asset on a floor sign that names it, the greybox box it stands
for and its part count. It is in the place file, so the place has to be saved to keep
it. Nothing in it carries a CollectionService tag or an `ArenaId`.

**How it is built.** Every asset is generated by a Luau file under
[`src/server/Dev/LevelArt/`](../../src/server/Dev/LevelArt/README.md) and re-running
the file rebuilds it in place, so review feedback is a file edit. The README holds the
conventions and a digest of the rulings below. One asset is one Model whose invisible
`GreyboxRef` (its `PrimaryPart`) is the exact greybox box, so the swap can be
`model:PivotTo(greyboxPart.CFrame)`.

**Theme (the lead artist's, amended by the designer).** A floating rock island: a flat,
dark, calm top of olive turf, worn soil and flagstone; a rough cold slate ridge;
breakable cover of pale warm-grey layered "letter-stone" (it hides the fossil
letters); permanent cores of dark faceted basalt; gates and the cave plug of cut pale
stone with cool light in the joints; a plum rune circle under the boss.

### Senior designer's rulings

A designer session (Opus, read-only) answered ten questions before the artists were
briefed. **[W]** is a decision already in this wiki or the code. **[J]** is the
designer's own judgment: **the user has not confirmed any [J] ruling.**

| Topic | Ruling |
|---|---|
| Island | Build for `IslandReview`. The user's pick between the two islands is still open [W], but every boss fight and the AI playtest run on it |
| Stable | Floor top and outline, the ridge collider ring, the three exits, the cave chamber (32 x 28 x 14), dais radius 22 (it follows Ground Slam), cover heights by role [W] |
| Provisional | Gates and the cave plug (key letters decided 2026-11-17, not built; health may drop to 12); the return stairs (likely to go); the overlook (safe-spot fix not yet seen in a fight); cover counts and positions, spire health, letter heights (stage 4) |
| Collision [J] | The greybox boxes stay the collision **and query** truth. Art is non-colliding with `CanQuery` off: `BlockTapController` raycasts without `RespectCanCollide`, so a queryable banner would block taps |
| Envelope [J] | Visible shape within 1 stud of the box on every side facing the playfield; no collision face left uncovered by more than 1 stud. Tops +0.5 / -1 for low cover and cores, +-2 for tall cover, spires and ridge masses |
| Breakables [J] | The tagged part stays the **visible main body** at the greybox size (the fossil and key glyphs are SurfaceGuis on its broad faces). Decoration is up to 8 BaseParts parented directly under it: `Deco_<n>` takes the damage tint and the fade, `Seam_<n>` fades only. At most 1 stud outside the box, never over the glyph square. **Needs a later change to `BreakableWallVisuals`**, which today writes only the tagged part |
| Colour [J] | Large surfaces S <= 25%, playfield S <= 35%, floor value 30–45%. No surface above S 25% within 15 degrees of a reserved hue: both letter palettes, the spore ring, the boss's orange and violet. Plum is the dais only. Neon only on gate seams and dais runes, strips at most 0.4 wide. Moss only as olive |
| Vetoed [J] | Saturated warm sandstone for breakables (a gold wildcard glyph disappears on it, and the damage tint needs a light base): use a desaturated tan near #9c8a74. Amber gate seams (they clash with wildcard gold, fireballs and spores): use near-white cool light |
| Air space [J] | Nothing in the letter bands (+18 to +28 over open ground, +14 to +22 over the centre, +8 to +30 within 60 studs of the boss's paths), in the lanes from the boss point to each gate and the plug, or in a 40-stud zone above +8 in front of each gate (future key letters). No trees, banners or crystals inside the ridge ring |
| Floor [J] | Walkable collision stays flat [W]. Inlays up to 0.2, tufts and pebbles up to 1.5, none within 24 studs of the centre. No terrain |
| What gets art [J] | `Zone_`, `Hold_`, `Ridge_Collider`, `DeathZone`, `BossPoint`: invisible, no art. Arrival point: a subtle mark. Dais, overlook, underside: art. Ready room: later, it may move; keep the pad footprints |
| Tells [J; key letters W] | Gates and plug say "sealed, but it opens": cut stone unlike the natural ridge, light in the joints, a clear carving face. One silhouette beside each exit, never in the lane: Spit a leaning blade, Stones a cairn of three, Overhang a split boulder. The cave is a dark mouth with leaning jambs and a lintel |

The designer also measured that several greybox names repeat (two `Cover_01`, three
`Cover_10`), so the swap must map by part, not by name.

### What was built (first pass, for the user's review)

Three artist agents (Sonnet), one kit each, two rounds: a first build, then the lead's
notes from screenshots. 36 assets and a vignette, 998 parts in all, every one checked
by script to carry no tag, no `ArenaId` and no collision.

| Kit | Assets |
|---|---|
| `Kit_Rocks` (13) | `Cover_Low_A` / `_B` / `_C`; `Cover_Low_A` again as `_Cracked`, `_Critical` and `_Ghost` (the game's damage tint and fades applied by hand, with test glyphs); `Cover_Tall`; `Spire_A` and `Spire_A_Cracked` (gold star glyph); `Core_A`, `Core_B`; `Gate_Ridge`; `Gate_CavePlug` |
| `Kit_Terrain` (13) | `Floor_Swatch` (with test letters in both palettes); `Ridge_Lip_A` / `_B`; `Ridge_Mass_A` / `_B` / `_Small`; `Ridge_Marker_Spit` / `_Stones` / `_Overhang`; `Ledge_Stones`; `Ledge_Spit`; `Overhang_Slab`; `Island_Underside` |
| `Kit_SetPieces` (10) | `Dais_Boss`; `Overlook_Shelf` (with the arrival mark); `Cave_Outcrop`; `Pad_Entry`, `Pad_Return`, `Pad_Spawn`; `Dressing_Floor`; `Floating_Rock_A` / `_B`; `Rim_Crystals` |
| `Vignette` | A 120 x 120 slice at (400, 200, 1540) assembled from clones: dais, a cover formation, a spire, the gate in the rim with its marker, floating rocks beyond, letters at +22. Stand on the dais and look +Z |

Seen in screenshots by the lead: breakable against core reads at a glance; red, green,
blue and gold letters read against the floor in both palettes; fossil glyphs, including
gold on a spire, stay readable on the stone; the gates read as built stone with light
in the joints; the cave reads as a dark mouth. Nothing was judged in a playtest, under
fight VFX, or from a real player camera.

Known weak points, for the review:

- **Spires and tall cover are plain.** The body must stay the exact greybox box and
  take at most 8 children within 1 stud, so a spire is a box with a broken top.
- **The overlook still reads as a box.** The 1-stud envelope and the no-step rule
  leave little room. A bolder shelf needs one of those relaxed.
- **Envelope not measured.** No asset was checked numerically against the 1-stud rule.
  By the artists' reports the exceptions are: the cave's mound reaches about 9 studs
  beyond its 40 x 36 shell on the sides and back; its leaning jamb tops come about 2
  studs into the 21-wide lane above +14; the three exit markers stand about 10 above
  their mass top against the designer's cap of 3 (the lead accepted this so they read
  from across the arena); the spire's summit is 2.9 above the box against +-2.
- **The ready room has pads only**, as the designer ruled.

### Before the swap

Steps 2 and 3 were done on 2026-11-18: see § The island dressed.

1. The user reviews the dressed island and the [J] rulings above.
2. ~~`BreakableWallVisuals` learns the `Deco_` / `Seam_` children.~~ Done.
3. ~~A swap script maps each greybox part to an asset and pivots a clone onto it.~~
   Done as four dress passes.
4. Lighting was not touched. The place's haze and flat ambient do the art no favours;
   a lighting pass is its own decision.

## The island dressed (2026-11-18)

The user asked for the art to go onto the review island in place of the greybox look,
with the senior designer's agreement before their own review. Done the same day on
`Workspace.Arena.IslandReview` and its ready room. `IslandGreybox`, the baseline, is
untouched. **The user has not reviewed it yet, and the place has to be saved to keep
it.**

**How.** Four dress passes under `src/server/Dev/LevelArt/dress/` (rocks, terrain, set
pieces, and the lead's), run like the kits. No greybox part was moved, resized, renamed,
re-tagged or deleted: all 268 are still the collision, raycast and gameplay truth.

- Non-breakable greybox parts are hidden (transparency 1) under non-colliding art in
  `Workspace.IslandReviewArt`, outside `Workspace.Arena` so no arena scan walks it.
- The 25 breakable walls stay visible as the art's body: re-skinned, with `Deco_` /
  `Seam_` children parented under them.
- The 96 floor wedges are re-skinned and stay visible as the walkable surface.
- Zone, key and boss-point volumes are invisible.
- Every change is recorded on the part (`ArtPass`, `ArtOrig*`), so undressing the four
  passes puts the greybox look back exactly, and re-running a pass rebuilds it. The
  [README](../../src/server/Dev/LevelArt/README.md) § Dressing the island has the
  helpers.

**Code.** `BreakableWallVisuals` now draws a wall's `Deco_` children (damage tint and
every fade) and `Seam_` children (fades only) with the wall, including children that
stream in after it: [[systems/BreakableWalls]] § Client look. That was step 2 of
§ Before the swap.

**What is on the island.** About 1,620 art parts.

| Pass | Covers |
|---|---|
| `Dress_Rocks` | 20 breakable covers across 11 assets (six low, two tall, three spires), 8 cores across three, the three ridge gates (one asset) and the cave plug |
| `Dress_Terrain` | Floor (the `Soil` role with a few dark paving patches), 34 ridge parts across 16 lip and mass assets, three exit markers, the Stones, the Spit as three pieces, the six return blocks, the Overhang slab, a rim strip and the underside |
| `Dress_SetPieces` | Dais, overlook with an arrival plinth, the cave (shell plus its ten cladding rocks one by one), ready-room pads, floor scatter, four floating rocks, four crystal clusters |
| `Dress_Lead` | Hides the working volumes |

**Checked.** By script after a clean re-run of all four: every audit reports no
problems; no art part collides, answers queries, touches, or carries a tag or an
`ArenaId`. In one playtest, on one cover and one gate with `WallState` set from the
server: tint at cracked and critical, everything hidden at broken, seams keeping their
colour, all restored at intact; the console showed nothing new. **Not checked:** real
boss fire on dressed walls, a spire, the Overhang slab or the cave plug changing state,
fight VFX against the art, a real player camera, frame rate.

### Designer's review of the dressed island

The same designer session reviewed it read-only in Studio, measuring for itself.
First verdict: agree with conditions. Two blockers, both fixed and re-measured by the
designer; final verdict: **agree**.

| Blocker | Fix |
|---|---|
| The Spit's drawn floor was 2 to 3 studs off the real floor on the ramp and tip (one asset placed by its middle box, with the ends carried along) | Ramp, mid and tip are three assets, each on its own part; the designer sampled 25 points a segment and found no floor drawn past an edge |
| The arrival mark was cyan neon, 12 degrees from the high-contrast letter green | Pale metal inlay, no neon |

The designer measured and passed: lanes from the boss point to the three gates and the
cave plug clear from +3 to +12, no art in any letter zone, dais radius 22 and the only
plum, cover decoration within 1 stud, breakable body colour and gate seams as ruled.

Rulings the designer changed after seeing them built (its own judgment, **not confirmed
by the user**):

- **Spires and tall cover:** the 1-stud envelope stands up to +12. Above +12 decoration
  may reach 3 studs outside the box, with a top of +3. Up to 12 `Deco_` / `Seam_`
  children. The five tall pieces were rebuilt to this.
- **Exit markers:** up to +11 over the mass top; no part more than 3 studs in front of
  the gate's boss-facing face, none in the gate's central 14 studs.
- **Ridge mass tops:** +-3 instead of +-2.
- **Arrival mark:** "subtle" means no neon and no reserved hue.

Departures the designer accepted: the `Soil` floor in place of turf (the Grass material
renders mint green beside letter green; moss and soil patches were dropped), one asset
for all three ridge gates, the dressed lintel rock over the cave mouth, gate keystones
1.9 above the gate top.

Also done from its non-blocking list: the ridge builders reworked so the rim reads less
like masonry, a paving ring 6 studs outside the dais removed (it blurred Ground Slam's
edge), the Stones' tops off grass, and full decks on the ridge lips, six of which a
player can step onto.

Left open by the review:

- Ring-out edges (the Spit, the Overhang slab) fade into the pale horizon, and the
  lobby and the baseline island show over the low rim: for the lighting pass and the
  swap.
- The ready room's entry ring is orange neon, a hue reserved for the boss: for the
  ready room's real dressing.
- The Stones marker reaches about 1.4 studs into a corner of the Stones key-letter
  volume.
- From the boss's spot the ridge still reads a little stacked.
- To check in a fight: letter colours (blue and the high-contrast green and blue most)
  against the floor and the blue-grey ridge; fireballs and the spore ring against the
  floor and dais; whether new players read the cave as an exit; edges and fossil glyphs
  at distance; frame rate with about 1,800 more parts.

## Pick up here (rewritten 2026-11-14 at the end of the session)

All code is committed. Two islands sit in the place file: `IslandGreybox` (the
baseline) and `IslandReview` (the senior review's copy, plus the wider cave plug and
the gate hold zones). Each has a pad in the lobby. **The place file had unsaved changes
when the session ended**; check both models still exist before assuming they do.

1. **The user walks both islands and picks one.** The review copy is the candidate.
   Nobody but the review session has looked at it. Decide then whether the stairs back
   in stay now that gates hold open.
2. **Watch a letter being pulled, on a client.** Built and tested server-side only:
   the tether, the letter's motion and tapping it in flight have never been seen. No
   boss spawns on either island, so this needs the swap or a boss in the old arena
   with a letter within 60 studs.
3. **The swap** (§ Greybox staging lists the steps; apply them to whichever island was
   picked, and delete the other and `TEMP_IslandWalkthrough`). Until then nothing has
   been seen under real boss fire: walls breaking, gates re-sealing and holding, the
   cave word, fossil glyphs and freed letters, the boss entrance, the letter pull, the
   4 degree spread.
4. **First real fight, then tune (stage 4).** The spread's effect on hit rate and on
   how fast gates can be baited open; wall and spire health; pull radius, speed and
   heal; letter height; quotas; glyph size; whether the cave word should always buy a
   top-tier cast. Deferred to this pass by the user: a shorter pop reach for premium
   letters.
5. **Small follow-ups:** a fade on a freed fossil letter (`FossilExpiresAt` is
   published for it); `boss-arena-review-layout.html` is a snapshot and must be
   regenerated from Studio if the level changes; the `NPC_deals_damage` test fails
   intermittently; the possible code issues the wiki reconcile listed in [[log]]
   (2026-11-14) are unexamined; no full 102-test run since the last `isTowed` fix.

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
