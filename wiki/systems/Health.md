---
type: system
description: Damage pipeline — one path. applyDamage.process / applyDamage.heal are the only Humanoid.Health writers; spells reach them through the DamageSink HealthService injects into SkillEffects; every request carries a cause id the kill feed credits; PvP is allowsPvP on the victim's mode, resolved through their session.
updated: 2026-09-08
---

# Health System

Damage flows through `HealthService.applyDamage` server-side. **It is the only thing that writes `Humanoid.Health`** outside spawn-init (`HealthService.initializeCharacterHealth` / `initializeDamageable`, `BossSpawner`). Every caller — player spells, boss skills, NPC melee, the death zone — goes through this one entry point so modifiers, the PvP gate, damage feedback, kill credit and respawn bookkeeping apply uniformly.

## One damage path (2026-09-08)

Refactor chunk 4 ([[design/refactor-plan-2026-09]]; audit findings F1, F2, F34) closed the split-brain the Skills pipeline had carried since 5.1: player spells used to write `Humanoid.Health` directly, so a spell kill never fired `PlayerEliminated`, never reached the kill feed or `DeathHandler`, never sent `DamageFeedback`, and ignored the PvP gate.

- **`DamageTypes.DamageSink`** — `{ process(DamageRequest) → DamageResult?, heal(HealRequest) → HealResult? }`. `applyDamage` implements it. `HealthService/init.server.luau` hands it to `SkillEffects.setDamageSink(applyDamage)` at server start. There is no client implementation, deliberately: the client's predicted run has nowhere to put damage, so the `damage`/`heal` handlers refuse (`ok=false, "no damage sink on this VM"`) instead of writing. The old upward `pcall(require)` from ReplicatedStorage into ServerScriptService is gone, and so is `EffectSpec.useApplyDamage` — every spec takes the same path.
- **`applyDamage.heal`** — the heal half. Skips the modifier chain (a shield must not "absorb" a heal), fires no damage events, sends no feedback. It exists only so that Health has exactly one writer.
- **`cause: string?`** on `DamageRequest`, carried onto `DamageResult`. What dealt the damage: the skill name (`SkillDelivery.applyImpactEffects` passes `skill.name` through `SkillEffects.apply(spec, target, source, cause)`), a `DamageTypes.Cause` id (`death_zone`), or a weapon name. `GameModeService.onPlayerEliminated` credits `result.cause` to the kill feed. This replaced reading the attacker's equipped Tool, which was why every entry said "Unknown" — the Spelling Staff cast every spell.
- **`sourcePlayer`** is resolved in `SkillEffects` from the delivery `source` (a player character Model → its Player; a boss or NPC → nil). That is what drives the PvP gate, the attacker's hitmarker (`DamageConfirm`) and kill credit.
- **Shield drains once.** Damage that reaches the body drains the `_shield` pool in `DamageModifierRegistry.shieldModifier` only. `SkillBuffs.consumeShield` is the shell-deflection charge — a projectile destroyed at the bubble never reaches an effect handler, so it can never also be charged here. Pinned by `Skills/__tests` scenario 8 (25 into a 40 pool through `SkillEffects.apply` → Health untouched, pool 15).

## Callers

| Caller | `sourcePlayer` | `cause` |
|---|---|---|
| Player spells (`SpellCastService` → `SpellExecutor` → `SkillDelivery` → `SkillEffects`) | the caster | skill name (`Firebolt`, `Inferno`, …) |
| Boss skills (`BossStates` → `SkillDelivery` → `SkillEffects`) | nil | skill name (`GroundSlam`, `FireballVolley`) |
| `DeathZoneService` | nil | `death_zone` (`HealthConstants.INSTANT_KILL_DAMAGE`, so it kills through any shield or armor) |
| NPC melee (`MeleeHitDetector`) | nil | none yet — an NPC kill still reads "Unknown"; noted under chunk 9 of the refactor plan |

## PvP gate (2026-09-08)

Whether player A may damage player B is a property of **the mode B is playing under**, not a server-wide flag:

- `GameModeDefinition.getConfig().allowsPvP: boolean?` — absent means false. `LobbyMode` and `NoOpMode` set it false; a duel mode sets it true.
- `GameModeService` answers the `ServerScriptService.Server.GameMode.Events.AllowsPvP` BindableFunction from the victim's session (`modeForPlayer(victim)`). It binds `OnInvoke` at file scope, before anything yields, because a BindableFunction with no handler makes its caller yield forever.
- `HealthService` injects `allowsPvPFor(victim)` into `applyDamage.initialize`; `applyDamage.process` drops player-on-player damage when it returns false. Self-damage, NPC-on-player and player-on-NPC are never gated.

`GameConfig.PLAYER_VS_PLAYER_ENABLED` was deleted with this; the remaining global round flags move to mode config in chunk 8. See [[design/lobby]] § PvP gate.

## Files

