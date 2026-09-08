---
type: design
description: Ordered, tickable refactor plan from the 2026-09 audit — 12 chunks sized to one session each, cheap de-risking work first, the structural authority/session work behind it. Each item names its files, its no-touch list, its done condition, risk, playtest need and dependencies. Sessions claim a chunk, tick items, and record the commit.
updated: 2026-09-08
---

# Refactor Plan — 2026-09

Executes the findings in [[design/system-audit-2026-09]] (F-numbers below refer to that page). Recorded as Phase 7 in [[design/build-plan]]. Nothing in this plan has started.

## How to pick up work

1. Pick the **lowest-numbered chunk whose `Depends on` are all `done`**. Every question is answered (§ Decisions below and each chunk's `Decision:` line); the audit page § Needs your input is the record of the options that were considered.
2. Set the chunk's `Status:` line to `claimed — <session name> — <date>` before editing anything. One chunk per session; stop and report if you discover work outside the chunk's `Owns`.
3. Re-verify each item's `file:line` against `src/` before changing it — the audit is a snapshot.
4. Tick items as they land (`- [x]`). When every item is ticked and the done condition holds, set `Status: done — <date> — <commit>` and append a one-line note under the chunk if anything diverged.
5. Wiki updates for the chunk go in the same commit (system pages named under `Wiki:`), plus a `log.md` ingest entry. Run `graphify update .` before proposing the commit.
6. **Playtest lock** applies to every chunk marked `Playtest: yes`. Cap at two playtest iterations per session; escalate with a diagnosis after that.

Status legend: `open` · `claimed — session — date` · `done — date — commit` · `dropped — reason`.

## Decisions (2026-09-08)

The user read and validated the recommendations on the audit page. Every question is answered; no chunk is blocked on input any more. Each chunk carries its own `Decision:` line below; this is the summary.

| Q | Decision |
|---|---|
| Q1 | All spell damage/heal through `applyDamage.process` via an injected sink; direct `Health` writes deleted. |
| Q2 | PvP gate is `allowsPvP` on the mode config, resolved through the victim's session. Global `PLAYER_VS_PLAYER_ENABLED` deleted. |
| Q3 | Ledger reset hook + tile cap first, one measured playtest, flip `ENFORCE` in the same session only on zero honest rejections. |
| Q4 | Charge-tier trust stays accepted; record on the PvP page; revisit once duels are playable. |
| Q5 | Settings menu cut (builder, config, script, `P` keybind); tracker filed for a future settings surface. |
| Q6 | `SessionRegistry` module before Phase 6 stage 5. |
| Q7 | `TEAMS_ENABLED` and team branches deleted; `allowsPvP`, `timeLimit`, `countdownSec` move to mode config; the three global flags deleted. |
| Q8 | Wire the seven unit suites under `Suites/Unit`; delete the dead Multiplayer suites and the Melee suite; fixture-gated suites build their own dummy in `setup`. |
| Q9 | Accept one RTT on impact cues; delete the client-originated relay. |
| Q10 | Boss/NPC per-session as its own chunk (9) immediately before stage 5. |
| Q11 | `shared/Hud` stays where it is. |

Risk: **L** = deletions and renames with grep-verified zero consumers; **M** = behaviour-preserving restructure with suite coverage; **H** = changes authority, ownership, or replication and needs a two-client check.

---

## Chunk 0 — Turn the lights off (dead code, dead flags, stale comments)

Status: done — 2026-09-08 — `ba9891d`
Findings: F26, F35, F36, F37, F38 (comments only), F19 (`PlayerRespawned` only), F32 (delete half)
Risk: L · Playtest: **boot smoke only** (clean console, HUD builds) · Depends on: nothing · Blocked on: nothing

Owns: `src/utility/*` except `lerp`, `src/shared/Core/Cleanup.luau`, `src/server/Utility/TypeValidation/{validateCFrame,validateSimpleTable}.luau`, `src/shared/Hud/{ReticleBuilder,ReticleConfig,TouchControlBuilder,TouchControlConfig}.luau`, `src/client/UI/TeamScoreGui.client.luau`, `src/server/Dev/{SimulateLoadoutCycling,DevAutoEquipTool,BotSpawner}.server.luau`, `src/shared/Core/GameConfig.luau`, `src/shared/Skills/SkillTypes.luau` (two fields), `src/shared/CastAction/init.luau` + `__tests.luau` (two functions and their cases), `src/client/DevDebug.client.luau` (comments), `src/client/UI/BossHudGui.client.luau:94` (comment), `src/shared/Hud/HudLayoutManager.luau` (three dead methods), `src/shared/Hud/HudConstants.luau:66-71`.
Must not touch: anything under `Skills/` beyond the two type fields; `ScoreTracker` (its `recordBotKill` goes in chunk 8); any Test suite (chunk 1).

- [x] `GameConfig`: flip `DEV_COUNT_POP_VFX = false`; delete `TPS_CHARACTER_ENABLED`, `SHOW_WEAPON_ROLODEX`, the three `*_SPEED_MULTIPLIER` keys, `DEV_AUTO_EQUIP_TOOL`, `DEV_SIMULATE_LOADOUT_CYCLING`, `DEV_BOT_COUNT`; rewrite the `:26-29` "single flag flip restores it" comment to say the template was deleted in `6610291`.
- [x] Delete `SimulateLoadoutCycling`, `DevAutoEquipTool`, `BotSpawner` (grep `BotSpawner`/`recordBotKill` first; leave `recordBotKill` itself for chunk 8). Deleting `BotSpawner` removes the only listener that credits `Suites/Multiplayer/applydamage_credits_bot_kill.luau`'s synthetic kill — expected, since Chunk 1's Decision Q8(a) already deletes that exact test file next.
- [x] Delete `src/utility/{adjustListIndexAfterRemoval,bindToInstanceDestroyed,disconnectAndClear,safePlayerAdded}`, `Core/Cleanup.luau`, `TypeValidation/{validateCFrame,validateSimpleTable}` (re-grep each name for zero consumers).
- [x] Delete `ReticleBuilder`/`ReticleConfig`/`TouchControlBuilder`/`TouchControlConfig`, `TeamScoreGui.client.luau`, and `HudConstants.luau:66-71` aliases; delete `HudLayoutManager:unregister`, `:moveToRegion`, `_onInputCategoryChanged`.
- [x] Delete `vfxName`/`sfxName` from `SkillTypes.SkillSpec` (`:74-75`); delete `CastAction.tapReservoir` + `resolveTapSpec` and their `__tests` cases (`castSpecific`/`resolveSpecAtCharge` cases stay).
- [x] Delete unread constants: `GameModeConstants.{ROUND_TIME_LIMIT,SCORE_LIMIT,SPAWN_MIN_ENEMY_DISTANCE}`, `HealthConstants.{TORSO_MULTIPLIER,INVINCIBILITY_DURATION,HEALTH_BAR_LAYOUT}`, `NPCConstants.COMBAT_RAY_RADIUS`. **Deferred:** did NOT delete the `PlayerRespawned` BindableEvent fire / `.model.json` — `Suites/Multiplayer/multiplayer_invariants.luau` (a Test suite, must-not-touch) structurally asserts `ServerScriptService.Server.Health.Events.PlayerRespawned` exists; unlike `BotSpawner`, Chunk 1's stated trim list for that file ("drop the Weapon.Remotes and TDM blocks") doesn't name this check, so there's no pre-committed fix. Leave for Chunk 1 to either drop the check or for this line item to be picked up once Chunk 1 confirms.
- [x] Fix comments: `SkillEffects.luau:40` (no longer client-authoritative — rewritten), `DevDebug.client.luau:15,144` (already correct, says `;`, no edit needed), `BossHudGui.client.luau:94` (was "toggle with P", fixed to `;`), `SettingsMenuGui.client.luau:4` (was "Escape keybind", fixed to "P keybind" — note: lines 105/108-110 in the same file repeat the stale "Escape" framing but weren't in the item's line list, left untouched per scope).
- [x] Studio: after sync, check for stale duplicates of the deleted scripts (Rojo does not always clean up). First playtest found 9 stale duplicates (Reticle/TouchControl Builder+Config, `bindToInstanceDestroyed`, `Core.Cleanup`, two `TypeValidation` functions, `TeamScoreGui`) — pruned via a `ChangeHistoryService`-wrapped `execute_luau` pass. Second boot smoke (fresh Studio instance) confirmed none remained.

Done when: `grep` for every deleted symbol returns nothing; boot playtest shows a clean console and the full HUD; `graphify update .` run.
Wiki: [[systems/HUD]] (Reticle/TouchControl rows), [[systems/Tests]] no change yet, [[concepts/DevDebugHotkeys]] (`;` note).

---

## Chunk 1 — Make the test harness tell the truth

Status: done — 2026-09-08 — `f8d9dc1` (follow-up to `8d9cb83`)
Findings: F41, F42, F43, drift 9
Risk: L · Playtest: **yes** (one `RunTests = "all"` run; clear the attribute after) · Depends on: chunk 0 · Blocked on: nothing (Q8 answered)
Decision: Q8(a) — wire the seven unit suites; delete `drop_request_zone_gated`, `respawnzone_tracks_hrp_presence`, `applydamage_credits_bot_kill`, `restoreToSafeSpawn` and `Suites/Melee/*`; NPC suites build their own Patroller in `setup`.

Owns: `src/shared/Tests/**`, `src/server/Tests/TestAutoRunner.server.luau`, every `src/shared/*/__tests.luau` (return shape only), `wiki/systems/Tests.md`.
Must not touch: the modules under test.

- [x] Delete `Suites/Multiplayer/{drop_request_zone_gated,respawnzone_tracks_hrp_presence,applydamage_credits_bot_kill}.luau` and `Helpers/restoreToSafeSpawn.luau`; trim `multiplayer_invariants.luau` to remotes that exist (drop the Weapon.Remotes and TDM blocks).
- [x] Delete `Suites/Melee/*` (Q8: the melee chain is dead; chunk 11 removes the modules).
- [x] Normalise all ten `__tests.luau` to `return { run = function() ... end }` — `EnergyEconomy` and `Dictionary` must stop executing on require. Only three of the ten actually needed a shape change: `Dictionary` and `EnergyEconomy` ran their asserts at require time (wrapped in `M.run()` / `{ run = runAll }`), and `WordBuffer` returned a bare function (now `{ run = runTests }`). The other seven already returned a table exposing `.run()` or `.runAll()` and needed no edit. `SpellExecutor`/`SpellRegistry` keep `.runAll()` returning `(passed, failed)` — matches the existing `spellexecutor_tests.luau` wrapper shape, not `.run()`.
- [x] `MemorizeAction/__tests.luau` scenario 2 asserts an invalid word preserves the buffer; `tryMemorize` has cleared it on the invalid path since `9ae3719`, and [[systems/MemorizeAction]] documents the clear as intended. Fix the assertion to the documented behaviour (found by chunk 2's direct run, 2026-09-08).
- [x] `multiplayer_invariants.luau` also asserts `Health.Events.PlayerRespawned` exists — drop that check, then delete the `PlayerRespawned` fire + `.model.json` that chunk 0 deferred (F19). Divergence: the versioned file is `PlayerRespawned.meta.json`, not `.model.json` — the plan's filename was wrong, the instance (a bare `BindableEvent`, no properties) is the same one chunk 0 deferred.
- [x] Add `Suites/Unit/` with one wrapper per unwired module (WordBuffer, EnergyEconomy, EnergyReservoirs, Dictionary, SpellRegistry, MemorizeAction, MindFullManager), same shape as `Suites/Skills/castaction_tests.luau`. Also wired `Hud/__tests` (chunk 3 left it unwired) — see divergence note below.
- [x] NPC suites: `setup` clones `ServerStorage.AIWorldData.Rigs.Patroller` if `Patroller_1` is absent (Q8: fixtures are built, not assumed). Verified via `inspect_instance`: the template exists at that path. In practice `Patroller_1` was already present at every run (NPCService boot-spawns it from `AIWorldData` spawn points before `TestAutoRunner`'s startup delay elapses), so the clone path is untested live code — see divergence note.
- [x] Run `all`; record pass/fail per suite in the log entry; clear `RunTests`.
- [x] Rewrite [[systems/Tests]]: discovery rules, suite table with status, `__tests` wiring, fixture requirements.

Done when: `RunTests = "all"` reports no `[AUTORUN WARN] Skipped` and no suite errors in `run`; every `__tests` module is reachable from a Suite. **Met** — 2026-09-08 second verification run: **28/28 passed, 0 failed**, zero `[AUTORUN WARN] Skipped`, zero setup/run pcall errors. First verification run (26/28) surfaced two failures that parent review determined were both test-side bugs inside this chunk's `Owns`, not real regressions or out-of-scope module bugs — see § Follow-up fixes below.

**Divergence log:**
- A bare `template:Clone()` of `AIWorldData.Rigs.Patroller` has a Humanoid but no state machine — `CurrentState` would never be set and the NPC would never react, since `NPCController.new` + a Heartbeat tick loop are what actually drive it (both currently private to `NPCService.server.luau`, a Script, not requireable). Added `src/shared/Tests/Helpers/ensurePatroller.luau`: reuses a boot-spawned `Patroller_1` if present (the common case — `created = false`, `teardown` no-ops); otherwise clones the rig, wires it to its own `NPCController` instance requiring `ServerScriptService.Server.NPC.Scripts.NPCController` directly, and ticks it on `Heartbeat` for the test's duration. All three NPC suites (`combat_engages`, `combat_disengages`, `npc_deals_damage`) now go through this helper.
- `Hud/__tests.luau` requires `Players.LocalPlayer` and errors immediately on a server VM (see its own "Client only" header comment), and `TestAutoRunner.server.luau` only ever runs server-side — there is no client autorunner. Wiring it in as a plain `{run=...}` wrapper would make `RunTests=all` fail every time for a harness-shape reason, not a real regression. `Suites/Unit/hud_tests.luau` checks `RunService:IsServer()` and reports an explicit, visible pass-with-skip message (`"skipped — client-only ..."`) instead of a false fail; on an actual client VM it runs the real suite. Recorded here since it's a structural gap, not a "Found:" module bug — a client-side autorunner is out of this chunk's scope.

**Found in the first verification run, then resolved as test-side bugs (parent review, 2026-09-08):**
- `Suites/Multiplayer/multiplayer_invariants.luau` failed: "ShotReplication LocalScript missing from StarterPlayerScripts". Initially misdiagnosed as a live placement regression. It is not: `src/client/ShotReplication.client.luau` was deleted on purpose in `6610291` (confirmed via `git show --stat 6610291`), along with the Weapon.Remotes files this chunk had already stopped asserting on. The check itself is what went stale, not the game. **Fix:** deleted the ShotReplication check (both the StarterPlayerScripts-presence half and the stray-in-ReplicatedStorage half) and the header comment bullet that motivated it; renumbered the remaining assertions. `wiki/concepts/LocalScriptPlacement.md` needed no change — it documents the historical incident, not current state, and was already accurate.
- `Suites/NPC/npc_deals_damage.luau` failed intermittently: "Player took no damage (still at 100 HP)". Confirmed root cause: `combat_disengages` teleports the player 80 studs from the NPC as part of its own test (`FAR_OFFSET`), which can land them over open air and into `Workspace.Arena.DeathZone` → a `DeathZoneService`-driven trip through the Lobby and back. If `npc_deals_damage` starts its engage-poll loop while that's still resolving, it snapshots `ctx.initialHealth` moments before another respawn silently resets it, so real damage during `run()` reads as none. **Fix, test-side only, `NPCService`/`Perception`/`Actions`/`HealthService` untouched:** `combat_disengages`'s `teardown` now calls a restored `Helpers/restoreToSafeSpawn.luau` (the same helper chunk 1 had deleted as an orphan before this fixture need reappeared — recovered verbatim from `8d9cb83`'s parent) to put the player back on solid ground away from the DeathZone. `npc_deals_damage`'s `setup` now calls a new `waitForStableFullHealth` at the very start: polls (bounded to 8s) until the player's character/Humanoid exists and `Health >= MaxHealth` has held for a continuous 1s window, restarting the window on any Humanoid-identity change (a mid-wait respawn); fails `setup` with a clear reason if it never stabilises, rather than silently proceeding.
- A third, previously-passing test failed once during re-verification for a reason unrelated to either fix above: `Suites/Phase3/blockspawner_fills_to_target.luau` failed "invalid color attribute: wild" — its `verify` hardcoded `color ~= "red" and color ~= "green" and color ~= "blue"`, predating the wildcard tile system, so a block randomly rolling the (valid, shipped) `"wild"` color intermittently failed it. **Fix, test file only:** the color-membership check now derives its accepted set from `Core/Colors.SPELL_COLORS` (the codebase's single source of truth for reservoir colors) plus `Wildcard.COLOR` (the single source of truth for the wildcard tile color), instead of a hardcoded fourth string.

**Per-suite results:**

First verification run (2026-09-08, before the fixes above) — 26/28 passed, 2 failed:

| Suite | Result |
|---|---|
| NPC | 2/3 passed — "deals damage" failed |
| Multiplayer | 0/1 passed — `multiplayer_invariants` failed |
| Phase3 | 7/7 passed |
| Skills | 5/5 passed |
| Hardening | 3/3 passed |
| Economy | 1/1 passed |
| Unit | 8/8 passed |

Second verification run (2026-09-08, after fixing `multiplayer_invariants` and `npc_deals_damage`) — 27/28 passed, 1 failed: NPC 3/3, Multiplayer 1/1, Phase3 6/7 (`blockspawner_fills_to_target` failed — the wildcard-color issue above, not yet fixed at this point), Skills 5/5, Hardening 3/3, Economy 1/1, Unit 8/8.

Third verification run (2026-09-08, after fixing `blockspawner_fills_to_target`) — **28/28 passed, 0 failed**: NPC 3/3, Multiplayer 1/1, Phase3 7/7, Skills 5/5, Hardening 3/3, Economy 1/1, Unit 8/8 (`hud_tests` passed via the explicit server-VM skip).

---

## Chunk 2 — One name per number

Status: done — 2026-09-08 — `a49d5a3`
Findings: F27, F31, F38, F21 (constant half), F19 note
Risk: L · Playtest: **boot smoke** (unit suites carry the rest) · Depends on: chunk 1 · Blocked on: nothing

Owns: new `src/shared/Core/Colors.luau`; `WordBuffer`, `EnergyEconomy`, `EnergyReservoirs`, `SpellRegistry`, `CastAction` (type imports only), `BlockSpawner:68`, `VfxConfig:144,1644`, `SpellMenuConfig:31`, `DevDebug:33-34`; `SkillConstants` + `SkillDelivery:333-341,376,844-846` + `SkillEffects:191,309` (defaults); `HealthConstants:3` / `GameModeConstants:14` / `DeathScreenGui:101-103`; `BlockTapController:47` / `GameplayHudGui:39` / `SpellMenuGui:87` → `VfxConfig.SFX`; `EconomyConstants:41`; `SpellCastConstants:22` + `SpellMenuGui:43` → `SpellRegistry.AUTO_TARGET_RANGE_STUDS`; `NPCConstants` + `Perception:51` / `Actions:269,303` (eye height).
Must not touch: handler logic in `SkillDelivery`/`SkillEffects` (only the fallback literals move).

- [x] `Core/Colors.luau`: `SpellColor`, `TileColor`, `Tile`, `SPELL_COLORS`, `isSpellColor`; every duplicate type/list imports it; server modules stop requiring `EnergyReservoirs` for `COLORS` (`ChargeStateService:39`, `EnergyLedger:39` — keep the require only if `CAP_PER_COLOR` still needs it, and say so).
- [x] Skills fallback defaults → `SkillConstants.DEFAULT_*`.
- [x] One `RESPAWN_TIME`; `DeathScreenGui` reads `respawnTime` from the GameState payload (add the field in `RoundManager`'s payload — additive only).
- [x] `VfxConfig.SFX.FIZZLE_PLAYBACK_SPEED`; `REJECTION_LOG_THROTTLE_SEC` unified; `AUTO_TARGET_RANGE_STUDS` on `SpellRegistry`; `NPCConstants.EYE_HEIGHT`; `DevDebug.TIER_ENERGY = SpellRegistry.TIER_COSTS`.
- [x] Run `Unit`, `Skills`, `Hardening`, `Economy` suites. (`Unit` suite doesn't exist until chunk 1 wires it — ran the seven pure-module `__tests` directly instead; see § Divergence log.)

Done when: `grep -rn '"red" | "green"'` finds one declaration; the suites above are green; boot smoke clean.
Wiki: [[systems/SpellRegistry]] (range constant), [[systems/SpellCastService]] § Tuning (duplicate-constant note resolved).

---

## Chunk 3 — HUD ownership

Status: done — 2026-09-08 — `974a5d4`
Findings: F4, F20, F22, F23, drift 7
Risk: M · Playtest: **yes** — die in the lobby, walk into the arena, confirm no death overlay; then die in the arena and confirm the overlay · Depends on: chunk 0 · Blocked on: nothing

Owns: `src/client/UI/DeathScreenGui.client.luau`, `src/shared/Hud/HudGate.luau` (+ new `__tests`), `HudConstants.luau` (TopRight), the five `_G.PlayerHud` writers, `DashManager.client.luau` + `DashButtonGui.client.luau` (dash bridge), the six Builder/Config pairs named in F23, `wiki/concepts/HudGate.md`.
Must not touch: `SpellMenuGui` cast logic (chunk 7), any hand-built ScreenGui port (chunk 12).

- [x] DeathScreenGui toggles a child overlay's `Visible`; `screenGui.Enabled` is written only by the gate. Add a `HudGate` unit test for the closed-gate `true`→`false` sequence (F4).
- [x] [[concepts/HudGate]]: add the rule "owners never write the gated property".
- [x] TopRight `stackVertical` (or BuffTray to its own region).
- [x] Delete the `_G.PlayerHud` writes; replace `_G.BrainFighter.requestDash` with a `client/DashApi` ModuleScript.
- [x] Config extraction for SpellMenu, AttributeBar, BuffTray, PortalPanel, MemorizeButton (SettingsMenu is deleted in chunk 12 per Q5 — do not extract it).

Done when: the lobby-death → arena-entry playtest shows no overlay; `grep _G.PlayerHud` is empty; the six Builders contain no inline geometry/colour literals outside a Config read.

---

## Chunk 4 — One damage path

Status: done — 2026-09-08 — a0dfc73
Findings: F1, F2, drift 1, 2 · plus cause id for F34's kill-feed "Unknown"
Risk: **H** · Playtest: **yes** — spell kill on the dummy credits the kill feed; boss damage unchanged; shield absorbs a spell hit once (not twice) · Depends on: chunk 1, chunk 2 · Blocked on: nothing (Q1, Q2 answered)
Decision: Q1(a) + Q2(a) — every spell damage/heal goes through `applyDamage.process` via an injected sink; PvP gate is `allowsPvP` on the mode config resolved through the victim's session; `GameConfig.PLAYER_VS_PLAYER_ENABLED` is deleted here (chunk 8 moves the other flags).

Owns: `src/shared/Skills/SkillEffects.luau` (damage/heal handlers + the sink injection), `src/server/Health/Scripts/HealthService/{init.server,applyDamage}.luau`, `src/shared/Health/DamageTypes.luau` (cause id), `src/server/Arena/DeathZoneService.server.luau`, `src/shared/Skills/SkillBuffs.luau:230-262` (second drain site), `src/shared/Skills/SkillTypes.luau` (DeliveryCtx source), `GameModeService/init.server.luau:390-420` (`onPlayerEliminated` weapon name), `Suites/Skills/*`.
Must not touch: `SkillDelivery` handlers beyond passing `ctx.source` through; `ScoreTracker` internals; respawn code (chunk 5).

- [x] `SkillEffects.setDamageSink(fn)` called from `HealthService/init.server.luau`; remove the `pcall(require)` at `:44`.
- [x] `damage`/`heal` handlers call the sink with `sourcePlayer` (from `ctx.source` when it is a player character) and `cause` (skill id); delete the direct `Health` writes at `:172,174,184`. `useApplyDamage` field becomes redundant — remove from `BossConfig`.
- [x] `applyDamage` request gains `cause: string?`; `DamageResult` carries it; `onPlayerEliminated` uses it for the kill feed instead of an equipped Tool.
- [x] PvP gate per Q2 (`allowsPvP` on mode config, resolved through the victim's session) replaces `GameConfig.PLAYER_VS_PLAYER_ENABLED` at `applyDamage.luau:41`.
- [x] DeathZone through `applyDamage` with `sourcePlayer = nil`, `cause = "death_zone"`.
- [x] `SkillBuffs.consumeShield` stays for shell deflection only; document that the body-hit drain is `DamageModifierRegistry`.
- [x] Update `predicted_run_writes_nothing` and `Skills/__tests` shield case for the new path.

Done when: `grep -rn "\.Health\s*=" src` hits only `applyDamage.luau` and the two HealthService init writes; a spell kill appears in the kill feed with the spell name; suites green.

Divergences (2026-09-08):
- The sink is the `applyDamage` module itself (`DamageTypes.DamageSink = { process, heal }`), not a bare function — heals must not run the modifier chain (a shield would "absorb" them), so `applyDamage.heal` is a second entry point on the one writer.
- "Resolved through the victim's session" needed three files outside `Owns:`: `GameModeDefinition.getConfig().allowsPvP: boolean?` (absent = false), `allowsPvP = false` on `LobbyMode`/`NoOpMode`, and a new `Server/GameMode/Events/AllowsPvP.model.json` BindableFunction that `GameModeService` answers from `modeForPlayer(victim)` — bound at file scope, because an unbound BindableFunction makes `Invoke` yield forever.
- `DeathZone` needs `HealthConstants.INSTANT_KILL_DAMAGE` (1e9): `MaxHealth + 1` through the modifier chain would let a shielded player survive the fall.
- Spells default to `DamageType.Spell` (was `Bullet`), which is what `DamageFeedbackGui` now prints for boss and player spell hits. Hit zone stays `Torso`, so boss numbers are unchanged (GroundSlam 25, Brain volley 5/shot, both observed).
- Kill feed only lists **player** victims (`onPlayerEliminated` returns early for NPC/dummy victims — pre-existing, `ScoreTracker` territory, untouched). Verified instead with the player as victim, read from the Client datamodel: `[death_zone] ZandaLuki` and `[FireballVolley] ZandaLuki`; a player-sourced spell kill on another player needs the two-client check that chunk 9/stage 6 will run.
- Found, not fixed (chunk 9): NPC melee (`MeleeHitDetector`) sends no `cause`, so an NPC kill still reads "Unknown" in the feed.
Wiki: [[systems/Health]] (callers list, cause id), [[systems/SkillPipeline]] (damage section; delete the stale `drawnLocallyBy`/`casterUserIdFrom` paragraph and the Reserved Hooks section), [[design/lobby]] (PvP gate mechanism).

---

## Chunk 5 — One respawn owner

Status: done — 2026-09-08 — c63488e
Findings: F3, F13 (offsets), F17
Risk: M · Playtest: **yes** — die in arena: exactly one `CharacterAdded`; `RequestRespawn` after respawn is refused · Depends on: chunk 4 · Blocked on: nothing

Owns: `GameModeService/init.server.luau:319-372` (Died handler), `HealthService/init.server.luau:16,46-62,113` (RequestRespawn), `applyDamage.luau:135`, `DeathScreenGui.client.luau:79` (respawn button), `SpawnManager.luau:208,223`, `ScoreTracker.luau:37,87-125` (`recentDamage` expiry).
Must not touch: `DeathHandler` (non-player rigs — correct as is); session tables.

- [x] `Players.CharacterAutoLoads = false` in GameModeService `initialize`; GameModeService is the only `LoadCharacter` caller for players.
- [x] `RequestRespawn` becomes a request the session answers (early respawn allowed only while dead, checked against the live Humanoid, not `pendingRespawns`) or is deleted with the button — pick the one the death screen UX wants and record it in the divergence log.
- [x] `pendingRespawns` cleared on `CharacterAdded` (or removed if the remote goes).
- [x] `recentDamage` entries expire on insert; key dropped on `Died`/`Destroying`.
- [x] Name the two SpawnManager offsets.
- [x] `HealthConstants.RESPAWN_TIME` (5) survives chunk 2 only because `HealthService/init.server.luau:54` and the Damageable-NPC timer read it; once the `RequestRespawn` gate is gone, keep it solely as the NPC respawn default and rename it `NPC_RESPAWN_TIME` so it can no longer be mistaken for the player value.

Done when: the playtest above; `grep LoadCharacter src/server` hits GameModeService only.

Divergences (2026-09-08):
- **`RequestRespawn` deleted (option b), not kept as a session request.** The death-screen button was already decorative: it only became visible after the client counted down the *same* `respawnTime` the server counts, and by then `GameModeService`'s `Died` handler had already respawned the player, whose `CharacterAdded` hides the overlay. The button had no window in which it could do anything, so "a request the session answers" would have been a remote with no caller. Deleted: the `TextButton` + `UICorner` + click handler, the `RequestRespawn` RemoteEvent and its `Remotes/RequestRespawn.meta.json`, `onRequestRespawn`, and `pendingRespawns` from both `HealthService` and `applyDamage`'s refs. The overlay's post-countdown text is now unconditionally "Respawning..." — the old `else` branch printed "Eliminated" beside the button and would otherwise have been a dead-end screen.
- The stale `RequestRespawn` RemoteEvent had to be destroyed in Studio by hand: `Shared/Health/Remotes/init.meta.json` carries `ignoreUnknownInstances: true`, so deleting the file does not make Rojo remove the instance. Done under a `ChangeHistoryService` waypoint; the folder now holds `DamageFeedback` and `DamageConfirm` only. **The .rbxl needs saving to persist that.**
- Touched one line outside `Owns:` — `DeathHandler.server.luau:105` reads `HealthConstants.RESPAWN_TIME` for its non-player rigs, so the rename to `NPC_RESPAWN_TIME` had to follow it there or the attribute default would have gone `nil`. Symbol rename only; DeathHandler's own `pendingRespawns` and respawn cycle are untouched.
- `CharacterAutoLoads = false` needs a first spawn from somewhere: `onPlayerAdded` now calls `player:LoadCharacter()` when the player has no character. Deliberately a bare call rather than `SpawnManager.getBestSpawn` — the engine's SpawnLocation pick is what auto-load did, and the join lands in the lobby, which has no threat scoring to do.
- F13's other half (`getLivingEnemyPositions` iterating all of `Players` rather than the session roster) is **not** done here — only "name the offsets" was in this chunk's item list. That half is already chunk 8 (`F13 (roster)`, `SpawnManager.luau:50`) — nothing new to file.
- `ScoreTracker` also needed a `forgetDamage` helper so `resetAll` disconnects the per-Humanoid `Died`/`Destroying` connections instead of dropping the table and leaking them.
- Playtest (2 iterations, session `chunk-5-respawn`): a hub death and an arena death each produced exactly **one** `CharacterAdded` (counter installed on the Server datamodel before the kill), ~4.4 s after death, matching the mode's `respawnTime = 4`. The death overlay was observed on the Client datamodel going visible → "Respawning..." → hidden on respawn, with no `TextButton` in the tree and no `RequestRespawn` under `Shared.Health.Remotes`. Harness `all`: **28/28 passed, 0 failed** (`npc_deals_damage` green); `RunTests` cleared in both VMs.
Wiki: [[systems/Health]] § Respawn, [[systems/GameMode]] § Respawn.

---

## Chunk 6 — Economy that can be switched on

Status: done — 2026-09-08 — <commit>
Findings: F8, F9, F19 (`RoundStarted`), A28 tile cap
Risk: M · Playtest: **yes** — memorize, cast, round restart, confirm `[EconomyService]` reset line and zero would-reject lines across a full honest round · Depends on: chunk 1 · Blocked on: nothing (Q3 answered)
Decision: Q3(a) — reset hook and tile cap land first; one measured honest playtest; flip `ENFORCE = true` in the same session only if the shadow log shows zero honest rejections. Q4(a) — charge-tier trust stays accepted; add the note to [[design/lobby]] when this chunk touches the wiki.

Owns: `src/server/Economy/*`, `RoundManager.luau` (`roundStartedEvent` payload only), `Suites/Economy/*`, `wiki/systems/SpellCastService.md` (affordability section + frontmatter), `wiki/index.md` (SpellCastService line).
Must not touch: `SpellCastService` handler order; client reservoirs.

- [x] `EconomyService` listens to `RoundStarted` (or a `SessionRegistry` hook once chunk 8 lands — do not wait for it) and resets each roster member's ledger account.
- [x] `EnergyLedger.reportMemorize` rejects `#tiles > WordBuffer.DEFAULT_CAP` outright.
- [x] Suite: round reset clears the ceiling; over-cap payload refused.
- [x] Measured playtest per Q3(a); flip `ENFORCE` in the same session only if zero honest rejections.
- [x] Fix drift 4: one sentence on the SpellCastService page and index line that says the check exists, and whether it is enforced.

Done when: the reset line appears on round start; `ENFORCE` state matches the wiki; suites green.

**Outcome: `ENFORCE = true`.** The measured playtest showed **zero** would-reject lines.

- The reset hook is `RoundManager.luau:234` firing `roundStartedEvent:Fire(self:getPlayers())` — the roster is the only RoundManager change — and `EconomyService` mapping it to `EnergyLedger.resetRound(userIds)`. Observed in production code: `[RoundManager] [Default] Round started!` immediately followed by `[EconomyService] round start — reset 0 of 1 roster accounts` on a real transfer into the arena, and `reset 1 of 1` when the account had earned state.
- The cap check is `EconomyConstants.MEMORIZE_TILE_CAP = WordBuffer.DEFAULT_CAP` (12), refused ahead of `accountFor` and ahead of the per-tile walk so an oversized payload can neither conjure an account nor make the ledger walk an unbounded list, with its own verdict reason in both modes.
- Harness `all`: **30/30 passed, 0 failed** — 28 baseline plus `ledger_resets_on_round_start` and `ledger_refuses_over_cap_memorize`. Re-run after the flip, still 30/30 with `[EconomyService] ready — validated memorize active (ENFORCING)`. `RunTests` cleared in both VMs.

Diverged / worth knowing:

- **The honest sample is narrow.** Four words (DRAGON, PIANO, CLUE, MOON) and three casts (Mend, Mend, Shield), one player, driven through the real client modules (`PlayerSession`, `EconomyReport`, `CastAction`) and the real remotes, but not through mouse input. It did **not** exercise discards, the `ConsumeBlock` rejection rollback, wildcards drawn from real blocks, or a second client. `ENFORCE = false` is the right first response to a player reporting a refused cast they earned.
- **No natural second round start exists in this build.** The `Default` arena runs No-Op mode (`scoreLimit = math.huge`) with `ROUND_TIMER_ENABLED = false`, so `_activeRound` never returns and `RoundStarted` fires exactly once per session — on the transition out of `_waitForPlayers`. Transferring the roster out and back does not halt a round in progress. The reset over a *non-empty* ledger was therefore observed by firing the same Bindable by hand with the real roster, plus the suite test; the RoundManager→listener half is proven by the transfer above. Noted under chunk 8.
- **The two round resets are a pair.** Server clears on `RoundStarted`, client clears on the `Active` broadcast (`client/EnergyRoundReset`). Under enforcement, firing one without the other diverges the halves — recorded on [[systems/SpellCastService]].
- `RoundEnded` (F19's other half) is still fired with no listener. Left alone: chunk 6 owns the `roundStartedEvent` payload only.

Wiki: [[systems/SpellCastService]] (affordability + validated memorize + Q4 note), [[index]] (SpellCastService line), [[design/lobby]] (affordability blocker closed, Q4(a) charge-tier sentence).

---

## Chunk 7 — One VFX broadcast lane

Status: open
Findings: F6, F7, F29 (`spellResolved` bindable + lazy cache), F21 (SpellCastController)
Risk: **H** · Playtest: **yes, two clients** — caster sees cast cue instantly and impact on confirm; the second client sees both once; a rate-limited cast draws nothing on the second client · Depends on: chunk 4 · Blocked on: nothing (Q9 answered)
Decision: Q9(a) — impact cues arrive on server confirmation; prediction draws the cast cue only; the client-originated relay is deleted outright.

Owns: `src/server/Vfx/VfxBroadcastService.server.luau` (delete), `src/shared/Vfx/Remotes/{BroadcastSpellVfx,SpellVfxEvent}.model.json` (delete), `src/client/Vfx/VfxController.client.luau`, `src/shared/Skills/SkillVisuals.luau`, `src/shared/Skills/SkillDelivery.luau:129-134,157,611-630` (ProjectileVfxEvent → VfxBroadcast; lazy cache), `src/shared/Vfx/VfxBroadcast.luau` (new `projectile` kind), `src/shared/CastAction/init.luau:69-100` (`spellResolved` exposure), new `src/client/SpellCastController.client.luau`, `src/client/UI/SpellMenuGui.client.luau` (cast/target code moves out).
Must not touch: `VfxConfig` entries; status-visual controllers (chunk 10).

- [ ] Authoritative run raises cast cue + impact cues via `SkillVisuals` with `drawnLocallyBy = ctx.predictedBy` for the cast cue only.
- [ ] `VfxController` draws the cast cue from `spellResolved` and nothing at the target; delete the `BroadcastSpellVfx` fire.
- [ ] `ProjectileVfxEvent` becomes a `VfxBroadcast` kind; `VfxBroadcastService` deleted.
- [ ] `spellResolved` exposed without requiring the executor; `SkillDelivery`'s Heartbeat cache connects lazily and server-only.
- [ ] `SpellCastController` owns target resolution + `castSpecific` + relay; `SpellMenuGui` forwards `menu.cast`.
- [ ] `client-server-boundary` gains a row for the removed relay; `VisualEffects` frontmatter status corrected (drift 8, 10).

Done when: `grep -rn "FireServer" src/client/Vfx` is empty; two-client playtest as above; `predicted_run_writes_nothing` green.
Wiki: [[design/client-server-boundary]], [[systems/VisualEffects]], [[systems/HUD]] (SpellMenuGui responsibilities).

---

## Chunk 8 — Sessions own their scores (and their registry)

Status: open
Findings: F12, F13 (roster), F16, F34 (team plumbing + definition trim), Q7 flags
Risk: **H** · Playtest: **yes, two sessions** (the disjoint-roster cross-talk test stage 3 never ran) — a round start in one arena leaves the other's scores intact; the scoreboard in each shows only its roster · Depends on: chunk 5, chunk 6 · Blocked on: nothing (Q6, Q7 answered)
Decision: Q6(a) + Q7(a) — `SessionRegistry` module lands here, before Phase 6 stage 5; `TEAMS_ENABLED` and every team branch deleted; `allowsPvP`, `timeLimit`, `countdownSec` on the mode config; `ROUND_TIMER_ENABLED` and `ROUND_COUNTDOWN_ENABLED` deleted; `RoundTimerGui` reads the payload.

Owns: new `src/server/GameMode/Scripts/SessionRegistry.luau`, `GameModeService/init.server.luau` (thin bootstrap), `LobbyService.server.luau:37-38,182,198,216` (call the module), `Events/{TransferPlayer,SetPlayerQueued}.model.json` (delete), `ScoreTracker.luau` (`new(roster)`), `RoundManager.luau` (owns its tracker; `winnerTeamName` out), `SpawnManager.luau:50` (roster), `NametagService.server.luau` (team branch), `applyDamage.luau:57-69` (team branch), `GameModeDefinition.luau`, `GameModeTypes.luau` (delete), `Modes/{NoOpMode,LobbyMode}.luau`, `Arena.luau` (SpawnTags gains the default), `GameConfig.luau` (four flags → mode config), `RoundTimerGui.client.luau` (reads payload), `BroadcastAudience.luau` (resolver reads the module).
Must not touch: boss/NPC spawning (chunk 9); `BlockShootService`.

- [ ] `SessionRegistry` module: `sessions`, `playerSessions`, `queued`, `create`, `transferPlayer`, `setQueued`, `forPlayer`, `forArena`, `rosterOf`; GameModeService becomes wiring only; the two BindableFunctions deleted.
- [ ] `ScoreTracker.new(roster)` per session; `RoundManager` constructs and owns it; leaderstats mirror stays server-wide; `recordBotKill` deleted.
- [ ] `SpawnManager.getBestSpawn(player, arenaId, roster)`.
- [ ] Team plumbing deleted (`TEAMS_ENABLED`, FF branch, nametag team colour, `winnerTeamName`, `getTeamConfig`); `GameModeTypes` deleted; `NoOpMode` spawn tag from `Arena.SpawnTags`.
- [ ] Per Q7(a): `allowsPvP`, `timeLimit`, `countdownSec` on mode config; `ROUND_TIMER_ENABLED`/`ROUND_COUNTDOWN_ENABLED`/`PLAYER_VS_PLAYER_ENABLED` deleted; `RoundTimerGui` reads the payload.
- [ ] Suite: two sessions with disjoint rosters; score reset isolation; transfer moves roster + attributes.

Done when: the two-session playtest and suite above; `grep BindableFunction src/server/GameMode` empty; `grep TEAMS_ENABLED src` empty.

> Noted by chunk 6: with `ROUND_TIMER_ENABLED = false` and No-Op's `scoreLimit = math.huge`, the `Default` session's round never ends, so `RoundStarted`/`RoundEnded` fire once per session and nothing downstream of them can be exercised twice in a playtest. Q7 moves `timeLimit` onto the mode config here — give No-Op a finite one, or this chunk's two-session round-start test has the same problem.
Wiki: [[systems/GameMode]] (the stage-7 rewrite — do it here), [[design/lobby]] (stage rows), [[systems/Health]] (FF section removed).

---

## Chunk 9 — The world knows its arena

Status: open
Findings: F14, F15, F30 (Hittables helper as the filter seam)
Risk: **H** · Playtest: **yes, two arenas** — a boss in one arena never targets the other's players; a hub player cannot pop arena blocks even in range · Depends on: chunk 8 · Blocked on: nothing (Q10 answered)
Decision: Q10(a) — this chunk runs as its own session immediately before Phase 6 stage 5; stage 5 is then only `Modes/PvEBoss.luau` and the queue.

Owns: `src/shared/BlockSpawner/init.luau:426-437` (ArenaId stamp), `src/server/BlockShoot/BlockShootService.server.luau` (+ `BlockShootValidation`), new `src/shared/Skills/Hittables.luau`, `SkillDelivery.luau:146-200` and `CosmeticProjectile.luau:160-190` (use it), `Perception.luau:82`, `BossService.server.luau` (per-arena BossPoint), `NPCService.server.luau` (per-arena spawns, `destroy()`), `Suites/Hardening/blockshoot_*`, `Suites/Phase3/*`.
Must not touch: mode files; `LobbyService`.

- [ ] Blocks carry `ArenaId`; `ConsumeBlock` refuses a mismatch; Hardening suite case.
- [ ] `Hittables.collect(arenaId?)` shared by `SkillDelivery`, `CosmeticProjectile`, and `Perception`; one target definition.
- [ ] BossPoints and NPC spawns tagged with `ArenaId`; one boss / NPC set per session; `NPCService` gains `disable()`/`destroy()`.
- [ ] Studio: tag the existing `BossPoint` and NPC spawn snapshots with `ArenaId = Default` (MCP, under a `ChangeHistoryService` waypoint).

Done when: the playtest above; `grep "Players:GetPlayers()" src/shared/Skills src/server/NPC` empty.
Wiki: [[systems/Boss]], [[systems/NPC]], [[systems/BlockShoot]], [[systems/BlockSpawner]].

- Note (chunk 4, 2026-09-08): `MeleeHitDetector` builds its `DamageRequest` without a `cause`, so an NPC kill still shows "Unknown" in the kill feed. Pass the archetype name (or a `DamageTypes.Cause` id) when this chunk touches the NPC damage call.

---

## Chunk 10 — Presentation dedupe and layering

Status: open
Findings: F28, F29 (remaining), F33 (telegraph), F40, F45 (client controllers)
Risk: M · Playtest: **yes** — freeze, burn, shield, charge orb each still render on a second client; boss windup disc renders · Depends on: chunk 7 · Blocked on: nothing

Owns: new `src/shared/Vfx/CharacterAttributeWatcher.luau`, new `src/shared/Vfx/MotePath.luau`, `src/client/Vfx/{Freeze,Inferno,Shield,ChargeOrb}*Controller.client.luau`, `StatusVisuals/{ChargeOrbVfx,ShieldVfx}.luau` (inputs instead of registry reads), `CosmeticProjectile.luau:37-40`, `collectStream.luau:140-201`, `SkillVisuals.luau` (`spawnTelegraph`), `VfxBroadcast.luau` (telegraph kind), `BossStates.luau:176`, `client/BossWindupClient.client.luau` (delete), `BossWindupEvent` remote (delete).
Must not touch: `VfxConfig` effect entries; server delivery logic.

- [ ] Watcher extracted; four controllers become handler pairs with `disable()`/`destroy()`; decide and document whether Shield/Charge also watch tagged rigs.
- [ ] `ChargeOrbVfx`/`ShieldVfx`/`CosmeticProjectile` take their gameplay inputs as parameters.
- [ ] `MotePath` shared by `ChargeOrbVfx` and `collectStream`; jitter bands named.
- [ ] `spawnTelegraph` replaces `BossWindupClient`.

Done when: the four status visuals and the telegraph render on a second client; `grep "require(.*Skills" src/shared/Vfx` returns only `SkillConstants`.
Wiki: [[systems/VisualEffects]], [[systems/SkillPipeline]] (status visuals section).

---

## Chunk 11 — Boss ownership

Status: open
Findings: F5, F11, F33 (AI folder), F35 (laser + melee), F39
Risk: M · Playtest: **yes** — freeze the boss across a phase change and confirm the restored speed is the new phase's; boss turns without jitter; NPC tracer visible · Depends on: chunk 9 · Blocked on: nothing

Owns: `src/server/Boss/**`, `src/server/NPC/Scripts/{Perception,StateMachine,Actions}.luau` → `src/server/AI/Scripts/`, `src/shared/Skills/SkillEffects.luau:98,209` (speed multiplier), `src/shared/Weapon/**` (delete or `LaserBeam.model.json`), `src/shared/Boss/BossConfig.luau`, `Suites/Melee/*` (delete if still present).
Must not touch: `Hittables` (chunk 9); `applyDamage`.

- [ ] `baseWalkSpeed` attribute owned by the spawner; SkillEffects freeze applies/restores against it.
- [ ] `AlignOrientation` on the boss HRP; `BossStates.luau:86` CFrame write removed.
- [ ] Perception/StateMachine/Actions moved to `server/AI/`; Boss requires updated.
- [ ] `laserBeamEffect` → `VfxBroadcast.beam` (the export exists, unused) with a client draw, or `LaserBeam.model.json` checked in; `Actions.MeleeAttack` + `Weapon/Melee/*` deleted.
- [ ] Boss/NPC magic numbers named (`BossConstants`, `NPCConstants`).
- [ ] Reduce `(bb :: any)` where a typed Blackboard field suffices.

Done when: the playtest above; `src/shared/Weapon` is gone or contains only `Objects/`.
Wiki: [[systems/Boss]], [[systems/NPC]], [[systems/Weapon]] (final REMOVED note).

---

## Chunk 12 — HUD ports and the settings call

Status: open
Findings: F24, F25, F38 (remaining)
Risk: L–M · Playtest: **yes** (each ported GUI renders at two viewport sizes) · Depends on: chunk 3 · Blocked on: nothing (Q5 answered)
Decision: Q5(a) — settings menu is cut (builder, config, script, `P` keybind); file a tracker for a real settings surface. Q11 — `shared/Hud` stays.

Owns: `src/client/UI/{DeathScreenGui,DamageFeedbackGui,GameStateGui,ScoreboardGui,BossHudGui,KillFeedGui}.client.luau` + new Builder/Config pairs; `SettingsMenu*` (delete per Q5(a)); `HudConstants.LAYERS`.
Must not touch: HudGate; region registrations.

- [ ] Delete `SettingsMenuGui.client.luau`, `SettingsMenuBuilder.luau`, `SettingsMenuConfig.luau` and the `P` keybind; file a `task` tracker for a future settings surface.
- [ ] `HudConstants.LAYERS`; each self-owned ScreenGui reads it and gets a `UIScale` from `HudLayoutManager`.
- [ ] Port the six GUIs to Builder+Config, one per commit.

Done when: no `DisplayOrder = <literal>` in `src/client/UI`; all six render correctly at 720p and 1440p.
Wiki: [[systems/HUD]].

---

## Sequencing summary

```
0 lights off ──► 1 tests ──► 2 constants ──► 4 damage ──► 5 respawn ──┐
                    │                              │                   ├──► 8 sessions ──► 9 arena ──► 11 boss
                    └──► 6 economy ────────────────┘                   │
0 ──► 3 HUD ownership ──► 12 HUD ports                                 │
4 ──► 7 VFX lane ──► 10 presentation                                   │
```

Chunks 8 and 9 are the prerequisites for Phase 6 stage 5; chunk 4 is the prerequisite for stage 6. Chunks 0–3 can run in any order after 0 and are safe to interleave with Phase 6 work. Chunks 4, 7, 8, 9 must not run in parallel with each other or with a Phase 6 stage.

## Divergence log

Append here when a chunk lands differently from the plan (what changed, why, which finding it affects).

- **Chunk 3** ran before chunk 1, so the new `HudGate` suite (`src/shared/Hud/__tests.luau`, `M.run()`) was invoked directly via `execute_luau` rather than through the not-yet-wired `Suites/Unit` autorunner. It is **client-only** — `HudGate` resolves `Players.LocalPlayer` at require time, so it errors on the Server datamodel; whoever wires chunk 1 needs to put it in a client-side suite, not the shared Unit list. Scenario 1 of that suite asserts the *broken* F4 outcome for a non-compliant owner on purpose (it is the only way to pin why the rule exists); the assertion message says to delete the scenario rather than weaken it if the gate ever learns to see the missing write. The `TopRight` item took `stackVertical` rather than the "BuffTray to its own region" alternative; the tray's container additionally moved to `AutomaticSize.XY` with a zero authored size, because `AutomaticSize` treats the authored `Size` as a minimum and the old `ICON_SIZE`-tall frame would otherwise have reserved a row in the new stack and pushed the kill feed down with no buffs active. Part of this chunk's diff (`DeathScreenGui`, `HudConstants`, `SpellMenuConfig`, `SpellMenuGui`, `GameplayHudGui`) was swept into chunks 0 and 2's commits by whole-file staging in a shared checkout — the changes are correct and verified, they just do not all sit in chunk 3's commit.
- **Chunk 2** ran before chunk 1 (its stated `Depends on`); chunk 1 had not landed. Unit tests (`WordBuffer`, `EnergyEconomy`, `EnergyReservoirs`, `SpellRegistry`, `MemorizeAction`, `MindFullManager`, `CastAction`) were invoked directly via `execute_luau` (each module's own `.run()` / `.runAll()` shape) rather than through the (not-yet-wired) autorunner Unit suite. `MemorizeAction.__tests` failed a pre-existing, chunk-2-unrelated assertion (see `wiki/log.md` 2026-09-08 ingest) — flagged, not fixed, since it is outside chunk 2's `Owns`.
