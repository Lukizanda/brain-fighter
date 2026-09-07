---
type: design
description: Whole-repo system design audit (2026-09-07) — what closed since 2026-06, what is still open, and what the sessions refactor exposed. Headline = the damage path bypasses HealthService and blocks PvP kill credit; ScoreTracker/respawn/targeting are still server-wide; the HUD gate and the VFX relay each have one authority hole. Companion refactor plan in design/refactor-plan-2026-09.
updated: 2026-09-08
---

# System Design Audit — 2026-09-07

Design-and-structure audit of everything under `src/`, run against the three prior audits ([[design/system-audit-2026-06]], [[design/ui-architecture-review]], [[design/client-server-boundary]]) as a baseline, not as truth. Method: `wiki/index.md` → `git log` (178 commits; template cut at `6610291`; Phases 5.6–5.8 and 6 stages 1–4 since) → three read-only area sweeps (gameplay chain + Skills/VFX; world/session/server; HUD/client/tests) with Ollama doing the bulk reads → every finding below re-read at its `file:line` before it went in. No code was changed. No playtest was run; anything that needs one is tagged **[UNVERIFIED]** with what would confirm it.

Ordered, tickable refactor plan: [[design/refactor-plan-2026-09]]. New phase recorded in [[design/build-plan]] § Phase 7.

## Headline

The Brain Fighter chain is in better shape than in June: the Skills leak is closed, BossAdapter and the template stack are gone, the Skills pipeline has a named authoritative/predicted split, and Phase 6 gave rounds, block pools, spawns and screen-space broadcasts an arena to belong to. The debt has moved, not vanished. **The single most consequential structure is the damage path**: player spells still write `Humanoid.Health` directly, so a spell kill never fires `PlayerEliminated` — no kill credit, no kill feed, no death handler, no PvP gate — which means Phase 6 stage 6 (duels) cannot ship on today's code. Behind it sit three things the sessions refactor deliberately left server-wide (`ScoreTracker`, spawn threat scoring, boss/NPC/targeting), a three-way respawn ownership split, one authority hole each in the HUD gate and the client→server VFX relay, and a test harness where seven of ten unit suites are not wired to the runner. The strategic call from June — cut the template — was made and executed; the strategic call now is **where authority lives for damage, PvP and the economy** before any more session work stacks on top.

## Since 2026-06

| June finding | Status 2026-09 | Evidence |
|---|---|---|
| T1-1 Per-Humanoid state leak in `Skills/` | **CLOSED** | `SkillEffects.luau:215-223`, `:287-293` Died/HealthChanged/Destroying purge; `SkillInterrupt.luau:74-82`; `SkillBuffs.luau:85-92` |
| T1-2 BossAdapter half-retired | **CLOSED** | deleted in `6610291` |
| T1-3 Split-brain damage path | **OPEN, escalated to H** | `SkillEffects.luau:172,174` still write `Health` directly; `useApplyDamage` only in `BossConfig.luau:64,79,130`. See F1 |
| T1-4 Server trust gaps (ConsumeBlock / SpellCast) | **PARTLY CLOSED** | payload/range/rate validation landed (5.4); affordability is checked by `EnergyLedger.checkCast` (`SpellCastService.server.luau:122`) but `EconomyConstants.ENFORCE = false` (`:25`) so nothing is refused. See F8/F9 |
| T2 Doc-as-code, duplicate Staff script, malformed pragmas | **CLOSED** | deleted with the template / 5.7 |
| T2 DevDebug stale `;` header | **OPEN** | `DevDebug.client.luau:15,144` (F38) |
| T3 Color type ×4 | **OPEN, grown** | now ×5 types and ×6 literal lists (F27) |
| T3 Magic numbers in Skills/Vfx | **OPEN, reduced** | inline defaults remain (F31); `rbxassetid://0` placeholders are gone |
| T3 `Skills/` has zero tests | **CLOSED** | `Skills/__tests.luau` + `Suites/Skills/*` (5 files) |
| T3 Lifecycle drift (FreezeVfx, VfxController, SkillDelivery) | **OPEN** | `SkillDelivery.luau:157` module-scope Heartbeat; client Vfx controllers have no `destroy()` (F45) |
| T3 `(bb :: any)` in Boss AI | **OPEN** | 17 sites in `BossStates.luau`, 5 in `BossController.luau` |
| T3 Dead `damageAmpMultiplier` | **CLOSED** | zero hits |
| T3 Silent `ok=true` stubs (shield/buff/wall) | **CLOSED** | real handlers `SkillEffects.luau:329-353`, `SkillDelivery.luau:908` |
| Strategic: template keep-or-cut | **DECIDED — cut** (`6610291`) | a second layer of remnants survived; see F34–F37 |
| Forward trap: LocomotionController vs freeze WalkSpeed | **MOOT** — Locomotion deleted | replaced by a new fight: BossController vs freeze (F5) |
| UI R-5 TopRight/TopCenter overlap | **OPEN** | F20 |
| UI R-6/R-7 SpellMenu/BuffTray magic numbers | **OPEN, grown** | F23 |
| UI R-8 untracked tween connections | **OPEN (accepted)** | not re-tabled |
| UI R-9 `_G.PlayerHud` write-only | **OPEN** | F22 |
| Boundary stages 1–6 | **CLOSED** | `SkillDelivery.luau:102,327,838,912` gate on `ctx.mode`; `predicted_run_writes_nothing` suite |
| Boundary "BlockShoot/LetterBlaster/BlockSpawner came back clean" | **INCOMPLETE** | the audit never looked at the client-originated `BroadcastSpellVfx` relay, the one remaining client-trusted gameplay-adjacent remote (F6) |

