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

## Inventory tracking gotchas

These are Roblox engine behaviors that have bitten `LoadoutService` and `PickupStacker` — all four are now handled canonically in those files.

### Backpack.ChildAdded fires on every equip-swap, not just fresh pickups

`Humanoid:EquipTool(other)` is implemented as an atomic unequip-then-equip pair. The previously-equipped tool moves Character → Backpack, firing `Backpack.ChildAdded` for it. **Any handler wired to `Backpack.ChildAdded` must be idempotent** — if the same Tool instance is already registered, early-return. Use `table.find(order, tool)` or `map[tool]`. Non-idempotent handlers re-register the unequipped tool as a fresh pickup, triggering cap-eviction or duplicate-claim destruction on every Tab-cycle. Symptom: "weapons disappear when I cycle them."

### Pedestal pickups bypass Backpack.ChildAdded entirely

When a Tool sits in Workspace and a player's character touches it, Roblox auto-parents the Tool **directly to Character** — `Backpack.ChildAdded` never fires. Any server-side inventory tracking must hook **both** `Backpack.ChildAdded` and `Character.ChildAdded`. The handler should be idempotent so the duplicate fire from the swap path is a no-op. Single-player testing with `tool.Parent = backpack` dev scripts exercises only the Backpack path and masks this.

### Player.Backpack is replaced on character load

`Player.Backpack` is destroyed and recreated when the character spawns. Any `backpack.ChildAdded:Connect(...)` made at `PlayerAdded` time binds to the original container, which then gets destroyed, silently disconnecting the signal. **Re-hook `Backpack.ChildAdded` on every `CharacterAdded`**, plus use a `{ [Backpack]: true }` dedup set so repeat hooks on the same container are no-ops. See `hookBackpack` + `watchPlayer` pattern in `LoadoutService.server.luau` and `PickupStacker.server.luau`.

### Client-side AncestryChanged sees a nil-parent intermediate during equip swaps

On the **client**, replicated parent changes for `EquipTool` arrive in two stages — the tool passes through `Parent = nil` between Character and Backpack. `AncestryChanged` fires for each stage, so a handler that immediately checks `tool.Parent` against an expected set can false-positive on the nil intermediate and treat a normal equip-swap as a "drop." Fix: wrap the parent check in `task.defer(function() ... end)` so it runs after the frame's ancestry transitions settle. **Server-side AncestryChanged does NOT exhibit this race** — synchronous parent checks are safe there.

## Cross-references

- Per-weapon templates → [[systems/Weapon]]
- Ammo behavior on pickup → `Ammo.performReload` and `PickupStacker`
- Loadout regression tests → `src/shared/Tests/Suites/Multiplayer/pickupstacker_survives_respawn.luau`
