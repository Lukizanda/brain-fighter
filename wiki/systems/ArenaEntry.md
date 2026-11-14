---
type: system
description: One-way teleporter from an arena's ready room onto its island (Phase 8 stage 5, 2026-11-13). A player of the pad's arena who touches a part tagged ArenaEntryPad is moved onto a random ArenaArrivalPoint of the same ArenaId. Nothing leads back; dying respawns the player in the ready room. Server-owned, cues through VfxBroadcast. 5 tests; the physical Touched signal and the client cues are not yet verified, and no pad exists in the place yet.
updated: 2026-11-14
---

# ArenaEntry

The way into the boss arena once the bridge is removed. Decided in
[[design/boss-arena]] § Entry: players teleport in and cannot walk back to the ready
room, so the only ways off the island are dying or quitting.

No pad or arrival point exists in the place yet. Placing them, removing the bridge and
moving the `LobbyReturnPad` into the ready room are Phase 8 stage 3.

## Files

| File | Purpose |
|---|---|
| `src/shared/Arena/ArenaEntryConstants.luau` | Tags, cooldown, standing offset, cue ids, result strings |
| `src/server/Arena/ArenaEntryService.luau` | The service, a ModuleScript so tests can drive `handleTouch`. `enable()` / `disable()` / `destroy()` |
| `src/server/Arena/ArenaEntryBoot.server.luau` | Enables it and binds `destroy` to close |
| `src/shared/Tests/Suites/Arena/entry_*.luau`, `Tests/Helpers/arenaEntryFixture.luau` | Tests and fixture |

## Authoring

- Tag a `BasePart` in the ready room **`ArenaEntryPad`**.
- Tag one or more `BasePart`s on the island **`ArenaArrivalPoint`**.
- Pad and arrival match by `ArenaId` (absent means `Default`). The player lands standing
  on top of the arrival part, facing the way the part faces. With several arrival points
  one is picked at random.

## Several routes in one arena (`EntryLink`, 2026-11-14)

A pad and its arrival points may carry an optional string attribute **`EntryLink`**.
A pad with a link reaches only arrival points with the same link; a pad without one
reaches only arrival points without one. A blank value counts as none.

It exists because pad and arrival match by `ArenaId`, and the pad's `ArenaId` must be
the arena the player's session is in. Two pads in the lobby, each meant for a
different island, are therefore both `Lobby` pads and would otherwise each pick at
random between both islands' arrival points. The temporary pad to the designers' review
copy of the boss island uses `EntryLink = IslandReview`
([[design/boss-arena]] § Review copy).

Verified 2026-11-14: `entry_link_routes` in a 26/26 Arena run, and a character walked
onto each lobby pad and landed on the right island.

## Rules

| Touch by | Result |
|---|---|
| Not a player's character | Ignored |
| A dead character | Ignored |
| A player whose session is in another arena, or who has no session | Refused |
| The same player within `COOLDOWN_SEC` (2 s) | Ignored, so one touch is one teleport |
| A pad with no matching arrival point | Warns once naming the pad, does nothing |

**Which arena a player is in** is `SessionRegistry.forPlayer(player):getArenaId()`, the
registry [[systems/BlockShoot]] also reads. It deliberately does not use BlockShoot's
`arenaIdFor` helper, which falls back to `Default` for a player with no session and
would let such a player use a `Default` pad.

Cues are `impact_shield` on departure and `impact_buff` on arrival, sent with
`VfxBroadcast.playAt`. They are stand-ins reused from spells.

## Arrival signal (stage 6, 2026-11-13)

After a successful teleport the service fires the server-side BindableEvent
`shared/Arena/ArenaEvents/PlayerEntered(player, arenaId)`. It only announces. Two
listeners today: `BossService` starts the boss entrance on the first arrival of a round
([[systems/Boss]] § Entrance), and `HealthService` opens a 2 s protection window
([[systems/Health]] § Protection).

`ArenaEntryService.hasPadFor(arenaId)` answers whether an arena's players enter by
teleporter. `BossService` asks it to decide whether to hold the boss for an arrival.

**At the swap the real ready-room pad must carry `ArenaId = Default`.** Until a pad
with that id exists, `Default` stays an immediate-spawn arena.

## Verification (2026-11-13)

`RunTests=all` gave 58/58. The three tests cover matching by arena id, the no-arrival
warning, and a real character being moved by `handleTouch`, including the wrong-arena
refusal and the cooldown.

Not verified:

- ~~The physical `Touched` signal from a walking character.~~ Checked later the same
  day: a character walked onto the temporary lobby pad with `Humanoid:MoveTo` and was
  teleported to the island ([[design/boss-arena]] § Greybox staging).
- A client drawing the two cues.
- The service's own boot lines: the console output was truncated at the top in that
  playtest, though no errors appeared in what remained.

## See also

- [[design/boss-arena]] — the decision and the greybox consequences
- [[systems/GameMode]] — sessions and where a player spawns and respawns
- [[systems/Lobby]] — the portals that bring a player to the ready room and back
