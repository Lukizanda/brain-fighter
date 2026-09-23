---
type: system
description: Damage pipeline — one path. applyDamage.process / applyDamage.heal are the only Humanoid.Health writers; spells reach them through the DamageSink HealthService injects into SkillEffects; every request carries a cause id the kill feed credits; PvP is allowsPvP on the victim's mode, resolved through their session.
updated: 2026-09-22
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
| NPC melee | — | **removed** in chunk 11; `Actions.MeleeAttack` and the `MeleeHitDetector` modules are deleted, and no archetype ever called them. NPC shots carry `cause = <Archetype>` (chunk 9) |

## PvP gate (2026-09-08)

Whether player A may damage player B is a property of **the mode B is playing under**, not a server-wide flag:

- `GameModeDefinition.getConfig().allowsPvP: boolean?` — absent means false. `LobbyMode` and `NoOpMode` set it false; a duel mode sets it true.
- `SessionRegistry.allowsPvPFor(victim)` (a module `HealthService` requires) answers from the victim's session; a player with no session yet gets false. The `AllowsPvP` BindableFunction chunk 4 introduced was deleted in chunk 8 — an unbound BindableFunction makes its caller yield forever, which a module call cannot.
- `HealthService` injects `SessionRegistry.allowsPvPFor` into `applyDamage.initialize` as `allowsPvPFor`; `applyDamage.process` drops player-on-player damage when it returns false. Self-damage, NPC-on-player and player-on-NPC are never gated.

`GameConfig.PLAYER_VS_PLAYER_ENABLED` was deleted with this (chunk 4); `TEAMS_ENABLED` and the round flags went in chunk 8. This gate is the only player-vs-player filter left in `applyDamage` — the team friendly-fire branch is gone with the teams. See [[design/lobby]] § PvP gate.

## Round-start heal (2026-09-19)

`HealthService` listens to the GameMode `RoundStarted(roster, arenaId)` Bindable and heals every living roster member to `MaxHealth` through `applyDamage.heal` with cause `DamageTypes.Cause.RoundStart` (`"round_start"`), logging `[arena] Round start — N of M roster members healed to full` when anyone needed it. Phase 6 stage 6, user decision: a duellist arriving at 30 HP from a previous round would fight at a disadvantage nobody chose, and a boss party deserves the same start — so it applies to every mode, not just duels. Dead members are skipped; the respawn owner (GameModeService) is about to hand them a fresh body. `Humanoid.Health` still has exactly one writer.

## Files

- `src/shared/Health/DamageTypes.luau` — `DamageRequest`/`DamageResult` (with `cause`), `HealRequest`/`HealResult`, `DamageSink`, the `DamageType`, `HitZone` and `Cause` enums
- `src/shared/Health/DamageModifierRegistry.luau` — pluggable damage modifiers (headshot, armor, shield)
- `src/shared/Health/HealthConstants.luau` — magic-number-free constants (incl. `INSTANT_KILL_DAMAGE`)
- `src/shared/Health/getHitZone.luau` — head/torso/limb classification from hit position
- `src/server/Health/Scripts/HealthService/init.server.luau` — spawn-init health, round-start heal, wires `applyDamage` and injects it into `SkillEffects`
- `src/server/Health/Scripts/HealthService/applyDamage.luau` — `process(...)` and `heal(...)`, the only `Health` writers
- `src/server/Health/Scripts/DeathHandler.server.luau` — Damageable death cleanup + respawn
- `src/shared/Hud/NameplateBuilder.luau` / `NameplateConfig.luau` — the over-head plate: name, health bar, damage numbers
- `src/client/UI/NameplateGui.client.luau` — finds the combatants, binds `Humanoid.Health`, pops the damage numbers
- `src/server/Arena/DeathZoneService.server.luau` — lethal fall volumes, through `applyDamage` with `cause = death_zone`
- `src/StarterCharacterScripts/Health.client.luau` — no-op override of Roblox's built-in client health-regen script (see below)

