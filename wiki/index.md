---
type: index
description: Catalog of every Brain Fighter wiki page, grouped by category. Updated on every ingest.
updated: 2026-09-22
---

# Wiki Index

Start here. See [[WIKI]] for conventions and operations.

## Design

- [[design/gameplay-loop]] — canonical core loop: aim → shoot letter blocks → buffer/arrange → cast color-typed spells; tuning, spell roster, worked examples
- [[design/build-plan]] — phased build plan with parallel/sequential dependencies; one tracker per system
- [[design/ArtDirection]] — lowpoly / chunky / oversized sci-fi proportions; greybox-first level building
- [[design/ui-architecture-review]] — Phase 4.8 audit of `src/client/UI/` + `src/shared/Hud/` (re-audited 2026-06-05); R-1..R-4 cleanup landed + verified, no High open; 2 Medium / 3 Low deferred; Phase 5 gate = GO
- [[design/system-audit-2026-06]] — whole-repo architecture/tech-debt audit (2026-06-05); ~half the repo is dormant template code; Tier 1 = Skills Humanoid leak + BossAdapter retirement + split-brain damage; key call = template keep-or-cut. **Superseded by [[design/system-audit-2026-09]]** — kept as the baseline it was audited against.
- [[design/system-audit-2026-09]] — whole-`src/` design audit (2026-09-07): June's leak/BossAdapter/template items closed; **the damage path is the blocker** — spells write `Humanoid.Health` directly so a spell kill fires no `PlayerEliminated` (no duel credit); `ScoreTracker`/spawn threat/boss targeting still server-wide; HudGate reveal on DeathScreenGui; client-trusted `BroadcastSpellVfx` relay; ledger never resets. 45 findings, 12 wiki-vs-code drifts, 11 questions waiting on the user
- [[design/refactor-plan-2026-09]] — **tickable** 12-chunk refactor plan (Phase 7): each chunk has owns / must-not-touch / done condition / risk / playtest / depends-on and a `Status:` line — claim, tick, record the commit. Chunks 4 and 8–9 gate Phase 6 stages 6 and 5
- [[design/client-server-boundary]] — audit of which systems run gameplay code on both VMs (2026-08-04); root cause of the four VFX replication bugs = the Skills chain is implicit client prediction with authoritative re-simulation. Recommends authority/prediction/presentation split; 6-stage plan = Phase 5.6
- [[design/tap-to-pop]] — Phase 5.7 plan (2026-08-10): retire the Spelling Staff / LetterBlaster, click or tap blocks directly to pop them; a hover outline says whether a click will land (and greys out past reach), and a **collect stream** funnels block-coloured sparks onto whoever took it as the PvP attribution cue replacing the beam. Also closes the optimistic-append phantom-letter hole PvP exposes
- [[design/lobby]] — Phase 6 plan (2026-08-20): welcome lobby + PvE/PvP mode selection. Mode choice is a **session-container** problem, not a menu — `RoundManager`/`GameModeService` are a server-wide singleton. Hub place with in-place arena zones, co-op queued PvE, 1v1 duels on a pad pool, diegetic portals. Its PvP-gate blocker closed 2026-09-08 (refactor chunk 4): spells go through `applyDamage`, gate = `allowsPvP` on the victim's mode Stages 1–6 shipped; stage 6 (duels, forfeit rule, real queue, tunable kill limit/clock) 2026-09-19.
- [[design/arena-instancing]] — future-work plan (2026-09-20) for scaling the duel pad pool: **decision = stay single-server with scene-authored pads**, author more pads before writing code (nothing names `Duel1`/`Duel2`). Records the two switch paths with diagrams: in-server dynamic instancing (~4–5 days, one factory + two boot scans become listeners, risk = teardown race) and reserved match servers (~2 weeks, second place + teleports). Not scheduled.
- [[design/game-page]] — Phase 5.4 "game page assets" drafts (2026-09-20): short + two long store descriptions, icon concept (one cracked letter block), three-shot thumbnail list with Studio camera positions, Creator Dashboard upload path. Nothing uploaded yet
- [[design/persistence-progression]] — persistence & progression strategy (2026-07-27): mastery-first (no meta unlocks), ProfileStore-backed PlayerData, settings + word PBs + reserved cosmetics schema; analytics pulled into the 5.4 gate; implementation = Phase 5.5