**Regressed:** nothing that was closed has reopened. Two things got *worse by context*: the split-brain damage path went from "UI sees a subset" to "PvP cannot credit a kill" once duels became a planned mode, and the singleton `ScoreTracker` went from harmless to wrong once a second session could exist.

## Findings

Severity: **H** = blocks a planned phase or is a correctness/authority hole; **M** = structural debt paid on the next touch; **L** = hygiene. Effort: **S** < ½ session, **M** ≈ 1 session, **L** > 1 session.

### Authority and ownership

| ID | Area | Sev | Eff | file:line | Symptom | Recommended change |
|---|---|---|---|---|---|---|
| F1 | Damage | **H** | M | `src/shared/Skills/SkillEffects.luau:172,174,184` | Player spell damage and heal write `Humanoid.Health` directly; only boss specs set `useApplyDamage` (`BossConfig.luau:64,79,130`). `applyDamage.process` is the only path that fires `PlayerDamaged`/`PlayerEliminated` (`applyDamage.luau:101,131`), fills `pendingRespawns` (`:135`) and honours `PLAYER_VS_PLAYER_ENABLED` (`:41`). A spell kill therefore never reaches `GameModeService.onPlayerEliminated` (`init.server.luau:479`) → `ScoreTracker.recordKill` (`:417`), never reaches `DeathHandler.handleDeath` (`:173`), never sends `DamageFeedback`. The shield pool needed a second drain site because of it (`SkillBuffs.luau:236-244`). | Make `applyDamage.process` the only `Health` writer. Inject the sink from the server instead of the upward `pcall(require)` at `SkillEffects.luau:44`; carry `sourcePlayer` + a cause id in the request; delete the direct-write branches. Prerequisite for Phase 6 stage 6. |
| F2 | Damage | M | S | `src/server/Arena/DeathZoneService.server.luau:37` | `humanoid:TakeDamage(MaxHealth + 1)` is a third `Health` writer; same consequences as F1. | Route through `applyDamage.process` with `sourcePlayer = nil`. |
| F3 | Respawn | **H** | S | `GameModeService/init.server.luau:345-365`; `HealthService/init.server.luau:46-62`; `applyDamage.luau:135` | Three player-respawn paths: GameModeService `Died` → `LoadCharacter`; HealthService `RequestRespawn` remote → `LoadCharacter`; the engine's `CharacterAutoLoads` (never set false — only a comment at `init.server.luau:322`). `pendingRespawns[player]` is set on lethal `applyDamage` and cleared only inside `onRequestRespawn` or on leave, never on `CharacterAdded`, so after the auto-respawn a later `RequestRespawn` (sent by `DeathScreenGui.client.luau:79`, or by any client) passes both checks and reloads a *living* character. **[UNVERIFIED]** engine double-spawn: die once with `CharacterAdded` logged. | One owner. GameModeService respawns (it knows the session); delete the HealthService remote path or make it a request the session answers; set `Players.CharacterAutoLoads = false`; clear `pendingRespawns` on `CharacterAdded`. |
| F4 | HUD gate | **H** | S | `DeathScreenGui.client.luau:44,86,96`; `shared/Hud/HudGate.luau:142-150` | DeathScreenGui binds `screenGui.Enabled` to the gate (`ArenaOnly`) *and* writes that property itself. Gate closed + `show()` writes `true` → gate records `ownerWants = true` and re-suppresses; `hide()` writes `false` to an already-false property, which fires no changed signal, so `ownerWants` stays `true`. Next arena entry reveals the death overlay to a living player — the leak [[concepts/HudGate]] exists to stop. Lobby deaths are real (DeathZone; the stage 4a log describes a player who "fell off the lobby"). | Owners never write a gated property: DeathScreenGui toggles a child `overlay.Visible` (as GameStateGui/ScoreboardGui do), or HudGate gains `setOwnerWants(instance, bool)`. Add a test for the closed-gate write sequence. |
| F5 | WalkSpeed | M | S | `SkillEffects.luau:98,209`; `Boss/Scripts/BossController.luau:178`; `NPC/NPCService.server.luau:139` | Three writers of the same Humanoid's `WalkSpeed`. A boss phase change during a freeze writes the new speed over the frozen 0, then `purgeFreeze` restores the captured pre-phase speed. The June "forward trap" reincarnated. | One owner per rig: a `baseWalkSpeed` attribute set by Boss/NPC spawners; SkillEffects applies a multiplier against it rather than a captured value. |
| F6 | VFX authority | **H** | M | `client/Vfx/VfxController.client.luau:140`; `server/Vfx/VfxBroadcastService.server.luau:26-36,94-104,116` | Spell cosmetics reach other clients three ways: client-originated `BroadcastSpellVfx` → `SpellVfxEvent:FireAllClients` (client chooses `impactTarget`, any BasePart under Workspace, and `impactEffectIds`); server `VfxBroadcast` → `WorldVfxEvent`; `SkillDelivery.luau:129-134,626` firing `ProjectileVfxEvent` directly. Path one predates Phase 5.6, fires even when the server rejects the cast, carries a hand-rolled rate limiter and colour list, and [[design/client-server-boundary]] never listed it. | Delete `BroadcastSpellVfx`/`SpellVfxEvent`/`VfxBroadcastService`. The authoritative run raises cast + impact cues through `SkillVisuals`/`VfxBroadcast` with `drawnLocallyBy = predictedBy` (parameter exists, `SkillVisuals.luau:163`). Route `ProjectileVfxEvent` through `VfxBroadcast` too. |
| F7 | VFX prediction contract | M | S | `VfxController.client.luau:117-127` | The predicted path draws impact bursts at the target for non-projectile spells before the server accepts the cast, contradicting the "no mispredicted hit marker" contract quoted in the same file's header (`:17-21`). | Prediction draws the cast cue only; impact cues come from the authoritative broadcast (with F6). |
| F8 | Economy trust | M | S | `server/Economy/EconomyConstants.luau:25`; `SpellCastService.server.luau:122-129` | `ENFORCE = false`: affordability is computed and logged, then the handler debits and continues. The cast rate limit is the only thing stopping an unlimited-energy client. The flip criterion ("zero rejections against honest play") has not been measured. | Needs your input (Q3). F9 must land first or the flip is meaningless. |
| F9 | Economy drift | **H** | S | `client/EnergyRoundReset.client.luau:56`; `server/Economy/EnergyLedger.luau:312-320` | The client zeroes its reservoirs on the transition into `Active`; nothing zeroes the server ledger — `EnergyLedger.reset()` has no callers outside the suite, `forget` runs only on `PlayerRemoving` (`EconomyService.server.luau:70`). The ceiling carries across rounds and lobby banking, so once `ENFORCE` flips the server is permanently richer than the client and never refuses. | `EconomyService` resets each roster member's account on the session's round start (server side — `roundStartedEvent` exists and has no listener, F19). |
| F10 | Charge tier trust | L | M | `SpellCastService.server.luau:95`; `SpellCast/ChargeStateService.server.luau:22-30` | The server takes the client's `tier`; `ChargeStateService` records the charge as a cosmetic attribute the cast handler never reads. [[systems/SpellCastService]] § "Not checked: hold duration" records this as accepted (a liar gains speed, not mana). Listed for completeness. | Needs your input (Q4). |
| F11 | Boss transform | M | M | `Boss/Scripts/BossStates.luau:86` | `bb.humanoidRootPart.CFrame = currentCFrame:Lerp(...)` every Attack/Cooldown tick while `Actions.MoveToWithPath` (`:123`) drives the same Humanoid. Violates the project's HRP.CFrame rule; two-writer fight. | `AlignOrientation` (RigidityEnabled) on the boss HRP owned by BossController; BossStates sets only the target. |