## Client-side regen suppression (2026-07-14)

`HealthService` has no regen logic — health is server-authoritative and only changes via `applyDamage`/respawn. Roblox auto-inserts its own default "Health" LocalScript into every character (from `StarterPlayer.StarterCharacterScripts`) that passively regenerates health over time; left unchecked this fights the server-authoritative model. A no-op `Health.client.luau` at `src/StarterCharacterScripts/` occupies that same name so Roblox's own regen script is never inserted (Roblox only auto-populates a default script when one of that name isn't already present).

**Rojo placement gotcha:** `StarterCharacterScripts` is not a root-level DataModel service — it only exists nested at `StarterPlayer.StarterCharacterScripts`. A `default.project.json` entry for `"StarterCharacterScripts"` as a sibling of `"StarterPlayer"` at the tree root silently fails to sync (no error, no red delete — Rojo just has nowhere valid to put it). It must be nested inside the `"StarterPlayer"` block alongside `"StarterPlayerScripts"`. Caught by a live playtest verification (character's `Health` object was still Roblox's default `Script`, not our `LocalScript`) before this shipped — see [[concepts/RojoJsonValidator]] for the class of Rojo silent-fail traps this belongs to.

## Hit zones

`getHitZone` classifies the hit `Vector3` against the target's R15 rig and returns a multiplier (head > torso > limb). Multipliers live in `HealthConstants`.

## Death pipeline

1. `applyDamage.process` reduces Humanoid health to ≤ 0 and fires `PlayerEliminated(sourcePlayer, humanoid, result)`.
2. `GameModeService.onPlayerEliminated` (player victims) credits `result.cause` to the kill feed via `ScoreTracker.recordKill`; `DeathHandler.handleDeath` (Damageable rigs) runs the explode-and-respawn cycle.
3. Roblox fires `Humanoid.Died`; the Skills registries purge their per-Humanoid state.
4. `GameModeService` handles the actual player respawn — see § Respawn.

## Nameplates (2026-09-22)

Every combatant the local player can look at carries a **nameplate** — a name
line, a health bar showing a fraction, and a damage number that pops every time
the health moves. Two kinds of combatant get one:

| Combatant | Found by | Name shown |
|---|---|---|
| Another player | `Players` + `CharacterAdded` | `player.Name` |
| A training dummy | the `TrainingDummy` tag (`HealthConstants.TRAINING_DUMMY_TAG`) | the `NameplateLabel` attribute, else the model name |

The local player gets none — they have the HUD health bar.

**The dummy and a real opponent share one builder on purpose.** The hub dummy
is the only safe place to learn what an attack spell is worth, so it has to
teach the display a real opponent will show; a dummy with its own bespoke
readout would be teaching the wrong lesson. That shared path is the feature,
not a convenience — if the two ever diverge, the tutorial is lying.

`TrainingDummy` stays separate from `Damageable` because `Damageable` means
"can be hurt", which is every NPC in the game, and none of those want a bar
over their head. The hub's `Workspace.Lobby.TargetDummy` is the only rig
carrying it.

**No remote in the read path.** `Humanoid.Health` already replicates, so the
delta between two replicated values *is* the damage — the same number
`applyDamage` computed, without a second wire to keep in step. The consequence
is that two hits landing inside one replication batch arrive as a single change
and read as one combined number; for a practice target that is the honest
total, and a damage-over-time spell still shows its individual ticks.

Damage is a **fraction of the target's max HP** (`fractionOfMaxHP` — Firebolt
5%, Fireball 20%, Inferno 50%), so the number is only meaningful against the
target's max. The dummy has no `maxHealth` attribute, which lands it on
`DEFAULT_MAX_HEALTH` — the same 100 a player gets — so what you read off the
dummy is exactly what a player would take.