## Systems

- [[systems/Weapon]] — **REMOVED (commit 6610291)**; historical record of the deleted TPS firearm/melee stack. No Luau left under src/shared/Weapon as of chunk 11 (melee deleted, laserBeamEffect moved to shared/Vfx)
- [[systems/Health]] — damage types, hit zones, modifiers, HealthService, DeathHandler
- [[systems/Character]] — **mostly REMOVED (commit 6610291)**; Camera/Locomotion controllers deleted, only DashController + CharacterSystemsLoader survive
- [[systems/NPC]] — Perception → StateMachine → Actions, Patroller archetype, WorldDataManager
- [[systems/HUD]] — Builder + Config + LayoutManager pattern, attribute bars, Phase 4 gameplay widgets (WeaponRolodex + LoadoutDropClient removed in 6610291); all seven own-ScreenGui elements on Builder+Config since 2026-09-19 (`RoundTimerGui` last), round-over copy via `RoundOutcomeCopy`
- [[systems/Settings]] — client-side preferences (2026-09-20, BRA.21): SFX volume (one `SoundGroup`, every Sound routed in), Reduced effects (`spawnEffect`/`ScreenImpact` read the flag), letter palette (`Colors.PALETTES` default / Okabe–Ito high-contrast, drawn through `Colors.tint` on blocks, tiles and menu discs). Pure `Settings` module over `Settings_*` LocalPlayer attributes; `SettingsGui` gear + panel are the first `LobbyOnly` HUD elements. Not persisted until 5.5
- [[systems/Analytics]] — Phase 5.4 analytics (2026-09-22): onboarding funnel joined → first_pop → first_memorize → first_cast → first_boss_damage → boss_kill (once, strictly in order, per player) + loop-health custom events (word_memorized, memorize_fizzle, spell_cast, round_played, blocks_popped, session_length) on Roblox `AnalyticsService`. Domains fire `BlockConsumed` / `WordMemorized` / `MemorizeFizzled` / `SpellCast` BindableEvents on their accept branch; `AnalyticsReporter` only listens; `AnalyticsSink` budgets + pcalls. `Analytics_FunnelStep` / `Analytics_Events` on the Player. Suite 2/2, live pop + cast probed
- [[systems/Loadout]] — **REMOVED (commit 6610291)**; pedestal pickup / RespawnPedestalManager / drop remote all deleted
- [[systems/GameMode]] — **sessions**: `SessionRegistry` module owns the session tables (chunk 8, 2026-09-09); `RoundManager.new(deps)` per arena with its own roster, per-roster broadcast and its own `ScoreTracker`; `SpawnManager` per arena scored against the roster; `allowsPvP` / `timeLimit` / `countdownSec` on the mode config, no global round or team flags; FFA/TDM/TeamService deleted (6610291). Registered modes: **PvEBoss** (default, runs the shipped arena — co-op, 300 s clock, ends on `BossDefeated`, roster sent home after the intermission; Phase 6 stage 5, 2026-09-19) + Lobby + NoOp. Page rewritten (Phase 6 stage 7) **Stage 6 (2026-09-19):** `PvPDuel` live on two scene-authored duel pads (`ArenaSlot` tag → session at boot), `minPlayers`/`maxPlayers` on the config, `RoundOutcome` ids on `RoundEnded` + the PostRound payload.
- [[systems/Lobby]] — the hub's portals: `LobbyService` owns the per-portal queue (one session by `TargetArenaId`, or every session running a `TargetMode`; intake only when the queue can bring a session to `minPlayers`, 1 s flush heartbeat), request validation (tag, range 34, same arena, cooldown), and the published `Occupancy`/`Capacity`/`Waiting`; `PortalGui` draws signs + confirm panel and decides nothing. Written 2026-09-20 (Phase 6 stage 7)
- [[systems/Tests]] — in-Studio harness: TestRunner + `TestAutoRunner` (`workspace.RunTests`), 7 suites / 40 tests (NPC, Multiplayer, Phase3, Skills, Hardening, Economy, Unit), results in `TestResult_*` attributes; MCP-driven via `/run-tests`
- [[systems/EnergyEconomy]] — Phase 1 pure-Luau module: word → per-color mana (Scrabble values × length tiers, floor-reconciled color splits)
- [[systems/EnergyReservoirs]] — Phase 1 pure-Luau state container: three per-color energy bars, cap 60, `.changed(color)` BindableEvent signal
- [[systems/Dictionary]] — Phase 1 pure-Luau word lookup; case-insensitive `isWord` plus wildcard-aware `resolve`/`isSpellable`, ~79.9k words (SCOWL 60 + geographic/playtest supplements); 26 per-letter sub-modules background-preloaded at game start
- [[systems/WordBuffer]] — Phase 1 pure-Luau 12-slot color-tagged buffer for the word being spelled; append-on-shot, reorder, double-tap-destroy; drains on Memorize
- [[systems/MemorizeAction]] — Phase 2 action: validate buffered word → split per-color energy into reservoirs + clear buffer; fizzle on empty (no mutation) or invalid (buffer cleared, letters consumed)
- [[systems/SpellRegistry]] — Phase 1 config layer for the spell roster (R/G/B × T1–T4); tier costs 5/10/20/40, name/color/cost/targeting/`skill:SkillSpec`; consumed by SpellExecutor + SpellMenu HUD
- [[systems/SpellExecutor]] — Phase 2 effect runner; dispatches `damage`/`heal`/`freeze`/`knockup`/`shield`/`buff` against caster/target (all real as of 5.2)
- [[systems/MindFullManager]] — Phase 2 transition watcher over WordBuffer: rising-edge `mindFull` / falling-edge `mindFreed` signals for the shoot gate + HUD indicator
- [[systems/CastAction]] — Phase 2 cast pipeline: `castSpecific` (the production path since 5.8) + `resolveSpecAtCharge` (hold duration → tier); `tapReservoir` retired but kept for its tests. Drains the reservoir, fires `spellResolved`
- [[systems/ChargeCast]] — Phase 5.8 (2026-08-12): press-hold-release on a colour panel picks the spell tier. Mana flows at 5/sec so T1 is a tap and T4 is a 7 s commitment; the charge clamps at what you can afford; nothing is drained until release, so cancelling is free. The panels are circles that fill outward from the centre with concentric tier rings, a reserve annulus and a centred numeral; a character orb, with the spell's name over it, makes the windup a PvP tell. Supersedes the never-built drag-from-reservoir tier menu
- [[systems/LetterBlock]] — Phase 3 entity: floating block prefab with `Block.Letter` + `Block.Color` attributes; chunky 4×4×4 cube with 6-face SurfaceGui letter glyph + colored ParticleEmitter; CollectionService tag drives the client animator (sinusoidal bob + 28°/s tumble on a tilted axis). 2026-08-20 face treatment: dark border + inset panel + light-tinted glyph, and a value tell scaling the emitter with the letter's Scrabble value
- [[systems/BlockSpawner]] — Phase 3 server-side populator: Scrabble-weighted letter picks (plus a 27th wildcard roll at ~4%), configurable color weights, auto-refill via CollectionService removed signal. Arena bounds come from tagged `BlockSpawnVolume` parts, **not** the 40×8×40 figure in the config — that is only the fallback default; the shipped arena measures 219×20×248 and holds 40 blocks
- [[systems/Wildcard]] — the gold ★ block that stands in for any letter (`D★G` → DOG); ASCII `*` internally / `★` on screen, uncapped per word, length-indexed dictionary matcher, energy spread across all three reservoirs
- [[systems/BlockShoot]] — shared helpers + server handler for block consumption; client input is `BlockTapController` (Phase 5.7 — click/tap a block directly, `gameProcessedEvent`-guarded); payload/range/rate validation added 5.4 and unchanged by the input migration
- [[systems/SpellCastService]] — server relay for client-initiated casts (client Health writes don't replicate on server-owned rigs); 5.4 validates spell/caster/target/rate, and **affordability is checked and enforced** since 2026-09-08 via the validated-memorize ledger (`EconomyConstants.ENFORCE = true`)
- [[systems/Boss]] — Full boss system: custom non-humanoid rig (BossBrain sphere), AI state machine (Idle/Patrol/AttackPrep/Attack/Cooldown), phase scaffolding, FireballVolley + GroundSlam attacks, BossHudGui health bar
- [[systems/BossAdapter]] — Phase 3 MVP (**REMOVED commit 6610291**, previously superseded by Boss): static Humanoid-bearing Model; module + Phase 3 tests now deleted
- [[systems/SkillPipeline]] — Unified `SkillSpec` + `SkillEffects` + `SkillDelivery` shared by player spells and boss attacks; pure data-driven dispatch, multi-effect `onImpact` arrays, reserved hooks for VFX/SFX/status-effects
- [[systems/LetterBlaster]] — **REMOVED (Phase 5.7, commit 14881d9)**; historical record of the Spelling Staff Tool and its controller, which owned block input from 4.6 until tap-to-pop replaced it
- [[systems/AudioSFX]] — Sound effect inventory, two-backend overview (Sound vs AudioPlayer), wiring patterns, placeholder locations, gap priority list
- [[systems/Tutorial]] — Phase 5 guided first-play sequence: shoot → buffer → memorize → cast → boss hit; step machine, overlay builder, skip flag (planning)
- [[systems/VisualEffects]] — world spell cast/impact particles; the caster's client predicts the cast cue (VfxController ← SpellResolved), the authoritative run broadcasts cast + impact cues over the one VfxBroadcast → WorldVfxEvent lane (client relay deleted 2026-09-08); per-color (R/G/B) theming; PERF guardrails shipped

## Concepts (recurring patterns)

- [[concepts/SingleOwnership]] — one system owns each Motor6D / property
- [[concepts/BuilderConfigLayout]] — HUD architecture: Builder constructs, Config tunes, LayoutManager places
- [[concepts/ModelJsonInstances]] — `.model.json` creates versioned non-script instances; `.meta.json` only modifies
- [[concepts/ClientServerPredictionParity]] — client prediction must use identical math to server validation; otherwise silent rejects produce desyncs
- [[concepts/LocalScriptPlacement]] — `.client.luau` only auto-runs from `src/client/` (or inside Tool templates); shared/ LocalScripts are dead code
- [[concepts/RojoJsonValidator]] — pre-commit linter that hard-blocks the silent-fail traps in `.meta.json` / `.model.json` files
- [[concepts/MultiplayerTestPattern]] — how to write integration tests for server-authoritative multiplayer paths against a synthetic enemy
- [[concepts/ServerLogicTestHarness]] — gated `.server.luau` drivers for testing server-only logic when MCP only gives client-side execute_luau
- [[concepts/ValidateBeforeShip]] — a fix is not done until you've observed it working; build a deterministic repro before pushing
- [[concepts/RobloxOpenCloudAuth]] — Open Cloud "Invalid API Key" 401 with a previously-working key → regenerate from the dashboard, paste new value into `.env`, move on
- [[concepts/RemoteVisualDebugging]] — 5-layer diagnostic checklist for "works for me, not for other clients" multiplayer visual bugs
- [[concepts/HudGate]] — HUD suppression by player state; a required policy argument, because a leaked element fails silently
- [[concepts/DevDebugHotkeys]] — `[ ] \ 1–4 M` hotkeys in DevDebug.client.luau for word buffer, energy tier fills, and mobile-input simulation

## Decisions

- [[decisions/HybridMeleeHitDetection]] — client detects, server sanity-validates (2026-04-17)

## Ideas Scrapbook

- [[ideas]] — raw ideas and playtest observations; not committed to build
