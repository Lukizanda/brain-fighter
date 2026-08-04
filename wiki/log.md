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