### Session scope (what Phase 6 left server-wide)

| ID | Area | Sev | Eff | file:line | Symptom | Recommended change |
|---|---|---|---|---|---|---|
| F12 | ScoreTracker | **H** | M | `GameModeService/ScoreTracker.luau:36,316-323`; `RoundManager.luau:225,249,269` | Scores are one server-wide table. Each session's round start calls `resetAll`, which zeroes *every* player; `checkWinCondition`/`getRoundLeader` read `getAllScores()` for all players. With two round-running arenas, A's round start wipes B's kills and B's win check sees A's players. Deferred to stage 5 (`init.server.luau:19`); it is a prerequisite for stage 5, not part of it. | `ScoreTracker.new(roster)` per session, owned by `RoundManager`; leaderstats stays a thin server-wide mirror. |
| F13 | SpawnManager | M | S | `SpawnManager.luau:50,208,223` | Pads are per-arena (stage 2) but `getLivingEnemyPositions` iterates `Players:GetPlayers()`, so hub and other-arena players count as threats. Two magic offsets. | Pass the session roster as the enemy set; name the offsets in `GameModeConstants`. |
| F14 | Boss / NPC / targeting | M | M | `Boss/BossService.server.luau:156`; `NPC/NPCService.server.luau:36,164-171`; `NPC/Scripts/Perception.luau:82`; `Skills/SkillDelivery.luau:176-180` | One boss per server (`workspace:FindFirstChild("BossPoint")`), NPCs spawned with no arena, and both `Perception` and `collectHittables` scan every player on the server. Two "valid target" definitions (range+LOS+Health vs tags+all players). Not a bug today because the hub is 533 studs away; a prerequisite for stage 5. | Tag BossPoints/NPC spawns with `ArenaId`, spawn per session, filter candidates by `Arena.idOf`. Merge the two target definitions behind one `Hittables` helper (F30). |
| F15 | BlockShoot | M | S | `BlockShoot/BlockShootService.server.luau:128-169`; `shared/BlockSpawner/init.luau:426-437` | `ConsumeBlock` validates rate, tag and range but not arena membership; spawned blocks carry no `ArenaId`. Range (300 studs) is the only thing keeping a hub player off arena blocks. Fine for one hub, wrong for adjacent arenas. | Stamp `ArenaId` on spawn (the pool knows `self.arenaId`) and reject a mismatch. |
| F16 | GameModeService | M | L | `init.server.luau:71-75,451,459`; `Lobby/LobbyService.server.luau:37-38,182,198,216`; `Dev/BotSpawner.server.luau:60` | Session tables live in a Script, so every consumer goes through an untyped `BindableFunction` and the broadcast resolver is injected by hand (`:291-303`). | Extract a `SessionRegistry` ModuleScript owning `sessions`/`playerSessions`/`queued` + `transferPlayer`/`setQueued`/`forPlayer`/`forArena`; thin bootstrap Script. Before stage 5 adds a third consumer. |
| F17 | ScoreTracker leak | M | S | `ScoreTracker.luau:37,87-99,123` | `recentDamage[Humanoid]` appends on every `PlayerDamaged`, purged only for Player victims or on `resetAll`. Boss/NPC hits accrue forever in a session that never ends a round (Lobby, NoOp). | Expire on insert past `ASSIST_TIME_WINDOW`; drop the key on `Humanoid.Died`/`Destroying`. |
| F18 | Lobby remote | L | S | `LobbyService.server.luau:222-231` | `lastRequestAt` is stamped after `validate`, so malformed payloads are never throttled and each one logs. | Stamp before validate, or use `RateLimiter`. |
| F19 | Dead server events | L | S | `HealthService/init.server.luau:61` (`PlayerRespawned`); `RoundManager.luau:227,279` (`RoundStarted`/`RoundEnded`) | Fired, no listener anywhere. `RoundStarted` is exactly the hook F9 needs. | Wire or delete. |

