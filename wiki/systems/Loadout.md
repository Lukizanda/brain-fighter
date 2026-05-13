---
type: system
description: Loadout system — Normal/Special slot model, RespawnPedestalManager, drop remote, cooldown overlay. Team-aware spawn paths currently gated off.
updated: 2026-05-13
---

# Loadout System

Players pick weapons from pedestals in the spawn room, carry up to 2 Normal weapons + 1 Special, and can drop their currently-equipped Tool to swap. Reserves reset per life (no carry hoarding).

## Team-aware spawn gate (2026-05-13)

With `GameConfig.TEAMS_ENABLED = false`, `SpawnManager.filterSpawnsForPlayer` short-circuits before reading per-team SpawnLocation TeamColor / Team-attribute filters, so every player draws from the full neutral spawn pool. `RespawnZoneService` is unchanged but naturally degrades: callers pass `player.Team` (now nil), and the zone filter treats nil as "match every zone", giving a single unified respawn zone. Re-enable by flipping `TEAMS_ENABLED`.

## Slot model

| Slot | Cap | Notes |
|---|---|---|
| Normal | 2 simultaneous | Pickup-order prune: dropping an old one when picking up a new third. |
| Special | 1, with claim uniqueness | Only one player on a team can claim a given Special at a time. Cooldowns enforced via `_cooldownEnd` attribute. |
| Melee | (typically 1) | Same Tool slot system; uses `WeaponSlot` attribute on the Tool. |

`WeaponCategory` attribute on each Tool gates which slot rules apply. See `src/shared/Weapon/WeaponConstants.luau`.

## Active contracts

- **`LoadoutRequestDrop`** RemoteEvent — `ReplicatedStorage.Shared.Loadout.Remotes.LoadoutRequestDrop`. Client fires (no args), server destroys equipped Tool. Special claims + Normal pickup-order prune via `AncestryChanged`.
- **`_cooldownEnd`** attribute on Special Tools — set to `workspace:GetServerTimeNow() + seconds`. WeaponRolodex special card overlay reads this on Heartbeat. Constant: `WeaponConstants.COOLDOWN_END_ATTRIBUTE`.

## RespawnPedestalManager

Server scans `Workspace` for BaseParts named `RespawnPedestal` at boot. Reads `WeaponName`, `Team`, `SpawnerMesh`, `RespawnAfterClaim` attributes. Spawns the matching template above each pedestal (floor + 1 stud, chest height). On pickup (Tool.AncestryChanged out of Workspace), waits 3s and re-clones.

Editor labels (`Label` BillboardGui) on pedestals are hidden at runtime so they only show in Studio edit view.

## Open work

Notably:
- **`RespawnZoneService`** not built — needed to gate drop UX on "player is in their respawn zone".
- **Drop UX** — drop key binding + zone-gated client validation.

## Cross-references

- Per-weapon templates → [[systems/Weapon]]
- Ammo behavior on pickup → `Ammo.performReload` and `PickupStacker` (see project memory `feedback_backpack_lifecycle.md` for the latent bug)