- `src/shared/Health/DamageTypes.luau` — `DamageRequest`/`DamageResult` (with `cause`), `HealRequest`/`HealResult`, `DamageSink`, the `DamageType`, `HitZone` and `Cause` enums
- `src/shared/Health/DamageModifierRegistry.luau` — pluggable damage modifiers (headshot, armor, shield)
- `src/shared/Health/HealthConstants.luau` — magic-number-free constants (incl. `INSTANT_KILL_DAMAGE`)
- `src/shared/Health/getHitZone.luau` — head/torso/limb classification from hit position
- `src/server/Health/Scripts/HealthService/init.server.luau` — spawn-init health, respawn gate, wires `applyDamage` and injects it into `SkillEffects`
- `src/server/Health/Scripts/HealthService/applyDamage.luau` — `process(...)` and `heal(...)`, the only `Health` writers
- `src/server/Health/Scripts/DeathHandler.server.luau` — Damageable death cleanup + respawn
- `src/server/Arena/DeathZoneService.server.luau` — lethal fall volumes, through `applyDamage` with `cause = death_zone`
- `src/StarterCharacterScripts/Health.client.luau` — no-op override of Roblox's built-in client health-regen script (see below)

## Client-side regen suppression (2026-07-14)

`HealthService` has no regen logic — health is server-authoritative and only changes via `applyDamage`/respawn. Roblox auto-inserts its own default "Health" LocalScript into every character (from `StarterPlayer.StarterCharacterScripts`) that passively regenerates health over time; left unchecked this fights the server-authoritative model. A no-op `Health.client.luau` at `src/StarterCharacterScripts/` occupies that same name so Roblox's own regen script is never inserted (Roblox only auto-populates a default script when one of that name isn't already present).

**Rojo placement gotcha:** `StarterCharacterScripts` is not a root-level DataModel service — it only exists nested at `StarterPlayer.StarterCharacterScripts`. A `default.project.json` entry for `"StarterCharacterScripts"` as a sibling of `"StarterPlayer"` at the tree root silently fails to sync (no error, no red delete — Rojo just has nowhere valid to put it). It must be nested inside the `"StarterPlayer"` block alongside `"StarterPlayerScripts"`. Caught by a live playtest verification (character's `Health` object was still Roblox's default `Script`, not our `LocalScript`) before this shipped — see [[concepts/RojoJsonValidator]] for the class of Rojo silent-fail traps this belongs to.

## Friendly fire (TDM)

Implemented in `applyDamage.process` — when source and target are on the same `Player.Team`, damage is silently dropped with a diagnostic log.

## Hit zones

`getHitZone` classifies the hit `Vector3` against the target's R15 rig and returns a multiplier (head > torso > limb). Multipliers live in `HealthConstants`.

## Death pipeline

1. `applyDamage.process` reduces Humanoid health to ≤ 0 and fires `PlayerEliminated(sourcePlayer, humanoid, result)`.
2. `GameModeService.onPlayerEliminated` (player victims) credits `result.cause` to the kill feed via `ScoreTracker.recordKill`; `DeathHandler.handleDeath` (Damageable rigs) runs the explode-and-respawn cycle.
3. Roblox fires `Humanoid.Died`; the Skills registries purge their per-Humanoid state.
4. `GameModeService` handles the actual player respawn — see § Respawn.

## Respawn (2026-09-08)

**This system does not respawn players.** Chunk 5 of the 2026-09 refactor
([[design/refactor-plan-2026-09]]) collapsed three player-respawn paths into one:

| Path | Was | Now |
|---|---|---|
| `Players.CharacterAutoLoads` | never set (engine spawned on join) | `false`, set first thing in `GameModeService.initialize` |
| `HealthService` `RequestRespawn` remote | client could ask for a `LoadCharacter` | **deleted**, remote and `.meta.json` with it |
| `GameModeService` `Humanoid.Died` handler | one of three | the only one |

`grep -rn LoadCharacter src/server` hits `GameModeService/init.server.luau` and
nothing else. The reason it is the owner rather than this system: respawn needs
the player's session, because the session picks both the delay (the mode's
`respawnTime`) and the pad (`SpawnManager.getBestSpawn` in that session's arena).
`HealthService` knows about Humanoids, not sessions.

Consequences worth knowing:

- `pendingRespawns` is gone from `HealthService` and from `applyDamage`'s refs.
  It was written on lethal damage and cleared only inside the remote handler, so
  after an auto-respawn a later `RequestRespawn` reloaded a *living* character.
  `applyDamage` now announces the kill and schedules nothing.
- The `pendingRespawns` in `DeathHandler.server.luau` is a different table for
  non-player rigs and is untouched.
- `HealthConstants.RESPAWN_TIME` was renamed **`NPC_RESPAWN_TIME`** (still 5). It
  is the default `respawnTime` attribute for a Damageable rig and is read only by
  `HealthService.initializeDamageable` and `DeathHandler`. The player number is
  `GameModeConstants.RESPAWN_TIME` (4), broadcast in `GameStateChanged`.
- `DeathScreenGui` is display-only: countdown, then "Respawning...". The manual
  respawn button went with the remote.

## Cross-references

- Damage callers → see § Callers above; the spell side is [[systems/SkillPipeline]] § Damage paths. (The former firearm/TeamService friendly-fire path was deleted with the TPS stack in commit `6610291`.)
- Kill feed rendering → `KillFeedGui` prints `[<cause>]` between killer and victim; env kills (no `sourcePlayer`) print the cause alone.