**The plate is sized in studs, so it stays proportionate to its rig, and no
code runs per frame to make that happen.** The route here was not obvious and
is worth not re-walking:

1. A draft rescaled the plate every frame to cancel an assumed distance
   falloff. Measured instead: a `BillboardGui` sized in `Offset` holds a fixed
   *pixel* size at any distance — the same 220 px plate spans an identical
   width at 20 studs and at 70. The compensation would have made it *grow* as
   you backed away, so it was deleted.
2. Fixed pixel size then turned out to be the actual bug. From the lobby spawn,
   137 studs from the dummy, a 220 px plate is a banner over a rig the size of
   a thumbnail — it covered the dummy and the portal signs behind it.
3. Sizing the plate in **studs** (the `Scale` half of `Size`) is the fix: the
   engine shrinks it with its rig, so it reads as part of the character at
   every range. Everything inside it is in `Scale` too — a 6 px corner radius
   is meaningless against a canvas that is ~17 x 2.4 units at range.

The bar carries no `current / max` text. It was unreadable at any range worth
reading a health bar at, and the floating damage number already says what a hit
was worth — which is the number a player actually wants. The bar is left to do
the one job it does well from a distance: show a fraction.

**The engine is the third owner of the space over a head.** A `Humanoid` draws
its own name and, once damaged, its own health bar — so the dummy showed two
bars and two names (`Humanoid.DisplayName` = "Practice Dummy" against the
plate's "Training Dummy"). It hid during development because
`HealthDisplayType` defaults to `DisplayWhenDamaged`, and an undamaged dummy
reads 100/100. `attach` sets `DisplayDistanceType = None` per rig, which covers
the name and the bar together; turning off `HealthDisplayType` alone would
leave the engine's name behind.

`AbsoluteSize` is a trap in this investigation. For an `Offset`-sized billboard
it reports the billboard's own canvas and equals `Size.Offset` at every
distance, saying nothing about screen pixels. For a `Scale`-sized one it does
track the projected size (168 px at 14 studs, 17 px at 137).

**Death is not special-cased.** A dummy explodes through the normal
`DeathHandler` path and respawns as a fresh clone, which arrives through the
same tag signal as the original and gets a new plate. Its `respawnTime`
attribute is authored at **1s** rather than the `NPC_RESPAWN_TIME` default of
5, so the new dummy stands up while the old one's debris is still in the air
(fragments live `FRAGMENT_LIFETIME` = 3s).

### Verification status (2026-09-22)

Proven on the dummy, and on a player rig by temporarily tagging the local
player's character — which exercises `attach` against a real R15 character
(accessories, Tool, animate script) and confirmed exactly one `BillboardGui`
on the head.

**Not yet proven with a second player.** `watchPlayer` — the path that names a
real opponent off `player.Name` and rebuilds their plate on `CharacterAdded`
after a respawn — has never run against an actual second client. It is the one
branch a single-client playtest cannot reach. Worth a two-client pass on a duel
pad before relying on it in PvP; see [[concepts/MultiplayerTestPattern]].

### Scene state, not repo state

Four things this feature needs live in the `.rbxl`, not in git, the same way
the portal pads' `ModeLabel` and `TargetArenaId` do. If the hub geometry is
ever rebuilt, they go with it and the code silently falls back to defaults:

| Instance | Carries |
|---|---|
| `Workspace.Lobby.TargetDummy` | the `TrainingDummy` tag, `NameplateLabel` = "Training Dummy", `respawnTime` = 1 |
| `Workspace.Lobby.Portal_PvE.Pad` / `Portal_PvP.Pad` | `SignHeight` = 38 |

### Replaces NametagService

`NametagService` (server, name only) is gone. One head cannot have two owners
— the Single Ownership rule — and the health half has to be client-side
anyway, since it is computed from replicated `Humanoid.Health`. Names are now
drawn client-side with the rest of the plate. `PlayerToHideFrom` became "skip
the local player", which the coordinator does directly.

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