### HUD

| ID | Area | Sev | Eff | file:line | Symptom | Recommended change |
|---|---|---|---|---|---|---|
| F20 | Region overlap | L | S | `BuffTrayGui.client.luau:26`; `KillFeedGui.client.luau:63`; `HudConstants.luau:46-52` | Two TopRight registrants, no `stackVertical`. Latent — carried from R-5. | `stackVertical` on TopRight or a dedicated region. |
| F21 | UI runs gameplay | M | M | `client/UI/SpellMenuGui.client.luau:43,72-80,214,230` | The HUD coordinator resolves targets (CollectionService scan + `workspace:FindFirstChild("Boss")` by name), runs `CastAction.castSpecific` and relays to the server. `AUTO_TARGET_RANGE_STUDS = 150` is duplicated on the server (`SpellCastConstants.luau:22`). | A `client/SpellCastController` owns target resolution + cast + relay; SpellMenuGui forwards `menu.cast` and plays feedback. Range constant on `SpellRegistry`, read by both sides. |
| F22 | `_G` | L | S | `GameplayHudGui:123-126`, `SpellMenuGui:251-252`, `MindFullIndicatorGui:38-39`, `BuffTrayGui:28-29`, `DashButtonGui:47-48`; `DashManager.client.luau:36-37` ↔ `DashButtonGui:39` | `_G.PlayerHud` is write-only (no reader anywhere). The dash bridge is the only live `_G` contract. | Delete the `PlayerHud` writes; replace the dash bridge with a client ModuleScript or BindableEvent. |
| F23 | Builder/Config | M | S | `SpellMenuBuilder.luau:119-126,267,300,448-449,958`; `SettingsMenuBuilder.luau:178,207-208,215,349-350,433-434,499-500`; `AttributeBarBuilder.luau:63,117-118,199-202,230-241`; `BuffTrayBuilder.luau:82-83,102`; `PortalPanelBuilder.luau:208-225`; `MemorizeButtonBuilder.luau:128` | Inline geometry, colours and Z-index ladders that belong in the sibling Config. R-6/R-7 grew. | Mechanical extraction into each Config. |
| F24 | Hand-built GUIs | M | L | `DeathScreenGui.client.luau:47-76`; `DamageFeedbackGui.client.luau:47-49`; `GameStateGui`, `ScoreboardGui`, `BossHudGui`, `KillFeedGui` | Six live ScreenGuis bypass Builder+Config, own their ScreenGui, get no `UIScale` (ignore `HudConstants.REFERENCE_HEIGHT`, `HudLayoutManager.luau:36-38`). `DisplayOrder` literals 15/20/25/30 per file while `HudConstants.luau:66-71` holds unread weapon-era aliases. | Port as each is next touched; add `HudConstants.LAYERS`. |
| F25 | Settings menu | M | M | `SettingsMenuGui.client.luau:26-31,83-100`; `SettingsMenuBuilder.luau` (690 lines) | Writes `Settings_*` attributes that nothing reads; the reticle consumer `ReticleBuilder` has no requirers. A shipped menu that does nothing. | Needs your input (Q5). |
| F26 | Dead HUD code | L | S | `shared/Hud/{ReticleBuilder,ReticleConfig,TouchControlBuilder,TouchControlConfig}.luau`; `HudLayoutManager.luau:89-90,119,123`; `TeamScoreGui.client.luau:29` | Four Builder/Config files with zero requirers (TouchControl builds Shoot/Reload buttons); `unregister`/`moveToRegion`/`_onInputCategoryChanged` uncalled; TeamScoreGui returns at boot. | Delete. |

### Duplicated concepts and layering

