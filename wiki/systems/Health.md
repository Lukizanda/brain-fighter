---
type: system
description: Damage pipeline — DamageTypes, hit zones, modifiers, HealthService.applyDamage, DeathHandler, friendly-fire block. PvP currently gated off.
updated: 2026-05-13
---

# Health System

Damage flows through `HealthService.applyDamage` server-side. All damage callers (firearms, melee, death zone) go through this single entry point so modifiers, friendly-fire rules, and death tracking apply uniformly.

## PvP gate (2026-05-13)

Player-on-player damage is currently disabled at two layers:

- `applyDamage.process` — early-returns `nil` when `GameConfig.PLAYER_VS_PLAYER_ENABLED` is false and both source and target are Players (and not the same Player). Self-damage (fall, environment), NPC-on-player, and player-on-NPC continue unaffected.
- `canPlayerDamageHumanoid` — shot-validation predicate also rejects when the target is a Player and PvP is off. Used by `Blaster/validateTag` so projectile validation matches the server-side authority.

Flip `GameConfig.PLAYER_VS_PLAYER_ENABLED = true` to restore. The friendly-fire branch below remains in place and resumes its role once PvP is on.

## Files

- `src/shared/Health/DamageTypes.luau` — type definitions (DamageInfo, DamageType enum, etc.)
- `src/shared/Health/DamageModifierRegistry.luau` — pluggable damage modifiers
- `src/shared/Health/HealthConstants.luau` — magic-number-free constants
- `src/shared/Health/getHitZone.luau` — head/torso/limb classification from hit position
- `src/shared/Weapon/Scripts/Utility/canPlayerDamageHumanoid.luau` — friendly-fire / valid-target gate
- `src/server/Health/Scripts/HealthService/init.server.luau` — `applyDamage.process(...)`
- `src/server/Health/Scripts/DeathHandler.server.luau` — death cleanup, kill credit, `DeathScreenGui` trigger

## Friendly fire (TDM)

Implemented in `applyDamage.process` — when source and target are on the same `Player.Team`, damage is silently dropped with a diagnostic log.

## Hit zones

`getHitZone` classifies the hit `Vector3` against the target's R15 rig and returns a multiplier (head > torso > limb). Multipliers live in `HealthConstants`.

## Death pipeline

1. `applyDamage.process` reduces Humanoid health to ≤ 0.
2. Roblox fires `Humanoid.Died`.
3. `DeathHandler` reads kill credit attribution, fires kill-feed remote, triggers respawn timer.
4. `RoundManager` (via [[systems/GameMode]]) handles the actual respawn.

## Cross-references

- Friendly fire team logic → [[systems/GameMode]] (TeamService)
- Damage callers → [[systems/Weapon]]
- Death zone (falls) → `src/server/Arena/DeathZoneService.server.luau`
