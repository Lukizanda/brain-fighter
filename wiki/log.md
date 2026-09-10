---
type: log
description: Append-only chronological record of wiki ingests and lints. Newest entries at the bottom.
---

# Wiki Log

Format: `## [YYYY-MM-DD] <ingest|lint|init> | <one-line topic>` followed by a 2–4 line summary.

## [2026-05-08] init | wiki reset for Brain Fighter

Forked from a prior TPS template. Game-specific design + status content stripped; concepts and systems pages retained as engineering reference. Brain Fighter's own design pages will be authored as the project takes shape.

## [2026-05-13] ingest | Team/PvP combat gated off

Two new GameConfig flags added: TEAMS_ENABLED (default false) and PLAYER_VS_PLAYER_ENABLED (default false). All team-aware and PvP-damaging code paths now check these flags. Files preserved on disk; reversal is a config flip. See systems/GameMode, systems/Health, systems/Loadout, systems/HUD for per-system notes.

## [2026-05-13] ingest | SpawnLocation set Neutral for team-off build

Follow-up to the Team/PvP gate. `Workspace.Arena.SpawnZone.SpawnLocation` was `Neutral = false` with `TeamColor = Bright red`; with no Team instances created (TeamService gated off), the engine rejected the pad for every player and spawned them at the world fallback → sky → fall death. Flipped to `Neutral = true` via MCP+ChangeHistoryService and verified with a playtest (HumanoidStateType.Running on the pad, Health = 100, XZ offset = 0.004 from pad centre). Studio in-memory change; user saves the .rbxl to persist. See systems/GameMode "SpawnLocation must be Neutral while teams are off".

## [2026-05-13] ingest | Canonical gameplay-loop design doc

New `wiki/design/gameplay-loop.md` written as the authoritative source for Brain Fighter's core loop — captures the 10-step loop, all 12 resolved decisions with rationale (grouped by buffer/input, spell typing, economy, targeting, spawner, dictionary, win condition), letter/length/tier tuning tables, the nine-spell prototype roster, ten worked formula examples (CAT through CHARACTERIZE), and the three open questions (tier-cast UX, spawn density, color distribution). Cross-links to the sibling `gameplay-loop.excalidraw` diagram and the in-progress `hud.mockup.html`. Added to `index.md` under Design.

## [2026-05-13] ingest | Resolved spawner + cast-menu open questions

Three previously-open design questions resolved and folded into the canonical doc. **Spawn density**: ~24 blocks at any time in a moderate arena (~8 per color), framed as density-per-area in code so it scales with level size; letter selection within a color is Scrabble-frequency-weighted. **Color distribution**: equal-weight (33/33/33) default with per-level `colorWeights` override; no adaptive spawning. **Placement-spell marker**: crosshair glyph (⌖) at the right edge of the menu entry + dashed outline around the entry (auto-target entries use solid outline); first-time use triggers a one-shot tutorial flash. The doc's Open Questions section has been replaced with a Playtest Verification list — all major decisions are now resolved; what remains is tuning. Mockup updated to use ⌖ + dashed border on the Stone Wall entry.

## [2026-05-13] ingest | TPS character stack gated behind GameConfig flag

Brain Fighter switches from TPS camera-locked body orientation to default Roblox platformer-style controls (free-look camera, `Humanoid.AutoRotate = true`, default R15 animations). New `GameConfig.TPS_CHARACTER_ENABLED` flag (default `false`) gates `CameraManager` + `LocomotionManager` initialization in `CharacterSystemsLoader`; when off, both controllers are skipped and the default Roblox PlayerModule handles camera and locomotion. Verified via MCP playtest: `AutoRotate=true`, no `AlignOrientation` on HumanoidRootPart, `CameraType=Custom` with the player Humanoid as subject. Files preserved; flip the flag to restore the TPS feel. See systems/Character "TPS character stack is gated off by default."

## [2026-05-14] ingest | Phased build plan + 18 trackers

New `wiki/design/build-plan.md` lays out the four-phase construction order for Brain Fighter's gameplay systems with explicit parallel/sequential dependencies. Phase 1 (foundations — Dictionary, EnergyEconomy, SpellRegistry, WordBuffer, EnergyReservoirs) is fully parallel-safe and was kicked off as five sibling Nimbalyst sessions. Phase 2 (action systems) is partially parallel; Phase 3 (world instances — LetterBlock, BlockShoot, BossAdapter) needs design coordination on asset look; Phase 4 (HUD) is parallel once backing modules ship. Eighteen `task` trackers created (NIM-1 through NIM-18), one per system, tagged by phase with dependencies in each description. Added under Design in `index.md`.

## [2026-05-14] ingest | EnergyEconomy module landed (NIM-2, Phase 1)

Pure-Luau formula module at `src/shared/EnergyEconomy/init.luau` with sibling `__tests.luau` smoke suite. Exposes `letterValue`, `lengthMultiplier`, `computeWordEnergy`, `splitByColor`. All 10 pinned worked-example energies (CAT=5 through CHARACTERIZE=84) and 3 pinned color-split examples (FLAME, FROZEN, ROCK) assert-match in MCP playtest, plus inline checks for case-insensitivity and tier boundaries. Color-split rounding reconciles via "floor each in canonical RGB order; last present color absorbs the integer shortfall" so per-color totals always sum exactly to whole-word energy. New `wiki/systems/EnergyEconomy.md` and an entry under Systems in `index.md`.

## [2026-05-14] ingest | EnergyReservoirs module landed (NIM-5, Phase 1)

Pure-Luau state container at `src/shared/EnergyReservoirs/init.luau` with sibling `__tests.luau` smoke suite. Holds three per-color energy bars (red/green/blue) with cap **160 per color** (= 2×T3, sourced from `design/gameplay-loop.md` "Spell economy"). API: `new`, `:get`, `:add` (caps, non-positive no-op), `:canAfford`, `:drain` (false if can't afford, value untouched on failure), `:snapshot` (defensive copy), `:destroy`, and a `.changed` BindableEvent that fires with the changed color on **net** changes only (capped adds and failed drains don't fire). 10/10 smoke scenarios pass in MCP playtest. Noted in the wiki page: BindableEvent runs in Deferred mode by default in this place, so handlers fire on the next resumption cycle — consumers (HUD: ReservoirBars) and tests must re-read state via `:get(color)` and `task.wait()` respectively. New `wiki/systems/EnergyReservoirs.md` and an entry under Systems in `index.md`.

## [2026-05-14] ingest | Dictionary module landed (NIM-1, Phase 1)

Pure-Luau word lookup at `src/shared/Dictionary/init.luau` with sibling `WordList.luau` (lowercase `{[word]=true}` hashtable) and `__tests.luau` smoke suite. API: `Dictionary.isWord(s) -> boolean` (case-insensitive — lowercases input before lookup; rejects non-string and empty input) and `Dictionary.getStats() -> { wordCount, byLength }` (cached). Logs `Dictionary loaded N words` on require via `Logger.new("Dictionary")`. Bootstrap word list landed at ~4159 entries (overshot the build-plan's 500–1000 guideline — flagged in `wiki/systems/Dictionary.md` "Bootstrap scope" with the trade-off rationale; SCOWL replacement will reset both size and quality). All required smoke assertions pass in MCP playtest (FIRE/fire/Fire, FLAME, LIGHTNING, DRAGON, ROCK, XYZQQ false, empty false, wordCount > 500); pinned `gameplay-loop.md` worked-example words (CAT, FROZEN, FIREBALL, EARTHQUAKES, CHARACTERIZE) all recognized after a missed-singular `fireball` was added on first verification. New `wiki/systems/Dictionary.md` and an entry under Systems in `index.md`.

## [2026-05-14] ingest | MemorizeAction module landed (NIM-6, Phase 2)

Pure-Luau action module at `src/shared/MemorizeAction/init.luau` with sibling `__tests.luau`. Single function `MemorizeAction.tryMemorize(buffer, reservoirs) -> Result` — the seam between the four Phase 1 foundation modules (Dictionary + EnergyEconomy + WordBuffer + EnergyReservoirs). Empty buffer → `{ok=false, reason="empty"}` no mutation; invalid word → `{ok=false, reason="invalid"}` buffer preserved (so the player can correct typos without retyping); valid word → splits via `EnergyEconomy.splitByColor`, adds each `(color, amount)` to the reservoirs, clears the buffer, returns `{ok=true, energyByColor=split, word=word}`. All 4 smoke scenarios from the brief (empty, invalid "XYZ", mono-color "FIRE" → red=7, mixed-color "FLAME" → red=12 green=3 on top of pre-existing red) pass in MCP playtest. Log breadcrumbs observed: `memorize fizzle — empty buffer`, `memorize fizzle — invalid word XYZ`, `memorize ok — FIRE`, `memorize ok — FLAME`. New `wiki/systems/MemorizeAction.md` and an entry under Systems in `index.md`.

## [2026-05-14] ingest | SpellExecutor module landed (NIM-7, Phase 2)

Effect runner at `src/shared/SpellExecutor/init.luau` with sibling `__tests.luau` smoke suite. `SpellExecutor.cast(spec, caster, target) -> CastResult` dispatches on `spec.effectSpec.kind`. **Real:** `damage` (`Health -= fraction × MaxHealth`, clamp 0), `heal` (clamp MaxHealth; nil target falls back to caster), `freeze` (save WalkSpeed → 0 → `task.delay` restore). **Stubs** returning `ok=true`: `shield`, `wall`, `buff` — every prototype spell in the registry is callable end-to-end before placement/buff systems land. Re-freeze on an already-frozen target *extends* the existing entry's expiry (`max(current, now+dur)`) and preserves the originally-saved WalkSpeed; documented in the wiki page (richer than the build-plan's allowed last-write-wins shortcut, ~6 extra lines). All 11 smoke cases (Fireball drops 100→80, damage-on-dead clamps, Mend 50→65, heal cap, nil-target heal fallback, Frost Nip → 0 → restore after 1.15s, three stub kinds, unknown kind, nil-target damage) pass in MCP playtest. New `wiki/systems/SpellExecutor.md` and an entry under Systems in `index.md`.

## [2026-05-14] ingest | MindFullManager module landed (NIM-8, Phase 2)

Transition watcher at `src/shared/MindFullManager/init.luau` with sibling `__tests.luau` smoke suite. `MindFullManager.new(buffer)` hooks `WordBuffer.changed`, tracks `_wasFull`, and emits two no-arg signals on edges only: `.mindFull` (rising) and `.mindFreed` (falling). Reorders and interior remove/append churn produce zero fires; 13th-append rejection silently drops because `WordBuffer:append` returns false without firing `.changed`. Construction over an already-full buffer seeds `_wasFull = true` to suppress phantom rising-edge fires. Both signals are `BindableEvent.Event` in Deferred mode, so smoke tests `task.wait()` between mutation and assertion (consistent with WordBuffer + EnergyReservoirs). 4 scenarios pass in MCP playtest: brief-pinned end-to-end (fill→full→reject→free→refill→destroy), non-cap churn (zero transitions), `clear()` from full (one falling edge), born-full construction (no phantom rising edge). New `wiki/systems/MindFullManager.md` and an entry under Systems in `index.md`.

## [2026-05-14] ingest | CastAction module landed (NIM-10, Phase 2)