| ID | Area | Sev | Eff | file:line | Symptom | Recommended change |
|---|---|---|---|---|---|---|
| F27 | Colour vocabulary | M | S | `WordBuffer:36`, `EnergyEconomy:131-134`, `EnergyReservoirs:47-49`, `SpellRegistry:30`, `CastAction:51`; literal lists `BlockSpawner:68`, `VfxConfig:144,1644`, `VfxBroadcastService:27`, `SpellMenuConfig:31`, `DevDebug:33-34` | ×5 types, ×6 literal lists; `Tile` declared in both WordBuffer and EnergyEconomy; the server requires `EnergyReservoirs` just to reach `COLORS`/`CAP_PER_COLOR` (`ChargeStateService:39`, `EnergyLedger:39`). | One `shared/Core/Colors.luau` (`SpellColor`, `TileColor`, `Tile`, `SPELL_COLORS`, `isSpellColor`). |
| F28 | Attribute→VFX watchers | M | M | `client/Vfx/FreezeVfxController:46-150`, `InfernoVfxController:41-182`, `ShieldVfxController:38-118`, `ChargeOrbController:55-161` | Four copies of the same watch/unwatch/bindPlayer/AncestryChanged machinery; Freeze/Inferno also watch tagged rigs, Shield/Charge watch players only (a shielded boss would render nothing). | Extract `shared/Vfx/CharacterAttributeWatcher.luau`. |
| F29 | Presentation → gameplay | M | S | `shared/Vfx/CosmeticProjectile.luau:37-40` (requires `SkillBuffs`, `SkillVisuals`); `StatusVisuals/ChargeOrbVfx.luau:51` (`SpellRegistry`); `StatusVisuals/ShieldVfx.luau:28`; `client/Vfx/VfxController.client.luau:35` (requires `CastAction` → whole executor, only for `spellResolved`) | Cosmetic modules depend on gameplay state; the client VFX relay drags SkillDelivery in and pays a module-scope Heartbeat for a cache it never uses (`SkillDelivery.luau:157`). | Pass tier/name/shielded-root data in from controllers; expose `spellResolved` as a bindable under `CastAction/Remotes`; connect the hittables cache lazily, server-only. |
| F30 | Rig collection ×2 | M | S | `SkillDelivery.luau:146-175,501`; `CosmeticProjectile.luau:133-136,160-190,419` | `collectHittables` and `collectRigs` are near-copies with the same cache and shell-padding maths; the comment admits they "need to change together". | One `Skills/Hittables.luau` used by both sims (also the seam for F14's arena filter). |
| F31 | Skills defaults | L | S | `SkillDelivery.luau:333-341,376,844-846`; `SkillEffects.luau:191,309` | Per-handler inline fallbacks (`or 30`, `or 3`, `or 12`, `or 0.5`, `or 1.0`, `or 50`) while `DEFAULT_BURN_SEC` (`SkillEffects:110`) shows the intended pattern. | Move into `SkillConstants`. |
| F32 | Tier-at-hold ×2 | L | S | `SpellMenuBuilder.luau:722-733`; `CastAction/init.luau:194,223,244` | The builder reimplements `resolveSpecAtCharge`'s climb because it cannot require CastAction; `tapReservoir`/`resolveTapSpec` have no production caller. | `SpellRegistry.tierAtHold(color, heldSec, ceiling)` (pure), used by both; delete `tapReservoir` + its tests. |
| F33 | Boss AI placement | L | M | `BossController.luau:24-25`, `BossStates.luau:36` (require `NPC.Scripts.*`); `BossWindupClient.client.luau:27-104` vs `SkillVisuals.luau:276-278` | Boss reaches into NPC's private folder for shared AI primitives; the windup telegraph is a hand-built disc with its own RemoteEvent (`BossStates:176`) and inline tuning, parallel to `spawnShockwave`. | Move Perception/StateMachine/Actions to `server/AI/`; add `SkillVisuals.spawnTelegraph` + a `VfxBroadcast` kind; delete `BossWindupClient`. |

### Dead, vestigial, and config

| ID | Area | Sev | Eff | file:line | Symptom | Recommended change |
|---|---|---|---|---|---|---|
| F34 | Template remnants, round 2 | M | M | `applyDamage.luau:57-69` (Team FF branch), `SpawnManager.luau:56,115-145`, `NametagService.server.luau:48-50,80-84`, `RoundManager.luau:44,142,250-291` (`winnerTeamName`), `GameModeDefinition.luau:54-64` (`getTeamConfig`, unread `checkWinCondition`/`getRoundLeader`), `GameModeTypes.luau` (zero requires), `NoOpMode.luau:43` (`"FFASpawn"` outside `Arena.SpawnTags`), `init.server.luau:401-407` (weapon name from an equipped Tool → always "Unknown") | The cut removed the modes but not the team/weapon plumbing. `GameConfig.luau:26-29` still says the template is "gated off rather than deleted so a single flag flip restores it" — false since `6610291`. | Delete the team branches and unread fields; carry a cause id in `DamageResult`; rewrite the GameConfig comment. Q7 for the round/PvP flags. |
| F35 | Dead scripts and modules | L | S | `server/Dev/SimulateLoadoutCycling.server.luau` (`:87` references missing `Weapon.Templates`), `server/Dev/DevAutoEquipTool.server.luau`, `server/Dev/BotSpawner.server.luau` (needs Teams; `:244` still hooks `PlayerEliminated`), `src/utility/{adjustListIndexAfterRemoval,bindToInstanceDestroyed,disconnectAndClear,safePlayerAdded}`, `shared/Core/Cleanup.luau`, `server/Utility/TypeValidation/{validateCFrame,validateSimpleTable}`, `Actions.MeleeAttack` (`Actions.luau:374`) + `shared/Weapon/Melee/*`, `SkillTypes.luau:74-75` (`vfxName`/`sfxName`), `VfxBroadcast.beam`, `Dictionary.getStats`, `WordBuffer:colorBag`, `PlayerSession.destroy` | Zero requirers/callers. `laserBeamEffect.luau:7` and `NPCService.server.luau:70` reference `Weapon.Objects.LaserBeam` / `Weapon.Templates`, neither on disk — the NPC tracer depends on `.rbxl`-only instances behind a `pcall` (`Actions.luau:324`). **[UNVERIFIED]** whether `LaserBeam` exists in the `.rbxl`: inspect `ReplicatedStorage.Shared.Weapon` in Studio. | Delete; check `LaserBeam` into `src/` as `.model.json` or route the tracer through `VfxBroadcast`. Melee chain goes with the Melee suite. |
| F36 | GameConfig hygiene | M | S | `GameConfig.luau:41-42` (`TPS_CHARACTER_ENABLED`, `SHOW_WEAPON_ROLODEX`: zero readers), `:73-75` (three locomotion multipliers: zero readers), `:47-50` (three DEV flags read only by dead scripts), `:51` (`DEV_COUNT_POP_VFX = true` — "turn back off when done", still on; installs `workspace.DescendantAdded` on every client) | Config that outlived its consumers; one dev instrumentation flag shipping on. | Delete the unread keys and dead DEV flags; flip `DEV_COUNT_POP_VFX` to false. |
| F37 | Unread constants | L | S | `GameModeConstants.luau:7,8,16`; `HealthConstants.luau:6,9,33`; `NPCConstants.luau:41`; `HudConstants.luau:66-71` | Zero readers each. | Delete or wire. |
| F38 | Duplicated / inconsistent constants | L | S | `HealthConstants.luau:3` (`RESPAWN_TIME = 5`) vs `GameModeConstants.luau:14` (`= 4`) with `DeathScreenGui.client.luau:101-103` picking by round state — hub players see a 5 s countdown after a 4 s server respawn; `FIZZLE_PLAYBACK_SPEED = 0.55` ×3 (`BlockTapController:47`, `GameplayHudGui:39`, `SpellMenuGui:87`); `REJECTION_LOG_THROTTLE_SEC` 5 vs 10 (`EconomyConstants:41` claims to match `SpellCastConstants:49`); `DevDebug.client.luau:34` re-declares `TIER_COSTS`; eye height `Vector3.new(0,1.5,0)` ×3 (`Perception:51`, `Actions:269,303`); DevDebug `;` hotkey documented at `:15,144` with the handler in `BossHudGui:146`; `BossHudGui:94` says "toggle with P" | One constant each; client reads `respawnTime` from the GameState payload. |
| F39 | Magic numbers, server | L | S | `HealthService/init.server.luau:54`, `BossService:79,138`, `NPCService:133,208`, `BossStates:80,85,187,227,277`, `DeathHandler:60,66-73`, `DamageModifierRegistry:30`, `DashController:105,140`, anim fade `0.2` ×3 | Named-constant rule not applied outside the spelling chain. | Name in the owning `*Constants` as each file is touched. |
| F40 | Magic numbers, VFX | L | S | `collectStream.luau:171,196,379`; `ChargeOrbVfx.luau:396,424`; `ScreenImpact.luau:186`; `spawnEffect.luau:94,129,179`; `BarrierCrumbleController:850-851`; `BossWindupClient:27-104` | Jitter bands and blend factors inline; `ChargeOrbVfx:389-430` and `collectStream:140-201` duplicate the Bézier mote helpers. | Name the bands; extract `Vfx/MotePath.luau`. |

### Tests

| ID | Area | Sev | Eff | file:line | Symptom | Recommended change |
|---|---|---|---|---|---|---|
| F41 | Unwired unit tests | M | S | `Suites/Skills/{castaction_tests,skillinterrupt_smoke,spellexecutor_tests}.luau` are the only wrappers; `EnergyEconomy/__tests.luau` ends `return runAll()`, `Dictionary/__tests.luau` ends `return true` (both execute on require); `WordBuffer/__tests` returns a function | Seven of ten `__tests.luau` (WordBuffer, EnergyEconomy, EnergyReservoirs, Dictionary, SpellRegistry, MemorizeAction, MindFullManager) are unreachable from `TestAutoRunner` (`:34-48`). The economy the server ledger now mirrors is the least-run code. | A `Suites/Unit/` folder with one thin wrapper per module; normalise every `__tests` to `return { run = ... }`. |
| F42 | Dead suites | M | S | `Suites/Multiplayer/drop_request_zone_gated.luau:22,59`; `respawnzone_tracks_hrp_presence.luau:21`; `multiplayer_invariants.luau:61-63,86-105`; `applydamage_credits_bot_kill.luau:52-65,124`; `Helpers/restoreToSafeSpawn.luau:19` | Require `Server.Loadout.RespawnZoneService`, `_G.LoadoutService_tryDrop`, `Shared.Weapon.Remotes`, a `Teams` child — none exist. [[systems/Tests]] (2026-08-03) still lists them as live. | Delete the three; trim `multiplayer_invariants`; rewrite the Tests page. |
| F43 | Fixture-gated suites | L | S | `Suites/Melee/*:31`, `Suites/NPC/combat_engages.luau:12`, `applydamage_credits_bot_kill.luau:78-80` | Depend on `TargetDummy1`/`Patroller_1`/`leaderstats` that only the `.rbxl` provides. **[UNVERIFIED]** whether the place still has them: run `RunTests = "NPC"` once. | Build fixtures in `setup`, or header-mark them fixture-gated. Melee suite goes with F35. |
| F44 | Untested high-consequence paths | M | M | (absence) | Zero suite coverage for session transfer, spawn selection, score reset, boss cycle, DeathZone, `HudGate` (which already shipped one bug), `BlockTapController` pending-append reconciliation, `SpellMenuBuilder` charge climb, `SpellCastService` handler wiring, `ChargeStateService`, `VfxBroadcastService`. | Add in the order the refactor plan touches them; HudGate and transferPlayer first. |

### Lifecycle

| ID | Area | Sev | Eff | file:line | Symptom | Recommended change |
|---|---|---|---|---|---|---|
| F45 | Controllers without `disable/destroy` | L | S | `BlockTapController.client.luau:308,348-349`; `LetterBlockAnimator.client.luau:405`; `PortalGui.client.luau:278-279`; `NPCService.server.luau:209`; client Vfx controllers; `MindFullManager` (no `:disable()`) | Script-lifetime loops with nothing to pause them. Per-Instance state *is* purged correctly (`LetterBlockAnimator:388,484`; `BlockTapController:334,354`), so this is the convention, not a leak. | Wrap each in a controller table with `disable()`/`destroy()` when next touched. |

## Design-intent drift

Where the wiki and the code disagree, and which one I think is right.

1. **[[systems/Health]]:9,54 says every damage caller goes through `applyDamage`, and lists player spells among them.** The code does not (F1). The wiki's intent is right, the code is wrong.
2. **`SkillEffects.luau:40` comment: "player spells use direct Health writes (client-authoritative)".** Stale since Phase 5.6 stage 3. Code comment wrong; delete with F1.
3. **[[systems/SkillPipeline]]:487 "Pass `drawnLocallyBy` from any handler that runs on both VMs — `projectile` and `aoe` do … `casterUserIdFrom(source)`".** Both were removed in boundary stages 2 and 4. The page also keeps a "Reserved Hooks" section (`:451`) for `vfxName`/`sfxName` that shipped as dead fields. Wiki wrong.
4. **[[systems/SpellCastService]] frontmatter says affordability is "blocked"; the body says validated memorize landed in shadow; [[index]] says "still client-trusted".** All half-right: the check exists (`SpellCastService:122`), is dark (`ENFORCE = false`), and would drift if lit (F9). Wiki needs the one sentence that says exactly that.
5. **[[design/lobby]] stage 6 turns on PvP with `PLAYER_VS_PLAYER_ENABLED = true`.** The page records that the flag does not gate spell damage. Beyond that, a *global* flag is the wrong primitive once a PvE co-op and a PvP duel share a server: it must be a property of the session's mode. **The wiki's intent is wrong here**, not just stale (Q2).
6. **`GameConfig.luau:26-29`: the template is "gated off rather than deleted so a single flag flip restores it".** False since `6610291`. Code comment wrong; the flags should follow the modes out (F36).
7. **[[concepts/HudGate]] "the gate never reveals".** The ambiguity rule at `HudGate.luau:142-150` reveals in the DeathScreen case (F4). Wiki intent right, code wrong. The page should add the rule that makes the code safe: *owners never write a gated property*.
8. **[[design/client-server-boundary]] declares `VfxBroadcast` the server→client channel and lists the remotes it audited.** `BroadcastSpellVfx` (client→server→all) is absent and still live (F6). The page's model of "which VM runs what" is incomplete.
9. **[[systems/Tests]] (2026-08-03) lists Melee/Multiplayer suites as live, says nothing about `__tests` wiring, and omits Economy/Skills suites.** Stale (F41–F43).
10. **[[systems/VisualEffects]] frontmatter: "planned (PERF guardrails)".** `VfxConfig.PERF` exists at `:1618`. Stale.
11. **`VfxController.client.luau:17-21` header vs `:117-127` body.** The file quotes the prediction contract and then breaks it for non-projectile impacts (F7). The intent (boundary stage 6) is right; the code is wrong. [[design/build-plan]] Phase 5.6 stage 6 was closed slightly early.
12. **[[systems/GameMode]] body still describes the NoOp-only world** — flagged in the 2026-09-07 lint; stage 7 work.

Where wiki and code *agree* and I think both are wrong: the singleton `ScoreTracker` is documented as "stage 5" (`init.server.luau:19`; [[design/lobby]] § Deliberately not in stage 4). It is a prerequisite for stage 5, not part of it — a mode cannot have a win condition against a table that another session zeroes.

## Needs your input

Each is a call I cannot make from the code. Answer inline; the refactor plan assumes the recommended option where it needs one.

**Q1 — Damage authority (F1).** Where should player spell damage land?
- (a) **Recommended:** everything through `applyDamage.process`, with `SkillEffects` receiving the sink by injection and passing `sourcePlayer` + a cause id. One writer, one elimination event, kill credit and PvP gate for free. Cost: `DamageModifierRegistry` (armour, shield) now applies to spells — which is what the shield code already assumes.
- (b) Keep direct writes; add a parallel `SpellEliminated` event and a second kill-credit path. Two damage pipelines forever.
- (c) Direct writes for boss-vs-player only, applyDamage for player-vs-anything. Same double bookkeeping as (b).

**Q2 — PvP gating primitive (drift 5).** Once F1 lands, what decides whether player A may damage player B?
- (a) **Recommended:** an `allowsPvP` field on the mode's `getConfig()`, checked in `applyDamage` via the victim's session. Global `PLAYER_VS_PLAYER_ENABLED` deleted.
- (b) Keep the global flag and add a per-session override. Two switches for one question.
- (c) An `ArenaId`-equality rule ("same arena ⇒ may damage") with the mode deciding co-op exceptions. PvE co-op needs the exception on day one.

**Q3 — `ENFORCE` flip (F8/F9).** When does the ledger start refusing casts?
- (a) **Recommended:** land the round-reset hook (F9) and the tile cap first, run one measured playtest with the shadow log, flip in the same session if it shows zero honest rejections.
- (b) Flip now, watch the log. The reset drift means it will almost never reject, so "no rejections" proves nothing.
- (c) Keep shadow until PvP is live. Defers the only anti-cheat gate past the phase that needs it.

**Q4 — Charge tier trust (F10).**
- (a) **Recommended for now:** keep it accepted; record on the PvP page as a known tell-skip; revisit when duels are playable.
- (b) Server-timed charge: `ChargeStateService` owns the start timestamp, `SpellCastService` cross-checks `chargeTimeFor(tier)` with latency slack.
- (c) Server-timed for T3+ only.

**Q5 — Settings menu (F25).**
- (a) **Recommended:** cut it (builder, config, script, `P` keybind) and file a tracker for a real settings surface when there is something to set.
- (b) Wire sensitivity and FOV to the camera; delete the crosshair/aim-assist rows.
- (c) Leave it.

**Q6 — Session registry (F16).** Convert `GameModeService` to a module before or after Phase 6 stage 5?
- (a) **Recommended:** before. Stage 5 adds a third consumer and per-session `ScoreTracker` wants a typed home. After means doing stage 5 twice.
- (b) After stage 6, as stage 7 cleanup.

**Q7 — Round/PvP flags (F34/F36).** `TEAMS_ENABLED`, `PLAYER_VS_PLAYER_ENABLED`, `ROUND_TIMER_ENABLED`, `ROUND_COUNTDOWN_ENABLED` are global booleans, but stage 6 wants timer + countdown on for duels only.
- (a) **Recommended:** delete `TEAMS_ENABLED` and its branches; move the other three into the mode config (`allowsPvP`, `timeLimit`, `countdownSec`), read per session. `RoundTimerGui` stays and reads the payload.
- (b) Keep the globals and flip them per server. Only works if a server never hosts two modes.

**Q8 — Test strategy (F41–F43).**
- (a) **Recommended:** wire the seven unit suites under `Suites/Unit`, delete the dead Multiplayer suites and the Melee suite (with its dead chain), make fixture-gated suites create their own dummy in `setup`.
- (b) Delete the unwired `__tests` too and rely on Suites only. Loses ~200 asserts on the economy.

**Q9 — VFX relay removal (F6/F7).** Deleting the client-originated broadcast means the caster's *impact* cue arrives after server confirmation (one RTT); the cast cue stays instant.
- (a) **Recommended:** accept the RTT on impact cues; it is what the boundary design already says should happen.
- (b) Keep a predicted impact cue only for self-target and placement spells (never for a hit on another entity).

**Q10 — Boss/NPC per-session scope (F14).**
- (a) **Recommended:** a separate chunk (plan chunk 9) immediately before stage 5, so stage 5 is only the mode file and the queue.
- (b) Inside stage 5.

**Q11 — `shared/Hud` location.** Everything under `shared/Hud` is client-only in practice and two modules pull gameplay registries in. Move to `client/Hud`, or leave? Recommendation: leave; F27/F32 remove the gameplay pulls and the rest is a misnomer.

## Out of scope / not examined

- Art, assets, sounds, `VfxConfig` entry-by-entry tuning, the 26 `Dictionary/words/*` modules.
- Anything that lives only in `BrainFighter.rbxl` (lobby geometry, `BossPoint`, `TargetDummy` rigs, `Weapon.Objects.LaserBeam`, Animation objects). Three findings depend on it and are tagged **[UNVERIFIED]**.
- Runtime behaviour that needs a playtest: the two-session cross-talk test the stage 3 log says never ran; the engine auto-respawn double-spawn (F3); whether the `.rbxl` still has the test fixtures (F43); NPC tracer visibility (F35).
- Performance and network cost — [[systems/VisualEffects]] § PERF owns that.
- Boss AI *behaviour* quality, block spawn *tuning*, dictionary coverage, gameplay balance.
- `Packages/`, `tools/`, `evals/`, `.githooks/`, `graphify-out/`, `.claude/`, the Rojo project file, the pre-commit validator.
- `--!strict` coverage and type-annotation completeness (a lint pass, not a design question).
- New-feature design: the tutorial, persistence, the PvE/PvP mode files themselves.