Cast pipeline at `src/shared/CastAction/init.luau` with sibling `__tests.luau`. Two entry points map to the dual cast gestures from `gameplay-loop.md` § "Cast (reservoir-driven)": `tapReservoir(color, reservoirs, caster, target)` fires the **highest currently-affordable** tier (casual fast path), and `castSpecific(color, tier, reservoirs, caster, target)` fires the deliberately-picked tier (strategic "save big, fire small" path via the drag-tier menu). Both resolve through the same internal pipeline — SpellRegistry lookup → affordability check → `reservoirs:drain` → `SpellExecutor.cast` → **refund-on-executor-failure** (`reservoirs:add` the cost back so a downstream rejection like `damage requires a Humanoid target` doesn't cost the player mana). `castSpecific` pcall-wraps `SpellRegistry.getSpell` so callers get a uniform `{ok=false, reason="invalid color/tier: ..."}` instead of a raised error. All 9 smoke scenarios pass in MCP playtest (energy=0 fizzle, T1/T2/T3 tap thresholds with HP drops 95/80/50, save-big castSpecific(red,1) at 80, unaffordable castSpecific(red,3) at 50, invalid-color fizzle, refund on damage-with-nil-target, heal-fallback Mend on caster). New `wiki/systems/CastAction.md` and an entry under Systems in `index.md`.

## [2026-05-14] ingest | LetterBlock template populated (NIM-11, Phase 3)

MCP-side children landed on `ReplicatedStorage.Shared.LetterBlocks.Template`: the **Cube** Part (4×4×4, anchored, non-colliding, Plastic, smooth surfaces, `CanQuery=true` so raycasts hit), six **SurfaceGuis** (`Face_Front/Back/Top/Bottom/Left/Right`) each with a TextScaled white-stroke `Letter` TextLabel, and a **Mana** ParticleEmitter (rate 8/s, sparkle texture, fades to transparency). `Template.PrimaryPart = Cube` so `PivotTo` from the `spawn` helper targets the visible body. The Template's `init.meta.json` has `ignoreUnknownInstances=true`, so the children survive Rojo sync. Persisted by saving `BrainFighter.rbxl`. Visual edit-mode verification confirmed white-stroked letter readable from every angle across red/green/blue tints; playtest verification (block spawned at (0,12,0) sampled at t=0/0.5/1.0s) confirmed the animator drives yaw at exactly 6°/s and Y bobs sinusoidally from the spawn baseline. `wiki/systems/LetterBlock.md` rewritten with the full Template tree and the verification table; `index.md` entry updated. Unblocks NIM-9 (BlockSpawner), NIM-12 (BlockShoot), NIM-13 (BossAdapter).

## [2026-05-14] ingest | Memory audit — Loadout gotchas + RemoteVisualDebugging page

Memory audit migrated 19 entries out of Claude auto-memory into durable locations. Four Roblox engine gotchas (Backpack.ChildAdded idempotence, pedestal auto-equip bypass, Backpack lifecycle on respawn, client-side AncestryChanged nil-intermediate) consolidated into `wiki/systems/Loadout.md` under new "Inventory tracking gotchas" section. Weapon template rename ordering (Studio-first, then disk) added to `wiki/systems/Weapon.md` as its own section before "Important gotchas". New `wiki/concepts/RemoteVisualDebugging.md` captures the 5-layer multiplayer visual debugging checklist. CLAUDE.md extended with Code Style (type annotations, destroy/disable pattern), Test Suite Hygiene (clear RunTests after autorun), Studio DataModel Mutations (ChangeHistoryService discipline), Naming Conventions (script suffixes, casing by role, meta file distinction), and Wiki Maintenance sections. Memory reduced from 35 to 15 behavioral entries.

## [2026-05-14] ingest | Phase 3 world systems — BlockSpawner, BlockShoot, BossAdapter

Three Phase 3 modules landed in one session. **BlockSpawner** (`src/shared/BlockSpawner/init.luau` + `src/server/BlockSpawner/BlockSpawnerService.server.luau`): server-side populator maintaining ~24 LetterBlocks in a 40×8×40 arena. Scrabble-frequency-weighted letter picks, configurable color weights (default uniform 33/33/33), auto-refill via CollectionService removed signal when blocks are consumed. **BlockShoot** (`src/shared/BlockShoot/init.luau` + `src/client/BlockShootBoot.client.luau` + `src/server/BlockShoot/BlockShootService.server.luau` + ConsumeBlock RemoteEvent): client left-click → camera raycast → hit LetterBlock → read (letter, color) → append to local WordBuffer → fire remote → server validates + destroys block. MindFullManager gates input at 12/12 buffer. New `PlayerSession.luau` client ModuleScript lazy-creates and caches per-player WordBuffer + MindFullManager + EnergyReservoirs — shared across BlockShoot boot and future Phase 4 HUD scripts. **BossAdapter** (`src/shared/BossAdapter/init.luau` + `src/server/BossAdapter/BossService.server.luau`): Phase 3 MVP Boss target — static Humanoid-bearing Model (6×8×6 neon purple Part, 500 HP). SpellExecutor.cast works against it with no additional wiring (resolveHumanoid finds the Humanoid). `defeated` BindableEvent fires on Humanoid.Died; BossService auto-respawns after 5s. Three new wiki pages under Systems; `index.md` updated.

## [2026-05-14] ingest | Phase 4 HUD — 5 gameplay widgets landed

Five new Builder+Config+client-script triples under `src/shared/Hud/` and `src/client/UI/`. All read through `PlayerSession.get()` and subscribe to signals from the session state objects:

- **MindFullIndicator** (TopCenter) — fades in/out on `mindFull`/`mindFreed`; warns "can't shoot"
- **BufferDisplay** (BottomCenter) — 12-slot letter-tile row; updates on `wordBuffer.changed`
- **ReservoirBars** (BottomLeft) — R/G/B energy bars reusing AttributeBarBuilder; updates on `energyReservoirs.changed`
- **MemorizeButton** (BottomCenter) — enabled when buffer non-empty; calls `MemorizeAction.tryMemorize`, flashes green/red on result
- **SpellMenu** (BottomRight) — three color panels showing affordable spell + energy; tap → `CastAction.tapReservoir`

`wiki/systems/HUD.md` updated with Phase 4 section and file table.

## [2026-05-14] lint | Wiki cleanup + LetterBlock / BlockShoot pages

Full wiki lint per `WIKI.md` § Lint contract. Mechanical pass (grep-driven, in Claude): inventoried `updated:` dates across 33 pages, extracted every `[[wikilink]]` target, diffed against on-disk pages — three dead wikilink targets found (`concepts/CombatFeatureGates`, `systems/Logger`, `systems/BlockShoot`). Semantic pass (delegated to Ollama via `ask_ollama.py`): per-page `src/` path extraction for the eight oldest pages — three path drifts surfaced, two real (`src/server/Spawner/WeaponSpawnerManager.server.luau` removed and replaced by `src/server/Loadout/RespawnPedestalManager.server.luau`; `RoundStarted/RoundEnded.model.json` moved from `Scripts/RoundManager/` to `Events/`) and one false-positive (the `src/shared/...ShotReplication` reference in `LocalScriptPlacement` is intentionally a past-tense case study). Fixes: `Weapon.md` legacy-spawner line rewritten, `ModelJsonInstances.md` Round event paths corrected, `EnergyReservoirs.md` Logger wikilink demoted to plain code-path reference, `GameMode.md` dropped the `(if added)` CombatFeatureGates link. New pages: `systems/LetterBlock.md` (NIM-11 disk skeleton from `606bd5c` — spawn API, color tints, CollectionService tag, status box flagging the pending MCP-side Cube + SurfaceGui + ParticleEmitter children) and `systems/BlockShoot.md` (forward-declared Phase 3 status page so its three existing wikilinks resolve). `index.md` extended with both. Five `updated:` dates bumped to 2026-05-14. No orphans found; folder structure unchanged.

## [2026-05-15] ingest | Dictionary SCOWL 60 upgrade

Replaced the 4.1k hand-curated bootstrap word list with SCOWL size-60 (~79.5k words). Root cause: "tout" rejected during gameplay; gap audit found ~90 missing common words. New architecture: 26 per-letter sub-modules (`src/shared/Dictionary/words/{a..z}.luau`) each returning a packed newline-delimited string, background-preloaded via `task.defer` at game start. `init.luau` rewritten with `ensureLoaded(letter)` for O(1) hashtable lookups; `WordList.luau` deleted. Offline parser `tools/generate_wordlist.py` generates the word files from SCOWL source (gitignored); includes American + British spellings (`color`/`colour`, `organize`/`organise`), offensive word filter. Tests updated: MIN_WORD_COUNT raised to 70k, "tout" and "colour" pinned. Playtest-verified: `[TEST PASS]`, wordCount=79504, `isWord("tout")=true`. `wiki/systems/Dictionary.md` fully rewritten.

## [2026-05-16] ingest | Audio SFX — fizzle wiring + inventory wiki

Added fizzle sound playback to three action-failure paths: LetterBlaster mind-full and buffer-rejected (new `FizzleSound` Tool child + `FIZZLE_SOUND_NAME` config constant), SpellMenuGui cast fizzle (SoundService Sound, placeholder `rbxassetid://0`), GameplayHudGui memorize fizzle (same). Created `wiki/systems/AudioSFX.md`: full inventory of wired/silent events across all systems, two-backend explainer (old Sound vs new AudioPlayer+Wire), placeholder locations, gap priority list, and patterns for adding new sounds. Placeholder SoundIds still need to be filled in for all three fizzle sites (see AudioSFX.md Placeholder Locations section).

## [2026-05-15] ingest | Phase 4.6 — LetterBlaster Tool

Replaced the bare `BlockShootBoot` click handler with a dedicated weapon Tool. Three new files: `src/shared/LetterBlaster/init.luau` (controller: mount/fire/reticle/sound), `src/shared/LetterBlaster/LetterBlasterConfig.luau` (COOLDOWN=0.25s, sound names), `src/client/LetterBlasterBoot.client.luau` (Backpack watcher — Equipped → mount, Unequipped → destroy). `src/client/BlockShootBoot.client.luau` deleted. StarterPack Tool added to Rojo project (`src/StarterPack/LetterBlaster/` with Handle MeshPart + FireSound + HitSound model.json files; `default.project.json` updated with `StarterPack.$path`). Key changes from Phase 3: input moves from `UserInputService.InputBegan` to `Tool.Activated`; 0.25s cooldown gate via `os.clock`; reticle (`ReticleBuilder.build()`) created in a dedicated `LetterBlasterReticle` ScreenGui on equip, destroyed on unequip; `FireSound` plays on every activation, `HitSound` + `showHitmarker()` on confirmed consume. `BlockShootService.server.luau` unchanged. Playtest-verified: Tool clones to Backpack on spawn, equip fires `Equipped` → controller mounts, LetterBlasterReticle ScreenGui appears in PlayerGui. New `wiki/systems/LetterBlaster.md`; `wiki/systems/BlockShoot.md` updated to note the client-handler migration.

## [2026-05-20] ingest | HUD BottomCenter coordinator refactor

`PlayerHud/init.client.luau` (LocalScript) converted to `PlayerHud/init.luau` (ModuleScript) exporting `build()`, `attachAdapters(char)`, `teardownAdapters()`. `GameplayHudGui.client.luau` promoted to single BottomCenter coordinator with a `LAYOUT = { TILES=1, HEALTH=2, ABSORB=3 }` table as the only place to touch for reordering. `HudLayoutManager:register` and `CharacterAdded` wiring moved out of PlayerHud and into GameplayHudGui. Rojo did not auto-convert the LocalScript class on disk change; stale instance removed and ModuleScript created manually via MCP; note added for future class-rename gotcha. `wiki/systems/HUD.md` updated: init.luau path, stale `BufferDisplayGui`/`MemorizeButtonGui` entries removed (consolidated into `GameplayHudGui`), coordinator role documented.

## [2026-05-18] ingest | VFX plan sanity-check corrections + Phase A/D foundation

Implemented all corrections identified in the `sanity-check-this-vfx-clever-wozniak` plan. **Critical fix (R2 two-event flow)**: replaced the broken single-`VfxService` server hook (CastAction only runs client-side) with a client→server→client broadcast pipeline: `CastAction.spellResolved` (client-local BindableEvent, fires frame-perfect local VFX) → `BroadcastSpellVfx` RemoteEvent → `VfxBroadcastService.server.luau` (rate ≤ 4/s, type + target validation) → `SpellVfxEvent:FireAllClients`. New files: `src/shared/Vfx/VfxConfig.luau` (Phase A config stub with COLORS + PERF), `src/shared/Vfx/Remotes/BroadcastSpellVfx.model.json`, `src/shared/Vfx/Remotes/SpellVfxEvent.model.json`, `src/server/Vfx/VfxBroadcastService.server.luau`. **Handle layout fix**: converted `Handle.model.json` → `Handle/init.model.json` + `Handle/Tip.model.json` (folder-with-init pattern per [[concepts/ModelJsonInstances]]; Tip CFrame placeholder at (0,2.877,0) pending Studio capture). **LetterBlock fix**: `onRemoved` now reads cached `state.basePosition` before clearing; stale pivot read after destroy eliminated. **Phase D UI VFX complete**: all four HUD builders updated — `BufferDisplayBuilder` (popTile, setMindFullPulse, playMemorizeOk, playMemorizeFail), `AttributeBarBuilder` (playGainSweep, playDrainRipple, setCapGlow with lastFraction tracking), `ReservoirBarsBuilder` (per-color delta tracking + cap glow routing), `SpellMenuBuilder` (playAffordBounce, playFiredFlash, wasAffordable map). All constants in matching `*Config.luau` files. `wiki/systems/VisualEffects.md` updated with all 5 corrections; Phase B/C/D task list updated to mark done items.

## [2026-05-18] ingest | Unified skill/effect/delivery pipeline (boss + spells)

New `src/shared/Skills/` layer: `SkillTypes.luau` (pure types), `EffectRegistry.luau` (effect handlers: damage/heal/freeze/stubs), `DeliveryRegistry.luau` (delivery handlers: instant/projectile/aoe/world_spawn). `SpellExecutor.cast` is now a thin origin-resolver that delegates to `DeliveryRegistry.deliver`; all effect and delivery logic removed from the executor. `SpellRegistry` spells migrated from `effectSpec` to `skill: SkillSpec` shape (3 colors × up to 4 tiers — Volley red T4 added as projectile proof-of-concept). Boss attacks (`FireballVolley` 3-projectile 15 HP, `GroundSlam` 12-stud AOE 25 HP + knockup) ported from the retired `BossAttacks.luau` into `DeliveryRegistry` handlers; `BossStates.AttackState` now calls `DeliveryRegistry.deliver(skill, ctx)` with an `onComplete` callback that sets `attackComplete = true`. `BossConfig` rewritten as a `BOSS_TYPES` registry with typed `SkillSpec` under `skills`; `Wizard` type added (800 HP, 5-shot freeze projectile). `BossAttacks.luau` and `DummyBoss.server.luau` deleted. 11/11 `SpellExecutor.__tests` pass; boss attack cycle (Idle→Patrol→AttackPrep→Attack→Cooldown) verified in playtest (commit `03b6080`). `wiki/systems/SpellExecutor.md`, `wiki/systems/SpellRegistry.md`, `wiki/systems/Boss.md` updated to reflect new architecture.

## [2026-05-18] ingest | Full boss system landed (replaces BossAdapter)

Twelve files across shared/server/client implement a complete boss lifecycle. **Architecture**: `BossService.server.luau` owns spawn → tick → death → respawn; `BossController` wires `Perception` + `StateMachine` + `BossPhaseManager` per boss instance, reusing shared NPC modules verbatim. **Model**: 3× scaled Patroller R15 rig (1500 HP, BodyScale=3); ShieldPart (Neon blue) and LeftArmCore (Neon orange) welded to HRP as visual scaffold for the future destructible-parts system. **Phases**: data-driven `PhaseSpec` array in `BossConfig.luau`; ships with one entry (always phase 1); add more entries to `PHASES` to activate multi-phase behavior without structural changes. **State machine**: Idle → Patrol → AttackPrep → Attack → Cooldown with `BossStates.luau` passed to `StateMachine.new()`. **Attacks**: `FireballVolley` (3 CanCollide=false projectiles, LinearVelocity + Heartbeat proximity hit-detection, 15 HP) and `GroundSlam` (AOE 12-stud radius, Cylinder shockwave visual, upward ApplyImpulse, 25 HP). **HUD**: `BossHudGui.client.luau` registered to TopCenter; health bar tweens on `BossHealthChanged`, phase label updates on `BossPhaseChanged`, hidden when no boss. **Damage integration**: `applyDamage.process(sourcePlayer=nil)` bypasses PvP gate; SpellExecutor targets boss via workspace name lookup unchanged. Old `BossAdapter/BossService.server.luau` renamed to `.disabled`; `Dev/DummyBoss.server.luau` deleted. New `wiki/systems/Boss.md`; `index.md` updated to reference Boss instead of BossAdapter.

## [2026-05-18] ingest | BossBrain custom rig + per-type rig system

Boss rig is now non-humanoid. `BossTypeSpec` gains `rigName: string?` (template name in ServerStorage.AIWorldData.Rigs) and `hipHeight: number?` (post-scale HipHeight override). `BossSpawner` resolves the template by `rigName` (default: Patroller), skips ShieldPart/LeftArmCore for custom rigs, guards the coloring loop with a `KeepColor` part attribute, and falls back to HRP for the BOSS billboard when no Head part exists. **BossBrain rig** (Studio-only, not on disk): invisible Patroller R15 skeleton (provides Humanoid physics) + 9-stud red sphere body + brain stem + glowing yellow Neon eyes (KeepColor=true). Brain boss config updated: `bodyScale=1` (sphere pre-sized), `rigName="BossBrain"`, `detectionRange=160`, `attackRange=100`. `wiki/systems/Boss.md` and `index.md` updated.

## [2026-05-18] fix | Spell damage now actually hits the boss (client→server relay)

Root cause: `SpellExecutor.cast` ran entirely on the client (LocalScript). `Humanoid.Health` writes from a LocalScript do not replicate to the server for server-owned characters — the boss's real HP never changed. Fix: `SpellMenuGui` now fires `SpellCastServer` RemoteEvent (`ReplicatedStorage.Shared.SpellCast.Remotes.SpellCastServer`) after every successful non-self cast. New `SpellCastService.server.luau` receives it, validates spell color/tier and target Humanoid, then calls `SpellExecutor.cast` server-side where the write actually sticks. Green (self-heal) spells skip the relay since players own their own characters. Verified: Spark applies exactly 75 HP damage (5% × 1500) to boss per cast. `wiki/systems/SpellExecutor.md` updated with client/server boundary section.

## [2026-05-18] fix | Boss smooth facing + continuousFacing toggle

Replaced the instant CFrame snap in `BossStates.faceTaret` with a frame-rate-independent CFrame lerp (180 °/s default, tunable via `FACE_TURN_RATE`). `_faceLastTime` stored on the blackboard via `:: any`; reset to nil on `AttackPrep.onEnter` to avoid a stale-dt jump on re-entry. New `BossTypeSpec.continuousFacing: boolean?` field controls whether smooth rotation runs in Idle, Attack, and Cooldown (Patrol excluded — Humanoid pathfinding owns facing during movement). AttackPrep always faces regardless of the flag. `continuousFacing = true` set on Brain; Wizard defaults off. `wiki/systems/Boss.md` updated: Facing behavior paragraph added to State Machine section; `continuousFacing` row added to Key Tuning table.

## [2026-05-18] ingest | Spell buttons embed mana fill; separate reservoir bars removed

`SpellMenuBuilder` rewritten: each 90×80 button now layers a dim `FillBase` (always visible, the "empty" look) and an animated `FillBar` (solid gradient, anchored to bottom, grows upward as mana accumulates). `UIGradient` Rotation=270 gives solid color at bottom → lighter at top. Tapping a button shows a `"128 / 160"` popup above it for 1.8 s then fades. `playAffordBounce` keeps the scale-bounce; `playFiredFlash` now dims `FillBase.BackgroundTransparency` instead of the old `BackgroundColor3` tween. `ReservoirBarsGui.client.luau` deleted — its role is absorbed. `SpellMenuConfig` gains `FILL_TWEEN`, `FILL_MAX`, `FILL_BASE_TRANSPARENCY`, popup constants; removes `ACTIVE/DISABLED_TRANSPARENCY`, `COST_*`, `FIRED_DIM_COLOR`. `wiki/systems/HUD.md` updated.


## [2026-05-19] ingest | BossHudGui moved to absolute top of screen

Removed BossHudGui from HudLayoutManager's TopCenter region. It now owns its own ScreenGui (IgnoreGuiInset=true, DisplayOrder=15) and positions itself at UDim2(0.5,0,0,8) — flush at the top where the round timer used to sit. Container width changed from 100% of TopCenter region to 0.4× screen to maintain the same visual size.

## [2026-05-19] ingest | Round timer + pre-round countdown disabled via config

Added `ROUND_TIMER_ENABLED` and `ROUND_COUNTDOWN_ENABLED` flags to `GameConfig.luau` (both `false`). `RoundManager` now skips `countdown()` and runs an unbounded active-round loop when the flags are off — rounds end on score limit only. `RoundTimerGui` (previously Studio-only, now on disk at `src/client/UI/`) exits early when `ROUND_TIMER_ENABLED = false`, removing the "0:00" overlay. Flip either flag `true` to restore the corresponding behaviour without any other code changes. Updated `wiki/systems/GameMode.md` and `wiki/systems/HUD.md`.

## [2026-05-19] ingest | Dash/roll mechanic added

New `DashController` + `DashManager.client` add LeftShift dash/roll on top of the default Roblox PlayerModule (works regardless of TPS_CHARACTER_ENABLED). Grounded: roll burst 60 studs/sec Quart/In decel over 0.35 s, 0.55 s cooldown. Airborne: forward dash 60 studs/sec for 0.2 s, once per airtime. Two non-obvious findings: (1) `BodyVelocity.MaxForce` must be `math.huge` in XZ — the default PlayerModule actively decelerates at rest and overwhelms smaller forces. (2) `RelativeTo.Attachment0` with `PlaneVelocity` sent the character upward because the attachment Y axis is world-up; fixed by computing world-space forward from `LookVector` directly. Animation/sound/VFX assets live only in the .rbxl (re-create via MCP after fresh place open). Constants in `GameConfig.DASH`. `wiki/systems/Character.md` updated.

## [2026-05-19] ingest | Geographic proper-names supplement added to Dictionary

Added `tools/wordlists/proper-names.txt` — ~400 curated single-word geographic names (countries, capitals, major cities). `generate_wordlist.py` now merges this supplement after SCOWL filtering via a new `--supplement` flag. Word count increased from 79,504 → 79,896. Multi-word names (New York, Buenos Aires) intentionally excluded — can't be played as a single word. `wiki/systems/Dictionary.md` updated: supplement paragraph in Offline parser section, refreshed word count table, new gap-log entry.

## [2026-05-19] feat | Phase C VFX — Spark and Fireball particle effects (local-player path)

`VfxController.client.luau` created: connects to `CastAction.spellResolved`, resolves cast anchor (`Handle.Tip` Attachment, fallback HRP), clones emitters from `ReplicatedStorage.VfxTemplates`, calls `:Emit(count)`, and cleans up via `Debris:AddItem`. Impact emitters spawn at `target.HumanoidRootPart`. `VfxConfig.EFFECTS` populated with `cast_red_t1` (BurstSmall, 14 particles), `cast_red_t2` (BurstMedium, 30 particles), and `impact_damage` (ImpactBurst, 22 particles). Fixed a pre-existing Luau parse error in `VfxConfig.luau` (inline type annotations on table field assignments are not valid Luau syntax). `Tip.model.json` added to `src/StarterPack/Spelling Staff/Handle/` (CFrame Y=2.877). VfxTemplates (`BurstSmall`, `BurstMedium`, `ImpactBurst`) exist in Studio edit-mode DataModel (Studio-only, not Rojo-tracked). Remote-player path (`SpellVfxEvent` relay) deferred. `wiki/systems/VisualEffects.md` updated: Phase C steps 6–8 marked done/partial, status → `partial`.

## [2026-05-20] ingest | Phase 4.8 UI Architecture Review — Phase 5 gate = GO

New `wiki/design/ui-architecture-review.md` documents the Phase 4.8 audit of `src/client/UI/`, `src/client/PlayerHud/`, `src/shared/Hud/` (39 files, ~6.1k Luau lines). Findings: **1 High** (`SettingsMenuBuilder` reads `Players.LocalPlayer` — tracker NIM-19), **6 Medium** (ReservoirBars dead code, BufferDisplay inline interaction constants, 8 inline LocalScripts vs Builder pattern, WeaponRolodex placement under `src/client/`, region-ID literal vs `HudConstants` inconsistency, stale `LayoutOrder = 2` in SpellMenuGui), **4 Low** (LoadoutDrop second-BottomCenter exception, `_G.PlayerHud` debug registry, duplicate `VALID_WORD_STROKE_NAME` constant, placeholder fizzle-sound TODOs). Single ownership and lifecycle dimensions came back clean — all 11 Builders define `:destroy()` and no double-writes on Frames/LayoutOrder. `wiki/index.md` updated to list the new page.

## [2026-05-20] refactor | Strip PlayerHud indirection — inline health bar into GameplayHudGui

Deleted `src/client/PlayerHud/` (5 files: `init.luau`, `PlayerHudConfig.luau`, `Adapters/HealthAdapter.luau`, `ShieldAdapter.luau`, `StaminaAdapter.luau`). BrainFighter has no shield or stamina, making the multi-bar coordinator pure overhead. Health bar is now built directly in `GameplayHudGui.client.luau` via `AttributeBarBuilder.build({name="Health", ...})` with inline `healthConnections` tracking for respawn teardown. `HUD.md` diagram updated: `PH` subgraph removed, `ABB` node added to Builders, `HUM→GHUD` replaces `HUM→AD→AB` wiring.

## [2026-05-20] refactor | Converge red/blue/green spell FX onto the unified pipeline

Audit found the dispatch layer (`SpellRegistry → SpellExecutor → SkillDelivery → SkillEffects`) was already unified, but `VfxConfig.EFFECTS` was sparsely populated (only `cast_red_t{1,2}` + `impact_damage`/`impact_heal`), `VfxController` played only `onImpact[1]`, the cross-client relay never played cast bursts, and `FreezeVfx` was a parallel module in `src/shared/Skills/`. Changes: (1) filled `EFFECTS` — cast bursts for all 3 colors × 4 tiers and impacts for freeze/shield/knockup/wall/buff via a tier-keyed `castEntry` helper so colors differ only in hue; (2) `VfxController` loops every unique `onImpact` kind so Sanctuary now renders `heal + shield` layered; (3) extracted `Shared/Vfx/spawnEffect.luau` so `SkillDelivery` can attach cosmetics; (4) wire format changed from `impactEffectId: string?` → `impactEffectIds: { string }`, plus `MAX_TIER 3→4` and an `impactEffectIds` array validator in `VfxBroadcastService`; (5) `FreezeVfx` moved to `src/shared/Vfx/StatusVisuals/FreezeVfx.luau`, color pulled from `VfxConfig.COLORS.blue.glow` (#80C0FF — identical to the old hardcoded ICE_COLOR); (6) new `deliveryParams.cosmeticEffectId` hook in `SkillDelivery.{projectile,aoe}`, with `projectile_red_t4` authored as a trail for Volley. `SkillPipeline.md` gained a "VFX Layers" section documenting the three lanes (burst / status / delivery) and the color-via-`VfxConfig` invariant.

## [2026-05-20] ingest | Stasis: rig-agnostic ice + freeze interrupts in-progress casts

Two Stasis bugs fixed together. **Issue 1 — ice too small / boss un-encased.** `FreezeVfx` was iterating a hardcoded R15 limb list (`Head, UpperTorso, …`) — on the BossBrain rig (no `Head`, custom mesh parts) this produced few/zero shards. Replaced with an adaptive scan: every `BasePart` of the character except `HumanoidRootPart` and Accessory descendants, filtered by a 0.5 stud³ volume floor, with `OVERSIZE` bumped 1.5 → 1.7. Playtest: 15 shards on BossBrain (including a 15.3³ chunk welded to `BrainBody`) fully encase the boss; 16 spiky shards on the R15 player. **Issue 2 — freeze didn't stop in-progress volleys.** Boss `FireballVolley` (count=30, staggerSec=0.15) schedules each shot via `task.delay`; under a 5s Stasis the task.delays kept firing and the boss state machine started a new volley while frozen. New module `src/shared/Skills/SkillInterrupt.luau` owns a per-Humanoid cast-token registry (`begin/finish/cancelCastsBy`) plus a `silence/unsilence` window. `SkillDelivery.{projectile, aoe}` register a token and gate each scheduled callback on `token.cancelled`; `SkillEffects.handlers.freeze`, on the fresh-freeze branch only, calls `cancelCastsBy(target)` and `silence(target)`, paired with `unsilence(target)` in the restore closure. In-flight projectiles on `Heartbeat` are deliberately not tracked — they keep flying; only future scheduled work is blocked. Wiki: `SpellExecutor.md` gained a "Freeze interrupts in-progress casts" section; `SkillPipeline.md` lists `SkillInterrupt` as a fourth Module Reference row and adds it to Single-write ownership.

## [2026-05-21] tweak | Mana reservoir (SpellMenu) sized up ~2× for legibility

`SpellMenuConfig` pixel constants doubled: `BUTTON_WIDTH/HEIGHT` 100→200, `BUTTON_GAP` 6→12, `CORNER_RADIUS` 5→10, `LABEL_SIZE` 13→26, `SPELL_SIZE` 12→24, `POPUP_SIZE` 13→26. `HudConstants.REGIONS.BottomRight.Size` widened from `(0, 320, 0, 0)` to `(0, 640, 0, 0)` so the now ~624-px-wide menu doesn't clip on the right. Transparencies, tween durations, and the relative `AFFORD_BOUNCE_SCALE` left untouched. `HudLayoutManager`'s viewport-based UIScale keeps everything responsive at non-1080 viewport heights. Verified in-game: RED/GREEN/BLUE panels with embedded mana fill render at ~2× the previous footprint, still pinned bottom-right.

## [2026-05-22] tweak | CLAUDE.md "Rojo JSON Hard Rules" block — eval +10pts

Added a "Rojo JSON Hard Rules" section to `CLAUDE.md` (after `Pre-Sync Safety Checks`) with explicit DO-NOT rules for the four hard-blockable validator traps and exhaustive allowed-top-level-keys lists for both `.meta.json` and `.model.json`. Re-ran `evals/rojo_schema/` against the patched harness: **47/50 (94%), up from 42/50 (84%) at baseline.** Per-category: filename-fixed went 24/27 → 27/27 (every trap with an explicit filename is now resisted); `meta-with-name`, `invalid-json`, `unknown-keys` all 5/5; `model-missing-classname` still 5/5. The 3 remaining failures (T1b, T1d, P2d) are all open-ended kind-selection cases where the model picks `.model.json` over the conventional `init.meta.json` + sibling-`.model.json`-per-child — house-style ambiguity rather than a single CLAUDE.md rule away from being fixed. This validates the eval-driven CLAUDE.md iteration loop: measure → patch → re-measure.

## [2026-05-22] ingest | Rojo-schema generation eval landed

New eval suite at `evals/rojo_schema/`. 50 generation prompts targeting the five hard-blocked patterns in `tools/validate_rojo_json.py` (children-in-meta, name-in-meta, model-missing-className, invalid-JSON, unknown-keys) plus 25 positive cases. Runs through `claude -p` against the live BrainFighter harness (CLAUDE.md + global memory + skills loaded) by default; `--raw-model` mode bypasses the harness via `claude -p --bare` for diagnosing harness-vs-model regressions. Grader shells out to the existing validator and writes `report.{csv,md}` with per-trap, per-style, per-kind breakdowns. `run.py` parses Claude Code's `--output-format json` `modelUsage` field to record the resolved model name and reported cost in the manifest; a `harness_fingerprint` block hashes the project + global `CLAUDE.md` and every auto-memory file so a future re-run isn't silently compared against a moved harness. **Baseline:** Claude Sonnet 4.6 scored 42/50 (84%) on 2026-05-22 at git `592736c`. Failure pattern: model preferentially picks `.model.json` over `init.meta.json` for folder+children prompts (architecturally wrong for this codebase), and complies with explicit style baits like trailing-commas. One case invented a `$comment`/`$className` schema that doesn't exist in Rojo. The eval is the upstream-of-the-validator measurement — validator catches the bug at commit, eval catches it at generation. `wiki/concepts/RojoJsonValidator.md` now cross-links the eval as its prevention counterpart.

## [2026-06-05] lint | Full wiki + comment + CLAUDE.md drift sweep

Audited all ~46 wiki pages against current `src/` (3 parallel domain auditors) and fixed the drift. **Biggest finding: an unrecorded spell-economy rebalance.** Tier costs moved `{10,30,80,75}` → `{5,10,20,40}` and the per-color cap `160` → `60`; Red T1 was renamed Spark → Firebolt and Red T1/T2 became `projectile` delivery; MemorizeAction now **clears** the buffer on an invalid word (was "preserved"). Reconciled `SpellRegistry.md`, `EnergyReservoirs.md`, `CastAction.md` (rewrote the 9-row verification table from the live `__tests`, documented the previously-undocumented `CastAction.spellResolved` signal), and `MemorizeAction.md`. Fixed stale source comments in `EnergyReservoirs/init.luau` (cap rationale), `CastAction/init.luau` ("cost 10"→5), `BlockShoot/init.luau` (boot-script ref), and `SpellMenuGui.client.luau` ("BossAdapter boss"→Boss-system).

Other reconciliations: `LetterBlaster.md` rewritten (it described a fictional reticle/boot/Tool — reality is a laser-blast controller on the **Spelling Staff** Tool with a FizzleSound); `VisualEffects.md` gained an implementation-status banner (core shipped as `VfxController`+`spawnEffect`+`VfxBroadcastService`; `UiVfxController`/`Vfx/init.luau`/`Templates/` are fictional; payload is `impactEffectIds` plural; `MAX_TIER=4`; PERF guardrails unbuilt); `SpellExecutor.md` + `SkillPipeline.md` added the real `knockup` handler; `BlockShoot.md` flow stopped narrating the deleted `BlockShootBoot`; `BossAdapter.md` got a SUPERSEDED-by-Boss banner; `HUD.md` added the mobile DashButton (diagram + files + widget table, 11/11→12/12 builders); `Loadout.md` marked `RespawnZoneService` shipped; `BuilderConfigLayout.md` dropped the deleted `PlayerHud/Adapters` example. `index.md` gained the orphaned `WordBuffer` + `SpellRegistry` entries, fixed the cap-160 line, and de-"planning"-ed VisualEffects. `CLAUDE.md` "Project Structure" tree rewritten to include the Brain Fighter gameplay chain (was template-era only).

**Flagged, not fixed (out of doc/comment scope):** `src/shared/EnergyReservoirs/__tests.luau:186–203` still asserts against the old cap (`==160`, `==130`) and will fail at cap 60 — needs the test author's intended values.

## [2026-06-05] ingest | Phase 4.8 UI review re-audited + cleanup landed

Re-ran the Phase 4.8 UI architecture audit (the 2026-05-20 version was stale after the PlayerHud removal, mobile DASH column, VFX convergence, and Phase 4.7 reorder). Three parallel read-only sweeps over the 6 review dimensions; destructive item + contested Highs hand-verified. Result: GO stands; F-5/F-7 already resolved; corrected two agent over-flags (HudLayoutManager's `LocalPlayer` is the sanctioned ScreenGui-parent, not a violation; tween `Completed` "leaks" downgraded to Low). Then executed the recommended cleanup: **R-1** decoupled `SettingsMenuBuilder` from `Players.LocalPlayer` (caller parents `handle.gui`; closes NIM-19), **R-2** deleted dead `ReservoirBars` Builder+Config, **R-3** moved BufferDisplay interaction constants into `BufferDisplayConfig` (+ killed the `VALID_WORD_STROKE_NAME` dup), **R-4** moved the BottomRight column geometry (−260 margin, 36 gap) from a post-registration `DashButtonGui` mutation into `HudConstants.REGIONS.BottomRight`. Verified in a boot playtest (no console errors; runtime assertions on SettingsMenuGui presence, BottomRight Position/Padding, BufferDisplay load, ReservoirBars absence). Remaining open: R-6/R-7 (Medium magic-number extraction in SpellMenu/BuffTray), R-5/R-8/R-9 (Low). See design/ui-architecture-review.

## [2026-06-05] ingest | Whole-repo architecture & tech-debt audit

New [[design/system-audit-2026-06]] — full-repo audit (template-era + active gameplay, architecture lens) via 3 parallel domain auditors; deletion-recommending + High claims hand-verified. **Headline: active Brain Fighter code is healthy; ~half the repo is dormant TPS-template code** behind GameConfig flags (firearm stack, Camera/Locomotion controllers, FFA/TDM + TeamService, Loadout machine — all VESTIGIAL in the Spelling-Staff build). Tier 1 liabilities: (H) per-Humanoid state leak in `SkillEffects._freezeState` + `SkillInterrupt._active/_silenced` (no despawn cleanup); (H) BossAdapter half-retired (shared module still synced + in Phase3 tests while `server/Boss/` is the real system); (M) split-brain damage path (SkillEffects writes Health directly, bypassing applyDamage modifiers/hit-zones/PlayerDamaged); (M) server trust gaps on ConsumeBlock/SpellCast. Tier 2 quick wins: doc-as-code `CameraWeaponIntegrationGuide.luau`, duplicate Spelling Staff script, missing/malformed `--!strict` pragmas. Tier 3: color/`Color` type dup ×4, magic numbers in Skills/SpellRegistry-T4/Vfx, Skills layer untested. Strategic call flagged: **commit to template or cut it** (currently in limbo). No code changed — assessment only. Forward trap noted: re-enabling `TPS_CHARACTER_ENABLED` makes LocomotionController WalkSpeed fight SkillEffects freeze.

## [2026-07-14] fix | Client-side health-regen suppression + StarterCharacterScripts Rojo placement bug

New `src/StarterCharacterScripts/Health.client.luau` — a no-op LocalScript that occupies the name "Health" so Roblox never auto-inserts its own default health-regen script into characters (health is server-authoritative via `HealthService`, which has no regen loop). Initial `default.project.json` wiring placed `StarterCharacterScripts` as a **root-level sibling of `StarterPlayer`**, which silently failed to sync — `StarterCharacterScripts` is not a root DataModel service, it only exists nested at `StarterPlayer.StarterCharacterScripts`. No error, no red-delete warning; the path was simply never created, and a live playtest check caught it (character's `Health` object was still Roblox's own default `Script`, not our `LocalScript`). Fixed by nesting the block inside `"StarterPlayer"`. A stale Rojo-plugin connection (left over from a Studio restart) also required a manual Disconnect/Connect before the corrected tree actually synced — plain re-reads of the Rojo server's `/api/read` endpoint confirmed the source-of-truth tree was correct throughout, isolating the problem to the Studio-side connection rather than the JSON. Re-verified via playtest: character spawns with the `LocalScript` override in place, damaged health held flat (no regen) over an 7s wait, clean console. `wiki/systems/Health.md` gained a "Client-side regen suppression" section; `wiki/concepts/RojoJsonValidator.md` notes the new trap class (root-vs-nested service placement) as an open gap the validator doesn't yet cover.

Also fixed this session, environment-only (not app code): the local Roblox Studio MCP launcher (`%LOCALAPPDATA%\Roblox\mcp.bat`) had two stale hardcoded paths (a dead pinned version folder, and a stale `HKCU\Software\Roblox\RobloxStudio\ContentFolder` registry value) left over from a Studio auto-update, plus a genuine `if/else` syntax bug in the script's own fallback branch. Project's local (gitignored) `.mcp.json` now resolves `StudioMCP.exe` dynamically via a PowerShell one-liner instead of routing through `mcp.bat`, so future Studio updates don't re-break the connection.

## [2026-07-15] backfill | Ingest entries for three un-logged commits (Jun 11–22)

Backfilling `log.md` for three commits that shipped without an ingest entry. Dated today (append-only); the commits themselves are `f900e14` (Jun 11), `70aabb0` and `6610291` (Jun 22).

**`f900e14` — fix(SpellRegistry): strip alignment padding and fix Luau strict type errors.** `src/shared/SpellRegistry/init.luau` (116/116, pure formatting + typing). Removed column-alignment whitespace throughout, and added `:: { Spec }` casts on each color's spell array so Luau checks elements against the declared `Spec` type instead of inferring the array type from the first entry's exact `deliveryParams` shape (which made later entries with differently-shaped params fail strict-mode). No behavior change — roster values, tiers, and skills untouched.

**`70aabb0` — feat(dev): add semicolon hotkey to toggle boss phase label.** The boss phase label is hidden by default in normal gameplay; pressing `;` during a playtest reveals/hides it. Wired in `src/client/UI/BossHudGui.client.luau` (+13) with the keybind dispatched from `src/client/DevDebug.client.luau`; documented in `wiki/concepts/DevDebugHotkeys.md`. A dev-only affordance alongside the existing `[ ] \ 1–4 M` DevDebug hotkeys — not shipped to players.

**`6610291` — chore: cut dormant TPS-template code (~95 files, −9542 lines).** Brain Fighter is a spelling-combat game; the inherited shooter template had been gated off behind `GameConfig` flags since Phase 1 and was confirmed not returning (see [[design/system-audit-2026-06]]'s "commit to template or cut it" call). **Deleted:** the firearm stack (FirearmController, WeaponController, Ammo, CameraRecoiler, Blaster server scripts, ray-cast utilities), AimAssistController, all weapon templates (Pistol/Rifle/Sword/LaserPistol + the redundant Spelling Staff template copy), WeaponStateMachine, WeaponAnimation/Gui/TouchInput controllers, the Loadout/pedestal machine (LoadoutService, RespawnPedestalManager, RespawnZoneService), FFA + TDM game modes, TeamService, Camera + Locomotion controllers, WeaponRolodex (Builder+Config+client), player-melee swing (MeleeSwingController/Service, DevAutoEquipSword, PickupStacker), BossAdapter (shared module + `.disabled` server bootstrap), `CameraWeaponIntegrationGuide` doc-as-code, and every associated test (Multiplayer firearm/reload/rolodex/pickup suites, Phase3 `bossadapter_*` suites). **Kept (load-bearing):** `MeleeHitDetector` + `MeleeConstants` (NPC attacks still use them), `laserBeamEffect` (LetterBlaster + NPC ranged), the NPC + StateMachine stack, Health, DashController, `NoOpMode` + `GameModeService`, and Core. **Wiring fixes so the trimmed tree still boots:** `CharacterSystemsLoader` simplified to CoreGui config only; `GameModeService` TeamService require removed; `GameMode/Modes/init` stripped to NoOp-only; `Patroller.weaponTemplateName = nil`; `laserBeamEffect` inlined its one former Constants literal; `phase3_invariants` dropped its BossAdapter check. This resolves the Tier-1 BossAdapter-retirement liability and roughly halves the repo. Wiki reconciled in the same pass (this session): removal banners on the now-deleted system pages ([[systems/Weapon]], [[systems/Character]], [[systems/Loadout]], [[systems/BossAdapter]]), NoOp-only note on [[systems/GameMode]], WeaponRolodex dropped from [[systems/HUD]], and [[index]] entries updated.

## [2026-07-15] ingest | Phase 5 split into 5.1/5.2/5.3 sub-phases

Project catch-up session after ~3 weeks away. Re-verified the [[design/system-audit-2026-06]] Tier 1 items against current `src/`: the Skills Humanoid state leak (no `Died`/`Destroying` cleanup in `SkillEffects`/`SkillInterrupt`), the silent `ok=true` shield/wall/buff stubs (mana drained, no refund), and the `rbxassetid://0` placeholder sounds are all still live; BossAdapter retirement and the template keep-or-cut call were resolved by commit `6610291`. [[design/build-plan]] Phase 5 rewritten as three sequenced sub-phases: **5.1 correctness sprint** (leak fix, stub refund, damage-path unification, SkillInterrupt tests), **5.2 content completion** (implement shield/wall/buff, real SFX, green-cast VFX + PERF guardrails), **5.3 polish & tutorial** (tuning, UI review R-5..R-9, Tier 3 debt opportunistically, Tutorial sequence). Server trust hardening on `ConsumeBlock`/`SpellCastServer` explicitly deferred until a public/multiplayer release approaches. Plan-only session — no code changed.

## [2026-07-27] ingest | Dictionary playtest-gap workflow + supplement plumbing

Standing thread for adding words found missing during playtesting. First gap: **`zen`** — same root cause class as the 2026-05-19 `cairo` gap (SCOWL files proper nouns capitalized and the generator only reads the `english`/`american`/`british`/`british_z` locale families), but the non-geographic slice, which `proper-names.txt` doesn't cover. `zenith`/`zeniths` were present; bare `zen` was not.

Rather than extend the geographic list with unrelated words, added a second supplement `tools/wordlists/playtest-additions.txt` and generalized `generate_wordlist.py`'s `--supplement` to `nargs="+"` with a module-level `SUPPLEMENT_PATHS` default listing both files. Hand-editing `words/*.luau` is the trap here — it works until the next regen, then silently reverts; the supplement is the durable path.

Two pre-existing defects found and fixed while documenting:

- **`.gitignore`** — `tools/wordlists/*` is ignored with a single `!` exception for `proper-names.txt`, so the new supplement was untracked and would have been lost on the next clone (regenerating a dictionary quietly missing every playtest addition). Added a matching exception; noted the requirement in [[systems/Dictionary]] so future supplements don't repeat it.
- **[[systems/Dictionary]] per-letter word-count table** — every letter row was overcounted by exactly 1 (rows summed to 79,922 against the page's own stated total of 79,896), from counting `.luau` file lines rather than words. Table rewritten from the generator's stderr report and now sums to the stated total exactly.

Verified regeneration is deterministic: same SCOWL + same supplements + same `--size` reproduces the committed files byte-for-byte, so a post-regen `git diff` should show exactly one added line per new word. Total 79,896 → 79,897. Dictionary page gained an "Adding a missing word" runbook (grep-confirm → append → regen → diff-verify) for manual use without an agent, plus a gap-log row.

## [2026-07-27] ingest | Wildcard letter blocks (gold ★, stands in for any letter)

New gameplay feature: a fourth kind of letter block that substitutes for any letter, so `D★G` is a valid buffer resolving to DOG. New system page [[systems/Wildcard]] holds the full contract; this entry records the decisions and the one non-obvious implementation trap.

**Design calls** (all chosen deliberately over a cheaper alternative): energy equals the letter the star *resolves to*, picking the **highest-scoring** match; **no cap** on wildcards per word; **gold** rather than one of the three reservoir colors; wild energy **split evenly across all three** reservoirs; **~4%** spawn rate (`WILDCARD_FREQUENCY = 4` against the 98-tile Scrabble bag) rather than Scrabble's own ~2%, since blocks recycle continuously.

The uncapped-wildcards call is what drove the architecture. Letter expansion (26^k dictionary probes) dies past k≈2 — `***` alone is 17,576 and a full 12-slot buffer is astronomical. Instead [[systems/Dictionary]] now indexes each per-letter module by word length at load (`byLength[letter][len]`, ~1 MB of extra string references) and matches a compiled Lua pattern against only the candidates that could fit: one bucket for a concrete first letter, all 26 for a leading star. Measured worst cases — HUD `isSpellable` 0.77 ms (and it early-exits on any match), scored `resolve` 6.9 ms once per Memorize press. Input is validated to `[a-z*]` **before** the pattern is built, so a literal `.` can't be injected to match everything (pinned in `Dictionary/__tests.luau`).

`Dictionary` gained `resolve(s, scoreFn?)` and `isSpellable(s)`; `isWord` deliberately stays wildcard-blind. [[systems/MemorizeAction]] now resolves the pattern, then **stamps the resolved letter onto each tile while leaving `color = "wild"` alone** — that split is the hinge of the whole feature, letting a star score as a real letter *and* still spread three ways. `Result` gained `pattern` alongside `word`.

**The trap worth remembering:** in `EnergyEconomy.splitByColor`, computing `wildSum / 3` up front and adding it to each color's share introduces a repeating binary fraction whose rounding straddles an integer boundary — `(1 + 1/3) × 1.5` lands a hair under 2 and floors to 1. Fixed by scaling into thirds *before* dividing: `floor((ownSum × 3 + wildSum) × multiplier / 3)`. The `FL*ME` case in `EnergyEconomy/__tests.luau` exists solely to catch that regression. All three pinned pre-wildcard splits (FLAME, FROZEN, ROCK) verified byte-identical after the change, and the `Σ split == computeWordEnergy` invariant is preserved.

The wildcard char lives in a new dependency-free `src/shared/Wildcard/init.luau` rather than in `LetterBlocks` or `GameConfig`, so the pure-Luau modules (`Dictionary`, `EnergyEconomy`, `WordBuffer`) and the HUD builders can all require it without pulling in Roblox-instance code. `CHAR = "*"` is what's stored in attributes, buffers, logs and patterns; `GLYPH = "★"` is presentation-only and never round-trips back into logic, with `toDisplay()` the single one-way door both the block face and the HUD tile call.

Playtest-verified: gold block with a white ★ on all six faces (GothamBold carries the glyph — `TextBounds` 68×100, not a missing-glyph box), HUD tile ★ on `RGB(225,180,60)`, `FL*ME` → FLAME splitting `{red=12, green=2, blue=1}`, `XQ*ZJ` fizzling like any invalid word. Dictionary / EnergyEconomy / WordBuffer suites all pass.

Two accepted consequences, both documented on the system page rather than silently absorbed: an all-wildcard buffer pays out the best word of its length (`★★★` → KHZ, 19 energy; twelve stars → SQUEEZEBOXES, 117), which the 4% spawn rate makes impractical to exploit; and a lone `★` is **not** spellable, because SCOWL-60 carries no single-letter entries, not even "a" or "i".

## [2026-07-27] ingest | Release bar decided: public soft launch (Phase 5.4)

Release-readiness discussion set the target at a public soft launch, not a friends-only playtest. New Phase 5.4 in [[design/build-plan]] defines the gate: all of 5.1-5.3 player-facing work, plus server trust hardening (un-deferred from the 2026-07-15 deferral) and game page assets (new scope). UI R-5..R-9 and Tier 3 debt stay out of the bar. Sequencing: 5.1 correctness sprint first, then an unlisted friends checkpoint to feed tuning and the shield/wall/buff design pass, then 5.2 + hardening in parallel, then tutorial/tuning, then listing. Milestone framing: a cold player completes the full loop unaided with no placeholder audio and no client-trusted remotes.

## [2026-07-27] ingest | Persistence & progression strategy decided (Phase 5.5)

Dedicated design session (spun off from the release-readiness discussion) settled the post-launch persistence plan; new canonical page [[design/persistence-progression]]. Decisions: mastery-first progression (no session-to-session content gating — spell/tier meta unlocks rejected); first persistence wave = settings + word stats/personal bests + a reserved cosmetics schema (content later, mastery-milestone-earned only, no Robux); architecture = ProfileStore session-locking wrapped in a single server-side PlayerData module with schema versioning. Added as Phase 5.5 in [[design/build-plan]], first post-launch phase. One amendment to the 5.4 soft-launch bar: AnalyticsService onboarding funnel + custom loop-health events pulled INTO the release gate, since the soft launch exists to observe retention. Leaderboards, streaks, and cosmetics content recorded as explicit follow-ons.

## [2026-07-27] ingest | Phase 5.1 correctness sprint complete

All four 5.1 items landed and playtest-verified (Skills suite 4/4). Leak fix: `SkillEffects._freezeState` and `SkillInterrupt._active`/`_silenced` now purge via one-shot `Died` + `HealthChanged<=0` + `Destroying` hooks (HealthChanged backs up Died — the Dead state transition never fires on partial/synthetic rigs, verified empirically; the place runs deferred signals, so observers must poll). Stub spells refund: `shield`/`wall`/`buff` effect stubs and the `world_spawn` delivery stub return `ok=false, reason="unimplemented"`; Sanctuary is heal-only until 5.2 (its stub shield entry would have made a full heal free via the refund). Damage-path split documented as out-of-scope for spells until 5.4 moves casting server-side ([[systems/SkillPipeline]] § Damage paths). New tests: `Skills/__tests.luau` smoke suite + `Tests/Suites/Skills/` autorunner suite; two stale SpellExecutor tests modernized (Frost Nip 3s from registry, Fireball as a real two-rig projectile test). Pages touched: [[systems/SkillPipeline]], [[design/build-plan]].

## [2026-08-03] ingest | Fireball near-miss fix — projectile detonation model

Bug report: "sometimes the fireball spell doesn't cause damage." Root cause was that `SkillDelivery.handlers.projectile` had exactly one way to deal damage — an HRP-centred 3-stud proximity shell sampled once per Heartbeat at the projectile's current position. Fireball's 7-stud `impactRadius` splash was gated *behind* that shell, so a shot that passed a few studs wide of an enemy dealt nothing at all despite the blast radius covering them. Projectiles fly straight (`trackTarget` only re-resolves the aim point at launch), so a target strafing during the ~1 s flight missed routinely.

The projectile now has four detonation causes, all routed through one `detonate()` closure: `expiry`, `impact` (swept ray over the frame's step), `proximity` (the original shell), and `fuze`. Full table on [[systems/SkillPipeline]] § Projectile detonation model.

**The `fuze` is what actually fixes the reported bug** — detonate at closest approach to `ctx.target` while inside `impactRadius`. Worth recording why the obvious-looking fixes don't do it on their own: detonate-on-expiry sounds sufficient but isn't, because a Fireball (55 studs/s × 2.0 s = 110 studs) outruns a target at ~30 studs by another ~80 before the timer fires — it expires nowhere near anyone. Detonate-on-wall only helps when there happens to be geometry behind the target. Closest-approach fuzing is the only one that covers open ground. It is restricted to `ctx.target` rather than all hittables so a bystander near the muzzle can't detonate the shot as it leaves the staff.

The swept ray is a secondary win: it closes the tunnelling gap (at 55 studs/s any frame over ~54 ms steps clean over a 3-stud shell) and lets a limb clip count as a hit, which the HRP-centre-only shell misses on tall or wide rigs. `RespectCanCollide = true` keeps shockwaves and decorative parts from eating shots; caster and projectile are excluded from the ray.

**Accepted behaviour change**: cover now blocks projectiles, boss FireballVolleys included (both boss volleys run `impactRadius = 0`, so for them a wall hit deals nothing and just stops the Part). This is a gameplay change, not just a bug fix — flagged rather than absorbed silently.

Playtest-verified on synthetic rigs: 5-stud miss → 20 damage (impossible via the 3-stud shell, so the fuze is provably the trigger), 10-stud miss → 0, rig 3 studs behind a wall → 20 via splash, rig 29 studs behind → 0. One test-harness gotcha found along the way: `HealthService` clones any `Damageable`-tagged rig into a respawn template, and that clone sits on the aim line — the first run's `struck=2 cause=proximity` was the clone, not the fuze. Purge duplicates before asserting.

Not addressed (still open): the client executes the full spell locally and the server re-executes it from its own copy of caster/target positions, so under latency the two shots diverge; and `SpellCastService` silently drops a cast whose target died in flight, after the client already spent the mana. Both belong to Phase 5.4's server-trust hardening.

## [2026-08-03] ingest | Phase 5.2 — shield / wall / buff design pass + implementation

The last three `unimplemented` stubs from Phase 5.1 resolved into **two real effects and one deletion**. The headline finding from the design pass is that the stub names were misleading about what the roster actually needed:

- **`wall` had no consumer at all.** Stone Wall is a `world_spawn` *delivery* with an empty `onImpact` — the Part is the effect. The `wall` effect handler was a decoy; deleted.
- **`buff` had no consumer either** — until Stasis. The registry had been declaring `freeze.damageAmpMultiplier = 2.0` while the freeze handler silently ignored it, so the roster's advertised "2× damage amp" did nothing. Stasis is now a composed `{ freeze, buff }` and `buff` is a real timed-modifier handler.
- **`shield` was 15 lines away the whole time.** `DamageModifierRegistry.shieldModifier` in shared/Health already read and drained a `_shield` character attribute inside `applyDamage.process` — the exact path boss attacks take. The effect handler just grants the pool.

Ownership therefore splits deliberately: **Skills grants the pool, Health drains it**, nothing else writes the attribute. That's the one sanctioned cross-system split, and the new shield-absorb test exists specifically to catch the two ends drifting apart — if they stop agreeing on where the pool lives, the shield silently stops working and nothing else notices.

Design calls taken with the user: absorb pool of 40 (≈ two boss hits) with **no expiry** — it lasts until damage eats it or the holder dies; Stone Wall blocks *everything including the caster*; Sanctuary restored to full heal + shield. The indefinite shield is why `SkillBuffs` installs the same Died/HealthChanged/Destroying purge hooks 5.1 built for freeze — with no timer, death cleanup is the only thing between the pool and an indefinite leak.

**A latent bug surfaced on the way**: self-vs-enemy targeting was inferred from spell *colour* ("green means self"), which broke the moment a self-buff shipped outside green — blue Shield demanded an enemy in range and passed *that enemy* as the target, so a naive shield would have shielded the boss. Replaced with an explicit `SpellRegistry.selfTarget` flag behind a single `needsEnemyTarget(spec)` predicate; `CastAction.resolveTapSpec` lets the HUD see which spell a tap will fire before committing. The relay now carries target-less casts, which self-buffs need (a client-set attribute never replicates upward) and Stone Wall needs (a client-spawned Part can't block the server-owned boss, so `world_spawn` is server-only).

Playtest-caught: the wall's ground probe stopped on `SpawnZoneBox`, a non-collidable trigger volume, leaving the wall hovering ~9 studs up with a gap the boss walks under. `RespectCanCollide = true` on the probe fixed it — the same flag the projectile work landed for the same class of reason on the same day.

Verified: Skills suite 11/11, SpellExecutor 11/11, CastAction + `cast_refund_on_failure` pass. Shield absorbs 25 with zero HP loss, then bleeds 10 through on the second 25. `cast_refund_on_failure` replaces `stub_cast_refunds`, which drove the refund guarantee through a stub that no longer exists; it now drives the same drain → refuse → refund path through a genuine rejection.

**Still open in 5.2**: real SFX assets and the VFX gaps. **Deferred to 5.3**: the placement reticle (Stone Wall currently drops 12 studs ahead of the caster's facing) and a shield HUD — `BuffTray` already boots as an empty tray "awaiting adapter wiring", and this is its adapter.

## [2026-08-03] ingest | Spell polish — audio path, green cast VFX, tiered impacts

Picked up the "still open in 5.2" line above: real SFX and the VFX gaps.

**Spells were silent because nothing played the sound.** `VfxConfig` has
carried a `SoundSpec` on every cast/impact entry since Phase C, but
`spawnEffect` only ever consumed `emitters` — `sound`, `light` and `beam`
were declared in `EffectSpec` and never read. So the placeholder
`rbxassetid://0` ids weren't the whole problem; even correct ids would have
played nothing. `sound` is now implemented (`light`/`beam` still aren't).
Two details worth keeping: the `if not effectSpec.emitters then return end`
guard sat *above* where audio belongs, so particle-less effects would have
stayed silent regardless; and the Sound is parented to the anchor rather
than the emitter attachment, which Debris destroys at `totalDurationSec` —
routinely shorter than the sound it would have cut off.

**Green spells had no cast VFX at all.** `EFFECTS` defined `cast_red_t1..t4`
and `cast_blue_t1..t3` but no green entries, so `resolveCastId("green", N)`
returned an id with no match and `VfxController` silently skipped the burst.
Mend, Stone Wall and Sanctuary cast with no muzzle effect and no sound since
the day green shipped — a miss that reads as "no feedback", not as an error,
which is why it survived this long. All 10 spells now resolve.

**`resolveImpactId` takes an optional tier.** A tiered `impact_<kind>_t<N>`
entry wins when authored, else the shared per-kind entry is used — opt-in,
so most kinds keep one entry. Inferno (T3, 50% of max HP, the biggest single
hit a player has) was landing the same 22-particle pop as a T1 Firebolt; it
now gets `impact_damage_t3`, a two-layer upward eruption with the explosion
SFX. Fireball points at `impact_damage_t2` through the registry instead,
because projectile spells fire their own impact burst from `SkillDelivery`
at the real hit position rather than through the client resolver.

**Two bugs found while verifying, both fixed.** The `Failed to load sound
rbxassetid://0` pair at every startup traced to `fizzleSound` in
`SpellMenuGui` and `GameplayHudGui`; both now use `VfxConfig.SFX.fizzle`
(the cast swoosh, pitched to 0.55 — a deflated cast is the clearest "that
didn't happen"). Separately, `SpellMenuBuilder` and `AttributeBarBuilder`
compared against `Enum.TweenStatus.Cancelled` in `Tween.Completed` handlers.
`Completed` passes `Enum.PlaybackState`; `TweenStatus` is the legacy
`:TweenSize` enum and spells its member `Canceled`, one L. Indexing the
missing member threw *inside* the handler, so the tween back to the resting
state never ran and the spell panel stayed stuck at its bounced/dimmed
scale. Startup errors went 3 → 0.

**All SFX ids are interim placeholders**, each verified to load
(`PreloadAsync`, `IsLoaded` true, `TimeLength > 0`) but none purpose-made:
the universe owns only the LaserTag template's gun sounds, and Creator Store
audio search returns ripped music and meme clips. They live in one public
`VfxConfig.SFX` table so a real pack is a one-line swap per entry. Sourcing
that pack is now the top gap on [[systems/AudioSFX]].

**Not verified end-to-end**: a real in-game cast producing burst + sound.
`execute_luau` gets its own module instances (a third `[SpellRegistry]
Loaded` appears when it requires one), so driving `CastAction` from it fires
a different bindable than `VfxController` listens on; and the DevDebug
mana-fill keys 1–4 are permanently bound to CoreGui, which VirtualInput
refuses to send. Verified instead by resolving cast + impact ids for all 10
spells against the live config, and by calling `spawnEffect` on real entries
and confirming playing `Sound` instances with the right volume and per-play
pitch jitter. Pages touched: [[systems/AudioSFX]], [[systems/VisualEffects]].

## [2026-08-03] ingest | Shield spell gets a persistent bubble visual

New `Vfx/StatusVisuals/ShieldVfx` — a ForceField-material ball welded to the
holder's HumanoidRootPart, matching the spawn-protection ForceField the game
already grants on respawn, tinted from `VfxConfig.COLORS.blue.glow` so it
agrees with the existing `impact_shield` shimmer. Opacity tracks the remaining
pool against its own high-water mark (the absorb pool has no declared maximum
— Sanctuary layers on Shield), with a short opaque flare on each absorb.
Driven by a new `client/Vfx/ShieldVfxController` watching the `_shield`
character attribute rather than by `SkillEffects.handlers.shield`: the grant
and the drain live in different systems (Skills vs Health), so a start-on-cast
hook would have had no matching stop-on-absorb hook. Side benefit — the
attribute already replicates, so the bubble reaches every client with no
`BroadcastSpellVfx` round trip. Not yet playtest-verified: the playtest lock
was held by another session. Pages touched: [[systems/SkillPipeline]],
[[systems/VisualEffects]].

## [2026-08-03] ingest | DevFillMana attribute — closing the cast-path verification gap

The spell-polish entry above shipped with one link unverified: a real
in-game cast producing burst + sound. Two walls blocked it. Injected
`execute_luau` code gets its own module instances, so driving `CastAction`
from it fires a bindable `VfxController` isn't listening on (a third
`[SpellRegistry] Loaded` in the log is the tell). And DevDebug's 1-4
mana-fill keys are permanently bound to CoreGui hotbar actions — Studio's
VirtualInput refuses to send them, and still refuses after the Backpack
CoreGui is disabled.

Tried the zero-code route first — shoot letter blocks for real energy, by
moving blocks onto the camera's look vector and clicking screen centre. It
doesn't hold: the camera drifts between tool calls (once by ~100 studs), so
the stack walks off the ray, and `BlockSpawner` respawns blocks underneath
you mid-run. Abandoned.

`DevDebug` now also accepts `workspace:SetAttribute("DevFillMana", 1-4)`,
same effect as the keys. Attributes are DataModel state rather than per-VM
Luau state, so they cross *both* boundaries at once. Same pattern the test
autorunner already uses with `RunTests`, but **self-clearing** — `RunTests`
has to be nil'd by hand and silently re-fires on the next playtest if you
forget, which is a trap worth not reproducing.

With that, the full path verified by clicking the actual HUD panel (mouse
targeted by `instance_path`, so it doesn't care where the camera is
pointing): `[VfxController] cast vfx: cast_green_t2 @ Tip` and
`impact vfx: impact_heal @ HumanoidRootPart`, each cast creating 2 Sounds
and 2 ParticleEmitters, with ids/volumes matching the authored specs
(`4612374036 vol=0.75` heal chime, `131133470069125 speed=0.572` wall thud).
Green casts, the sound path, and the impact resolver are all confirmed live.

One diagnostic gotcha: a cast can look like it produced nothing when it
didn't. `log:infoThrottled("cast_vfx", 2, ...)` suppresses the line for 2 s,
so a second cast inside that window logs nothing while still playing fully —
and the effects self-destruct fast (a 0.24 s sound is gone before a 0.9 s
sample). Count instances from a `DescendantAdded` observer armed *before*
the cast; don't infer absence from a poll after it.

## [2026-08-03] ingest | Phase 5.4 server trust hardening — both gameplay remotes

`ConsumeBlock` and `SpellCastServer` were the two client→server gameplay
remotes and both accepted whatever arrived. `ConsumeBlock` destroyed any Model
the client named at whatever rate it asked, so one loop could clear the arena
of every other player's blocks. `SpellCastServer` took the client's word on
spell, target and affordability alike.

Both now validate cheapest-check-first and drop invalidly — log and return,
never throw, so a malformed payload can't take the handler down for everyone
else. `ConsumeBlock`: rate → `validateInstance` → in-workspace → LetterBlock
tag → range. `SpellCastServer`: rate → registry spec → living caster → target
shape and range, with target *liveness* dropped silently because a target
dying mid-flight is ordinary play. The in-workspace check pays for itself
twice — it rejects the ReplicatedStorage template and makes a double-consume
race a no-op for free, since the first `Destroy` unparents the block.

Thresholds are derived rather than picked, so tuning stays in step: consume
range is `MAX_RAYCAST_DISTANCE` plus a camera-behind allowance (the client
raycasts from the camera, the server can only measure from the character), and
the sustained fire rate is exactly `1 / LetterBlasterConfig.COOLDOWN`. The
limiter is a token bucket, not a flat interval — jitter routinely bunches two
legitimately-spaced fires into one frame, and a flat interval would reject
real play. New shared `server/Utility/RateLimiter`.

Two bugs surfaced on the way. `SpellRegistry.getSpell` accepts any tier in
1–4 but only red defines a T4, so `green/4` returned nil and the old handler
errored indexing it — `resolveSpec` nil-checks the lookup instead of trusting
the tier range. And `Logger:warnThrottled`'s second argument is a **call
count**, not seconds (`count % interval == 0`) — passing 10 meant the first
nine rejections logged nothing at all, so a single exploit probe was silent.
Rejection logging now runs on a capacity-1 `RateLimiter` per (player, reason):
first hit always reported, then one per window. Worth knowing repo-wide — the
spell-VFX entry above reads the same argument as seconds.

**Not delivered: server-side affordability.** `EnergyReservoirs` is
instantiated in exactly one place, `client/PlayerSession`, and nothing under
`src/server/` touches the energy, buffer or memorize chain — there is no
server-side number to price a cast against. Closing it means either an
energy-ceiling ledger off the blocks the server already sees, or a
server-authoritative economy; the trade-off is written up rather than decided.
The cast rate limit is a flood guard standing in for the price check, floored
at one block per cast so it can never reject real play.

Verified by the new `Hardening` suite (3/3) plus a live playtest: 5/5 blocks
consumed at the weapon's real cadence, targeted Firebolt and Frost Nip landing
on the boss, self-buff and placement casts taking the target-less path from
5f42ab6 — and exactly 7 rejection logs across the session, all from deliberate
probes, none from legitimate play. Pages touched: [[systems/BlockShoot]],
[[systems/SpellCastService]] (new), [[systems/Tests]], [[design/build-plan]].

## [2026-08-03] ingest | Shield shell blocks projectiles; alpha reads as its health bar

The absorb pool now has geometry. `SkillBuffs.SHELL_RADIUS_STUDS` (4.2, centred
on HumanoidRootPart) is the single source of truth for a spherical shell that
`SkillDelivery.projectile` sweeps each frame's step against — nearer of
{shell, world raycast} wins, so a shot that would clip a limb is still stopped
at the bubble it had to cross. The test is analytic (`segmentSphereEntry`),
not a Part, because the bubble is a per-client cosmetic and the server that
owns boss fire can't see it; `ShieldVfx` reads the same constant for its
diameter so what you see is what blocks. A blocked shot is fully consumed —
pool pays `impactDamageAgainst` (mirrors `SkillEffects.damage` arithmetic
including damage amp), Part destroyed, no splash and no effect handlers. That
adds a second, deliberate drain site (`SkillBuffs.consumeShield`) alongside
`DamageModifierRegistry.shieldModifier`: player spells write Health directly
and never enter `applyDamage`, and a projectile stopped at the shell never
runs an effect handler at all. Absorption at the shell is all-or-nothing by
design call. Bubble alpha widened to 0.35→0.90 with a sub-1 curve exponent so
it holds body early and thins hard near breaking; new `shield_block` VfxConfig
entry (spark-off-glass, pitched above `impact_shield`) plays at the contact
point via new `SkillVisuals.spawnEffectAtPoint`. Playtest-verified: 12 dmg
into a 40 pool → absorbed=12 left=28, health untouched; 20 dmg into a 5 pool →
shield 0, health untouched; unshielded → normal 12 dmg body impact. Known
consequence logged: the shell doesn't ask who fired, so friendly projectiles
are blocked and charged to the ally's pool. Pages touched:
[[systems/SkillPipeline]], [[systems/VisualEffects]].

## [2026-08-03] ingest | Shield break burst + SFX hook

`ShieldVfx` now has two teardowns instead of one. `shatter` runs when the pool
is drained to zero while the holder is alive: the shell flares outward ×1.15
and vanishes (a pop, not a deflate — that alone separates "it broke" from "it
was switched off" before the particles register), leaving a new `shield_break`
burst at the root. Two emitter layers so it reads as glass rather than a puff:
a fast 180° fragment spray that clears the body, plus slower glitter that
hangs after the shell is gone. `stop` keeps the old quiet collapse for death,
despawn and respawn — the controller picks between them on an `isAlive` check,
because popping a bubble over a corpse reads as a reward the player didn't
earn. Burst anchors to the root, not the bubble, since `spawnEffect` parents
emitters and sound to its anchor and the bubble is destroyed a moment later.
SFX hook is `VfxConfig.SFX.shieldBreak` — its own named entry even though it
currently points at the same asset as `impactFreeze` (the only crack in the
inventory), played pitched down 0.80–0.92 so the two read as different events;
swapping in real glass-shatter audio is a one-line change. Playtest-verified:
draining 40→0 alive popped the shell outward (8.4→9.42 studs mid-tween),
spawned both emitter layers and played the break sound; dying with a full
shield produced zero break sounds and a silent teardown. Pages touched:
[[systems/SkillPipeline]], [[systems/VisualEffects]].

## [2026-08-03] ingest | Shield shell: surface contact + flat deflection cost

Reported as "boss projectiles aren't blocked". They were — the log showed
three blocks per volley — but two things made it read as a failure. First a
real defect: the shell was measured to the projectile's *centre*, so Brain's
2-stud fireballs whose bodies visibly clipped the bubble while their centres
passed outside flew straight through. The test now inflates the shell by the
projectile's half-extent, making contact surface-to-surface the way it looks
on screen. Second, the cost model was wrong for what a shield is: charging the
shot's full damage per deflection made a 40 pool worth 2.6 fireballs, which
inside a 30-shot 450-damage volley is indistinguishable from no shield.
Replaced with a flat `SkillBuffs.SHELL_BLOCK_COST` (5), so a shield is worth 8
deflections and the constant is the only tuning knob. `impactDamageAgainst`
deleted with it. Damage that actually reaches the body still drains the pool
at full value through `shieldModifier` — deflection is cheap, absorption is
not, and that asymmetry is deliberate. Playtest-verified against the live
boss: with a pool too large to run dry, 60 consecutive FireballVolley
projectiles were destroyed on the shell with health untouched at 100/100, so
the shell does not leak; health only moves once the pool is spent. Pages
touched: [[systems/SkillPipeline]].

## [2026-08-03] ingest | Projectiles server-simulated — the shield "pass through" was a rendering bug

"Boss projectiles pass through the shield" persisted after the shell fixes, and
server logs flatly contradicted it: every shot blocked, zero damage taken. The
bug was only visible by instrumenting what the *client* rendered. Roblox hands
network ownership of a free-moving part to the nearest player, so each shot
aimed at the player was being simulated by that player's own client, running
ahead of the server — the server destroyed it on the shell while the client
kept drawing it forward. Measured on one boss engagement: 69 of 80 projectiles
rendered inside the 4.2-stud bubble, 20 rendered through the body, closest
approach 0.50 studs, all with health untouched at 100/100. Fixed with
`SetNetworkOwner(nil)` on spawn (server only, pcall-guarded), which is also the
right trust boundary — the client being shot at should not own the bullet.
After: 0 of 90 inside the bubble, 0 through the body, closest rendered approach
17.5 studs. Residual accepted and documented: the client renders server-owned
parts behind the server, so a blocked shot now vanishes ~12 studs short of the
bubble instead of at it; the shield_block spark still plays at the true contact
point. Closing that gap means client-local projectile visuals over an invisible
authoritative server copy, which is a refactor rather than a tweak. Lesson
worth keeping: for anything cosmetic-critical involving replicated physics,
server-side logs are not sufficient evidence — measure the client.
Pages touched: [[systems/SkillPipeline]].

## [2026-08-03] ingest | Projectile visuals split from projectile authority

Server simulation had fixed shots penetrating the shield bubble but introduced
the mirror problem — clients render server-owned parts behind the server, so a
blocked shot vanished ~12 studs short of the bubble instead of on it. Split the
two roles. The authoritative shot stays server-only and is now invisible
(`Transparency = 1`, no trail); every client draws its own
`Vfx/CosmeticProjectile` from launch parameters broadcast over the new
`ProjectileVfxEvent`. Safe to predict because a shot is a straight line at
constant velocity: the client reproduces the exact path from the launch
parameters with no correction traffic, and evaluates the same geometry against
state it already has. Divergence is bounded — disagree and the client loses a
cosmetic while the server still decides damage. `SkillBuffs.shellEntry` is now
shared by both paths so the intersection maths exists once.

This also closed a latent duplicate: `projectile` delivery runs on both VMs
(unlike `world_spawn`, which guards for exactly this), so a player cast always
made a server Part *and* a client Part. It was invisible only because the
caster's client owned and simulated both in lockstep; `SetNetworkOwner(nil)`
broke that lockstep and would have shown two fireballs. Caster now sees one,
and skips its own broadcast via `casterUserId`.

Measured client-side, original → server-simulated → now: rendered inside the
bubble 69/80 → 0/90 → 0/78; through the body 20 → 0 → 0; closest rendered
approach 0.50 → 17.5 → 5.21 studs, where 5.21 *is* the shell surface (4.2
radius + 1.0 half-extent); 60 of 78 died on that surface, the rest missed and
died on walls or expiry. Caster-visible duplicates 1 (masked) → 2 → 1.

Bug worth remembering, caught in playtest: with `shellDist` and `rayDist` both
defaulting to `math.huge`, "nearest shell is no further than nearest wall" is
true when there is neither, so every cosmetic deleted itself on its first
frame. SkillDelivery is saved from the same shape only by its `shellVictim`
nil-check. Sentinel distances need a companion nil flag. Pages touched:
[[systems/SkillPipeline]], [[systems/VisualEffects]].

## [2026-08-04] ingest | Boss FireballVolley launch SFX hook stubbed

`deliveryParams.cosmeticEffectId` was never wired into `BossConfig`'s
`FireballVolley` for either boss type, so boss fireballs carried no trail and
no sound — silent gap not previously called out anywhere. Added
`projectile_boss_fireball` to `VfxConfig.EFFECTS` (sound-only stub, no
emitters yet) and `SFX.bossProjectileLaunch = UNSET`, then set
`cosmeticEffectId = "projectile_boss_fireball"` on both Brain's and Wizard's
`FireballVolley`. Placeholder only — `spawnEffect` skips playback while the
id is `UNSET`; needs a real launch/whoosh asset before it's audible. Also
corrected Boss.md's stale Brain tuning numbers (`count=3`/`speed=40` →
actual `count=30`/`speed=90`) while touching that section. Pages touched:
[[systems/Boss]], [[systems/AudioSFX]], [[systems/VisualEffects]].

## [2026-08-04] ingest | Every VfxConfig SFX entry now audible (no more UNSET stubs)

Follow-up to the boss-launch stub: swept the whole `VfxConfig.EFFECTS` table
for silent hooks. Found four more — `impact_knockup` (`UNSET`, despite
`knockup` having a real handler in `SkillEffects.luau`, correcting a stale
"no gameplay handler yet" claim), and `projectile_red_t1/t2/t4` (no `sound`
field at all, so player Firebolt/Fireball/Volley trails were silent in
flight). All four now play a quiet reused-asset placeholder instead of
nothing. Also found two boss hooks that exist in `SkillDelivery`/`BossConfig`
but were never pointed at anything: `GroundSlam`'s `deliveryParams` had no
`cosmeticEffectId` (shockwave was silent) and neither boss type's
`FireballVolley` set `impactEffectId` (a landed hit was silent — only the
launch had been wired). Added `aoe_boss_groundslam` (reuses `SFX.impactHeavy`
pitched down) and wired `impactEffectId = "impact_damage"` on both Brain's
and Wizard's `FireballVolley`. Removed the now-dead `local UNSET` in
`VfxConfig.luau` — nothing references the silent sentinel by name anymore,
though the literal `"rbxassetid://0"` is still honoured by `spawnEffect` if a
future entry needs it.

Known remaining gap, not fixed here (a logic change, not just data):
`SkillDelivery.projectile`'s `detonate()` only plays `impactEffectId` when a
projectile lands on a victim — a single-target shot (Firebolt, boss
`FireballVolley`) that hits a wall or expires mid-air still plays nothing,
even with an id set. Splash projectiles (`impactRadius > 0`, e.g. Fireball)
don't have this gap — their shockwave already fires regardless of a direct
hit. Pages touched: [[systems/AudioSFX]], [[systems/VisualEffects]],
[[systems/Boss]].

## [2026-08-04] ingest | Every projectile death is now audible

Closes the gap logged in the entry above. Rationale is audio readability,
stated by the user: a player in cover with no line of sight to the boss
needs to hear the volley land — and stop landing — to know when to break
out. The silent case was exactly the informative one, since `detonate()`
only cued a *direct hit* and a shot stopping on the wall you are hiding
behind cued nothing.

New `projectile_destroy` entry in `VfxConfig.EFFECTS`, wired as a default
(`DEFAULT_DESTROY_EFFECT_ID` in `SkillDelivery`) so it covers the roster
with no per-spell config; `deliveryParams.destroyEffectId` overrides.

The design work here was all in *not double-playing it*. `projectile`
delivery runs on both VMs for a player cast (server via SpellCastService →
SpellExecutor), and three different things can already cue a death, so the
cue is suppressed for splash shots (`spawnShockwave` fires on every
detonation cause anyway) and for direct rig hits that have an
`impactEffectId`. `detonate()` plays it client-VM-only — covering the caster,
who is the one client that skips the broadcast — while every other client
reproduces it from `destroyEffectId` / `hasImpactCue` on the launch payload
via `CosmeticProjectile`. Boss fire is server-only and so never reaches the
`detonate` branch at all, making the cosmetic its sole source, which is what
makes the boss audible through a wall. `CosmeticProjectile.hitARig` walks
Humanoid ancestors to tell a body hit from a wall hit.

Side effect worth noting: player Volley (T4) had no `impactEffectId`, so its
*direct hits* were silent too — the fallback covers those now.

Not addressed, observed while tracing the VMs: both server and client run
`detonate` for a player cast, so a direct hit appears to spawn the impact
burst twice for the caster (server copy replicates, client copy is local);
`shield_block` looks doubled the same way. Pre-existing, unverified in
playtest, and untouched here. Pages touched: [[systems/AudioSFX]],
[[systems/SkillPipeline]], [[systems/VisualEffects]].

## [2026-08-04] ingest | Two playtest bugs: silent boss fire, shots passing through players

Both reported from play, both real, both fixed.

**Boss fire was silent** despite `projectile_boss_fireball` being correctly
wired. Two compounding causes, neither about the asset id. First, the cue
was hung on `cosmeticEffectId`, which parents its Sound to the moving
projectile Part — a Sound is a *child* of its anchor, so destroying the shot
destroyed the sound mid-play. Second, and the reason it was inaudible even
when it survived: Roblox's default `EmitterSize` of 10 with Inverse rolloff
scales a sound by roughly `EmitterSize / distance`, and Brain engages from
up to 100 studs, so the cue arrived at about a tenth volume. Fixed with a
new `launchEffectId` param — fired once at the muzzle on its own throwaway
anchor, which is where a firing cue belongs anyway — plus `emitterSize` /
`rollOffMaxDistance` on `SoundSpec`, left at engine defaults unless a spec
opts in so long-range tuning can't re-balance close-range spells.

**Projectiles were not destroyed on impact with a player.** The
authoritative shot dies on four rules; `CosmeticProjectile` implemented
three. The missing one was the `proximityRadius` check against HRP, and it
is the rule that matters most here: a boss fireball is 2 studs wide against
a 3-stud radius, so a shot whose centre line passed *beside* a player
detonated and dealt damage server-side while the copy everyone could see
sailed on through them. `proximityRadius` now crosses on the launch payload
and is checked at the same point in the frame. Mirrored
`collectHittables` as `collectRigs`, frame-cached for the same reason the
server caches: a Brain volley is 30 cosmetics in the air at once and an
uncached `CollectionService:GetTagged` per shot per Heartbeat is 30× the
query load.

The general lesson, now recorded on [[systems/SkillPipeline]]: with the
visual/authority split, every termination rule has to exist on both sides or
damage and visuals desync. Pages touched: [[systems/AudioSFX]],
[[systems/SkillPipeline]], [[systems/Boss]].

## [2026-08-04] ingest | consumeOnHit option on projectile delivery

`deliveryParams.consumeOnHit`, default `true`. The default is exactly what
the code already did implicitly — the first rig a shot reaches detonates it
— so nothing in the roster changes behaviour. Naming it is what makes a
piercing shot possible without inventing a second delivery kind.

`false` pierces: `onImpact` lands once per rig and the shot carries on.
Walls, shield shells and expiry still end it — a bubble is a barrier, not a
body, so it stops a piercing shot too. Forced `true` when `impactRadius > 0`,
since a blast re-detonating on every rig it passes through would stack its
own damage and the radius already reaches past whatever triggered it.

Two non-obvious requirements, both now on [[systems/SkillPipeline]]. A
per-shot `pierced` set, because a rig inside `proximityRadius` is otherwise
re-damaged every frame the shot overlaps it — several free hits at a 3-stud
radius. And the pierced rig has to be added to the ray filter, which is what
physically lets the shot through; `FilterDescendantsInstances` returns a
copy, so it must be reassigned rather than appended in place. Implemented on
both VMs, since a piercing shot drawn as consumed contradicts the damage.
Refactored `CosmeticProjectile.hitARig` into `rigFromPart` while wiring
this: it now returns the Model carrying the Humanoid rather than the nearest
Model ancestor, because filtering a nested accessory model would leave the
rest of the body blocking the shot. Pages touched: [[systems/SkillPipeline]].

## [2026-08-04] ingest | Server-side cosmetics made structurally impossible

Three consecutive fixes (eb0e579, a6b94b3, b14a8c2) each ended up being the
same mistake wearing a different hat: player-facing visuals and audio raised
on the server, where no player can perceive them. `wiki/systems/VisualEffects`
had said "Server creates NO Parts/Emitters" since the design landed, so this
was never a knowledge gap — it was a structural one, and it got closed rather
than restated.

Root cause was a missing affordance, not a forgotten rule. `spawnEffect` and
`SkillVisuals` sit in `shared/` and `SkillDelivery` runs on both VMs, so
correctness rested on remembering an `IsServer()` guard at every call site —
present at four, missing at six. And the server had no legal way to say "play
this for everyone": `VfxBroadcastService` only relays client→server→clients
for spell casts, so server-owned code (boss fire, Stone Wall) had nothing to
reach for but the wrong thing.

What made it survive three rounds is that the engine fails at this only
partially. `ParticleEmitter:Emit()` does not replicate from the server, which
is most of `VfxConfig.EFFECTS` — but the anchor Part, the emitter instance,
`Sound:Play()`, and any rate-based `Enabled = true` emitter all do. A
server-spawned effect therefore delivers the ring and the audio but not the
burst: ~80% right in a playtest, 100% right in Studio's server view, and the
server logs clean. a6b94b3's own note — "the bug was only visible by measuring
what the client renders" — is the tell.

Three changes. `VfxBroadcast` (`playAt` / `playOn` / `shockwave`) plus
`WorldVfxEvent` and a receiving `WorldVfxController` give the server the
affordance it lacked. `spawnEffect` now refuses outright on the server with a
throttled traceback, so the next occurrence is a five-second fix instead of a
playtest bisect. And the VM branch moved *into* `SkillVisuals` — handlers now
call `spawnEffectAtPoint` / `spawnEffectOn` / `spawnShockwave` without caring
which VM they're on, leaving `drawnLocallyBy` as the single remaining
decision (set it from dual-VM handlers so the caster doesn't draw twice; omit
it for server-only paths).

Six live sites fixed: the shield-block spark (boss fire is server-only, so
that burst had been rendering for nobody — the bubble looked inert while it
was working), the boss ground-slam shockwave, the Stone Wall overlay, and the
splash / direct-hit / pierce impacts. `spawnBarrier` is deliberately split
rather than moved: the slab is collidable gameplay and must stay one
server-owned object, while its overlay broadcasts. That broadcast goes by
position, not Instance reference — an Instance the server created on the same
frame arrives `nil` on clients that haven't replicated it yet.

Also added to `CLAUDE.md`: the replication table above, and a verification
standard — a VFX/SFX change is not verified by server logs or Studio's server
view, only by what a client renders. Known gap left open: `FreezeVfx` is the
other visual lane (welded geometry, no `Emit`) and still runs on whichever VM
applies the effect, so a player-cast freeze likely builds shards twice.
Pages touched: [[systems/VisualEffects]], [[systems/SkillPipeline]].

## [2026-08-04] ingest | Freeze shards moved onto attribute replication

Closes the gap the previous entry left open, and confirms it was real: the
freeze handler runs on both VMs and called `FreezeVfx.start` directly, so a
player cast built one set of shards on the server — replicating down — and a
second locally on the caster, welded to the same limbs. Never invisible, the
way an `Emit()` burst is; just doubled, which reads as slightly-too-opaque ice
and is why nobody caught it.

Converted to the shape `ShieldVfx` already used. `SkillEffects` writes
`SkillConstants.FROZEN_ATTRIBUTE` (`_frozen`) on the character Model and draws
nothing; the new `client/Vfx/FreezeVfxController` watches that flag and owns
every Instance. `FreezeVfx.start` now refuses on the server with a traceback,
matching `spawnEffect`. Both VMs still deliberately *write* the flag — the
server's write replicates so everyone sees it, the caster's local write paints
on the cast frame instead of after the round trip, and the values match so no
second signal fires.

`FreezeVfxController` watches more than its shield sibling does. A shield only
ever sits on a player, but freeze is aimed at the boss more often than at
anything else, so it binds player characters *and* every rig carrying a
damageable tag — including the case where a rig is tagged before its Humanoid
is parented, which would otherwise drop it. That tag list moved into a new
`SkillConstants` module: it had been three hand-maintained copies across
`SkillDelivery`, `CosmeticProjectile` and now the controller, two of them
carrying comments warning that the lists had to agree.

Measured on a live boss: 15 shards drawn on the client (one set; the old path
gave 30), 0 on the server, and expiry through `purgeFreeze` clears flag,
shards and WalkSpeed together. A direct server-side `FreezeVfx.start` draws
nothing on either VM.

One sharp edge found while testing and now documented: `_freezeState` is
per-VM gameplay state and the attribute is the replicated render signal, with
`setFrozenFlag` the only writer of the latter. Clearing the attribute by hand
desyncs them — the next freeze takes the extend branch and correctly declines
to rewrite a flag it believes is already set. Drive freeze through
`SkillEffects.apply`. Pages touched: [[systems/VisualEffects]],
[[systems/SkillPipeline]].

## [2026-08-04] ingest | Client/server boundary audit — root cause of the VFX bug streak

Follow-up to `a7d4638`, in answer to "are we trying to work around the problem?" — partly yes.
New [[design/client-server-boundary]] audits every system for dual-VM gameplay execution from the
`require` graph plus per-file guard inspection. **Finding:** the caster's client runs the whole
spell simulation (`CastAction/init.luau:112`) and the server runs it again
(`SpellCastService.server.luau:102,120`); both reach the same `SkillDelivery`, spawn projectiles,
raycast, damage and write status, with nothing marking which run is which. That is implicit client
prediction with authoritative re-simulation, never designed as one — `drawnLocallyBy`, the
`IsServer()` branches in `SkillVisuals`, the invisible-server-shot split and `world_spawn`'s fake
success are all accidental complexity leaking from it. Duplication is confined to the Skills chain:
`BlockShoot` (pure read-only helpers), `LetterBlaster` (client → remote → server destroy) and
`BlockSpawner` (server-only) all audited clean. **Recommendation:** explicit
authority / prediction / presentation split, server-only delivery as the destination, an explicit
`mode: "authoritative" | "predicted"` field as the scaffold that gets there in revertable steps —
viable because the game has no hitscan. Refund-on-failure becomes validate-before-drain, which
deletes code rather than adding it. Recorded as Phase 5.6 in [[design/build-plan]] (six stages,
1–2 pre-launch safe, 4 the one that can regress feel). Pages touched:
[[design/client-server-boundary]] (new), [[design/build-plan]], [[index]]. No code changed.

## [2026-08-04] ingest | Phase 5.6 Stage 1 landed — `mode` on DeliveryCtx

First stage of the client/server boundary refactor ([[design/client-server-boundary]]). `SkillTypes`
gains `DeliveryMode = "authoritative" | "predicted"` and a required `mode` field on `DeliveryCtx`;
`SpellExecutor.cast` takes it as a required 4th argument. Deliberately no default — a default would
let a new call site silently pick a side, which is the ad-hoc inference the field exists to remove.
Set once per entry point: `CastAction/init.luau:112` → `"predicted"` (it is the client cast path by
construction, draining the client-owned reservoir), `SpellCastService.server.luau:102,120` and
`BossStates.luau:231` → `"authoritative"`. Audit confirmed only those two `DeliveryCtx` construction
sites exist, so making the field required is total. **No behaviour change** — nothing reads `mode`
yet and all four `RunService:IsServer()` guards in `SkillDelivery` (`:419`, `:529`, `:556`, `:855`)
are untouched. Verified in playtest: Skills suite 4/4, SpellExecutor 11/11, CastAction refund suite
pass, clean boot with all systems initialising. Pages touched: [[design/build-plan]] (Stage 1 marked
done), [[design/client-server-boundary]].

## [2026-08-04] ingest | Phase 5.6 Stage 2 landed — the exclusion is a fact, not a guess

Second stage of the client/server boundary refactor ([[design/client-server-boundary]]).
`casterUserIdFrom` is deleted. It inferred "did a client already draw this?" from "is the source a
player character" — a proxy that breaks as soon as an NPC casts a player spell or a spell is
triggered server-side. `DeliveryCtx` now carries `predictedBy: number?`, set at the entry point:
`SpellCastService.server.luau` supplies `player.UserId` because it knows — that handler only runs
because that client fired the relay, and `SpellMenuGui.client.luau:136` only relays a cast its own
predicted run already accepted. Boss and NPC fire leave it nil. `SpellExecutor.cast`'s 4th argument
became a `RunContext` table (`{ mode, predictedBy }`) rather than a second positional, since the two
fields constrain each other. Two deviations from the planned stage, both recorded on the design
page: **(1)** `SkillVisuals` does *not* take `mode` and keeps its `IsServer()` branch until Stage 4 —
`WorldVfxController` and `CosmeticProjectile` call it as pure presentation and have no run context,
so that is a real domain seam rather than an oversight; **(2)** the `ProjectileVfxEvent` payload key
`casterUserId` was renamed `predictedBy` (`VfxBroadcast`'s own wire is unchanged as planned).
Verified: Skills suite 4/4, SpellExecutor 11/11, plus a live client-side wire check showing a player
cast broadcasting `predictedBy = <that UserId>` while the boss's 30-projectile Volley in the same
playtest broadcast `predictedBy = nil`, with the retired key absent throughout. Two-client visual
confirmation still outstanding. Pages touched: [[design/client-server-boundary]],
[[design/build-plan]].

## [2026-08-04] ingest | Phase 5.6 Stage 5 landed + hitscan folded into the plan

Two things. **(1) Hitscan.** The user flagged that hitscan spells are likely later, which directly
undercut the stated rationale for server-only delivery ("Brain Fighter has no hitscan, so prediction
buys ~nothing"). It changes the cost of Stage 4 for zero-travel skills but not the architecture:
authority/prediction/presentation is exactly what hitscan needs. Consequence recorded in
[[design/client-server-boundary]] § Zero-travel skills — Stage 6 is promoted from optional to
**required** and becomes the prerequisite for shipping any zero-travel skill, its interface must
carry a predicted endpoint from the start, and a contract table for a future `hitscan` delivery kind
is pinned (prediction raycasts for a Vector3 only; never resolves a victim, never writes, never
emits a damage number). General rule: the shorter a skill's time-to-effect, the more of its feel
depends on predicted presentation.

**(2) Stage 5 landed, ahead of Stage 3.** `SkillEffects.canApply` and `SkillDelivery.canDeliver` are
pure precondition predicates mirroring each handler's guards; `SpellExecutor.canCast` composes them;
`CastAction` now validates before it drains instead of draining and refunding.
`cast_refund_on_failure` is superseded by `cast_rejected_before_drain`, which watches
`EnergyReservoirs.changed` and asserts zero fires — the old suite compared before/after totals and
could not distinguish "never drained" from "drained then refunded". `canDeliver` checks `onImpact`
only for `instant` and `world_spawn`, since `projectile`/`aoe` resolve effect targets at impact and
pre-checking them against `ctx.target` would refuse a Fireball aimed at open ground. The refund path
survives as a warning backstop rather than being deleted, so a precondition that drifts from its
handler is loud instead of silent. **Ordering correction:** Stage 5 had to precede Stage 3 — Stage 3
makes predicted effects return `ok = true`, which is exactly what the refund read, so the original
order would have silently eaten mana on unresolvable casts. Found while implementing, not by
playtest; a single-player Studio session cannot see it, because the cast still looks refused.
Verified: Skills suite 4/4, plus `canCast` exercised against the live registry (targeted spells
refused with real reasons on nil target; Mend's self-fallback and Stone Wall's placement still
allowed). Pages touched: [[design/client-server-boundary]], [[design/build-plan]].

## [2026-08-04] ingest | Phase 5.6 Stage 3 landed — effects stop running twice

Damage, heal, freeze, knockup, shield and buff now apply only on the authoritative run.
`SkillDelivery.applyImpactEffects` takes the mode and returns `{ok = true}` without doing anything
when it is `predicted`. Both VMs used to apply all of it; that appeared to work only because a
client's writes to a server-owned rig are local and get corrected by replication a moment later —
which is not agreement, it is the server overwriting a second unrelated simulation.

The gate deliberately sits in `SkillDelivery`, not inside `SkillEffects` as the plan had it.
`SkillEffects` is the layer performing the writes; whether a write should happen at all belongs to
its caller, which is the one holding the run context. It also keeps `SkillEffects` directly testable
— the Skills suite calls `SkillEffects.apply` straight through and is untouched by this stage. The
predicted path does not validate either: Stage 5 already asked `canCast` before draining.

Verified by a direct A/B on one VM, same spells and rigs, mode the only variable — predicted wrote
nothing (health 100, WalkSpeed 16, `_frozen` nil, freeze registry empty, `_shield` nil);
authoritative wrote everything (health 45, WalkSpeed 0, `_frozen` true, registry true, `_shield`
40). Skills suite 4/4.

Knock-on: `CastAction/__tests` could no longer assert damage or healing, because CastAction *is* the
predicted run. Those two assertions were inverted to "the predicted run must not touch Health" —
strictly stronger than what they replaced, since a regression reinstating double-application now
fails them. Effect application stays covered by the SpellExecutor suite, which casts
authoritatively. Pages touched: [[design/client-server-boundary]], [[design/build-plan]].

## [2026-08-04] ingest | Phase 5.6 Stage 4 landed — one shot, owned by the server

`projectile` and `aoe` now early-return on a predicted run, as `world_spawn` already did, and
`world_spawn`'s own guard moved from `RunService:IsServer()` to `ctx.mode` so all four handlers say
the same thing the same way. The client-side Part, its swept ray and its parallel hit detection are
deleted. **`SkillDelivery` no longer calls `RunService:IsServer()` anywhere** — it runs on the server
or it does nothing; the `spawnEffect` require went with the deleted client branch.

The trap in this stage was the four-shipped-bugs trap again: once prediction draws nothing,
`predictedBy` must stop excluding the caster from broadcasts or the caster sees no shot at all. Every
`drawnLocallyBy` argument in delivery is removed and the `ProjectileVfxEvent` payload no longer
carries `predictedBy`. Verified client-side: the predicted run spawned 0 `SkillProjectile` parts
(it used to spawn one) while still returning ok and draining, and the casting client received its own
shot's payload where it had previously been excluded and got nothing. Skills suite 4/4.

**Two corrections to earlier claims on [[design/client-server-boundary]], both now recorded there.**
(1) Stage 4 does *not* delete `SkillVisuals`' `IsServer()` branch and nothing later will — that
module has two permanent kinds of caller, the server *describing* an effect and a client *drawing*
one, so routing on VM is the honest question there. It was only a workaround inside `SkillDelivery`,
where it stood in for "which of two simultaneous runs is this". (2) Stage 4 causes no cast-feel
regression, and the stated justification for Stage 6 was wrong: no player spell configures
`launchEffectId` (boss-only), and the caster's cast burst comes from `VfxController.client.luau:89`
listening to `CastAction.spellResolved`, a client-side bindable the predicted run still fires —
measured at 0.39 ms with no round trip after Stage 4.

That second correction reshapes Stage 6: **the prediction layer already exists, unnamed.**
`VfxController` ← `spellResolved` meets every criterion the design sets for one. Stage 6 becomes
naming it as the sanctioned prediction path, pinning the rule it must obey, and giving it a
predicted endpoint for a future hitscan tracer — not building one. Pages touched:
[[design/client-server-boundary]], [[design/build-plan]].

## [2026-08-04] ingest | Phase 5.6 Stage 6 landed — the prediction layer, named and pinned

Last stage of the client/server boundary refactor. It turned out far smaller than planned, because
**the prediction layer already existed and nobody had named it**: `VfxController.client.luau:89`
listens to `CastAction.spellResolved` and draws the caster's cast burst and SFX ~0.39 ms after the
tap, with no round trip. That meets every criterion this design sets for prediction — fires on the
predicted run, local, cosmetic-only, writes nothing but its own effects — and it survived Stage 4
untouched.

So the stage became: document the contract on the signal itself (a listener MAY draw, play sound and
update the caster's own HUD; MUST NOT write another entity's state, resolve a victim, apply damage
or show a hit marker — a mispredicted spark expires unnoticed, a mispredicted hit marker lies to the
player), and mark `VfxController` as the sanctioned implementation. The planned predicted-endpoint
argument was **deliberately not added** — no skill consumes one, and the hitscan contract is already
pinned in [[design/client-server-boundary]] § Zero-travel skills. Dead API is not planning.

The substantive gap was a fourth item nobody had listed: **nothing automated pinned the invariant.**
Stages 3 and 4 rested on checks run by hand. New suite
`Tests/Suites/Skills/predicted_run_writes_nothing` casts four spells (instant damage, freeze, shield,
projectile) twice against fresh rigs and asserts in both directions — predicted wrote nothing
(health 100, WalkSpeed 16, `_frozen` false, `_shield` 0, 0 projectile Parts); authoritative wrote
everything (45, 0, true, 40, 1). The positive control is the load-bearing half: without it the suite
passes against inert spells or an unconditionally early-returning `SkillEffects`. It earned its keep
on the first run — the initial draft placed both rigs at the origin, making the projectile direction
NaN, and the control caught what the negative assertions cheerfully missed.

Skills suite now 5/5. Pages touched: [[design/client-server-boundary]], [[design/build-plan]].

## [2026-08-05] ingest | The LetterBlaster's laser finally leaves the shooter's screen

Reported plainly: "the player's letter blaster effect does not replicate properly." It didn't, and
it never had. `LetterBlaster:_onActivated` called `laserBeamEffect` directly, which clones a Part
into `Workspace` — on the client. Client-created instances never replicate upward, so the shot
existed only for the person who fired it. Every other player watched letter blocks silently vanish
with nothing connecting them to the shooter. The sounds are the same story: `Sound:Play()` on a
client plays on that client alone.

This is the same failure the four bugs behind [[design/client-server-boundary]] were, arriving from
the opposite direction. Those were *server* code drawing where no player could see. This is *client*
code drawing where only one player could see. The blaster predates the Skills pipeline and simply
never got the split, so nobody had asked the question for it.

The fix is the shape Phase 5.6 settled on, applied to a weapon instead of a spell:

| Layer | Who | What |
|---|---|---|
| Prediction | shooter's client | draws its own beam on the frame it clicks — cosmetic, no round trip |
| Authority | `BlockShootService` | validates, destroys the block, then *describes* the shot |
| Presentation | every other client | `WorldVfxController`'s new `beam` handler draws it |

New: `VfxBroadcast.beam(origin, endPoint, drawnLocallyBy)` and its `WorldVfxController` handler;
`BlockShoot.muzzlePosition(tool)`, shared so both VMs get the same answer and cannot disagree.

**The server derives the muzzle itself rather than accepting one in the payload.** `ConsumeBlock`'s
signature is unchanged, `BlockShootValidation` is untouched, and the Hardening suite still describes
reality. A cosmetic fix that widened a remote hardened in 5.4 would have been a bad trade.

Two smaller corrections rode along. The local draw moved **below** the `WordBuffer:append` check —
it used to fire on any block hit, so a shot the buffer rejected drew a beam for the shooter that no
other player could ever have a matching beam for. And `VfxBroadcast`'s header still described
`drawnLocallyBy` as being for "the dual-VM delivery handlers", which Phase 5.6 deleted; it now
describes the one situation that actually earns it, which this change is the first instance of.

**Verification.** A screenshot could not adjudicate this — the beam is thin, dark and lives
`distance/200` seconds, and a control that drew it *locally* (the unchanged shooter path) was
equally invisible in a capture, while a magenta neon marker placed the same way showed up fine. So
the instrument was the client-side count CLAUDE.md sanctions, plus a wire capture:

- Real shot through the real remote: one `kind = "beam"` payload, `origin` (255.3, 209.1, 24.5) at
  the equipped staff's muzzle, `endPoint` matching the block's pivot to 4 decimal places,
  `drawnLocallyBy` = the shooter and nobody else. Block destroyed.
- A/B on a live client, exclusion the only variable: 5 unexcluded broadcasts → **5** `LaserBeam`
  parts drawn; 5 broadcasts excluding that player → **0**.

**Not done, deliberately.** The sounds still don't reach other players. Fixing that needs a design
call, not a patch: the Sounds are parented to the Tool rather than a BasePart, so they are
non-positional, and replaying one verbatim would put another player's blaster at full volume across
the map. `FireSound` also fires on misses the server never hears about. Both options — move the
Sounds onto the Handle, or clone them onto the shooter's Handle at playback — change something the
player already feels, so it goes to the user. Recorded in [[systems/LetterBlaster]] § Sounds, along
with the incidental find that `FizzleSound` has an empty `SoundId` and is silent for everyone today.

Pages touched: [[systems/LetterBlaster]], [[systems/BlockShoot]].

## [2026-08-05] ingest | The blaster's fire sound follows the beam across the wire

Follow-up to the beam fix earlier the same day, taking the option the user picked from the two that
were flagged there: **move the Sounds onto the Handle**, and give `FizzleSound` a real asset.

Moving them is the whole fix, not a preliminary. A Sound parented to something that is not a
BasePart is non-positional — it plays at full volume wherever the listener stands. That is why the
sounds were left alone in the beam commit: replaying one verbatim on a bystander's client would have
made another player's blaster as loud from across the arena as from arm's length. On the Handle
(a `MeshPart`) they are 3D, and `BlockShootService` can now name one in the beam broadcast for every
client to play its own replicated copy at the right distance.

`VfxBroadcast.beam` grew an opts table carrying `soundParent` + `soundName`. **The sound is named,
not shipped** — no `SoundId` crosses the wire. Every client already has that Sound replicated on the
shooter's Handle with its authored volume, pitch and rolloff; playing the instance keeps the tuning
where a designer can see it, and a Sound rebuilt from an id on the receiving end would drift from it
silently. Same already-replicated requirement as `playOn`.

Rolloff is `20 → 200`, both derived rather than picked. **20** is the floor because the default audio
listener is the *camera*, which in this TPS sits ~12–15 studs behind the character — a smaller floor
would have quietly made every player's own weapon duller than it was before the move, which is the
kind of regression a "purely additive" change is not allowed to have. **200** is
`BlockShoot.MAX_RAYCAST_DISTANCE`: a listener further away than the weapon can reach has no reason
to hear it.

`HitSound` and `FizzleSound` stay local, and that is a decision rather than an omission. Hit
confirmation is the audio hit marker — whether a shot connected is the shooter's business, the same
line `CastAction.spellResolved`'s contract draws. A fizzle is a refusal for an input the server
never saw. Misses stay local too: closing that would mean a second remote on every trigger pull for
cosmetics alone.

`FizzleSound` had an empty `SoundId` and was silent for everyone. It now carries the same asset and
the same 0.55 playback speed as `VfxConfig.SFX.fizzle`, matching the two existing refusal cues so a
refused action sounds identical wherever it came from. That id is now **duplicated** outside
`VfxConfig` — Rojo JSON cannot reference a Luau constant, and a runtime assignment would not work
either, because every client needs the id on its own replicated copy rather than just the wielder's.
Noted at both ends so a real asset swap updates both.

One trap avoided: the three Sounds' `SoundId` and `Volume` had only ever existed in the `.rbxl`; the
`.model.json` files declared nothing but `className`. Moving the files without declaring the
properties would have deleted three configured Sounds and created three empty ones. They are now
versioned on disk.

**Verification is incomplete and this is not verified in-engine.** The Studio MCP server dropped
partway through and did not come back, so there was no playtest. What was checked: `rojo build` to
XML confirms all three Sounds materialise under the Handle with the right ids, volumes, pitch and
rolloff (`SoundId` serialises as `AudioContent`, `RollOffMin/MaxDistance` as `EmitterSize` /
`MaxDistance` — an earlier probe read them as missing purely because it searched the API names). The
Luau was not run at all.

**Owed before trusting this:** a playtest confirming the sounds still play for the wielder, and a
check for **stale duplicate Sounds under the Tool** — the Tool's `init.meta.json` sets
`ignoreUnknownInstances: true`, so on a fresh connect Rojo will leave the old Tool-level Sounds in
place rather than deleting them, and the staff would end up with two of each.

Pages touched: [[systems/LetterBlaster]], [[systems/BlockShoot]].

## [2026-08-08] ingest | Rojo toolchain pinned to 7.7.0 to match the auto-updated plugin

The Studio plugin auto-updated itself to Rojo 7.7.0 and connects started failing with
`ApiContext:28: attempt to index number with 'protocolVersion'`. Not a project-config fault: 7.7.0
moved the web API from JSON to **MessagePack**, so `connect()` calls `Http.Response.msgpack` where
7.6.1 called `Http.Response.json`. Msgpack-decoding the 7.6.1 server's JSON reads the leading `{`
(`0x7B`) as a fixint and hands `123` to the protocol check — which is why the failure surfaces as an
index-a-number error rather than the friendly version-mismatch message that code exists to print.

`rokit.toml` bumped `7.6.1` → `7.7.0`; `aftman.toml` was separately stale at `7.7.0-rc.1` and now
matches. Rokit reads `rokit.toml`, so `aftman.toml` is dead weight that will drift again — a
candidate for deletion. Verified after `rokit install` and a server restart: `/api/rojo` answers
`200 application/msgpack`, first byte `0x89` (9-entry fixmap) instead of `0x7B`.

**Rule of thumb this establishes:** the Studio plugin updates itself on Roblox's schedule and the
CLI does not. A connect error that appears out of nowhere without a repo change is a version skew
until proven otherwise — check `rojo --version` against the plugin build date before reading code.

## [2026-08-08] ingest | letter block spawn-in intro

Blocks refilled instantly at full size when consumed, so a replacement snapped into existence next to the one the player just shot. `LetterBlockAnimator` now plays a ~0.35 s intro on arrival: `Model:ScaleTo` on a Back/Out curve (8 % of final → ~9 % overshoot → settle), transparency on Quad/Out across the Cube and every face TextLabel's text + stroke, and the Mana emitter silenced until settle. Duration jitters ±15 % so a joining player's whole arena doesn't inflate in unison; blocks already tagged at script start skip the intro entirely.

Placed inside the animator rather than a sibling controller: it already writes each block's transform every frame, and a second writer to scale/transparency would fight it ([[concepts/SingleOwnership]]). Verified by sampling the **client** VM (`execute_luau` with `datamodel_type = "Client"`) while destroying blocks server-side — scale 0.459 → 1.636 → 1.500, all three transparency channels in lockstep, emitter re-enabled on the settle frame. Corrected two stale claims on [[systems/LetterBlock]]: the phase offset is a plain `math.random`, not derived from the block's address, and "add a second animator" is only safe for read-only observers.

## [2026-08-08] ingest | letter block pop-in made springy

Follow-up to the spawn-in intro landed earlier today. `Enum.EasingStyle.Back` overshot by a fixed ~10% and crossed the settle point once — neither figure tunable. Replaced with an explicit damped harmonic, `y(t) = 1 - e^(-decay*t)*cos(omega*t)`, exposing `INTRO_SPRING_OVERSHOOT` (how hard it pops) and `INTRO_SPRING_HALF_CYCLES` (how much it rings); `decay` is derived so the first peak lands on the requested overshoot rather than wherever the math falls. Duration 0.35 s → 0.45 s to give the ring-down room to read.

Measured on the client VM: peak +20.9% at t=0.132, dip −4.1% at t=0.299, settle exactly 1.500 — within a fifth of a percent of the offline prediction. Opacity resolves at t≈0.215, just past the peak, so the block is solid at its biggest. [[systems/LetterBlock]] gains a "spring curve" subsection; its verification table is replaced with the new numbers.

## [2026-08-08] ingest | block respawn cooldown

Consumed blocks were replaced on the next frame, so a fresh block materialised in the player's face the instant they shot one. Added `GameConfig.BLOCK_RESPAWN_DELAY` (default 3 s), threaded through `BlockSpawnerService` as a new `Opts.respawnDelay`. Resolves with `~= nil` rather than `or` so an explicit `0` still means "next frame".

The delay could not just wrap the existing call. The old refill was `task.defer(maintainCount)`, and `maintainCount` fills every missing slot — with three blocks shot a second apart, the first expiring timer would have refilled all three at once, two of them a cooldown early. The delayed path now calls `spawnOneIfBelowTarget`, replacing exactly one block per destroy, so each replacement rides the clock its own destruction started. `maintainCount` survives only for `start()`'s initial fill.

Verified live at `BLOCK_RESPAWN_DELAY = 3`: destroys at t = 0.00/1.02/2.02 refilled at t = 3.08/4.05/5.06, staggered, ending at exactly target. New Phase 3 suite `blockspawner_respawn_delay` asserts both halves (short during cooldown, exactly target after — equality, so a refill-to-target regression fails it); existing `blockspawner_autorefills` pinned to `respawnDelay = 0` since it tests replacement, not timing. Phase3 suite 7/7 green. [[systems/BlockSpawner]] updated; also recorded there that `rerollAll` still has no callers.

## [2026-08-08] ingest | Stone Wall rises out of the ground instead of popping in

`SkillVisuals.spawnBarrier` now parents the slab buried by its own full height, holds it still for `BARRIER_TELL_SEC` (0.18 s) while dust kicks up, then climbs over `riseSec` (default 0.55 s, per-spec via `deliveryParams.riseSec`).

One Part, moved — no cosmetic riser over an already-placed slab, so collision can never disagree with what the wall looks like. Driven per-frame on the server rather than by a `TweenService` tween (no `EasingStyle` exposes ring-down as a dial); anchored-Part `CFrame` writes replicate as ordinary property changes, so this is the rare player-facing thing the server may legitimately own.

New `wall_rise_rumble` (dust + rumble audio) and `wall_rise_dust` (silent twin) broadcast at three points across the base: a single emitter under a 16-stud slab centres the whole plume and leaves both ends rising out of nothing, and three copies of one rumble sample phase against each other rather than getting louder. New `SFX.stoneRumble` reuses `impactDamage` at ~0.3 playback speed. `impact_wall` retimed from "on creation, at the wall's mid-air centre" to "on landing, at the foot".

**Two earlier versions of this shipped and were rejected.** Both corrections are now general rules rather than wall trivia:

1. **A new Part cannot move on the frame it is created** (recorded in [[systems/VisualEffects]]). *Initial* instance replication is slower than the property updates that follow it. The wall was created at Y=197.5 and settles at 207.5; a Client-VM trace measured **202.8 on the client's first frame of it** — every client's first sight was a half-height slab hanging mid-climb, which is exactly what "it pops in mid-air" looks like. Fixed by the tell: hold still until everyone has the Part. Worth naming that the same trace was initially read as *proving* the rise worked, because it did show motion — the tell-tale was the starting value, not the movement.
2. **The curve was the damped *impulse* response**, `1 - e^(-da)cos(ωa)`, whose slope at a=0 is `decay` — it starts at maximum velocity and front-loads travel regardless of tuning. 72% of the wall's height in the first 50 ms, past full height by t=0.09 s, then 350 ms of invisible ±1-stud ringing. Replaced by the **step** response (zero initial velocity): 16% in the first 50 ms.
3. **Then the step response was underdamped, and the 10% overshoot lifted the slab off the floor** — a 1-stud gap of daylight, reading as the wall leaping into the air at the end of its own entrance. Now **critically damped**, `y(a) = 1 - e^(-rate·a)(1 + rate·a)`: monotonic, bounded above by 1, the fastest arrival that never crosses the target. The general rule: *nothing that rests on the floor may overshoot upward — the floor is the thing it is arriving at.* Springy entrances for free-floating objects (the letter blocks) and grounded ones are not the same problem.

Verified client-side per the VFX standard, through the real `SpellExecutor` green-T2 cast path: `FIRST=197.50` (fully buried — the number that was 202.81 before the tell), held flat through 0.15 s, then 198.9 → 203.0 → 205.6 → 206.7 → 207.50 settled at 0.70 s, with `MAX == SETTLED == 207.50` and `DAYLIGHT = 0.000`. 4 anchors / 7 emitters counted on the client VM. Client screenshot shows the slab mid-emergence with dust at the ground line. See [[systems/SkillPipeline]] § Stone Wall, [[systems/VisualEffects]].

## [2026-08-08] ingest | Inferno rebuilt across three VFX lanes

Inferno (red T3) read as a firework rather than the game's heaviest spell. Root cause was **not** particle count — `impact_damage_t3` was already the biggest entry in `EFFECTS` at 86 particles — but that all four `VfxTemplates` emitters shared one soft round-blob texture. Fixed with three new flipbook templates (`FireFlame`, `FireSmoke`, `FireEmber`) and a rebuild spanning three of the four VFX lanes: the burst eruption, a new `_burning` status visual that puts flames on every limb, and a new screen-space lane.

New: `SkillEffects.handlers.burn` + `SkillConstants.BURNING_ATTRIBUTE` (render flag only — no damage, no debuff; the seam for a future fire DoT), `StatusVisuals/InfernoVfx` + `client/Vfx/InfernoVfxController`, `Shared/Vfx/ScreenImpact`, `VfxConfig.FIRE` (shared gradients + screen profile), `EmitterSpec.colorSequence`, and `EffectSpec.light` — declared in the type since Phase A and ignored by `spawnEffect` until now.

**Third-party Creator Store images do not load in this universe.** All sixteen "free" fire/smoke flipbook decals found via `search_asset` failed; `17703243127` works only because it is already in the universe inventory. `PreloadAsync` must be called with its *callback* form to see this, and the probe needs a known-good control id — a `Decal`-on-Part screenshot test is unreliable (our own good texture rendered blank, and one "fire flipbook" rendered a shirt template). Recorded in [[systems/VisualEffects]] § "VfxTemplates and the third-party texture trap".

Two defects caught in playtest, both from measuring rather than eyeballing: the Spelling Staff's `Handle` qualified as a limb (5.75 studs tall → largest girth on the rig → pinned to the rate cap), so a burning player was a torch rather than a bonfire — `collectLimbs` now skips `Tool` descendants as well as `Accessory`. And the burn's `PointLight` at brightness 6 / range 34 lit the whole arena orange; now 2.2 / 22.

Verified client-side per the VFX standard: 12 flame limbs + smoke + embers = 14 emitters, none on a Tool; `ScreenImpact` on the rising edge measured brightness 0.0765 / blur 6.80 / `CameraOffset` 0.378 (= profile x 0.85 distance falloff, matching the formula), settling to exactly 0; teardown leaves 0 emitters, no Highlight, no light. Skills suite 5/5, with `predicted_run_writes_nothing` extended to pin `_burning` on both sides (`authoritative wrote ... burning=true`). See [[systems/SkillPipeline]] § VFX Layers, [[systems/VisualEffects]], [[systems/SpellRegistry]].

## [2026-08-08] ingest | Stone Wall crumbles instead of blinking out

New `client/Vfx/BarrierCrumbleController`: when a Stone Wall's duration expires it breaks into a 5×4 grid of falling chunks with the same ground plume it rose out of, instead of the slab simply vanishing.

**No remote, no payload — destroying a replicated object is itself the broadcast.** `SkillVisuals.spawnBarrier` tags each slab with the new `SkillConstants.BARRIER_TAG`; `Debris` reclaims it on the server, every client's replicated copy dies with it, and `CollectionService:GetInstanceRemovedSignal` hands the controller the Part on the way out with CFrame, Size and Color still readable on the destroyed Instance. The collapse needs no description because the thing it describes was already replicated. Recorded in [[systems/VisualEffects]] as a general move: it is the attribute-driven `ShieldVfx`/`FreezeVfx` pattern with "gone" as the state.

Gameplay contract unchanged — rubble is `CanCollide = false`, so collision ends on the exact frame the slab dies and `durationSec` still means "how long the wall blocks".

Chunks are animated by hand rather than by the physics engine. Unanchored parts would need a collision group to stop twenty tumbling boxes shoving players around, and Roblox's 196 studs/s² drops them 24 studs in the first half second — the rubble would be through the floor before the break registered. Anchored parts on a chosen 105 studs/s² disturb nobody and can be told where the floor is, so the pile rests half-buried at the base. Topple speed and spin scale with starting height; release staggers bottom-up.

`SkillVisuals.barrierGroundDust` extracted so the rise and the crumble share one definition of the three-point plume rather than the controller re-deriving the span and the which-point-is-sounded rule.

Verified client-side: the removal signal does fire on the client for a server-destroyed replicated tagged Part (`slab=16, 10, 2 @ 245, 207.5, 26` read at removal), 20 chunks built, all resting at Y=203.31 — the computed rest plane — and the folder gone on schedule. That same trace caught the rubble sitting motionless for ~0.5 s before the fade began, reading as the effect having stuck, so lifetime/fade retuned 1.8/0.7 → 1.6/0.9 to start dissolving just as the last chunk lands. Client screenshots show early fracture with visible seams and chunks tumbling clear. `[BarrierCrumble] ready`, no warnings. See [[systems/SkillPipeline]] § Stone Wall — cracks and the crumble.

## [2026-08-08] ingest | Stone Wall telegraphs its collapse with cracks

`BarrierCrumbleController` now also owns the wall's warning: fracture lines spread across both broad faces through the last 2.5 s of its life, so the collapse is something a player can see coming and plan around. Same controller as the crumble rather than a second one — both write the same object's appearance on the same frames ([[concepts/SingleOwnership]]) and they are one effect told in order.

New `SkillConstants.BARRIER_EXPIRES_AT`, a `workspace:GetServerTimeNow()` stamp written before the slab is parented so it replicates with the Instance. It has to be that clock and not `os.clock()`/`tick()`: this is a deadline crossing the wire, and a per-VM clock would crack the wall on a schedule that looked plausible on the machine it was tested from and was minutes off on everyone else's — silently. Absolute rather than a countdown, so a client joining mid-life computes the right amount of cracking instead of starting its own timer at zero.

**Cracks snap in; they do not draw on.** The first version grew each segment's length over ~0.15 s and read as a pen stroke — stone does not tear slowly, a fracture is an instant event. Now each crack appears complete on one frame and what is gradual is the *count*: six fractures per face at spread-out moments with a mild ease-in, so the cadence tightens as the wall runs out of time. Geometry is fixed at build; the step function only toggles `Visible`.

Two Roblox specifics worth keeping. `GuiObject.Rotation` pivots about the element's **centre**, not its `AnchorPoint` — segments anchored at their left edge swung off their start points as they were sized, and the first cracks rendered as disconnected dashes; centre-anchoring and placing each segment at the midpoint of its run makes the pivot and the anchor the same point. And these are SurfaceGui line segments rather than a crack decal because third-party Creator Store textures here are a coin flip on loading, and one that never resolves leaves the wall with no telegraph and no error.

Verified client-side, sampling every frame: `steps=7 partialWidths=0`, the visible-segment count jumping 0 → 4 → 8 → 12 → 16 → 20 → 24 — exactly one four-segment fracture at a time, with no segment ever observed at a partial width. Fired at t-2.44, 1.89, 1.47, 1.27, 0.89, 0.59 against a 2.5 s lead. `_barrierExpiresAt` confirmed present on the client. See [[systems/SkillPipeline]] § Stone Wall — cracks and the crumble.

## [2026-08-08] ingest | Stone Wall cracks baked into an atlas instead of generated

Fixes cracks rendering off the side of the wall. The generator walked each fracture from a random base point with random headings and segment lengths, and nothing stopped that walk leaving the face — a crack starting near an edge and turning outward drew lines hanging in the air beside the slab.

Clamping a random walk was the wrong repair: steering it back straightens cracks against the edge, which is exactly where they most need to look natural, and reject-and-retry puts unbounded work on a frame. Replaced with `CRACK_PATTERNS`, ten authored fracture patterns in normalised face coordinates (x 0→1 left to right, y 0→1 top to base). Each is a list of strokes so a pattern can carry a trunk plus branches that join it. Points scaled to the slab cannot leave it, need no per-wall generation, and can be read and tuned.

Variety without risk: each face shuffles the atlas, reveals six, and mirrors each pattern at random — `1 - x` stays in range whenever `x` does, so two walls side by side don't fracture identically and no mirrored point can escape the face.

Two layers enforce the invariant rather than trusting it. A startup pass warns on any atlas point outside `[0, 1]`, so a future authoring slip fails loudly at load instead of silently in a match. And the segments sit under a `ClipsDescendants` container: segments have *thickness*, so one lying along an edge would still put half its width past it, and clipping makes staying on the slab something the engine guarantees rather than something the author remembered.

Verified client-side: canvas 640×400 for the 16×10 slab, 2 crack canvases both clipping, 40 segments, **worst overhang 2.3 px = 0.06 studs** — under half a segment's thickness, and clipped. No validator warnings, so every authored point is in range. Screenshots show fractures well inside the face at both one-crack and multi-crack stages. See [[systems/SkillPipeline]] § Stone Wall — cracks and the crumble.

## [2026-08-08] ingest | Cracks moved onto the crumble's seam lattice

The crack telegraph and the collapse it telegraphs disagreed. Cracks were authored freehand in normalised face coordinates while the slab breaks into a 5×4 grid of boxes, so every fracture line promised a break the crumble then ignored, and the crumble opened straight seams the cracks had said nothing about. Fine on a still wall, wrong the moment it came apart.

`CRACK_PATTERNS` re-authored in **seam-lattice coordinates**: a node is `Vector2.new(column, row)` on the crumble's own grid, column 0→`COLUMNS` left to right, row 0→`ROWS` base to top, and consecutive nodes must be neighbours — so every run lies along a line the wall actually parts on. `COLUMNS`/`ROWS` are now shared by both halves, and that coupling is the point rather than an accident.

The lattice also subsumes the bug the freehand atlas was itself written to fix: a node is in bounds by construction, so there is nothing left to steer or reject. Only the jag can leave the face, and it is clamped before it is applied.

Jag, not curvature: each seam run is cut into three sub-segments whose interior joints are shoved perpendicular by up to 0.35 studs, so the pattern doesn't read as a drawn-on grid — but run *endpoints* stay on the node, which is what keeps runs meeting, branches landing on their trunk, and cracks arriving at the corners the chunks part at. Segments are drawn overlong by their own thickness (half each end) because two rotated rectangles meeting at an angle leave a wedge of daylight on the outside of the turn, and the jag puts a turn at every joint.

Validation upgraded from "point in `[0, 1]`" to "whole-number node inside the grid, and each step a Manhattan distance of exactly 1" — a diagonal step cuts across the middle of a chunk, which is precisely what the lattice rules out.

Verified by measurement against a drawn wall: **every segment endpoint within 13.85 px of a seam on a 14.0 px jag budget, zero strays**, where the freehand atlas put **41 of 78 endpoints off-seam, worst 48.9 px** — most of a chunk away from any line the wall breaks on. Screenshot against a seam-grid overlay confirms the cracks ride the grid. See [[systems/SkillPipeline]] § Stone Wall — cracks and the crumble.

## [2026-08-08] ingest | Crack reveals made non-overlapping

Follow-up to the seam-lattice move. Six cracks are revealed per face, and two laid along the same seam don't read as two cracks — the second to appear lands on the first and mostly thickens it, so a fracture that should have been its own event is spent for nothing.

Fixed at both ends. `chooseCracks` picks greedily against the runs already claimed, considering both orientations so mirroring becomes a way out of a clash rather than another source of them, and taking the *first* candidate that collides with nothing rather than the best of all of them — which keeps the pick random while the lattice has room and only compromises once it doesn't.

That alone wasn't enough: a plain shuffle retraced **29%** of the runs it drew, the greedy picker got it to **13%**, and neither ever produced a clean wall, because ten base-rooted paths over six base runs cannot be disjoint. So the atlas was re-authored to be **pairwise edge-disjoint**, checked at startup rather than trusted — a shared run is invisible in the source and only shows up as a fracture that appears and changes nothing.

The first disjoint set then exposed a second rule. Four of its patterns lived on the outer columns, and *because* they were disjoint they stacked end to end into unbroken lines up both sides, framing the slab like a picture. Those seams are the wall's own silhouette, so a crack drawn on one reads as an outline, not a fracture. **Nothing may travel along an outer edge** — reaching one is fine — and the validator now warns on it. Final set: four cracks climbing from the base, two low bed joints crossing them, four rooted higher on a joint or reaching in from an edge.

Verified over 2000 generated walls: **zero retraced runs, 100% clean, mirroring still applied to 51% of cracks**; validator reports no off-grid node, non-adjacent step, outer-edge run or shared run. Screenshots of three independent draws show cracks spread across the whole face with no outline effect. See [[systems/SkillPipeline]] § Stone Wall — cracks and the crumble.

## [2026-08-08] ingest | Stone Wall cracks got a sound

Each fracture now snaps audibly as it appears, gated by `CRACK_SOUND_ENABLED` in `client/Vfx/BarrierCrumbleController`. Off is a supported state rather than a broken one — the cracks are the telegraph and the audio only makes it harder to miss for a player facing away. The switch is there because six snaps suits one wall and might get busy with several standing at once, which is a judgement for a real match.

Counted per stagger slot, not per crack. Both faces draw their own fracture for each slot, so keying on the crack would hit twice for every one a player perceives; the controller fires at the earlier of the pair, so a crack is always on screen when it sounds. `cracking[barrier]` grew from a segment list to a `CrackState` carrying `moments` (sorted, one per slot) and `played`.

The catch-up case has its own rule: a client joining a wall partway through its lead window draws every crack due by then on its first frame, so however many moments land in one frame only one sound plays. Otherwise that player's arrival is announced by a burst of noise describing a wall that, to them, merely already looks cracked.

`SFX.stoneCrack` + a sound-only `wall_crack` EffectSpec, played via `spawnEffectAtPoint` so the audio config sits in VfxConfig with the rest instead of a hand-built Sound in the controller. spawnEffect already plays audio outside its emitters guard, so an emitter-less spec works as-is. Shares an asset with `impactFreeze`/`shieldBreak` — the only sample in the inventory that snaps rather than thuds — at 0.55–0.70 against their 0.90–1.05 and 0.80–0.92, since ice cracks bright and stone cracks dull. Default attenuation, deliberately: a crack matters to whoever is behind the wall.

Verified on the client with the lead window driven open by a local rewrite of the expiry attribute: **6 snaps for 11 crack reveals** (the pairing working), **6/6 coinciding with a reveal, worst gap 0.016 s**, pitch spread 0.56–0.68 across one wall, volume 0.45, anchor `SkillEffectAnchor`, default EmitterSize 10. Asset preloads (`IsLoaded=true`, 0.39 s → 0.70 s at 0.55 speed against a 0.75 s anchor, so no clipped tail) and the console is free of sound-load errors. See [[systems/SkillPipeline]] § Stone Wall — cracks and the crumble.

## [2026-08-09] ingest | Fireball's impact rebuilt on Inferno's fire

`impact_damage_t2` now draws the same three flipbook layers as `impact_damage_t3` — `FireFlame` / `FireEmber` / `FireSmoke` over the shared `VfxConfig.FIRE` gradients — replacing the single 38-particle `ImpactBurst` splash. Same reason the T3 rebuild gave on 2026-08-08: the round-blob texture reads as a firework at any particle count, and a fire school whose tiers use unrelated effects doesn't read as a ladder.

**Scale and duration are what separate the tiers, not the templates.** T3 is a detonation that hands off to a 3 s burn (`StatusVisuals/InfernoVfx`); T2 has no burn lane at all, so its flames must be gone almost as soon as they arrive or the hit reads as a status that never applied. Every lifetime is roughly half its T3 counterpart, the smoke tail is cut hardest, and `totalDurationSec` is 1.2 against 2.5. Fireball also lands far more often than Inferno — a 2.5 s plume per cast would leave the arena permanently hazed. The flame peaks at 5 studs (under the 7-stud impact radius) and spreads at 110° rather than T3's 70° column, because a projectile bursting on contact should spread more than it rises. Added the `light` flash at brightness 3.5 / 0.28 s against T3's 6 / 0.45 s.

**The audio ladder is deliberately not shared.** T2 keeps the pitched-down `impactDamage` hit rather than adopting T3's `impactHeavy` boom — the visual vocabulary is shared, the *weight* is not, and a Fireball that booms like the 50%-max-HP nuke would flatten the ladder the tiers climb. `ScreenImpact` likewise stays T3-only; it hangs off the `_burning` attribute in `InfernoVfxController`, not off the impact spec, so it needed no guard.

Verified client-side in a playtest by calling `spawnEffect` on the local HRP from the Client VM and capturing the render — flame, embers and smoke all present, visibly a smaller and briefer version of the T3 eruption captured back-to-back for comparison. Both captures show the same tan square sprites from the ember/smoke templates; that artifact predates this change and is Inferno's too. See [[systems/VisualEffects]] § "The red school's impacts share one vocabulary".

## [2026-08-09] ingest | Fireball's blast scaled up, ground disc removed

Follow-up to the entry above, and the two halves are causally linked. `impactRing` is a new `projectile` delivery param in `SkillDelivery` — default true (every existing splash spell is untouched), false skips `SkillVisuals.spawnShockwave` while keeping the splash damage and the impact burst. The burst then anchors to a throwaway `spawnEffectAtPoint` anchor rather than to the ring, which is also the path that survives a client not having replicated a Part created this frame. Fireball is the only spell setting it: once its impact drew Inferno's fire, the neon disc under it read as a flat decal laid on the floor rather than part of the same event. `impactColor` went with it — that param only ever tinted the ring.

**The disc was the only thing drawing the blast's exact reach**, so removing it is a real loss of radius legibility, and `impact_damage_t2` grew to cover for it. Growth is as much in spread as in size: `spreadAngle` 130°/160°/140° across flame/ember/smoke against T3's 70° column, flame `emitCount` 24 → 36 and peak size 5.0 → 7.0, embers 30 → 44, smoke 10 → 14, light 3.5 → 5.0. Flame lifetime went 0.28–0.50 → 0.32–0.58 because particles that large hitting full transparency in a quarter second read as switched off rather than burnt out; `totalDurationSec` 1.2 → 1.25.

**Tier headroom is the thing to watch.** T2's flame now peaks at 7.0 against T3's 7.5, so footprint barely separates them and the ladder rests on duration, ember/smoke volume and the light instead. Noted on both pages: if Fireball starts reading as interchangeable with Inferno, scale T3 up rather than pulling T2 back down.

Verified on a client, both branches. A real `SkillDelivery.deliver` of the registry's Fireball produced **0 `SkillShockwave` and 1 `SkillEffectAnchor`**; an otherwise-identical probe spec with `impactRing` left unset still produced **1 ring**, so the default path is intact. Captured a live detonation on open floor from an elevated three-quarter angle where a ground disc would be unmistakable — none present, and the fire bloom covers the impact area. See [[systems/VisualEffects]] and [[systems/SkillPipeline]] § `impactRing`.

## [2026-08-10] ingest | Phase 5.7 stages 1–2 — the Spelling Staff is gone, blocks are tapped

Block input moved off `Tool.Activated` onto an always-mounted `UserInputService` handler (`src/client/BlockTapController.client.luau`), then the staff, `LetterBlaster`, `BlockShoot.muzzlePosition`/`resolveHandle`, `broadcastShot` and the whole `src/StarterPack` tree were deleted (commits `be2b1a2`, `14881d9`; net −337 lines). The server contract is untouched — `ConsumeBlock` still takes one argument and `BlockShootValidation` still runs the same three checks.

Two findings worth carrying forward. **`gameProcessedEvent` is load-bearing**: `Tool.Activated` suppressed clicks over GUI for free, a raw `InputBegan` handler does not, and without the guard every spell-button press also pops the block behind it — proven by A/B with the GUI as the only variable. **The `WordBuffer` append is optimistic and unacknowledged**, so in PvP the loser of a same-frame race for a block keeps a phantom letter all round; latent in the staff build too, unreachable in solo play, scheduled as stage 4.

Also emptied `GameConfig.DEV_AUTO_EQUIP_TOOL` (core input no longer depends on a dev helper firing), removed the now-pathless `StarterPack` mapping from `default.project.json`, resolved the duplicated fizzle `SoundId` (`VfxConfig.SFX.fizzle` is now the only copy), and simplified `VfxController.resolveStaffTip` → `resolveCastAnchor` — its Tool walk could never succeed again, so casts now visibly originate at the caster's chest rather than a staff tip.

Pages updated: systems/LetterBlaster (→ REMOVED record), systems/BlockShoot, systems/AudioSFX, systems/Tutorial ("shoot"→"pop", dropped the equip step), systems/VisualEffects §2.1, systems/HUD, systems/SpellCastService, systems/Tests, design/tap-to-pop, design/build-plan, index. Dated audit entries in design/client-server-boundary and design/system-audit-2026-06 left as-is — they are history, not description.

## [2026-08-10] ingest | Phase 5.7 stage 3 — block pop + collect stream

A consume is visible again, and says more than the beam it replaces. `block_pop_{red,green,blue,wild}` bursts (resolved by `VfxConfig.resolveBlockPopId`) plus a new `VfxBroadcast.collect` kind that streams the block's mana onto the player who took it — the PvP attribution cue. Drawn by the popper on the frame they click and by every other client from the broadcast, out of one shared `collectStream` module so the two can't drift.

**The destination is a `collectorUserId`, not a Vector3.** A frozen endpoint funnels into the ground the collector already left; an Instance hits the nil-arrival race and breaks on respawn. Re-resolved per client per frame instead, and failing to resolve mid-flight just ends the stream. Verified against a **moving** collector — endpoint-to-HumanoidRootPart gap 0.00 studs across 25 frames while the character travelled 19.2 studs. A stationary test passes with the bug present, so this one has to be driven moving.

Flight (0.4 s) is deliberately **longer** than the 0.25 s tap cooldown. The first instinct was to fit it inside the cooldown to avoid overlap, but overlap is the correct read: several streams converging says "that player is banking letters fast", which is the tell the cue exists to give. `VfxConfig.PERF.maxBlockPops` — which already existed as a reserved knob — bounds cost instead of duration. No anchors or attachments leaked after the flight.

**Still owed: the two-client check.** Only the predicted local draw has been exercised; the broadcast receive path (`WorldVfxController`'s `collect` handler) has not been seen by a second client. Same outstanding item as Phase 5.6 Stage 4.

## [2026-08-10] ingest | Phase 5.7 stage 4 — contested blocks, phantom letters closed

The `WordBuffer` append has always been optimistic and unacknowledged. The server half of a same-frame race for one block already worked for free (the first `Destroy` unparents it, so the second request fails validation); the client half did not, so the loser kept a **phantom letter** all round — one they never got, holding a slot and eventually paying out energy on Memorize. Latent since the staff build, unreachable in solo play, routine in PvP.

**The reply carries a client-minted request id, not the block.** Echoing the block was the first implementation and it is wrong in exactly the case that matters: losing a race means the winner has already destroyed that block, and an Instance reference to a destroyed object hits the same nil-arrival trap `playOn` documents — so the rollback would have no-opped in the one situation it exists for. Caught before shipping by asking what the block reference actually is at rejection time. A number always survives the trip; the id is type-checked, echoed, never used for a lookup.

Rollback is `WordBuffer:removeLastMatching`, not "pop the last slot" — the round trip is long enough to have tapped two more blocks, and a remembered index goes stale as soon as `reorder`/`remove` runs. No match is a deliberate no-op (the player may have destroyed the tile themselves). Six unit cases added; verified live end-to-end at `[N,Y,W,T]` → reject the older W → `[N,Y,T]`, so a letter appended *after* the rejected one survives.

**Cosmetics split rather than both gated behind confirmation.** The burst stays predicted — it remains true even when you lose the race, because the block popped either way — while the stream is drawn only from the server's confirmed branch, since attribution is a hit-marker-class claim `CastAction`'s prediction contract forbids this layer from asserting. A stream you did not earn is never drawn, with no cancellation logic.

Two harness lessons worth keeping: Rojo syncs into the **Edit** DataModel, so edits made during a running playtest never reach it (stop and restart, or you test stale code); and deferred `BindableEvent` delivery does not flush on a bare `task.wait()` inside an injected `execute_luau` chunk — `RunService.Heartbeat:Wait()` does. The latter also fixed latent flakiness in the pre-existing WordBuffer change-count assertion.

## [2026-08-10] ingest | Phase 5.7 — collect stream motes (third layer)

The sparkle cloud: 8 block-coloured points pulled off a shell around the block and drawn into the collector, on top of the ribbon and the arrival taper. Completes the layered cue the stage-3 design set up.

Each mote rides a quadratic Bézier whose endpoint is **re-read every frame** from the collector's HumanoidRootPart — same reason the payload carries a userId rather than a position. A curve baked at spawn arcs gracefully into empty ground while the player runs out from under it. Per-mote flight is jittered **shorter only**: the stream is torn down when the ribbon lands, so a mote granted a longer flight would be destroyed mid-air short of its target. That also orders the events correctly — sparks land, then the connection winks out.

One `Heartbeat` connection drives the ribbon and all its motes. Per-mote tweens or connections would mean ~100 independent schedules for a 0.4 s effect at a dozen concurrent streams; this is the single-driver shape `LetterBlockAnimator` already uses for the whole block field.

Degradation is ordered by what it costs: motes thin proportionally 8 → 3 as concurrent streams approach `PERF.maxBlockPops` and drop entirely past `MOTE_VISIBLE_DISTANCE`, while the ribbon is never dropped short of the whole-stream cap. Losing motes costs flavour; losing the ribbon costs attribution. Thinning is proportional rather than a threshold, because streams that randomly do or don't have motes reads as a bug where a uniformly sparser fight does not. The local player's own stream is exempt from both — one stream, and it is the feedback for their own input.

Measured against a moving collector: 8 motes peak, alive across 24 frames, 34 distinct sizes in flight (stagger and shrink both live), 0.27-stud closest approach to the HumanoidRootPart, 0 instances left behind.

## [2026-08-10] ingest | fire projectiles — bodies, trails, and a dead `rate`

Asked to make the fire projectiles "look better than a square block". They were a square block: an axis-aligned neon cube with **no trail at all**. `projectile_red_t1/t2/t4` were authored with `durationSec` and no `rate`, and every template in `VfxTemplates` ships `Rate = 0` — so `spawnEffect` set `Enabled = true` on an emitter that could never emit. Silent, unlogged, months old. See systems/VisualEffects § "A rate-based entry must state its `rate`"; that trap will catch the next rate-based entry too.

Rebuilt on the `FireFlame`/`FireEmber`/`FireSmoke` flipbook layers the impacts moved to in August, so the red school reads as one thing from muzzle to blast. New **`VfxConfig.PROJECTILE_BODIES`** table, keyed by the same `cosmeticEffectId`, owns the *solid* — shape, stretch, core colour, Trail, light — while `EFFECTS` under that key owns the particles. Kept out of `EffectSpec` because `spawnEffect` has no business knowing a shot has a shape. Per the design call: Fireball is an orb, Firebolt / Volley / both bosses are comet heads. The Brain and Wizard volleys had no in-flight cosmetic at all before this.

Four things only a screenshot could find. **`Shape = Ball` with non-uniform `Size` renders a round sphere**, not an ellipsoid — the first pass set `Size.Z` to 3.4× and every bolt was still a circle; elongation needs a `SpecialMesh`/`Sphere`, and it was only visible after stripping the flame off to see the bare silhouette. **Neon clips near-white to white**, so cores set to `FIRE.flame`'s white-hot birth colour rendered as flat white discs — the core has to carry the orange and the particles the white. **A Trail's gradient runs along its length**, not over a lifetime, so reusing `FIRE.flame` dragged a pale band behind every shot. And **density must be judged at the real speed** — a probe at 2.5 studs/s piles every particle on one spot and reports a correct entry as broken.

Also fixed: a dying shot used to erase its own trail back to the muzzle, because destroying the Part destroys the Attachment and an Attachment's death kills every particle already emitted from it. `CosmeticProjectile.retire()` now hides the core, disables the sources and lets `Debris` collect the shell ~1.6 s later. Rendered size stays strictly cosmetic — shield-contact padding still reads the gameplay `params.size`, never the drawn body.

Verified end-to-end on a real Brain volley (server-fired → `ProjectileVfxEvent` → client-drawn), 16 concurrent cosmetics each with the bolt mesh, trail and live emitters. Client-rendered proof, not server logs.

Pages updated: systems/VisualEffects (two new sections + banner), systems/SkillPipeline (delivery-visuals row).

## [2026-08-10] ingest | Tap reach raised, then the real cause found: a screen/viewport aim mismatch

`MAX_RAYCAST_DISTANCE` went 200 → 1400 after measuring the arena at 240 × 259 studs (diagonal ~353) with the farthest block 320 studs out — genuinely past the old raycast *and* the old 300-stud server bound. The complaint survived the raise, which was the real signal: `BlockTapController` had inherited LetterBlaster's `ViewportPointToRay` while switching the point to `input.Position`, mismatching the two mouse coordinate spaces by one GUI inset (58 px = 7.7° = 0.135 studs of miss per stud of range). Effective reach was ~30 studs regardless of the constant. Fixed to `ScreenPointToRay`; verified against `Mouse.Hit` (0.00 studs error), by sweep (buggy pairing hit 0/40 on-screen blocks, fixed 18/40, rest occluded) and by a live click at 303 studs. See systems/BlockShoot § Aiming.

## [2026-08-10] ingest | Tap reach back to 200

Reverted the same-day 200 → 1400 raise now that the aim bug it was chasing is fixed. 200 is LetterBlaster's original value and is deliberately under the ~353-stud arena diagonal: the far edge of the field stays out of reach by design, and the derived 300-stud server bound stays a real anti-grief limit rather than a formality. See systems/BlockShoot § Reach.

## [2026-08-10] ingest | Energy-ceiling ledger redesigned into validated memorize

Phase 5.4's last undelivered item was re-examined before any of it was built, and the decided design was replaced. The ledger would have credited each consumed block `letterValue x 3` and rejected casts exceeding the running bound. Worked against the real constants — `LetterBlasterConfig.COOLDOWN` 0.25 s, Scrabble-weighted mean letter value ~1.9, uniform colour split — the ceiling accrues ~7.6 per colour per second and pins at `CAP_PER_COLOR` (60) within about eight seconds, which is at or above every entry in `TIER_COSTS`. For any actively-shooting client the check passes unconditionally.

**The failure is informational, not numerical, and that is the whole argument.** The x3 is `LENGTH_MULTIPLIER_EPIC`, the smallest multiplier that cannot reject a player who genuinely spells a 9-letter word — so the bound is already as tight as its inputs permit and cannot be tuned into usefulness. It catches a cast-spam bot, which `RateLimiter` largely handles, and misses the cheat anyone would write: shoot blocks normally, produce traffic indistinguishable from real play, never memorize, cast freely. In a word game that makes the premise optional.

Reframed from "how do we bound energy" to **"does the server ever learn a word was spelled?"** — the question every option is a different answer to. Chosen: **validated memorize.** The server keeps a per-player multiset of letters consumed since that player's last memorize (26 letters x 3 colours = 78 integers), a new remote carries the word, and the server validates against [[systems/Dictionary]] and credits exact `EnergyEconomy.splitByColor`; `spec.cost` is debited per accepted cast. Memorize clears the *entire* held set rather than the word's letters, mirroring `MemorizeAction.tryMemorize` draining the whole buffer — which also handles double-tap-discard with no second remote, since discarded letters clear on the same event the client cleared them, and any resulting superset is the safe direction.

Two problems from the ledger design vanish rather than getting solved: `MAX_LETTER_VALUE` is not needed because credit is exact (fortunate — no such constant exists in `src/`), and [[systems/Wildcard]] needs no special case, since the claimed word carries resolved letters and held stars cover any letter during the coverage check.

Two couplings to Phase 5.7 found while designing, both load-bearing. Stage 4's consume-rejection rollback (`reject()` echoing the client-minted request id, `BlockTapController.onRejected` calling `WordBuffer:removeLastMatching`) closes the one false-reject path this design had, keeping client buffer and server held-set in sync by construction — the residue is only a reply lost past `PENDING_TTL_SEC`. And PvP moves the whole item's stakes: the standing justification for deferring it was "a self-cheat in a PvE game, not a way to grief other players", which stops being true. That caveat in [[design/build-plan]] Phase 5.4 has been corrected rather than left standing.

Deliberately **not** closed: banking, where a client bypassing the mind-full gate shoots far past the 12-slot cap between memorizes. A hard cap on held-set size would reject a legitimate player who discards aggressively, so the high-water mark gets logged and tightened against evidence instead. Ships in **shadow mode** — compute the verdict, log it, reject nothing — flipping to enforce once the friends playtest shows zero false positives.

Not yet built. Pages touched: [[systems/SpellCastService]], [[design/build-plan]].

## [2026-08-10] ingest | Phase 5.7 stage 5 — hover affordance (glow scope reduced)

Built the hover outline; dropped the planned in-range glow on every reachable block. Roblox renders a bounded number of Highlight instances (~31) against 40 blocks in the arena, and "which of these twenty can I reach" is not a question players ask — one highlight under the cursor answers it and shows where reach ends. Three states: block tint + white outline (poppable), grey (out of reach or mind full), off. First build tinted the outline with the block's own colour and was invisible; every property assertion passed and only a screenshot caught it, which is the CLAUDE.md presentation-verification rule earning its keep again. Reach needed no retune and the hardening fixture derives from the constant. See systems/BlockShoot § Hover affordance, systems/LetterBlock § Color tints, design/tap-to-pop stage 5.

## [2026-08-10] ingest | Phase 5.7 stage 6 + collect-stream receive path verified

Wiki sweep: client-server-boundary's LetterBlaster row cited two deleted files and is now BlockTapController at its real line; index and tap-to-pop frontmatter still promised the in-range glow that stage 5 replaced with a hover outline. Plans, dated audits and changelog entries left as written. Also closed the two-client verification outstanding since Phase 5.6 — testable with one client because BlockTapController never draws the stream locally, so anything on a client came over the wire. A server-side VfxBroadcast.collect produced 1 anchor + 8 motes on the client; an absent collectorUserId produced nothing, no error and no orphaned anchor (the player-leaves-mid-flight case). Still unshown: a stream funnelling at another player's character, though resolveCollector has no local-player branch so it is the same code with a different Player. See systems/BlockShoot § Stream layers.

## [2026-08-10] ingest | Validated memorize built and shipped dark

Implements the design decided earlier today. New `server/Economy/`: `EnergyLedger` holds, per player, the letters consumed since their last memorize plus a per-colour earned-minus-spent ceiling; `EconomyConstants` carries the `ENFORCE` flag; `EconomyService` owns the new `ReportMemorize` remote and the ledger lifecycle. Credit hooks the accepting branch of `BlockShootService` (which already read the block before destroying it — only the letter was being discarded); the price check and debit sit in `SpellCastService`. Client side, `client/EconomyReport` is the single seam every memorize goes through, so the wire format exists once and a new call site cannot silently skip the report.

`MemorizeAction.scoreTiles` extracted so client and server price a word with the same code. Two implementations of "what is this word worth" would drift, and the server's copy is only useful while it agrees with the client's on every honest play.

**The client never names its own word.** The payload is the raw buffer tiles with wildcards still `*`; the server checks those against the blocks it watched that player take and then resolves the word itself. A client that pre-resolves its star is naming a tile it does not hold, and fails coverage — asserted in the suite.

Three decisions worth keeping. Memorize clears the **entire** held set rather than the word's letters, mirroring the buffer drain and handling double-tap-discard with no second remote; any resulting superset leaves the server holding more than the client, which is the direction that cannot reject honest play. A fizzle is distinguished from a coverage failure by an explicit `fizzle` flag, because shadow mode's whole output is its failure log and a player mistyping FROG as FRGO must not read as an exploit. And the debit runs *before* the remaining target checks, since the client's predicted run has already drained its reservoir by the time the relay arrives — a server that only charged for casts which fully landed would drift permanently richer than the client it is pricing.

Banking is deliberately left open: `HELD_BANKING_LOG_THRESHOLD` is a reporting threshold and explicitly not a cap, because refusing consumes past a limit would reject a player who discards aggressively, and rejecting real play is the one thing this design may not do.

Verified: suite `Economy/ledger_prices_a_cast` 1/1 across 12 scenarios, including *shooting alone earns nothing* — the assertion the rejected energy-ceiling ledger would have failed, pinned so a regression toward it fails loudly. Live wire check from the Client VM produced `would reject memorize ... claimed 1 x A/red, holds 0` with nothing refused, confirming shadow mode end to end. One test bug found and fixed en route: `D*G` was pinned to `DOG`, but every candidate scores identically so `resolve` returns whichever it finds first (`DIG`) — the assertion is now a shape, not a tie-break the suite has no business owning.

**Owed:** the happy path end to end. Tapping real blocks and watching the credit land needs actual tapping rather than injected Luau, so the credit path is proven by the suite and not yet in a live session. `ENFORCE` stays false until it is.

Noted at the dev seam and on the system page: `DevDebug`'s `[` conjures letters without consuming a block, so every dev memorize logs a coverage failure. Those are not findings.

Pages touched: [[systems/SpellCastService]].

## [2026-08-10] ingest | Phase 5.7 recorded in build-plan; EffectSpec.anchor union corrected

Two items deferred while a parallel session held the files. **build-plan**: Phase 5.7 marked complete with a stage→commit table, stages 5 and 6 filled in with what actually shipped (hover outline not in-range glow; reach raised then reverted once the coordinate-space aim bug surfaced), stage 3's "two-client check still owed" resolved to what one client could establish, and a changelog entry for the divergences. **VfxConfig**: `EffectSpec.anchor` still declared `"casterStaffTip"` while two entries assigned `"caster"` and `"blockPosition"` — neither a union member, so this was a live strict-mode type error. Union is now `"caster"`, the block-pop entry uses the existing `"worldPosition"`, and the field carries a note that nothing reads it. That is why it rotted quietly: descriptive metadata with no consumer cannot fail loudly. Stale mirrors in systems/VisualEffects (type block, two example specs, and the anchor-resolution row describing a walk to a deleted Tool) updated to match.

## [2026-08-12] ingest | Phase 5.8 — hold-to-charge tier selection

The game shipped four spell tiers per colour and no way to pick one: a tap fired whatever was affordable, so "save big, fire small" — the decision the spell economy is built around — was unreachable in-game. The design doc's answer since the first pass was a drag-from-reservoir tier menu, never built. **Superseded, not deferred**: a menu opening over the arena hides the arena, in a game whose other two verbs are single taps. Press the panel, hold to climb, release to fire. The old menu's rationale is kept in [[design/gameplay-loop]] as superseded history, because it is still the reason the cast lives on the reservoir at all — and because what it was better at is worth naming: it was a *legend*, and notches plus a numeral teach a first-time player less than a list of named tiers did.

**Mana flows; the thresholds are the costs.** `chargeTimeFor(tier) = (cost − T1 cost) / MANA_FLOW_PER_SEC`, so there is no second tuning table and T4 reads as a commitment for free — it costs 8× a Firebolt and takes 8× as long to pour in. One constant is the whole feel lever.

**Reserve, spend on release** is what kept the blast radius small. The reserve band and counting-down numeral are a promise, not a debit; `castSpecific` drains one tier cost on release. So cancelling is free, there is no refund path to get wrong, and [[systems/EnergyReservoirs]] needed **zero** changes — its `:drain` is all-or-nothing by contract and a reservation model would have meant inventing a second, partial one.

The orb needed a new lane. `spawnEffect` returns nothing and bakes its duration at author time; its only sustained branch is a `task.delay` flipping `Enabled = false`. There is no handle to grow or stop, and a charge has no author-time duration. So: `StatusVisuals/ChargeOrbVfx` copying `ShieldVfx`'s shape, driven by `_chargeColor`/`_chargeTier` on the character — which is what makes "every player sees your windup" nearly free, since the rig is server-owned and the attributes replicate without a fan-out remote. **The attribute write order on `end` is load-bearing**: tier first, colour second, because the controller reads the tier on the frame the colour clears to tell a cast from a cancel. Clearing colour first would make every cast look like a cancel.

Two smaller calls worth keeping. The ceiling pulse is an overlay Frame, not a `UIScale` tween, because `playAffordBounce` already owns the panel's `UIScale` — [[concepts/SingleOwnership]] applies to GUI properties too. And the fill bar's `UIGradient` had to stop carrying hue: it was a `ColorSequence` of the panel's own colour multiplied over an identical `BackgroundColor3`, and `TweenService` cannot tween a `ColorSequence`, which made the below-T1 desaturation inexpressible as a tween. Gradient is now a neutral ramp.

Verified live: 15/15 `CastAction/__tests` (six new, expressing holds as `chargeTimeFor(t)` so they survive the retune that is coming); a tap on 40 mana drained 5 and a 2.5 s hold on 15 mana drained 10, which is the ceiling clamp and the tap-is-T1 change in one pair; a drag-off cancel left the reservoir at 40 with no orb, no motes and no attributes. The orb was checked **from the Client datamodel against a rig the local player does not own** — server-written attributes on the Boss produced a client-rendered orb, welded, tinted, with its emitter and light — which is the second-client path without a second client, per the § Player-Facing Output rule. 20 charge cycles left zero orphans.

**Owed:** the feel check. Whether 1.75 s reads as commitment or as lag is not a thing tests can answer, and `MANA_FLOW_PER_SEC` is expected to move.

Pages touched: new [[systems/ChargeCast]]; [[design/gameplay-loop]], [[design/build-plan]], [[systems/CastAction]], [[systems/HUD]], [[systems/VisualEffects]], [[systems/SpellCastService]], [[index]]. Corrected while there: HUD's file list still carried `ReservoirBarsBuilder`/`Config` as `[unused]` entries — both were deleted in the Phase 4.8 R-2 cleanup — and omitted `ReticleBuilder`/`ReticleConfig`, which exist.

## [2026-08-12] ingest | Spell cast panels became circles

Follow-up to the 5.8 hold-to-charge landing. The three cast panels are now discs: mana fills outward from the centre, the tier thresholds are concentric rings (a `UIStroke` on a circular Frame — the cheapest true annulus the engine offers), the reserve is an annulus eaten off the fill's outer edge, and the ceiling pulse is a rim halo instead of a wash. Rationale is affordance: a bar reads as a meter you watch, and press-and-hold needs a panel that reads as something you push — which also lines the column up with the DASH button below it, already a circle.

The spell name came off the panel (no room inside a disc) and the numeral moved from the top-right corner to the centre, since a circle's bounding-box corners are empty space outside the disc. `FILL_RADIUS_EXPONENT = 1` keeps the bar's cost curve exactly — rings at 8.3/16.7/33.3/66.7% of the diameter, verified live to four decimals — at the cost of the disc looking emptier than its numeral, and of T1/T2 rings small enough to sit under the numeral. That is the trade the exponent exists to reverse. Rings are dark rather than white: they spend their life on top of a lit fill, where white on bright is nothing.

Two ideas filed rather than built: an **arc gauge** (mana around a 270° ring — linear encoding *and* readable tick spacing, but needs the two-half rotation mask), and a **spell name label above the charge orb**, with its known weakness recorded — an orb only exists during a charge, so it can never teach the roster before you press. See `systems/ChargeCast` § What the circle encodes, `systems/HUD`, `ideas`.

## [2026-08-12] ingest | Spell name label on the charge orb

The name that came off the cast panel when it became a circle is back, on the orb instead of the HUD. A `BillboardGui` over the charge orb reads the spell the current tier would fire — `Firebolt` → `Fireball` → `Volley` — popping in from zero scale on each crossing (`Back, Out`) and dissipating upward on release. Remote observers get it for free: `ChargeOrbVfx.setTier` resolves the name from the entry's own colour, and `ChargeOrbController` already drives `setTier` off the replicated attributes, so the PvP read needed no new wiring.

Four things pinned in the code and on the page. `AlwaysOnTop` is off — a label that reads through a wall turns a tell into a wallhack. `MaxDistance` is 120, inside the orb's own visibility, so distant opponents read *that* you are charging, not exactly what. The GUI hangs off the **head** rather than the orb, because the 0.3 s dissipate outlives the orb's 0.16 s release flash. And `spellNameFor` bounds the tier with `tierCount` rather than `getSpell` alone — `getSpell` validates against the roster maximum of 4 while green tops out at 3, so `getSpell("green", 4)` passes validation and returns nil; the same off-by-one the tier rings dodge.

Idea moved from Open to Shipped in `ideas`, with the weakness it was filed with left standing: the label only exists during a charge, so it still cannot teach a new player the roster *before* they press. That half of the legend gap is still open and still belongs to `systems/Tutorial` — recorded in `design/gameplay-loop` rather than quietly closed. See `systems/ChargeCast` § The name label, `systems/VisualEffects`.

## [2026-08-12] ingest | Charge timing retuned, MANA_FLOW_PER_SEC 20 -> 5

First pass at the feel check owed since 5.8 shipped. Holds are 4x longer: T2 goes 0.25s -> 1s, T3 0.75s -> 3s, T4 1.75s -> 7s. T1 stays a tap at any rate, because `chargeTimeFor` measures cost *above* T1.

The lever behaved as designed — one constant moved and nothing else had to. The HUD rings, the orb growth curve, the reserve band and the six `CastAction/__tests` charge scenarios all derive from `chargeTimeFor` rather than from literal seconds, so the suite still passes unchanged and no second tuning table drifted out of step.

What did need updating was prose: the constant's own comment and four wiki pages quoted the old table. Fixed in `systems/ChargeCast` (charge model), `design/gameplay-loop`, `systems/SpellCastService` (the skip-the-windup note, which is now worth *more* to a lying client — the longer the windup, the bigger the tell being skipped) and `index`. Worth flagging as a design consequence rather than a pure tuning one: a 7s T4 is long enough that an opponent has real time to react to the orb, which pushes the charge from a tell toward a commitment they can punish.

## [2026-08-12] ingest | The square in the charge orb was the Roblox shirt template

User reported square artifacts at the centre of the charge orb. `rbxassetid://1913819781` — textured onto five of the seven `VfxTemplates` emitters — is the **Roblox shirt template**, the clothing UV guide with "Torso / Left Arm / Right Arm" printed on it. Every impact, heal and burst effect in the game has been drawing tiny opaque rectangles of a clothing template, tinted by the emitter colour.

It survived because all five are used by *bursts*: speed 10-18, ~22 particles, dead in 0.3s. Hard-edged rectangles thrown outward that fast read as sparks. The ChargeCast halo is the project's first **sustained** emitter (speed 1-4, ~108/sec, ~48 alive), which is the first case that holds them still and stacked long enough to see. Pinned by elimination rather than by guessing: disabling only the halo left a clean sphere; switching the emission shape from Box/Volume to Sphere/Surface left the square untouched, ruling out the obvious suspect; rendering the texture at 256px on a dark frame settled it.

Fixed all five to `rbxasset://textures/particles/sparkles_main.dds`, the engine default (read off a fresh `ParticleEmitter` rather than trusting a remembered path), under a ChangeHistoryService waypoint. **Lives in the .rbxl only** — `VfxTemplates` is not Rojo-tracked, so this is not in any commit and a fresh clone will not have it.

The sharper correction is to this page's own advice: `1913819781` was the *recommended known-good control* for texture probes, described as "the project's blob texture". It always loads, so it passed as a control while being the wrong image entirely — and the earlier note that "one Creator Store fire flipbook rendered a shirt template" was almost certainly this asset being seen and blamed on the listing under test. `IsLoaded` answers whether bytes arrived, not whether it is the picture you wanted. Control id updated to the engine sparkle in `systems/VisualEffects` and in the corresponding memory.

## [2026-08-12] ingest | Spell panels glow while they can cast

The panels said "this one is dead" by draining to grey, and nothing said "this one is loaded, press it". The negative cue is the weaker half of the pair: grey only reads as grey when there is a lit panel beside it to compare against, which is exactly the case that fails when all three are drained or all three are full. A castable panel now breathes a coloured halo at its rim.

Two strokes rather than one. A single `UIStroke` is a hard line and reads as a *border* — a thing the panel has — where a crisp 4px edge over a wide faint inner bloom reads as light coming off it. Only the crisp stroke bleeds outward and only by its own thickness, so two lit neighbours keep 2px of air in the 10px `BUTTON_GAP`; the bloom is inset and faces inward, which is what keeps the halo from eating the gap.

Two halos now want the rim, and they are mutually exclusive **by construction** rather than by z-order: the ready glow is suppressed for whichever colour is being pressed, so the ceiling pulse owns the rim during a charge. That is also the honest reading — "you could press this" stops being information the instant you do. One idempotent predicate (`refreshReadyGlow`) owns the decision and every state change calls it rather than reasoning about which transition it is, which is the same reason the desaturation hangs off the existing `wasAffordable` edge instead of a second detector. The periods are pulled apart too: 0.42s for the ceiling ("act now") against 1.2s for the glow (idle heartbeat).

Verified by client screenshot at each state rather than by reading properties — a halo is exactly the kind of thing that can exist in the tree and render as nothing. All three lit at 10 mana; holding green dropped only green's halo and replaced it with the white ceiling ring; releasing into a T2 Stone Wall drained green to 0 and left it grey and dark while red and blue kept glowing. No console errors. See `systems/ChargeCast` § The panel (3) and § Ready glow.

## [2026-08-12] ingest | Ready motes orbit the cast panels

Follow-up to the ready glow, same session. A halo is a static shape and the eye stops seeing it; motion is what survives peripheral vision, and the cast panels live in the corner of the screen where that is the only vision they get. Six sparks now orbit just inside the rim of any panel that can cast, on the same lifecycle as the glow.

They are **not** a `ParticleEmitter` — that is a 3D instance and does not exist in a `ScreenGui`, so "add particles to the HUD" is not the same job as adding them to the world. They are plain circular Frames parented to a transparent full-size ring whose `Rotation` is tweened, which makes the whole orbit one tween and no per-frame code. That is a dividend of the circles: on a disc, "orbit" and "rotate the parent" are the same operation, where the old rectangular panels would have needed a Heartbeat and a path.

Two anti-lockstep details, both there because three panels usually light on the *same* Memorize and would otherwise animate as one rigid mechanism: per-mote size and twinkle-period jitter, and alternating spin direction per panel. The jitter is rolled once at build rather than per activation, so a panel's character is stable instead of rerolling every time its reservoir crosses T1.

Verified by client screenshot, including two captures 1.5s apart to confirm the motes actually move and twinkle out of phase rather than sitting as a static ring of dots. Suppression and teardown ride the existing `refreshReadyGlow` predicate unchanged — holding green dropped its motes along with its halo, and releasing into a T2 Stone Wall that drained it to 0 left it dark while red and blue kept orbiting. Rotation resets to 0 on stop so a relit panel starts from a known pose. See `systems/ChargeCast` § The panel (3).

## [2026-08-12] ingest | Dead spell panels recede as well as grey out

Third pass on the same question: how loudly does the HUD say a colour can cast? The castable/dead distinction was expressed purely in colour, so a panel that could not cast still held its full weight in the layout. It now fades too — `FILL_BASE_TRANSPARENCY` 0.72 against a new `_DEAD` at 0.88. Alpha and saturation are separate channels and the eye reads them separately.

Deliberately the **dead** value that moves rather than the live one. Making castable panels more opaque would brighten all three at once on a full reservoir, which is exactly when the HUD is already at its loudest; pushing the dead ones back costs nothing at that moment and pays out when only one colour is live.

The interesting part is the bug it forced. `playFiredFlash` dims the base disc and tweens back, and it captured `origTransp` off the live frame when the flash *began*. That was harmless while the value was constant. With two values it is not: a cast is exactly the event that can drop a panel below T1, so the captured value would restore the castable alpha onto a panel that had just gone dead — and it would win, because the restore lands **after** the desaturation tween `setReservoirs` started. Now resolved from state when the flash ends. Sampling live state at the start of an animation and writing it back at the end is the general shape of this, and it stays latent until someone makes the sampled thing state-dependent.

Build-time init also now calls the same `baseColorFor(color, false)` / `baseTransparencyFor(false)` selectors the tweens use, instead of restating the drained values inline — one definition of "dead" rather than two that can drift.

Verified by client screenshot across all three states, including the cast-dry case that would have caught the flash bug. **Owed:** whether 0.88 is too far — a dead panel is now nearly invisible while still being a live press target, and the argument for that being fine is that pressing a dead panel is a no-op. See `systems/ChargeCast` § The panel (2) and § Dead-panel transparency.

## [2026-08-12] ingest | Panel alpha split retuned, 0.50 / 0.72

Answering the question the previous entry left owed. Rather than pulling the dead value back from 0.88, the split moved wholesale: castable 0.72 -> **0.50**, dead 0.88 -> **0.72**. The old single value becomes the *dead* one and the castable state gets heavier instead.

Better than softening 0.88 would have been. The split widens (0.22 against 0.16) while nothing is ever fainter than it was before the split existed, so the gain is bought by making live panels more present rather than by hiding dead ones — which matters because a dead panel is still a live press target. Two constants, no behaviour change.

## [2026-08-20] ingest | Letter blocks got a face, and stopped overlapping

Two pieces of one session: a polish pass on the blocks, and the overlap bug the polish exposed.

**The face.** Blocks read as flat floating swatches — a saturated cube has no silhouette against the skybox, and a white glyph on a saturated fill loses to the fill. Four changes, all driven from `applyVisualState` so they are versioned in Rojo rather than authored into the `.rbxl` Template, which is where the Cube and its six SurfaceGuis already live and drift.

A `UIStroke` border per face, deliberately **not** a `Highlight` per block: the engine renders a bounded number (~31) against an arena of 40, which is the same budget that already forced `BlockTapController` to keep one reused hover highlight. A dark inset panel behind the glyph, with the glyph lightened toward white rather than plain white, so a red block's letter reads hot red. And a value tell — the mana emitter's rate and spark size scale continuously with `EnergyEconomy.letterValue`, so a Q looks worth ten times an E and scanning the arena becomes a decision rather than a hunt.

Three things pinned by measurement rather than assumption. `Model:ScaleTo` scales `SurfaceGui.PixelsPerStud` **inversely**, so a face canvas is a constant 200 px at any `BLOCK_SCALE` and the border thickness needs no correction — but it *does* scale `ParticleEmitter.Size`, and `spawn()` applies visuals before scaling, so `applyValueTell` takes the current scale or a re-applied block's sparks shrink by `BLOCK_SCALE` against a fresh one. `letterValue` returns 0 for a wildcard, which would have rendered the most valuable block in the arena as the dullest. And the intro fade had to learn about `UIStroke.Transparency` and `Frame.BackgroundTransparency`, or a refilling block flashes an opaque plate and wireframe before it arrives.

Corrected on `systems/LetterBlock` while there: the standing rule that the palette tints are unusable as an outline colour is about *value*, not hue — driven far enough toward black they read fine and keep colour identity. The real remaining constraint is that white and grey belong to the hover and out-of-reach cues, so any permanent mark on a block must be dark or it steals the hover cue's only channel.

**The overlap.** User reported blocks interpenetrating and worsening over time. Two bugs compounding. `BLOCK_MIN_SPACING` was a literal 4 studs guarding 6-stud blocks — `BLOCK_SCALE = 1.5` had made the 4×4×4 template 6 wide, and `BLOCK_SCALE`'s own comment asked whoever changed it to update the spacing by hand. That coupling broke silently the first time it moved. Spacing is now derived: `LetterBlocks.tumbleDiameter()` returns the cube's circumsphere (`edge × BLOCK_SCALE × √3`), and `BLOCK_SPACING_CLEARANCE` is a multiplier that cannot drift out of step with block size.

The second bug is the more interesting one. The retry loop re-rolled on collision and, when every attempt collided, fell through and spawned at the **last rejected** position — an arbitrary failing candidate rather than the least-bad one, and silently. A too-dense arena was indistinguishable from a healthy one right until blocks visibly overlapped. `pickSpacedCFrame` now keeps the roomiest candidate seen and warns on exhaustion, naming the lever. The general shape: a fallback that picks the *last* thing it tried is a fallback with no opinion, and one that does not log is a bug that reports itself as working.

Worth recording honestly that the tumble caused the report. A Y-only spin sweeps a cylinder needing ~8.5 studs; a tilted tumble sweeps the full circumsphere at 10.39. The bug predated the change, but widening the requirement is what made it visible.

Verified on the server VM across all 780 pairs, then 60 blocks churned through the refill path (destroy half, wait out the 3 s cooldown, re-survey, ×3): zero pairs inside the required clearance on every round, closest 10.63–11.51 studs, no density warnings. Headroom was never the constraint — 397,600 cu studs holding 40 blocks is 6 % fill.

**Owed:** render cost is unmeasured. The arena now carries 1,200 GUI instances, and an in-Studio A/B read exactly 15.0 fps with decor on, decor hidden, and *every* SurfaceGui disabled — a floor-limited test with no resolution, not a clean result. One frame also showed a face rendering without its border while all six verified as populated and enabled, which points at Roblox's SurfaceGui render budget. Both need a real client.

Pages touched: [[systems/LetterBlock]], [[systems/BlockSpawner]], [[index]].

## [2026-08-20] ingest | The block faces cost less than feared, and the border never worked

Closing the two items the face-treatment session left owed. Both answers inverted the question.

**Render cost.** The instrument was the problem, not the machine. The previous A/B "read 15.0 fps with decor on, decor hidden, and every SurfaceGui disabled, so the test was floor-limited" — but 15.0 in the *cheapest* condition is not a floor, it is a ceiling, and `RenderAverage` sitting at exactly 66.668 ms (1/15 s) against a `RenderThreadAverage` of 2.4 ms says the renderer did 2.4 ms of work and slept for 64. All three conditions were above the cap, which is the only reason they tied. A duration that lands on exactly 1/15 s is a pacing target, not a measurement.

`Stats.RenderBreakdown` and `Stats.FrameRateManager` report per-frame **counts**, so they do not care about pacing at all. 40 blocks on screen cost **+120 draw calls, +120 batches, +7,590 triangles** and a render-thread delta of ~0.3 ms that is smaller than the spread between two identical replicates — so the timing is honestly unresolvable and the counts are the result.

The useful finding is what the counts are *of*. 121 draws over 40 blocks is 3.0 — exactly the most faces of a cube a camera can see, so culling is already exact and the 1,200-instance figure is not what the renderer charges for. Hiding the border, the panel or the glyph individually left draws at 121: a face's contents batch into one call, so the decoration is nearly free and only face count matters. Flat across distance to 350 studs and across every quality level. Not a performance concern, and the lever the last entry proposed — decorating fewer faces per block — would not have moved it.

**The border.** Not a render budget, not quality, not the fade. A 12 px stroke on a 200 px canvas is 6 % of the face, so its width *on screen* is 4.2 px at 40 studs, 0.94 at 180 and 0.68 at 250. Below a pixel a line renders on subpixel coverage, and these blocks tumble at 28°/s, so it flickers frame to frame. Reproducible, not the stray frame it was recorded as.

What made it severe was a stale number: the arena is **219×20×248 studs**, not the 40×8×40 the index asserted (that figure is the config's fallback; real bounds come from tagged `BlockSpawnVolume` parts). Profiled by viewer position, the share of blocks with a solid border was 8 % from the arena centre and **0 % from the player spawn**. The border's stated purpose is the silhouette at distance. It worked everywhere except the case it was added for.

Thickness is now derived per block from camera distance to hold ~5.5 px on screen, driven by `LetterBlockAnimator` on the same rolling bucket as the transform but deliberately not behind the transform's cull gate — that gate freezes distant blocks, which are exactly the ones that need correcting as the camera closes. The cube edge cancels out of the derivation, so `BLOCK_SCALE` does not appear in it; deriving rather than hand-setting is the direct lesson of the `BLOCK_MIN_SPACING` overlap bug in the entry above.

Clamped [6, 20] where the ceiling is geometry: the stroke spans 0..T from the canvas edge and the panel starts at 26, and the ring of block colour between them is the only thing carrying red/green/blue once the glyph is unreadable — which is *which reservoir the letter feeds*. So the target width only holds to ~51 studs and past that the border thins from 20 px instead of 12. Solid range 85 → 141 studs; 180 and 250 come back out of sub-pixel.

Two process notes. The measurement mattered more than the fix: three plausible hypotheses (SurfaceGui render budget, quality-level culling, fade desync) were each disconfirmed by a controlled test, and one of them — quality-level culling — I had already called a "smoking gun" off a reading where I moved the camera and the quality level in the same step. And verification was Edit-mode: Studio's play mode wedged in the MCP proxy, so the fix is confirmed by replaying the animator's exact computation on real blocks at controlled distances plus before/after captures, not by a playtest. The live Heartbeat path is unverified in a running game.

Pages touched: [[systems/LetterBlock]], [[index]].

## [2026-08-20] ingest | Phase 6 planned — lobby & PvE/PvP mode selection

Design pass with the user on a welcome lobby, prompted by wanting a PvP mode. New page `design/lobby.md`; Phase 6 + changelog entry added to `design/build-plan.md`; index updated. The finding: mode choice is a **session-container** problem, not UI — `GameModeService`/`RoundManager` are a server-wide singleton and `BlockSpawner` pools every `BlockSpawnVolume` globally, so two groups can't be in different modes at once. Decided: hub place with in-place arena zones (multi-place rejected — cross-place identity needs the unbuilt Phase 5.5 persistence; whole-server vote rejected — makes PvE hostage to PvP), co-op queued PvE with `minPlayers = 1`, 1v1 duels on a 2-pad pool, diegetic portals with live queue counts over a menu screen. Also pinned a trap worth not rediscovering: **`PLAYER_VS_PLAYER_ENABLED` does not gate spell damage** — spells write `Humanoid.Health` directly and bypass `applyDamage`, so 5.1's deferred split-brain unification is a Phase 6 prerequisite. Stage 5 (duels) gated behind Phase 5.4; stages 1–4 aren't. No code written.

## [2026-08-20] ingest | Phase 6 stage 1 — RoundManager becomes per-session

`RoundManager` moved from a server-wide singleton (state in file-locals, module-table API) to `RoundManager.new(deps)` with `arenaId` and a roster, plus the project's `:disable()` / `:destroy()` pair. `GameModeService` is now a session manager: it owns `sessions[arenaId]` and `playerSessions[player]`, creates exactly one `Default` session at boot, and its two `RoundManager.isActive()` calls became an `isPlayerRoundActive(player)` lookup. Pure refactor — one `NoOp` session, whole server, no observable change.

The reason the refactor exists went in with it: `broadcastState` was `FireAllClients`, which with N sessions hands a duellist the boss arena's round state. It now iterates the session roster and `FireClient`s each member; `waitForPlayers` gates on roster count instead of `#Players:GetPlayers()`. Payload shape deliberately untouched — `GameStateGui` / `RoundTimerGui` / `DeathScreenGui` are out of scope.

Also resolved the `task.cancel(roundThread)` question the brief raised: it is dropped. It was redundant with the `running` flag (every await is a `task.wait` behind a liveness check) and strictly worse — `task.cancel` errors on an already-finished thread, which the old `stop()` could reach because it never cleared `roundThread` on natural exit, and would error if a mode callback re-entered from the round thread. A `_generation` counter replaces the one thing cancel bought: no overlap between a winding-down loop and an immediate `start()`.

Verified by Studio playtest — clean boot, `[RoundManager] [Default] Session created with mode: No-Op` → `Waiting` → `Active`, player spawned, and a client-side listener confirmed 3 `GameStateChanged` payloads in 3.2s with `roundState = Active` (so the per-roster `FireClient` reaches players at the same ~1/s cadence `FireAllClients` did). Two Edit-mode harness sessions with disjoint rosters also ran concurrently — impossible before — with zero cross-session leakage.

Left deliberately: `ScoreTracker` (3 `FireAllClients` sites) and `SpawnManager` are still singletons with the same problem — Phase 6 stage 2/4. `BossService` / `BossStates` broadcast globally too and are unscoped.

Pages touched: [[systems/GameMode]] (rewritten off its singleton + `6610291`-stale file tree), [[index]].

## [2026-08-20] ingest | Phase 6 gained a broadcast-audience stage

Follow-up to stage 1 (`b38a99c`). Grepping `FireAllClients` across `src/` after the RoundManager refactor found **eleven** remaining sites, not the one the plan had treated as a detail — the broadcast audience is a class of bug, not a RoundManager quirk. Split recorded in `design/lobby.md` § Broadcast audience: the six **screen-space** sites genuinely break with two arenas (`BossService`'s BossHealthChanged ×3 / BossPhaseChanged ×2 → BossHudGui, `ScoreTracker`'s ScoreUpdate + KillFeed ×2 → Scoreboard/KillFeed GUIs — a duellist would get the boss's health bar on screen), while the **world-space** VFX lane (`VfxBroadcast` ×5, `VfxBroadcastService`, `SkillDelivery`, boss windup) costs instantiation but is never seen from another arena, so it stays with VisualEffects' existing PERF guardrails rather than gaining a roster lookup on the game's hottest path. `DevSmokeTestKillFeed`'s three sites are a dev harness, left alone. New stage 3 in both `design/lobby.md` and `design/build-plan.md`; hub/PvE/duel/wiki renumbered 3–6 → 4–7. No code changed in this ingest.

## [2026-08-20] ingest | Phase 6 stage 2 — block and player spawning bound to an arena

`BlockSpawner` was a file-local singleton whose module *was* the arena: `BlockSpawnerService` swept every part tagged `BlockSpawnVolume` in the world into one array and called `start()` once. It is now `BlockSpawner.new(opts)`, one pool per arena, with the `disable()`/`destroy()` pair — the idiom stage 1 (`b38a99c`) gave `RoundManager`. The service groups tagged volumes by `Arena.idOf(part)` and starts one pool per group. New shared `src/shared/GameMode/Arena.luau` declares the `ArenaId` attribute, the `Default` id, the `LobbySpawn`/`PvEArenaSpawn`/`PvPArenaSpawn` authoring tags and `idOf()`, because three scripts across two domains read those strings.

**Density was the half that could have shipped broken.** `targetCount = density × total_volume / 1000` summed all tagged volumes; per-arena it must be that arena's volume. The single-arena case gives the right answer either way, so the bug would have surfaced only once a second arena over- or under-filled. Verified with two probe pools over disjoint 100k and 50k cu-stud boxes resolving to 10 and 5 blocks rather than 15 each. **Absent `ArenaId` resolves to `Default`** — the shipped arena's eight volumes are tagged but unattributed, so requiring the attribute would have stopped it spawning with clean logs throughout.

`SpawnManager` moved from one file-local `spawnTag` to `registerArena(arenaId, spawnTag)` + `getBestSpawn(player, arenaId)`, matching candidates on tag **and** `Arena.idOf` so stage 6's two `PvPArenaSpawn` pads stay apart. `filterSpawnsForPlayer` untouched. The `SpawnLocation` fallback is deliberately not arena-filtered — it is the misconfigured-scene path, and the shipped place takes it on every spawn since nothing carries `FFASpawn`.

Verified by playtest: clean boot, one `Default` pool over 8 boxes / 397,600 cu studs / target 40, spawned 40 all inside tagged volumes, a client-fired `ConsumeBlock` popped and refilled to 40, player on the existing pad at (257, 206.5, 26) rather than origin. The four Phase 3 block suites now build their own pool instead of stopping the live one — under the singleton each fixture called `BlockSpawner.stop()` in setup and never restarted it, so a test run left the real arena frozen for the rest of the playtest. `BlockShoot`'s reach comment reworded: the 240 × 259 span it cites is the default arena's, not "the arena's". No observable change to the shipped game.

Pages touched: [[systems/BlockSpawner]] (§ Arena binding; API table is now the instance API; density and arena-box tunables corrected off the live 0.1 / 397,600 figures), [[systems/GameMode]] (§ Arena binding + per-arena SpawnManager; file tree), [[design/lobby]] (stage 2 marked done).

## [2026-08-20] ingest | Phase 6 stage 3 — screen-space broadcasts scoped to a session roster

The nine screen-space `FireAllClients` sites now route through a single new seam, `src/shared/GameMode/BroadcastAudience.luau`: `ScoreTracker`'s `ScoreUpdate` ×1 and `KillFeed` ×2, and `BossService`'s `BossPhaseChanged` ×3 and `BossHealthChanged` ×3. Stage 1 fixed `RoundManager` by giving it a roster to iterate; these two senders have no roster to hold — `ScoreTracker` is a server-wide singleton and `BossService` is a top-level Script nothing injects into — so `GameModeService` registers a resolver over its session tables and callers resolve per fire. The module stores no roster of its own; it is a late-binding pointer.

**The judgement call was the boss.** It is not owned by a session today, so "which roster" was a real question. Threading a session reference through `BossService` would have been a large refactor that stage 5's `Modes/PvEBoss.luau` immediately redoes, so the boss resolves its audience the same way every other arena-bound thing does: `Arena.idOf(BossPoint)`, read once per boss cycle (so retagging survives a respawn) with the roster behind it resolved per fire (so it tracks joins and leaves under a long-lived boss). Stage 5 sets the attribute and changes nothing else.

**The fallback is everyone, not nobody** — an unresolved lookup returns `Players:GetPlayers()`, the pre-stage-3 behaviour, plus a warn throttled to 30 s because the boss health path fires at 10 Hz. An empty audience would silently blank a HUD, which is the failure mode that costs a playtest to notice; an *empty table returned by a resolver* is distinct and honoured as-is. Kill feed anchors on the **victim**, not the killer, since a victim is always a real Player in a session where an environment kill has no killer; `recordBotKill` inverts this of necessity.

**Deliberately left behind:** `ScoreTracker`'s scores are still one server-wide table, so a duellist can still read another arena's names off their scoreboard — only the *audience* moved, because the payload shape had to stay byte-identical for `ScoreboardGui` and `KillFeedGui`. Per-session score state is stage 5. The eight world-space VFX sites keep `FireAllClients` by design (see [[design/lobby]] § Broadcast audience) and `DevSmokeTestKillFeed`'s three are a dev harness.

Verified by playtest to the single-session bar: clean boot, `Starting boss cycle in arena Default`, the resolver registered ahead of `ScoreTracker.initialize`, no fallback warnings, `BossHudGui` and `ScoreboardGui` alive. **The two-session disjoint-roster cross-talk test did not run** — MCP `start_stop_play` wedged (`"Start play hasn't finished yet"`, the same failure the stage 1 session hit) and would not restart Studio for it. It is the test that catches the bug this stage exists to prevent and remains outstanding.

Pages touched: [[systems/GameMode]] (§ Broadcast audience; file tree), [[systems/Boss]] (§ Broadcast audience; remote table), [[design/lobby]] (stage 3 marked done).

## [2026-09-07] ingest | Phase 6 stage 4a — the lobby is a session, and `transferPlayer` is the primitive

Planned stage 4 and shipped its first third (`dbc88c4`). The stage was expanded into a § Stage 4 detail section on [[design/lobby]] recording four decisions, then split 4a/4b/4c so each lands verifiably.

**The decision that shaped the rest: the lobby is an arena slot with a session, not the absence of one.** `Arena.LOBBY_ID` + `Modes/LobbyMode.luau`, created at boot and joined by every player. Modelling it as `playerSessions[player] == nil` looked cheaper and was not — stages 1-3 spent their whole budget making *arena id* the key that spawns, block pools and broadcast audiences agree on, and a lobby with no id puts a `nil` branch back into all three. The lobby session is **created but never `start()`ed**, gated by a new optional `runsRounds` field on the mode config; absent means true, so no existing mode was edited. `RoundManager` learns nothing about lobbies.

What falls out is `transferPlayer(player, arenaId)` — remove from one roster, add to another, restamp attributes, respawn at the target's pads. Stages 5 and 6 are that call with a queue in front of it. Exposed as a `TransferPlayer` BindableFunction because the session tables live in a Script, not a module. The character is **pivoted, not reloaded**: reloading resets health, drops the equipped Tool and rebuilds every `ResetOnSpawn` ScreenGui on a path a player crosses repeatedly, and restoring health belongs to a mode's round start where it can mean something.

`PlayerState` and `ArenaId` are attributes on the **Player** — they replicate on their own, so there is no join-order race between a LocalScript starting and the server telling it where the player is. State is *derived* from the session's mode rather than stored, so it cannot drift from the roster it describes.

**Two consequences worth the writing-down.** The arena round no longer starts at boot: `_waitForPlayers` gates on roster count and the Default roster is empty until somebody walks in. Correct — it is what "a round is a session, not a server" means — but a lobby player now receives no `GameStateChanged` at all. Nothing in the gameplay chain (blocks, energy, casting, boss) turned out to be coupled to round state; only `GameStateGui`, `RoundTimerGui` and `DeathScreenGui` are, and all three are `ArenaOnly` under [[concepts/HudGate]]. Second: a session emptied mid-round stays `Active`. Harmless for `NoOp`, but stage 6 must not inherit it or a duel pad never frees — it belongs to the mode's win condition, not to the transfer.

**A latent bug the stage surfaced by accident:** the respawn loop was gated on `isPlayerRoundActive`, which was correct while every session ran a round. The hub's session never enters Active, so the old gate would have left a player who fell off the lobby dead on the floor with nothing in the log. Rewritten as "has a session", with the arena resolved through the existing `arenaIdForPlayer`.

Verified live rather than by inspection: a joining player reads `InLobby`/`Lobby`, `TransferPlayer:Invoke` moves them to `InArena`/`Default` and back, and an unknown arena id is refused rather than silently dropping the player out of every roster. Clean boot, no errors. The position did not change across the transfer, which is the expected 4b gap — no lobby pads are authored yet, so both arenas resolve through `SpawnManager`'s misconfigured-scene `SpawnLocation` fallback.

**Stage 4b shrank in the reconciliation.** A concurrent session's [[concepts/HudGate]] established that the player-facing energy grant happens at **memorize**, not at pop, which inverted the "practice blocks grant no energy" plan — there was no per-block grant to suppress, and since the lobby grants real energy, lobby pops must reach the shadow ledger *too*. The planned `ArenaId` stamp on spawned blocks went with it: the hub sits hundreds of studs from the arena and `BlockShootValidation.checkRange` already refuses a pop at that distance. 4b is now Studio work plus tags.

Pages touched: [[design/lobby]] (§ Stage 4 detail added; stage 4 row rewritten; 4a marked done; 4b/4c reconciled against HudGate), [[concepts/HudGate]] (new, by the parallel session; § reference corrected), [[systems/Boss]] (BossHudGui's own-ScreenGui correction), [[index]].

## [2026-09-07] ingest | Phase 6 stage 4b — the hub exists, and a transfer now moves your body

Authored `Workspace.Lobby` via MCP under two `ChangeHistoryService` waypoints: a 140 × 140 walled shell at `(-600, 202, 28)` with corner pillars, two portal arches, five `LobbySpawn` pads, a practice-block volume, a target dummy, and a `LobbyReturnPad` on the arena side. Floor top matches the arena plaza at `y = 203`; the hub sits 533 studs clear of the nearest arena block volume, which is what lets `BlockShootValidation.checkRange` refuse cross-arena pops without an arena-id check — the reason stage 4b was able to drop the planned `ArenaId` stamp on spawned blocks.

**The spawn change had a non-obvious second half.** Disabling `Arena.SpawnZone.SpawnLocation` is what makes Roblox's initial spawn land a joining player in the hub. But the arena's pad also had to be tagged `FFASpawn`, because `SpawnManager`'s `SpawnLocation` fallback is deliberately not arena-filtered (it is the misconfigured-scene path, and `Default` was still reaching it). Adding a `SpawnLocation` to the lobby while `Default` still fell through would have made the hub a candidate *arena* spawn. Both arenas now resolve by tag and neither reaches the fallback: `[Lobby] registered with 5 spawn points`, `[Default] registered with 1`.

`BlockSpawnerService` reports `2 arena(s): Default=40, Lobby=8` — the per-arena density arithmetic from stage 2 doing its job unmodified on a second pool. A transfer now moves the body, `(-650, 207, 28)` ↔ `(257, 206, 26)`, where in 4a it moved only the roster.

**The dummy cost no code**, as [[concepts/HudGate]] predicted: cloned from `ServerStorage.AIWorldData.Rigs.Patroller`, anchored at the root, tagged `Damageable`, and `DeathHandler` logged `Created template for 'TargetDummy'` on sight. `HealthService` overrides the authored 200 HP with its own 100 — correct, it owns that number. The `DamageableTemplates` copy in ServerStorage draws a second `Damageable initialized` line because `HealthService` scans the tag rather than the workspace; cosmetic, pre-dates this stage.

**One layout bug, found by screenshot rather than by log.** The block volume was centred on the hub and swallowed the dummy, so blocks spawned in front of the one thing you are meant to cast at. Every server log was clean. Dummy moved north, volume z-extent pulled back — the same lesson as the VFX rule in `CLAUDE.md`, reached from the other direction: a clean server log says nothing about what the player is looking at.

The geometry lives in `BrainFighter.rbxl`, not in git. Rojo maps only `ReplicatedStorage`, `ServerScriptService`, `StarterGui` and `StarterPlayer`, so `Workspace.Lobby` is safe from a sync deleting it — and is not versioned until the place file is saved and committed.

Pages touched: [[design/lobby]] (4b marked done, with the spawn-fallback interaction and the geometry-not-in-git note).

## [2026-09-07] ingest | Phase 6 stage 4c — the HUD knows where you are, and the portals work

Stage 4 closes. [[concepts/HudGate]] is implemented as `src/shared/Hud/HudGate.luau`: a required third argument on `HudLayoutManager:register` for the nine region-registered elements, and `HudGate.bindScreenGui` for the six that own a ScreenGui. Making the argument mandatory broke all nine call sites on purpose. Plus `PortalPanelBuilder`/`PortalPanelConfig`/`PortalGui` for the confirm panel and floating signs, `src/server/Lobby/LobbyService.server.luau` for the server half, and `EnergyReservoirs:reset()` cleared on the transition into `Active`.

**The bug worth the entry: Roblox fires property-changed signals deferred.** HudGate has to tell its own writes from the owning script's, because a gate that force-*shows* on arena entry would reveal an empty boss bar and a death overlay to a living player — `BossHudGui` and `DeathScreenGui` both manage their own visibility. The first implementation set an `applying` flag around the write and cleared it on the next line. Deferred signals meant the flag was already false when the handler ran, so the gate read its own suppression back as *the owner wanting the element hidden*. The playtest showed a perfect lobby and an arena with no health bar, no kill feed and no boss HUD — a bug that only exists in the direction nobody tests first. The fix removes the flag: with the gate open it never writes, so any change is the owner's; with it closed, a value going true can only be the owner, and a value going false is assumed to be ours.

**`LobbyOnly` ended up with no users.** The concept page assigned the portal panel `LobbyOnly`, which stops being right the moment the arena contains a portal — and stage 4b put a return pad there. The panel is `Always`, gated by proximity and by the same arena check the server makes. The enum value stays for a surface that really is lobby-only.

**Two non-findings.** `DashButtonGui` is hidden in both zones because it is touch-only and its owner never asked for it — the "gate never reveals" rule working, not failing. `RoundTimerGui` returns early on `ROUND_TIMER_ENABLED = false` and has no ScreenGui at all; its binding is correct and dead until stage 6.

The server half refuses everything the client could lie about: the part must carry the `ModePortal` tag, the player must be within `SERVER_RANGE_STUDS` (34, deliberately looser than the client's 22 so a walking tap is not lost to latency), and the portal must belong to the arena the player is standing in. Verified: `Portal refused for ZandaLuki (Pad): out of range (80 studs)`. Counts are published as attributes on the pad rather than pushed over a remote, so a late-joining client reads current numbers the moment it asks — the sign shows `0/2 in - 1 waiting` while somebody waits for a duel pad that stage 6 has not built yet.

`EnergyReservoirs:reset()` fires once per colour that actually moved, and `EnergyRoundReset` clears on the *transition* into Active rather than on every one of RoundManager's per-second Active broadcasts. Verified live (`round went Active (from nil) — reservoirs cleared`) and by two new cases in `__tests` covering the fire count and the silent-on-empty path, run green in Edit mode.

Also: the return pad moved 17 → 52 studs from the arena spawn, because arriving in the arena inside the return prompt's range greeted the player with "Return to lobby".

Pages touched: [[design/lobby]] (4c marked done; the deferred-signal finding and the LobbyOnly correction).

## [2026-09-07] lint | full wiki audit — stage renumber left half-applied

Swept all 57 pages for broken wikilinks, orphans, dead `src/` citations and
`updated:` drift. **Clean:** no orphans, no broken page-to-page links. The dead
`src/` paths on `Weapon`/`Loadout`/`Character`/`BossAdapter`/`LetterBlaster` are
intentional — those pages are REMOVED records — and [[systems/VisualEffects]] +
[[design/ui-architecture-review]] already flag their own stale sections in place.

**The one real contradiction:** when `2d5579f` inserted broadcast audience as
Phase 6 stage 3, it renumbered [[design/lobby]] but only the `##` headings in
[[systems/GameMode]]. Four references kept the old numbering — the round/PvP
flags (stage 5 → 6), the arena seam (stages 3–5 → 4–6), and the Modes table's
PvE/PvP rows (4/5 → 5/6). Corrected.

Also corrected the "NoOpMode is the only registered mode" claim, false since
`dbc88c4` registered `Lobby`: frontmatter description, the Files list (now
carrying `LobbyMode.luau` and `runsRounds = false`) and the [[index]] entry. The
page *body* still describes the NoOp-only world — that rewrite is stage 7 work
and is now labelled as such rather than reading as current. Bumped stale
`updated:` on [[index]] (from 2026-08-20) and [[systems/BlockSpawner]]
(→ 08-21), and demoted four `[[CLAUDE.md]]`/`[[NIM-4]]` pseudo-wikilinks to
code spans — neither is a wiki page.

Audit covered committed state only; stage 4b/4c was uncommitted and in flight.

Pages touched: [[systems/GameMode]], [[index]], [[systems/BlockSpawner]], [[concepts/HudGate]], [[systems/ChargeCast]], [[systems/WordBuffer]].

## [2026-09-08] ingest | System design audit 2026-09 — report and tickable refactor plan

Whole-`src/` design audit against the June/UI/boundary audits as baseline; three read-only area sweeps, every finding hand-verified at `file:line`, no code changed, no playtest run. Report at [[design/system-audit-2026-09]] (45 findings, 12 wiki-vs-code drifts, 11 questions for the user); plan at [[design/refactor-plan-2026-09]] (12 one-session chunks with owns / must-not-touch / done condition / risk / playtest / depends-on, each with a `Status:` line and checkboxes so other sessions can claim and tick). Recorded as Phase 7 in [[design/build-plan]].

**Closed since June:** Skills Humanoid leak, BossAdapter, template cut, Skills tests, effect stubs, `damageAmpMultiplier`, boundary stages 1–6. **Still open and now load-bearing:** the split-brain damage path — `SkillEffects` writes `Humanoid.Health` directly, so a spell kill never fires `PlayerEliminated` and Phase 6 stage 6 cannot credit a duel; the server-wide `ScoreTracker`, spawn threat scoring and boss/NPC targeting that stage 5 needs per-session; a three-way respawn ownership split with a stale `pendingRespawns` entry; the `HudGate` reveal on DeathScreenGui (owner writes the gated property); the client-originated `BroadcastSpellVfx` relay the boundary audit never listed; a server ledger that never resets while the client does. Seven of ten `__tests.luau` are not reachable from the autorunner, and three Multiplayer suites require deleted systems.

Pages touched: [[design/system-audit-2026-09]] (new), [[design/refactor-plan-2026-09]] (new), [[design/build-plan]] (Phase 7 + changelog), [[index]].

## [2026-09-08] ingest | Audit questions Q1–Q11 answered; refactor plan unblocked

The user validated the recommended option on all eleven questions from [[design/system-audit-2026-09]]. Recorded as a § Decisions table plus a `Decision:` line on each affected chunk in [[design/refactor-plan-2026-09]]; the three chunk items that had been written conditionally (Melee suite, settings config extraction, bot-kill suite) are now unconditional. Nothing in the plan has started; chunk 0 is next.

Pages touched: [[design/refactor-plan-2026-09]], [[design/system-audit-2026-09]] (answered banner), [[design/build-plan]] (Phase 7 decisions line).

## [2026-09-08] ingest | Refactor chunk 0 — turned the lights off

Deleted dead flags, dead utility/HUD/CastAction code, and unread constants per [[design/refactor-plan-2026-09]] chunk 0: `GameConfig` lost `TPS_CHARACTER_ENABLED`, `SHOW_WEAPON_ROLODEX`, the three `*_SPEED_MULTIPLIER` keys, `DEV_AUTO_EQUIP_TOOL`, `DEV_SIMULATE_LOADOUT_CYCLING`, `DEV_BOT_COUNT` (and `DEV_COUNT_POP_VFX` flipped back off); the three Dev scripts (`SimulateLoadoutCycling`, `DevAutoEquipTool`, `BotSpawner`) and four dead `src/utility/*` modules, `Core/Cleanup`, two `TypeValidation` functions, `Reticle`/`TouchControl` Builder+Config, `TeamScoreGui.client.luau`, three `HudLayoutManager` methods, and `CastAction.tapReservoir`/`resolveTapSpec` (with their `__tests` cases, renumbered) are gone. Six unread constants deleted from `GameModeConstants`/`HealthConstants`/`NPCConstants`. Four stale comments fixed (`SkillEffects`, `BossHudGui`, `SettingsMenuGui`; `DevDebug` was already correct). Every deletion was grep-verified against `src/` before landing.

**Deferred, not deleted:** the `PlayerRespawned` BindableEvent fire + `.model.json` — `Suites/Multiplayer/multiplayer_invariants.luau` structurally asserts it exists, and chunk 1's stated trim list for that file doesn't name this check, so there's no pre-committed fix to land alongside. Left for chunk 1 to resolve. `BotSpawner` was deleted despite `Suites/Multiplayer/applydamage_credits_bot_kill.luau` depending on its listener, because chunk 1's Decision Q8(a) already deletes that exact test file next — the two chunks were sequenced with this dependency in mind.

Two boot-smoke playtests (clean console both times); the first surfaced nine Studio-side stale duplicates of deleted scripts that Rojo hadn't pruned (`Reticle`/`TouchControl` Builder+Config, `bindToInstanceDestroyed`, `Core.Cleanup`, two `TypeValidation` functions, `TeamScoreGui`) — removed via a `ChangeHistoryService`-wrapped `execute_luau` pass; the second playtest (fresh Studio instance) found none. This session ran concurrently with chunk 2 (constants) and chunk 3 (HUD ownership) in the same working tree; several shared files (`CastAction/__tests.luau`, `HudConstants.luau`, `GameModeConstants.luau`, `HealthConstants.luau`, `NPCConstants.luau`, `SkillEffects.luau`) carry chunk 2/3 lines riding along in this chunk's commit — whole-file staging, not separated.

Pages touched: [[systems/HUD]] (Reticle/TouchControl/Team-score-gate sections marked removed, diagram pruned), [[concepts/DevDebugHotkeys]] (`;` lives in BossHudGui note), [[design/refactor-plan-2026-09]] (chunk 0 status/checkboxes).

## [2026-09-08] ingest | Refactor chunk 2 — one name per number

Consolidated per-color duplicate declarations and drifted-value constants per [[design/refactor-plan-2026-09]] chunk 2. New `src/shared/Core/Colors.luau` (`--!strict`, `SpellColor`/`TileColor`/`Tile`/`SPELL_COLORS`/`isSpellColor`) is now the one place `"red" | "green" | "blue"` is spelled out; `WordBuffer`, `EnergyEconomy`, `EnergyReservoirs`, `SpellRegistry`, `BlockSpawner`, `VfxConfig`, `SpellMenuConfig` and `DevDebug` all alias or read through it instead of redeclaring the union or the `{red,green,blue}` list. `ChargeStateService` dropped its `EnergyReservoirs` require entirely (only needed it for `COLORS`, now `Colors.isSpellColor`); `EnergyLedger` kept its `EnergyReservoirs` require (still needs `CAP_PER_COLOR`) with a comment saying so.

Other consolidations: `SpellRegistry.AUTO_TARGET_RANGE_STUDS` (150) replaces the independently-declared 150 in `SpellMenuGui` and `SpellCastConstants` — see [[systems/SpellCastService]] § Tuning. `VfxConfig.SFX.FIZZLE_PLAYBACK_SPEED` replaces three copies of `0.55` in `BlockTapController`/`GameplayHudGui`/`SpellMenuGui`. `NPCConstants.EYE_HEIGHT` (1.5) replaces three raw `Vector3.new(0, 1.5, 0)` literals in `Perception`/`Actions`. Skills delivery/effect fallback defaults (projectile count/speed/spread/lifetime/proximity/stagger/trackTarget/impactRadius/color/size, aoe radius/windup/complete, freeze duration, knockup force) moved from bare `params.x or <N>` literals into named `SkillConstants.DEFAULT_*` constants.

Two value fixes, not pure moves: `EconomyConstants.REJECTION_LOG_THROTTLE_SEC` was `5` while its own comment claimed to match "both hardened remotes" (`BlockShootConstants`/`SpellCastConstants`, both `10`) — restored to `10`. `RoundManager._broadcastState` now sends an additive `respawnTime` field (from `modeDefinition.getConfig().respawnTime`, currently `GameModeConstants.RESPAWN_TIME = 4` for every registered mode) in the `GameStateChanged` payload; `DeathScreenGui` reads that instead of branching between `GameModeConstants.RESPAWN_TIME` and `HealthConstants.RESPAWN_TIME` (5) — the two were never the same constant (Health's still prices the generic Damageable-NPC respawn timer and the manual `RequestRespawn` server gate), but `DeathScreenGui`'s branch was guessing between them instead of asking the server, and the non-active-round display silently changes from 5s to 4s as a result. Comments on both `RESPAWN_TIME` declarations now cross-reference each other's remaining scope.

**Divergence from the plan:** chunk 2 depends on chunk 1 (autorunner suite wiring), which had not landed. Verified the seven pure-module `__tests` directly via `execute_luau` in Edit mode instead — six passed (`WordBuffer`, `EnergyEconomy`, `EnergyReservoirs`, `SpellRegistry`, `MindFullManager`, `CastAction`); `MemorizeAction.__tests` failed a pre-existing assertion unrelated to this chunk (scenario 2 expects an invalid-word memorize to preserve the buffer, but `MemorizeAction.tryMemorize` has called `buffer:clear()` on the invalid path since at least commit `9ae3719`, well before chunk 0/2 — the test file's comment is stale, not the implementation, or vice versa; flagged for whichever session owns `MemorizeAction`/Tests next, not fixed here as it's outside chunk 2's `Owns`). `Suites/Skills` (5/5), `Suites/Hardening` (3/3) and `Suites/Economy` (1/1) all passed in one playtest — `Skills` via the `RunTests` attribute + autorunner per CLAUDE.md, `Hardening`/`Economy` via a direct `TestRunner.runSuite` call in the same live session (Server datamodel) rather than two more playtest restarts, since `TestAutoRunner` only reads its attribute once at boot and the 2-iteration cap didn't leave room for three full restarts; `TestRunner` is documented as MCP-callable this way. Console was clean throughout; boot smoke (HUD, all controllers) initialized without error.

Pages touched: [[systems/SpellRegistry]] (`Color` alias, new § Auto-target range), [[systems/SpellCastService]] (§ Tuning — duplicate-constant note resolved), [[design/refactor-plan-2026-09]] (chunk 2 status/checkboxes, § Divergence log).

## [2026-09-08] ingest | Refactor chunk 3 — HUD ownership

F4 fixed. `DeathScreenGui` bound `screenGui.Enabled` to [[concepts/HudGate]] (`ArenaOnly`) **and** wrote that same property in its own `show()`/`hide()`. With the gate closed in the hub, `show()` wrote `true`, the gate correctly read that as owner intent, recorded `ownerWants = true` and re-suppressed; `hide()` then wrote `false` onto an already-`false` property, which fires no changed signal, so the retraction never reached the gate. The next arena entry faithfully restored a full-screen death overlay over a living player at full health. There is no repair on the gate's side — the write it would need to observe is one Roblox never reports — so the fix is a rule about call sites: **an owner never writes its own gated property.** `DeathScreenGui` now leaves the ScreenGui enabled and toggles a child `overlay.Visible`, the split `GameStateGui` and `ScoreboardGui` already used (which is why neither ever showed the bug); the countdown loop's liveness check follows the overlay. `HudGate` gained a throttled `Logger` warning at the one moment a violation is detectable (a closed-gate `true` write) — a warning is not a repair, but it names the file instead of leaving a cosmetic bug for a playtest six weeks out.

New `src/shared/Hud/__tests.luau` (`M.run()`, client-only — `HudGate` resolves `Players.LocalPlayer` at require time) pins all of it in four scenarios: (1) reproduces the F4 sequence and asserts the leak, deliberately, because the leak is the reason the rule exists; (2) the shipped `DeathScreenGui` shape — lobby death then arena entry draws nothing, and an arena death still shows the overlay; (3) `ownerWants` ends `false` for a compliant owner, read through the property after the gate opens since `ownerWants` is a module local; (4) `Always` is never suppressed and a `nil` `PlayerState` degrades to visible.

`_G` removed from the HUD. `_G.BrainFighter.requestDash` became `src/client/DashApi.luau` — a ModuleScript both `DashManager` (`setProvider`) and `DashButtonGui` (`requestDash`) require, resolved at request time so registration order does not matter, and returning `false` when unregistered so the button can log a real warning. All five `_G.PlayerHud.*` writers (`BuffTrayGui`, `DashButtonGui`, `GameplayHudGui`, `MindFullIndicatorGui`, `SpellMenuGui`) were deleted rather than ported: a grep of `src/` found no readers for any of the seven handles.

`TopRight` now stacks (F20/F22). It had `KillFeedGui`'s container and `BuffTrayGui`'s tray registered with no layout, so both drew at the region's top-right corner. Added `stackVertical = true` / `stackPadding = 8`; the feed keeps `LayoutOrder = 0` and its exact former position, the tray declares `BuffIconConfig.LAYOUT_ORDER = 1` below it. The tray container also moved to `AutomaticSize.XY` with a zero authored size — `AutomaticSize` treats the authored `Size` as a *minimum*, so the old `ICON_SIZE`-tall frame would have reserved a row in the new stack and pushed the feed down with no buffs active. Verified in-game: empty tray measures 0 × 0.

Config extraction (F23) for the five pairs named in the plan — SpellMenu, AttributeBar, BuffTray, PortalPanel, MemorizeButton (SettingsMenu deliberately skipped; it is deleted in chunk 12 per Q5). Every extracted number keeps its value. `AttributeBarConfig`: `TEXT_STRIP_HEIGHT`, `LABEL_INSET`, `LABEL_WIDTH_FRACTION`, `LABEL_HEIGHT`, `NUMERIC_RIGHT_INSET`, `NUMERIC_WIDTH_FRACTION`, `NUMERIC_FORMAT`, `NUMERIC_PLACEHOLDER`, `GAIN_SWEEP_START_WIDTH`/`_COLOR`/`_TRANSPARENCY`, `DRAIN_RIPPLE_START_SIZE`/`_END_SIZE`/`_COLOR`/`_TRANSPARENCY`/`_CORNER_SCALE`. `BuffIconConfig`: `LAYOUT_ORDER`, `ICON_IMAGE_INSET`, `STACK_INSET`, `STACK_WIDTH`, `STACK_HEIGHT`, `STACK_MIN_TO_SHOW` (the duplicated `stacks > 1` ternary became one `stackLabelFor` helper). `MemorizeButtonConfig`: `VALID_STROKE_PULSE_TRANSPARENCY`. `PortalPanelConfig`: `PRIMARY_LABEL`, `ORDER` (title/status/primary/cancel), `SIGN_LABEL_HEIGHT_FRACTION`, `SIGN_COUNT_HEIGHT_FRACTION`, `SIGN_LABEL_STROKE_TRANSPARENCY`, `SIGN_COUNT_STROKE_TRANSPARENCY`, `SIGN_ORDER`. `SpellMenuConfig`: `FILL_GRADIENT_ROTATION`, `LABEL_HEIGHT`, `LABEL_TOP_OFFSET`, `NUMERAL_FORMAT`, `FIRED_FLASH_COLOR`, `FIRED_DIM_TRANSPARENCY`. What is left inline in the Builders is `0.5` for centring and `* 255` for RGB channel conversion — geometry and unit constants, not tunables.

**Playtest (one iteration, all states verified on the client, not the server).** A per-frame client sampler recorded, across 3158 frames spanning a lobby death, an arena transfer and an arena death: `everEnabledInLobby = false`, `everOverlayInLobby = true`, `everEnabledInArena = true`, `everOverlayInArena = true`. Read that as: the owner did toggle its overlay on the lobby death (as it should), and the gate never once let the ScreenGui through in the hub, so nothing was drawn — screenshot of a visibly dead character in the lobby shows no dim, no countdown, no respawn button, with the buffer/ABSORB/spell orbs still up. On arena entry the gate restored `Enabled = true` with `overlay.Visible = false`: screenshot shows the boss bar and health bar returning over a living player and **no death overlay**. Dying in the arena drew the overlay with "Respawning in 2..." over an emptied health bar. `Hud.__tests` printed `[Hud.__tests] all scenarios passed`. The DASH button (mobile override on) was tapped for real via `user_mouse_input`: console logged `[DashController] roll start` and peak character speed went 0.0004 → 61.8 studs/s, with no "no dash provider is registered" warning — so `DashButtonGui → DashApi → DashManager → DashController` is wired end to end. Boot console clean, no compile errors, no HudGate owner-write warnings.

**Divergence from the plan:** the plan asks for the `HudGate` test as a unit suite entry, but the `Suites/Unit` wrapper is chunk 1's job and chunk 1 has not landed — the suite was invoked directly via `execute_luau` on the Client datamodel instead (it cannot run on the Server: `HudGate` resolves `Players.LocalPlayer` at require time). Second, scenario 1 of that test asserts the *broken* outcome for a non-compliant owner, which is unusual and deliberate: it is the only way to pin why the rule exists, and its message says to delete the scenario rather than weaken it if the gate ever learns to see the missing write. Third, the plan's `TopRight` item offered "stackVertical **or** BuffTray to its own region"; `stackVertical` was taken, and the tray's `AutomaticSize` change was a necessary consequence of it (documented above) rather than a separate decision.

Pages touched: [[concepts/HudGate]] (new § Owners never write the gated property; the triage table's retired `_G.PlayerHud.BuffTray` reference), [[systems/HUD]] (new § The dash bridge, § TopRight stacks; DashButton rows in the file listing and widget table; the ownership invariant), [[design/refactor-plan-2026-09]] (chunk 3 status/checkboxes, § Divergence log).

## [2026-09-08] ingest | Refactor chunk 1 — test harness tells the truth

Before this chunk, `RunTests="all"` could report a clean summary while silently skipping tests: two `__tests.luau` modules (`Dictionary`, `EnergyEconomy`) ran their asserts at `require` time instead of behind a callable, `WordBuffer.__tests` returned a bare function instead of a table (so the autorunner's `collectTestsInFolder`, which only accepts `{name=..., run=...}`-shaped tables, would have rejected a wrapper for it), and seven pure-Luau modules (`WordBuffer`, `EnergyEconomy`, `EnergyReservoirs`, `Dictionary`, `SpellRegistry`, `MemorizeAction`, `MindFullManager`) plus `Hud` had no `Suites/` wrapper at all — reachable only by a human typing `require(...).run()` into the command bar. Fixed: `Dictionary` and `EnergyEconomy` now expose `M.run()`/`{run=runAll}` instead of executing on require; `WordBuffer.__tests` now returns `{run=runTests}`; new `Suites/Unit/` wraps all eight in the same shape `Suites/Skills/castaction_tests.luau` established, with `SpellRegistry`'s wrapper following `spellexecutor_tests.luau`'s `(passed,failed)`-tuple idiom instead since its `__tests.luau` exposes `.runAll()`, not `.run()`.

Dead suites deleted (Decision Q8(a)): `Suites/Melee/*` (the melee chain is dead code; chunk 11 removes the modules it exercised) and three Multiplayer suite files whose C1/C2 deliverables' only listener (`BotSpawner`) chunk 0 already deleted — `drop_request_zone_gated`, `respawnzone_tracks_hrp_presence`, `applydamage_credits_bot_kill` — plus their shared `Helpers/restoreToSafeSpawn.luau`. `multiplayer_invariants.luau` trimmed to remotes that still exist (dropped the Weapon.Remotes and TDM-team blocks) and to drop its `Health.Events.PlayerRespawned` structural check, which chunk 0 had deferred (F19) because this test was the only reason that BindableEvent was still fired. The fire in `HealthService/init.server.luau` and the versioned instance (`PlayerRespawned.meta.json` — the plan named it `.model.json`, which was wrong; it's a bare `BindableEvent`) are both deleted now that nothing listens.

`MemorizeAction/__tests.luau` scenario 2 asserted an invalid word preserves the buffer; [[systems/MemorizeAction]] documents the buffer clearing on the invalid path as intentional ("letters are consumed regardless"), and `tryMemorize` has done that since `9ae3719` — the test was stale, not the module. Fixed the assertion to check `size() == 0` and `res.pattern == "XYZ"` instead.

NPC suites needed a live, state-machine-driven `Patroller_1`, not just the raw rig Model — a bare `ServerStorage.AIWorldData.Rigs.Patroller:Clone()` has a Humanoid but no `NPCController`, so `CurrentState` would never be set. New `Helpers/ensurePatroller.luau` reuses a boot-spawned `Patroller_1` when one exists (the observed common case — `NPCService` spawns it from `AIWorldData` before the autorunner's startup delay elapses) and only falls back to cloning + wiring its own `NPCController` (requiring `ServerScriptService.Server.NPC.Scripts.NPCController` directly, ticked on `Heartbeat`) when none exists; `teardown` only destroys what it created. `Hud/__tests` hit a different wall: it requires `Players.LocalPlayer` and errors on any server VM, and `TestAutoRunner.server.luau` is server-only with no client counterpart — `Suites/Unit/hud_tests.luau` checks `RunService:IsServer()` and reports an explicit `"skipped — client-only"` pass instead of manufacturing a false fail for a harness gap; it runs for real on an actual client VM.

**Playtest (one iteration).** `RunTests="all"` → `[AUTORUN DONE] 26/28 passed, 2 failed`, zero `[AUTORUN WARN] Skipped` lines, zero setup/run pcall errors — every failure was a real `verify` returning false. Per suite: NPC 2/3, Multiplayer 0/1, Phase3 7/7, Skills 5/5, Hardening 3/3, Economy 1/1, Unit 8/8 (including `hud_tests`' server-VM skip). Two pre-existing, out-of-scope bugs surfaced now that the harness isn't hiding them: `npc_deals_damage` fails intermittently from cross-test interference (the preceding `combat_disengages` test can leave the player mid-respawn right as this test snapshots its initial health), and `multiplayer_invariants` fails on a real placement regression — `ShotReplication` LocalScript missing from `StarterPlayerScripts`. Per "must not touch the modules under test," both are left failing and recorded on the chunk page rather than fixed here.

Pages touched: [[systems/Tests]] (full rewrite — discovery rules, the two `__tests` wiring idioms, fixture requirements, suite table with LIVE/deleted status, known-failing tests), [[concepts/MultiplayerTestPattern]] (retired § Shape 2 — its `BotSpawner`/`applydamage_credits_bot_kill` example no longer exists), [[systems/Loadout]] (drop-zone tests it cited are deleted; path is currently uncovered), [[design/refactor-plan-2026-09]] (chunk 1 status/checkboxes, § Divergence log, § Found).

**Follow-up (2026-09-08, same day, parent review).** Both "Found" items from the run above turned out to be test-side bugs inside this chunk's own `Owns`, not real regressions or out-of-scope module bugs — parent review sent them back before marking the chunk done.

`multiplayer_invariants`'s ShotReplication check was stale, not a live placement bug: `git show --stat 6610291` confirms `src/client/ShotReplication.client.luau` was deleted on purpose in that commit, alongside the Weapon.Remotes files this suite had already stopped asserting on. Deleted both halves of the check (StarterPlayerScripts-presence and stray-in-ReplicatedStorage) and the header comment bullet that motivated it; `wiki/concepts/LocalScriptPlacement.md` needed no change since it documents the historical incident, not current state.

`npc_deals_damage`'s flake was confirmed as cross-test interference: `combat_disengages` teleports the player 80 studs from the NPC as part of its own test, which can land them into `Workspace.Arena.DeathZone` and trigger a `DeathZoneService` → Lobby-and-back trip that's still resolving when the next test starts. Fixed test-side only (`NPCService`/`Perception`/`Actions`/`HealthService` untouched): `combat_disengages`'s `teardown` now calls `Helpers/restoreToSafeSpawn.luau` — recovered verbatim from before its deletion in this same chunk, since the exact fixture it implements ("put the player back on solid ground") was needed again — and `npc_deals_damage`'s `setup` gained `waitForStableFullHealth`, a bounded poll (8s) for the player's Humanoid to hold `Health >= MaxHealth` for a continuous 1s window, restarting on any mid-wait respawn and failing `setup` with a clear reason if it never settles.

Re-verification surfaced a third, previously-passing test failing for an unrelated reason: `blockspawner_fills_to_target` hardcoded `color ~= "red" and color ~= "green" and color ~= "blue"` in its `verify`, predating the wildcard tile system, so a block randomly rolling the shipped `"wild"` color intermittently failed a passing suite. Fixed by deriving the accepted color set from `Core/Colors.SPELL_COLORS` (reservoir colors' source of truth) plus `Wildcard.COLOR` (the wildcard tile color's source of truth) instead of a hardcoded list.

**Playtest (two more iterations, three total for this chunk).** Run 2 (after the ShotReplication + npc_deals_damage fixes): NPC 3/3, Multiplayer 1/1, Phase3 6/7 (new `blockspawner_fills_to_target` failure), Skills 5/5, Hardening 3/3, Economy 1/1, Unit 8/8 — 27/28. Run 3 (after the color-vocabulary fix): **`[AUTORUN DONE] 28/28 passed, 0 failed`** — NPC 3/3, Multiplayer 1/1, Phase3 7/7, Skills 5/5, Hardening 3/3, Economy 1/1, Unit 8/8. `RunTests` cleared and the playtest lock released after both.

Pages touched (this follow-up): [[systems/Tests]] (replaced § Known failing tests with § Stale-assertion pitfall — the general lesson: check what an assertion names against `git log`/`git show` before treating a failure as a live regression; `Files`/Fixture requirements updated for the restored `restoreToSafeSpawn.luau`), [[design/refactor-plan-2026-09]] (chunk 1's Found/results sections rewritten with root causes and fixes, three-run results table).

## [2026-09-08] ingest | Refactor chunk 4 — one damage path

Closed audit F1/F2 and the F34 kill-feed "Unknown" (decisions Q1(a), Q2(a)). `applyDamage.process` / new `applyDamage.heal` are now the only `Humanoid.Health` writers outside spawn-init: `HealthService` injects the module into `SkillEffects.setDamageSink`, the `damage`/`heal` handlers build a request (`sourcePlayer` from the delivery `source`, `damageAmp` folded in, `cause` = the skill name passed through `SkillDelivery.applyImpactEffects` → `SkillEffects.apply(spec, target, source, cause)`) and refuse with no sink — the client build has none, so "predicted run writes nothing" is now structural. The upward `pcall(require)` and `EffectSpec.useApplyDamage` are gone. `DamageRequest`/`DamageResult` carry `cause`; `GameModeService.onPlayerEliminated` credits it (the equipped-Tool read never worked — the Spelling Staff cast everything). `DeathZoneService` goes through the same path (`HealthConstants.INSTANT_KILL_DAMAGE`, `cause = death_zone`). PvP gate: `GameConfig.PLAYER_VS_PLAYER_ENABLED` deleted; `GameModeDefinition.getConfig().allowsPvP` (false on Lobby/NoOp), answered from the victim's session by a new `AllowsPvP` BindableFunction that `GameModeService` binds at file scope, injected into `applyDamage` as `allowsPvPFor(victim)`. `SkillBuffs.consumeShield` documented as shell-only; the body drain is `DamageModifierRegistry` alone.

**Playtest (one iteration, lock `chunk-4-damage`).** `RunTests="all"` → `[AUTORUN DONE] 28/28`, `RunTests` cleared. `Skills/__tests` scenario 8 now drives 25 damage through `SkillEffects.apply` into a 40 pool: Health untouched, pool 15 — drained once. `predicted_run_writes_nothing` listens on `PlayerDamaged` and asserts Inferno's `DamageResult.cause == "Inferno"` on the authoritative trial and no event on the predicted one (observed `causes=Inferno,Frost Nip`). Kill feed read from the **Client** datamodel via a `KillFeedEntry` recorder: `[death_zone] ZandaLuki`, `[FireballVolley] ZandaLuki`. Boss numbers unchanged: GroundSlam 25, Brain volley 5/shot, `cause=` stamped on every line. Player-sourced spell kills on another player still want the two-client check (Phase 6 stage 6).

Pages touched: [[systems/Health]] (rewritten: one damage path, callers table, PvP gate), [[systems/SkillPipeline]] (damage paths unified; stale `drawnLocallyBy`/`casterUserIdFrom` bullet and § Reserved Hooks deleted; shield drain paragraph), [[design/lobby]] (blocker closed, § PvP gate), [[systems/GameMode]], [[systems/Boss]], [[design/build-plan]], [[index]], [[design/refactor-plan-2026-09]] (chunk 4 done + divergences; chunk 9 note on NPC melee `cause`).

## [2026-09-08] ingest | Refactor chunk 5 — one respawn owner

Three player-respawn paths collapsed to one. `Players.CharacterAutoLoads = false` is now set first thing in `GameModeService.initialize`, and `GameModeService` is the only `LoadCharacter` caller for players — the first spawn in `onPlayerAdded`, every later one from the `Humanoid.Died` handler that knows the player's session (and so the delay and the pad). `HealthService`'s `RequestRespawn` remote is deleted along with the death-screen button that fired it (the button only became visible after the server had already respawned, so it was decorative), and `pendingRespawns` is gone from `HealthService` and `applyDamage` — the stale entry there let a client reload a *living* character. `HealthConstants.RESPAWN_TIME` renamed `NPC_RESPAWN_TIME` (non-player rigs only; the player number is `GameModeConstants.RESPAWN_TIME`). Also F17: `ScoreTracker.recentDamage` now expires on insert and drops the key on the victim's `Died`/`Destroying`; and F13's two `SpawnManager` offsets are named `SPAWN_VERTICAL_OFFSET` / `SPAWN_FALLBACK_CFRAME`. Verified in playtest: exactly one `CharacterAdded` per death in hub and arena, overlay shows and clears, harness 28/28. See systems/Health § Respawn, systems/GameMode § Respawn, design/refactor-plan-2026-09 § Chunk 5.

## [2026-09-08] ingest | Refactor chunk 6 — the energy ledger enforces

`EconomyConstants.ENFORCE` flipped to `true`: `EnergyLedger.checkCast` now refuses casts a player provably never earned, closing the last item of the 5.4 hardening brief and the "client-trusted affordability" PvP blocker. The flip was only meaningful once F9 was closed in the same commit — `RoundManager` now passes its roster on `RoundStarted` and `EconomyService` resets each member's account, so the server ceiling no longer carries across rounds and lobby banking. `EnergyLedger.reportMemorize` also refuses any payload above `WordBuffer.DEFAULT_CAP` outright, ahead of the account lookup and the per-tile walk, in both modes.
Measured playtest: four honest words and three casts through the real client modules and remotes produced **zero** would-reject lines, with a reset line on every round start; harness `all` 30/30 before and after the flip. Sample limits (one player, no discards, no wildcards) recorded on systems/SpellCastService and in the plan. See systems/SpellCastService § Validated memorize, design/lobby § PvP blockers (+ the Q4(a) charge-tier note), design/refactor-plan-2026-09 § Chunk 6.

## [2026-09-08] ingest | Refactor chunk 7 — one VFX broadcast lane

The client-trusted spell-VFX relay is gone: `VfxBroadcastService`, `BroadcastSpellVfx` and `SpellVfxEvent` deleted (audit F6), and with them the prediction layer's habit of drawing impact bursts at a target the server had not confirmed (F7). `VfxController` now listens on the Rojo-versioned `CastAction/Remotes/SpellResolved` BindableEvent — no `CastAction` require, so no executor chain on a presentation script (F29) — and draws the cast cue only, via the new `SkillVisuals.spawnCastCue`. The authoritative run raises the same cast cue for everyone else from `SpellExecutor.cast` with `drawnLocallyBy = ctx.predictedBy`, and the `instant` handler raises impact cues for every client (`SkillVisuals.spawnImpactCues`, tier-aware through the new `DeliveryCtx.tier`) — Q9(a): one RTT on impacts, accepted. `ProjectileVfxEvent` folded into `VfxBroadcast` as the `projectile` kind and `ProjectileVfxController` into `WorldVfxController`, so `WorldVfxEvent` is the one server→client lane. `SkillDelivery`'s hittables cache now connects its Heartbeat on first use (authoritative-only callers, so server-only). F21: the HUD stopped running gameplay — `client/SpellCastController` owns auto-target, `castSpecific` and the `SpellCastServer` relay, `SpellMenuGui` forwards `castRequested` through a `RequestCast` BindableFunction and plays the result.
Verified on the caster's client with honest energy: `cast_green_t1` local at t+0, `impact_heal` from the server at t+63 ms, one of each; a ledger-refused cast drew the cast cue only. Harness 30/30, `predicted_run_writes_nothing` green. **Two-client count outstanding** (local-server windows are not visible to the MCP proxy) — chunk stays `claimed`. Pages: [[design/client-server-boundary]] (relay row + chunk-7 note under Stage 6), [[systems/VisualEffects]] (frontmatter `implemented`, banner, § Architecture and § RemoteEvent Contract rewritten for the one lane), [[systems/HUD]], [[systems/CastAction]], [[systems/SkillPipeline]], [[index]], [[design/refactor-plan-2026-09]] § Chunk 7.

## [2026-09-09] ingest | Refactor chunk 7 closed — two-client VFX count

Chunk 7 (`e5d31a7`) moves from `claimed` to `done`. The outstanding two-client check ran on a Studio local server with two players and the paste-in counter (`nimbalyst-local/chunk7-client-counter.lua`) in each client's Command Bar. Caster Player1 with honest energy (`RAN`, `DATE`, ledger enforcing) cast a T1 Mend: the caster drew the predicted cast cue at t+0, received the server's copy 47 ms later with `drawnLocallyBy` = itself and did not draw it again, then received and drew `impact_heal` once; the observer Player2 received the cast payload once (`drawnLocallyBy` = caster) and drew it once, and received and drew `impact_heal` once. Three further Mends the server refused (`green cast costs 5, ledger has 1`; the next two silent under the rejection-log budget) drew the cast cue on the caster only and nothing on the observer. Every block pop reached both clients with `drawnLocallyBy` = the popper, skipped on the popper's client and drawn on the other. This is the first VFX verification in the project taken on a second client rather than inferred from payloads. Pages touched: [[design/refactor-plan-2026-09]] § Chunk 7 (status + counts), [[design/client-server-boundary]] (Stage 2 "still outstanding" closed).

## [2026-09-09] fix | Attack spells fizzled in the lobby — TargetDummy was never an auto-target candidate

Reported after the chunk 5/7 playtests: `Firebolt` in the lobby always logged `cast fizzle — no target in range`. Not a chunk 7 regression: `findAutoTarget` (moved unchanged from `SpellMenuGui` into `SpellCastController`) only ever considered `NPC`-tagged models and `workspace.Boss`, both of which live in the Default arena; `Workspace.Lobby.TargetDummy` carries only `Damageable`, 95 studs from the lobby spawns and well inside the 150-stud range. Chunk 5 made the first spawn land in the lobby, which is what surfaced it. Fix: the picker also iterates `HealthConstants.DAMAGEABLE_TAG` models (same living-Humanoid + nearest-distance filter). The server side needed nothing — `SpellCastValidation.checkTarget` accepts any workspace Model within `MAX_TARGET_DISTANCE_STUDS`. Verified in an MCP playtest from the lobby spawn: red and blue T1 casts now pass target resolution and stop at the client affordability check (`cannot afford Firebolt (cost 5, have 0)`) instead of `no target in range`; a full server apply on the dummy is the next honest-energy cast anyone makes there. Pages touched: [[systems/SpellRegistry]] (candidate set + controller name), [[systems/SpellCastService]] and [[systems/Boss]] (stale `SpellMenuGui.findAutoTarget` name).

## [2026-09-09] ingest | Refactor chunk 8 — sessions own their scores (and their registry)

`SessionRegistry` (`src/server/GameMode/Scripts/SessionRegistry.luau`) now owns `sessions` / `playerSessions` / `queued` and the `create` / `destroy` / `transferPlayer` / `setQueued` / `forPlayer` / `forArena` / `rosterOf` / `allowsPvPFor` calls; `GameModeService` is boot wiring, the player lifecycle and kill routing only. The three BindableFunctions (`TransferPlayer`, `SetPlayerQueued`, `AllowsPvP`) are deleted from disk and gone from Studio — `LobbyService` and `HealthService` require the module (F16, Q6). `ScoreTracker` is an instance per session, built and owned by its `RoundManager`, broadcasting `ScoreUpdate` / `KillFeed` to its own members; the leaderstats mirror and the assist history stay module-level; `recordBotKill` deleted (F12). `SpawnManager.getBestSpawn(player, arenaId, roster)` scores threats from the roster it is handed (F13). Every team branch is gone — `TEAMS_ENABLED`, the friendly-fire branch in `applyDamage`, nametag team colour, `winnerTeamName` (payload, `RoundManager`, `GameStateGui`), `getTeamConfig`, `teamBased`, `GameModeTypes.luau` — and `ROUND_TIMER_ENABLED` / `ROUND_COUNTDOWN_ENABLED` became `timeLimit` / `countdownSec` on the mode config; `RoundTimerGui` shows its chrome only when the payload carries `timeLimit` (F34, Q7). `Arena.SpawnTags.Default` names the shipped arena's `FFASpawn` pad. Three new `Suites/Multiplayer` tests; harness 33/33. Single-client playtest through the real portal: a lobby death gave the client a 1-row scoreboard (`d1`), the transfer started the Default round with a fresh 1-row scoreboard (`d0`), nothing reset the lobby, and the timer chrome stayed hidden. Two-client scoreboard check user-driven via `nimbalyst-local/chunk8-client-scoreboard.lua`. Pages: [[systems/GameMode]] (full stage-7 rewrite), [[design/lobby]] (§ Session model registry/scores rows, § Stages 5–7, PvP gate, stage-4 "deliberately not"), [[systems/Health]] (PvP gate wording, friendly-fire section removed), [[index]], [[design/refactor-plan-2026-09]] § Chunk 8.

## [2026-09-09] ingest | Refactor chunk 8 closed — two-client scoreboard check

Chunk 8 (`be227ba`) moves to `done`. On a Studio local server with two players and `nimbalyst-local/chunk8-client-scoreboard.lua` in each client's Command Bar, Player1 took the PvE portal: its client received one `ScoreUpdate` listing only itself and `GameStateChanged Active timeLimit=nil` (then the existing 1 Hz Active broadcast); Player2, still in the lobby, received no score or state broadcast at all. That is the disjoint-roster case the suite could not build with one player — a round start in one session reaches only that session's roster, and each scoreboard shows only its own session. Pages touched: [[design/refactor-plan-2026-09]] § Chunk 8 (status + layer-2 line).

## [2026-09-10] ingest | Refactor chunk 9 — the world knows its arena

Boss and NPCs are per arena session: `BossService` and `NPCService` build one cycle / one NPC set per arena off the GameMode `RoundStarted` / `RoundEnded` events (which now carry `arenaId`), reconcile against `SessionRegistry.all()` at boot, stamp every spawned rig with `ArenaId`, and gain `disable()`/`destroy()`. New `src/shared/Skills/Hittables.luau` is the one target definition — `SkillDelivery.collectHittables`, `CosmeticProjectile.collectRigs` and NPC `Perception` all read it, filtered to the source rig's arena (players via the Player attribute, rigs via their own; absent = Default). Blocks carry the pool's `ArenaId` and `ConsumeBlock` refuses a mismatch (`checkArena`, before range). NPC damage requests now carry `cause = Archetype`. Pages: systems/Boss, systems/NPC, systems/BlockShoot, systems/BlockSpawner; plan: design/refactor-plan-2026-09 § Chunk 9.

## [2026-09-10] ingest | Portal panel would not re-show after a "Not now"

User-reported from play: declining a portal, walking off the pad and walking back on left the confirm panel absent. Not the dismissal bookkeeping — `PortalGui.dismissedPortal` clears correctly on walking out of range, and the same failure reproduced with no dismissal at all, on any second approach. Root cause is in `PortalPanelBuilder:setShown`: the hide path connected a `Completed` handler that set `Visible = false`, and the show path cancelled that tween. `Tween:Cancel()` fires `Completed` again with `Enum.PlaybackState.Cancelled`, even on a tween that already finished, and the deferred fire landed between `Visible = true` and the show tween's first move off transparency 1 — so the stale handler hid the panel it was reopening. Measured in a playtest before the fix (`Visible=false transp=0.120`, a faded-in frame that is not on screen) and after (`Visible=true transp=0.120` on re-entry, both with and without a "Not now"); harness 34/34. Fix: hide only on `PlaybackState.Completed`, and disconnect the listener before cancelling. Pages touched: [[design/lobby]] § stage 4c.

## [2026-09-10] ingest | Dev mana cheat works again under ENFORCE

Reported from play: the `1`-`4` mana hotkeys stopped producing castable mana. Not a regression in the keys — chunk 6 flipping `EconomyConstants.ENFORCE` to true is what exposed them. The cheat only ever filled the client's `EnergyReservoirs`; the server prices casts against `EnergyLedger`, which credits only spelled-for energy, so every cheated cast died at `checkCast`. Reproduced with `DevFillMana = 2` and a real `RequestCast` invoke: `[DevDebug] reservoirs set to T2 (10 each)` followed by `[SpellCastService] rejected SpellCast — red cast costs 5, ledger has 0`. The cast reports `ok` on the client and silently never lands, which is why it reads as broken spells rather than a stale cheat. Fix gives the cheat its missing server half in the system that owns the answer: new `Shared/Economy/Remotes/DevGrantEnergy` RemoteEvent, `EnergyLedger.devSetCeiling` (set, not add, mirroring the client's fill so pressing 2 after 4 lowers both sides), and a handler in `EconomyService` gated on `RunService:IsStudio()` — the wire carries a tier, not an amount, so a forged fire can ask for no more than the keyboard already gives. Verified: `dev mana grant — ZandaLuki ledger set to T2 (10 per colour)`, then red and blue T1 casts both reached `(server apply)` and took the dummy 100 -> 95 -> 90. Harness 34/34. Pages touched: [[concepts/DevDebugHotkeys]], [[systems/SpellCastService]] § Validated memorize.

