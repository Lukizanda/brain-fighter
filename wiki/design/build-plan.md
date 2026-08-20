---
type: design
description: Phased build plan for Brain Fighter's core gameplay systems — construction order, parallel vs sequential dependencies, parallel-session strategy
updated: 2026-08-20
---

# Build Plan

Phased construction of Brain Fighter's gameplay systems. Each phase ends with a playtestable verification milestone. Companion to [[design/gameplay-loop]] (the WHAT) — this doc is the WHEN and HOW.

Work items are tracked as Nimbalyst `task` trackers, tagged with their phase. Each system below maps to one tracker.

## Strategy

- **Pure-Luau modules with no inter-deps run in parallel sessions** (Phase 1 and parts of Phase 4).
- **Anything that wires multiple modules together runs sequentially** so the integrating session has its dependencies pinned (most of Phase 2 + Phase 3).
- **Assets that need design judgment (LetterBlock look, spell VFX, boss model) are coordinated synchronously with the user** rather than fanned out to subagents — to avoid taste drift.

The plan is a living doc — update it as systems land or discover new dependencies. Each landing system gets a wiki/systems/`<Name>`.md page and a `log.md` ingest entry. Cross-link from this plan to those pages.

## Phase 1 — Foundations (parallel)

Pure Luau modules. Zero Roblox-instance dependencies. All five built in parallel sessions.

| Module | API surface | Notes |
|---|---|---|
| **Dictionary** | `isWord(s)`, `getStats()` | Hashtable lookup. 26 per-letter sub-modules from SCOWL 60 (~79.5k words); background-preloaded at game start. |
| **EnergyEconomy** | `letterValue(c)`, `lengthMultiplier(len)`, `computeWordEnergy(word)`, `splitByColor(tiles)` | Scrabble values × length tiers. Sanity-checked against the worked examples in `gameplay-loop.md`. |
| **SpellRegistry** | `getSpell(color, tier)`, `listAffordableSpells(color, energy)` | Config for 10 spells (R/G/B × T1–T3 + red T4 Volley) — cost, targetingMode, `skill:SkillSpec`. |
| **WordBuffer** | `new(cap)`, `:append(letter,color)`, `:remove(idx)`, `:reorder(from,to)`, `:clear()`, `:asWord()`, `:colorBag()`, `:isFull()`, `.changed` | 12-slot state + changed signal. |
| **EnergyReservoirs** | `new()`, `:add(color,n)`, `:get(color)`, `:canAfford(color,n)`, `:drain(color,n)`, `.changed(color)` | 3-color state with per-color signal. Cap 60 per color. |

**Milestone:** each module passes its own smoke-test asserts (e.g. `Dictionary.isWord("FIRE")` → true, `EnergyEconomy.computeWordEnergy("FLAME")` → 15). Each ships with a `wiki/systems/<Name>.md` page.

## Phase 2 — Action systems

Each depends on one or more Phase 1 modules. Some parallel-safe; sequencing noted.

| Module | Depends on | Parallel-safe? |
|---|---|---|
| **MemorizeAction** | Dictionary + EnergyEconomy + WordBuffer + EnergyReservoirs | Yes (with SpellExecutor, MindFullManager) |
| **SpellExecutor** | SpellRegistry | Yes (with MemorizeAction, MindFullManager) |
| **MindFullManager** | WordBuffer | Yes (with MemorizeAction, SpellExecutor) |
| **BlockSpawner** | Dictionary + LetterBlock template | Sequential — needs Phase 3 LetterBlock first |
| **CastAction** | EnergyReservoirs + SpellRegistry + SpellExecutor | Sequential — needs SpellExecutor first |

**Parallel strategy:** spawn MemorizeAction + SpellExecutor + MindFullManager once Phase 1 lands. BlockSpawner and CastAction wait for Phase 3 / Phase 2 prerequisites.

## Phase 3 — World instances + level integration

Mix of code + Roblox assets. Asset-heavy items need user coordination.

| Module | Notes |
|---|---|
| **LetterBlock** template | Roblox model — Part + letter glyph + color tint. Needs design coordination on look. |
| **BlockShoot** | Input handler — click on a LetterBlock → consume → append to WordBuffer. |
| **BossAdapter** | Reuses existing NPC system (Patroller archetype). Takes damage from SpellExecutor. |

## Phase 4 — HUD (parallel)

Five HUD pieces. Each builds against an already-shipped state module and runs in its own session.

| Piece | Depends on |
|---|---|
| **HUD: BufferDisplay** | WordBuffer |
| **HUD: ReservoirBars** | EnergyReservoirs |
| **HUD: MemorizeButton** | WordBuffer + MemorizeAction |
| **HUD: SpellMenu** | EnergyReservoirs + SpellRegistry + CastAction |
| **HUD: MindFullIndicator** | MindFullManager |

**Parallel strategy:** spawn five sessions once their backing modules are stable. Each session lands a builder under `src/shared/Hud/`.

## Phase 4.5 — Bug Fix Sprint

Play-test all current features end-to-end. Fix bugs as found, one session per bug.
Phase complete when the current feature set (Phase 1–4) feels stable during play.

No predetermined list — issues are raised by the user after playtesting.

## Phase 4.6 — LetterBlaster Tool

Replace the bare `BlockShootBoot` click handler with a dedicated weapon Tool.

| Item | Detail |
|---|---|
| **Tool placement** | `StarterPack` via MCP — auto-equips on spawn |
| **Input** | `Tool.Activated` replaces raw `UserInputService.InputBegan` |
| **Reticle** | Reuse `ReticleBuilder.build()` in a full-screen ScreenGui |
| **Rate of fire** | 0.25s cooldown (`os.clock` gate on `Tool.Activated`) |
| **Sounds** | `FireSound` on shot, `HitSound` + hitmarker on confirmed consume |
| **Model** | Handle MeshPart in `StarterPack.LetterBlaster` (placeholder neon cyan) |
| **Server** | `BlockShootService.server.luau` unchanged |

**New files:**
- `src/shared/LetterBlaster/init.luau` — controller (mount/fire/reticle/sound)
- `src/shared/LetterBlaster/LetterBlasterConfig.luau` — tuning constants
- `src/client/LetterBlasterBoot.client.luau` — mounts controller on CharacterAdded

**Deleted:** `src/client/BlockShootBoot.client.luau`

## Phase 4.7 — Letter Slot Reorder ✓ COMPLETE

Add drag-to-reorder and tap-to-swap interactions to the BufferDisplay letter tiles. The backend `WordBuffer:reorder(fromIdx, toIdx)` already exists and is unit-tested — this phase is purely UI input wiring.

| Item | Detail |
|---|---|
| **Drag-to-reorder** | `DragDetector` (or `InputBegan`/`InputChanged`/`InputEnded`) on each tile cell; ghost tile follows pointer; drop calls `session.wordBuffer:reorder(fromIdx, toIdx)` |
| **Tap-to-swap** | Tap selects a source tile (highlight); second tap on a different tile swaps the two indices; tapping the same tile or an empty tile cancels selection |
| **Visual feedback** | Selected tile gets a highlight border; drag ghost is a semi-transparent copy of the tile; both modes snap-animate on drop via `TweenService` |
| **Input routing** | Works on both mouse and touch; `UserInputService.TouchEnabled` decides gesture threshold |
| **Scope** | Changes confined to `BufferDisplayBuilder.luau` (adds input handlers to each tile frame) and its boot wiring in `GameplayHudGui.client.luau` |

**Backend:** `src/shared/WordBuffer/init.luau` `:reorder(from, to)` — already implemented, no changes needed.

**Files to modify:**
- `src/shared/Hud/BufferDisplayBuilder.luau` — main input handler work
- `src/client/UI/GameplayHudGui.client.luau` (or equivalent boot script) — wire `session.wordBuffer` into tile event callbacks

## Phase 4.8 — UI Architecture Review ✓ COMPLETE

Before Phase 5 polish work, conduct a structured review of the client UI system for modularity, single-ownership, and software design quality. Scope: `src/client/UI/`, `src/shared/Hud/` (`src/client/PlayerHud/` removed since the original audit).

**Status (2026-06-05):** Re-audited from current source; GO for Phase 5 confirmed. The recommended cleanup (R-1 SettingsMenuBuilder decouple / NIM-19, R-2 dead ReservoirBars delete, R-3 BufferDisplay constants → Config, R-4 DashButton region geometry → HudConstants) landed and was verified by playtest. No High findings remain open; R-5..R-9 (2 Medium / 3 Low) deferred into Phase 5. Full findings + resolutions: [[design/ui-architecture-review]].

| Question | What to check |
|---|---|
| **Single ownership** | Any two scripts writing to the same Frame, LayoutOrder, or property? |
| **Coordinator clarity** | Is `GameplayHudGui` the only BottomCenter coordinator, or do other scripts still self-register? |
| **Builder/Config/Layout compliance** | Every HUD element built via a Builder? Config values all in `*Config.luau`? No magic numbers inline? |
| **Lifecycle completeness** | Every controller/builder that holds connections have a `:destroy()` path? |
| **Dead code** | Any scaffold files or `[unused]` entries still in `shared/Hud/` that should be deleted? |
| **Coupling** | Do Builders depend on LocalScript globals (`_G`, `Players.LocalPlayer`)? Should be pure-module. |

**Deliverable:** A short findings doc or tracker entries for any issues found, with a go/no-go on Phase 5 polish starting before the fixes land.

## Phase 5 — Polish

Split into three sub-phases (2026-07-15), sequenced so correctness debt lands before content built on top of it. Source of the item list: [[design/system-audit-2026-06]] (re-verified against `src/` on 2026-07-15 — Skills leak, stub-spell mana drain, and placeholder sounds all confirmed still live).

### Phase 5.1 — Correctness sprint ✅ (2026-07-27)

The audit's Tier 1 items that survived the template cut. Small scope, gates 5.2. **Complete — all four items landed and playtest-verified (Skills suite 4/4).**

| Item | Detail | Outcome |
|---|---|---|
| **Skills Humanoid state leak [H]** | `SkillEffects._freezeState` + `SkillInterrupt._active`/`_silenced` were cleaned only by timer/finish paths. | ✅ One-shot `Died` + `HealthChanged<=0` + `Destroying` cleanup purges both registries (HealthChanged backs up Died — the Dead state never fires on partial rigs; place runs deferred signals). Also fixes orphaned FreezeVfx shards. |
| **Stub spells drain mana** | `shield`/`wall`/`buff` handlers no-op'd but returned `ok=true`, so CastAction never refunded. | ✅ Stubs return `ok=false, reason="unimplemented"`; the `world_spawn` delivery stub too (Stone Wall's actual no-op path — its `onImpact` is empty). Sanctuary's stub `shield` entry removed until 5.2 (real heal + refund would have been a free full heal). Refund verified end-to-end. |
| **Split-brain damage path [M]** | Spells write `Humanoid.Health` directly; boss attacks use `applyDamage.process`. | ✅ Decision (user, 2026-07-27): documented as out of scope for spells — `applyDamage` is server-only while spells cast client-side; unify when 5.4 hardening moves casting server-side. See [[systems/SkillPipeline]] § Damage paths. |
| **SkillInterrupt tests** | The Skills layer had zero `__tests`. | ✅ `src/shared/Skills/__tests.luau` (7 scenarios incl. death/despawn purge races) + `Tests/Suites/Skills/` autorunner suite wrapping it with SpellExecutor, CastAction, and an end-to-end refund check. Also modernized 2 stale SpellExecutor tests (Frost Nip 3s, Fireball-as-projectile). |

**Milestone:** ✅ freeze/death races show no leaked registry entries; casting a stub spell refunds its mana; Skills suite 4/4 in playtest.

### Phase 5.2 — Content completion

Make the full spell roster and AV feedback real.

| Item | Detail | Status |
|---|---|---|
| **Implement shield / wall / buff** | Replace the 5.1 `ok=false` stubs with real effects (design pass with user on behavior first). | ✅ 2026-08-03 — see below |
| **Real SFX assets** | Replace `rbxassetid://0` placeholders (SpellMenuGui, GameplayHudGui, VfxConfig fizzle sites); work the [[systems/AudioSFX]] gap priority list. | open |
| **VFX gaps** | Green cast effects + PERF guardrails from [[systems/VisualEffects]]. | open |

#### shield / wall / buff — design pass + implementation (2026-08-03)

Design decisions taken with the user, then implemented and playtest-verified. Full engineering detail in [[systems/SkillPipeline]] § Defensive layer.

The three stubs resolved into two real effects and one deletion — `wall` had no consumer at all (Stone Wall is a `world_spawn` *delivery* with empty `onImpact`; the effect handler was a decoy), while `buff` had no consumer either until Stasis's damage amp became its first.

| Decision | Choice | Rationale |
|---|---|---|
| **Shield mechanic** | Flat absorb pool, 40 HP, **no expiry** | Reuses the `_shield` attribute that Health's `DamageModifierRegistry` already drains inside `applyDamage` — the path boss attacks take. 40 ≈ two boss hits. Indefinite by user call; add a duration if playtest says it overstays. |
| **Self-target identification** | `selfTarget` flag on `SpellRegistry.Spec` + `needsEnemyTarget(spec)` | The cast UI inferred it from colour ("green means self"), so blue Shield demanded an enemy in range and passed *that enemy* as the target — a naive shield would have shielded the boss. |
| **Shield authority** | Extend the existing relay to self-casts | A client-set attribute never replicates upward, so an unrelayed shield protects nothing. Overlaps cleanly with 5.4 rather than fighting it. |
| **buff / wall fate** | Delete `wall`; make `buff` real via Stasis | Stasis declared `damageAmpMultiplier = 2.0` that the freeze handler silently ignored — a live roster lie. It's now a composed `{ freeze, buff }`. |
| **Stone Wall** | Solid blocker, blocks everything incl. the caster, 6 s | A wall you can walk through but the boss can't reads as broken; boxing yourself in is what makes placement a decision. |
| **Sanctuary** | Restored to full heal + shield | Stripped in 5.1 only because the failing stub refunded mana while the heal still landed. |

**Verified in playtest**: Skills suite 11/11, SpellExecutor 11/11, CastAction + refund suite pass; Shield pool absorbs 25 with zero HP loss then bleeds 10 through on the second hit; Stone Wall spawns collidable and flush with the floor.

**Carried forward, not done here:**
- **No placement reticle.** `world_spawn` honours an explicit `Vector3`, but no cast UI supplies one — Stone Wall drops 12 studs ahead of the caster's facing. Reticle UX belongs to 5.3 ([[design/gameplay-loop]] § Targeting).
- **No shield HUD.** The pool is invisible to the player. `BuffTray` exists and boots as an empty tray "awaiting adapter wiring" — that's its adapter.

### Phase 5.3 — Polish & tutorial

| Item | Detail |
|---|---|
| **Tuning passes** | Energy curve, spawn density, tier thresholds. |
| **UI review leftovers** | R-5..R-9 from [[design/ui-architecture-review]] (2 Medium / 3 Low). |
| **Tier 3 debt (opportunistic)** | Color type dedup ×4, Skills/Vfx magic-number extraction — as polish touches each area. |
| **Tutorial** | Guided first-play sequence per [[systems/Tutorial]] (shoot → buffer → memorize → cast → boss hit). |

## Phase 5.4 — Release gate: public soft launch

Release target decided 2026-07-27: **public soft launch** (unlisted first, then listed). The bar is everything in 5.1–5.3 that players touch, plus two items previously outside the plan. Explicitly *not* required: UI review leftovers R-5..R-9 and Tier 3 debt — those stay opportunistic.

| Item | Detail |
|---|---|
| **Server trust hardening** | ✅ **Mostly done 2026-08-03.** `ConsumeBlock` validates payload / in-workspace / tag / range / rate; `SpellCastServer` validates spell / caster / target / range / rate. Covered by the `Hardening` suite (3/3) and a live playtest. See [[systems/BlockShoot]] § Trust model and [[systems/SpellCastService]] § Trust model. ⚠️ **Server-side affordability NOT delivered** — energy state lives only in `client/PlayerSession`, so the server has nothing to price a cast against. The cast rate limit is a flood guard standing in for it, not a price check. **Decided 2026-08-03: close it with an energy-ceiling ledger** (not a server-authoritative economy). Design + rationale in [[systems/SpellCastService]] § Blocked; scoped as its own item below. |
| ~~Energy-ceiling ledger~~ → **Validated memorize** | Added 2026-08-03 as the energy-ceiling ledger; **redesigned 2026-08-10** after the bound was worked against the real constants and found to saturate at `CAP_PER_COLOR` within ~8 s of shooting — it would have passed nearly every cast an actively-shooting client made, catching cast-spam bots the rate limiter already handles while missing the cheat that matters (shoot normally, never memorize, cast freely). Replaced by **validated memorize**: the server tracks the letters each player has consumed, a new remote carries the word on memorize, and the server validates it against [[systems/Dictionary]] and credits exact `EnergyEconomy.splitByColor` energy; `spec.cost` debited per accepted cast. Ships in **shadow mode** first (log the verdict, reject nothing) and flips to enforce once the friends playtest shows zero false positives. Own session: needs its own suite plus a playtest. Full design + rejected alternative in [[systems/SpellCastService]] § Validated memorize. |
| **Game page assets** | Icon, thumbnails, description. Remember [[concepts/RobloxOpenCloudAuth]] and the `rbxthumb://` requirement for Open Cloud decals. |
| **Analytics** | Added 2026-07-27 (from the persistence discussion): `AnalyticsService` onboarding funnel (join → first shoot → first memorize → first cast → first boss damage → boss kill) + custom loop-health events. Pulled into the gate because the soft launch exists to observe retention — unobservable without it. See [[design/persistence-progression]]. |
| **Rollout** | Unlisted link → friends checkpoint → public listing. The friends checkpoint after 5.1 feeds tuning and the shield/wall/buff design pass before they're built. |

**Sequencing:** 5.1 → friends-playtest checkpoint → 5.2 + hardening (parallel) → tutorial + tuning (5.3) → store assets → listing.

**Milestone:** a cold player (no instructions) completes shoot → memorize → cast → boss damage inside their first session, with no placeholder audio and no client-trusted remotes.

> The "no client-trusted remotes" half of this milestone is **not** met yet, and won't be by hardening alone: a client can still cast a spell it never earned the energy for. Whether that blocks the soft launch is a judgement call, but it should be a conscious decision rather than an assumption. See [[systems/SpellCastService]] § Validated memorize.
>
> **The judgement changed on 2026-08-10.** This was previously written off as "a self-cheat in a PvE game, not a way to grief other players". Phase 5.7 plans for PvP, and against other players a client casting spells it never spelled for is griefing, not self-cheating — and in a word game it makes the premise itself optional. That moves the item from *defensible to defer* toward *should ship*.

## Phase 5.5 — Persistence & progression (post-launch)

First phase after the soft launch. Decisions and rationale live in [[design/persistence-progression]] (2026-07-27): **mastery-first** progression — no session-to-session content gating; retention via personal bests and stats.

| Item | Detail |
|---|---|
| **PlayerData module** | ProfileStore (session locking) wrapped in a single server-side `PlayerData` module — the only file allowed to touch DataStores ([[concepts/SingleOwnership]]). Schema versioning + reconcile-with-defaults from day one. |
| **Settings persistence** | Input prefs, UI options. |
| **Word stats & personal bests** | Total words, highest-value word, longest word, best boss clear time, boss kills, total sessions — all from existing MemorizeAction/CastAction/Boss events. |
| **Cosmetics schema reservation** | `owned`/`equipped` slots in the profile template; **no cosmetic content in 5.5**. Future cosmetics are mastery-milestone-earned only, no Robux. |
| **PB surface in HUD** | Minimal personal-bests display (end-of-run summary vs. menu page — design pass at kickoff). |

**Explicitly out of 5.5:** leaderboards (OrderedDataStore — wait for soft-launch analytics), streaks/run history, spell/tier meta unlocks (rejected), cosmetics content.

**Milestone:** rejoin after a session and see settings + personal bests intact; a second-device login is safely locked out mid-session (ProfileStore session lock verified).

## Phase 5.6 — Client/server boundary (post-launch refactor)

Added 2026-08-04 after four consecutive VFX/SFX bugs traced to one root cause. Full audit, architecture and stage-by-stage plan in [[design/client-server-boundary]].

**The finding:** the caster's client runs the entire spell simulation (`CastAction` → `SpellExecutor` → `SkillDelivery`), and then the server runs it again from `SpellCastService`. Both VMs spawn projectiles, run hit detection, apply damage and write status. It is implicit client-side prediction with authoritative re-simulation that was never designed as one — no prediction layer, no reconciliation, no marker saying which run is which. The audit confirmed the duplication is confined to the Skills chain; `BlockShoot`, `LetterBlaster` and `BlockSpawner` all came back clean.

**The recommendation:** an explicit **authority / prediction / presentation** split, with server-only delivery as the destination and an explicit `mode: "authoritative" | "predicted"` field as the scaffold that gets there safely.

**Hitscan (noted 2026-08-04):** the original rationale leaned on "Brain Fighter has no hitscan, so prediction buys ~nothing". Hitscan spells are now expected later, which changes the cost of Stage 4 for those skills but **not** the architecture — it promotes Stage 6 from optional to required and makes it the prerequisite for shipping any zero-travel skill. Contract for a future `hitscan` delivery kind is in [[design/client-server-boundary]] § Zero-travel skills. The general rule: the shorter a skill's time-to-effect, the more of its feel depends on predicted presentation.

| Stage | Item | Ship window |
|---|---|---|
| 1 | ✅ **Done 2026-08-04.** `mode` field on `DeliveryCtx`, set once at each entry point. No behaviour change — nothing reads it yet and every `IsServer()` guard is untouched. `SpellExecutor.cast` takes it as a required 4th arg (no default: a default would let a new call site silently pick a side). `CastAction` → `"predicted"`, `SpellCastService` + `BossStates` → `"authoritative"`. Verified: Skills suite 4/4, SpellExecutor 11/11, clean boot. | Pre-launch safe (can fold into 5.3) |
| 2 | ✅ **Done 2026-08-04.** Delete `casterUserIdFrom`; `DeliveryCtx.predictedBy` set from fact at the entry point (`SpellCastService` knows which player fired the relay). `SpellExecutor.cast`'s 4th arg became a `RunContext` table. Two plan corrections recorded in the design page: `SkillVisuals` keeps `drawnLocallyBy` and its `IsServer()` branch until Stage 4 (its presentation-layer callers have no run context), and the `ProjectileVfxEvent` payload key `casterUserId` was renamed `predictedBy`. Verified by suites + a live client-side wire check. Two-client visual confirmation still outstanding. | Pre-launch safe |
| 3 | ✅ **Done 2026-08-04.** Damage/heal/freeze/knockup/shield/buff stop running twice. Gate sits in `SkillDelivery.applyImpactEffects`, not inside `SkillEffects` — the layer doing the writes shouldn't decide whether a write is allowed; its caller holds the run context. Verified by a direct A/B on one VM with mode as the only variable (predicted: nothing written; authoritative: health/WalkSpeed/`_frozen`/`_shield` all set). `CastAction/__tests` damage+heal assertions inverted to "predicted must not touch Health". | Post-launch |
| 4 | ✅ **Done 2026-08-04.** All four handlers now gate on `ctx.mode`; `SkillDelivery` calls `RunService:IsServer()` nowhere. Client-side Part + parallel hit detection deleted. **Trap handled:** with prediction drawing nothing, `predictedBy` had to stop excluding the caster or they'd see no shot at all — all `drawnLocallyBy` args and the payload's `predictedBy` removed. Verified client-side: predicted run spawns 0 parts; casting client now receives its own shot's payload. **Correction:** does NOT delete `SkillVisuals`' `IsServer()` branch (legitimate server-describes / client-draws split) and causes **no** cast-feel regression — see Stage 6. | Post-launch |
| 5 | ✅ **Done 2026-08-04 — moved ahead of Stage 3.** `SkillEffects.canApply` + `SkillDelivery.canDeliver` + `SpellExecutor.canCast` are pure predicates; `CastAction` checks before draining. Suite `cast_refund_on_failure` → `cast_rejected_before_drain`, asserting zero `EnergyReservoirs.changed` fires. **Ordering correction:** 5 had to precede 3 — Stage 3 makes predicted effects return `ok = true`, which is what the refund path read, so doing 3 first would have eaten mana on unresolvable casts. | Pre-launch safe |
| 6 | ✅ **Done 2026-08-04 — smaller than planned; the prediction layer already existed unnamed.** `VfxController` ← `CastAction.spellResolved` draws the caster's cast burst locally in 0.39 ms and survived Stage 4 untouched. Landed: the contract documented on the signal and the controller (may draw/sound/own-HUD; must not write another entity's state, resolve a victim, or show a hit marker), plus new suite `predicted_run_writes_nothing` — 4 spells cast twice, asserting predicted writes nothing AND authoritative writes everything, so the negative half can't pass vacuously. A predicted-endpoint argument was deliberately **not** added: no skill consumes one yet, and the hitscan contract is pinned in the design doc. | Post-launch |

**Not in scope:** the client-trusted affordability hole. That is a separate problem with a separate decided answer (the energy-ceiling ledger, Phase 5.4) and the two are compatible — the ledger prices casts at the remote boundary, which none of this changes.

**Survives untouched:** attribute-driven status visuals (`_shield`, `_frozen`), `VfxBroadcast`, the server-side refusals in `spawnEffect` / `FreezeVfx.start`, and server-owned gameplay objects like the Stone Wall slab.

**Milestone:** a two-client playtest shows exactly one projectile and one impact burst per cast on both screens, with no `RunService:IsServer()` guard remaining in `SkillVisuals`.

## Phase 5.7 — Tap-to-pop (retire the Spelling Staff) ✅ **Complete 2026-08-10**

Added 2026-08-10. Full plan in [[design/tap-to-pop]]. All six stages shipped the
same day: `be2b1a2`, `14881d9`, `3204b0d`, `08a2e5a`, `e5f72cc` + `1080233` +
`2139661`, `d4bcfc3` + `4cc0ab6`.

**The finding:** the Spelling Staff is a wrapper around "click the thing you want". There is no aiming skill, no reticle (by design), no ammo, no alternate fire, and nothing else in the game is shot. What it costs is a boot chain no other input has — `StarterPack` → `Backpack` → `Tool.Equipped` → `LetterBlaster:mount()` — which with `SHOW_BACKPACK = false` means core input in a shipped build depends on the *dev-only* `DevAutoEquipTool` firing. Plus a two-VM muzzle position, a Studio-managed `Muzzle` attachment outside the Rojo tree, and a fizzle `SoundId` duplicated into `.model.json`.

**The change:** click/tap a block directly and it pops. Input and presentation layers only — `ConsumeBlock`'s payload, `BlockShootValidation`'s three checks and the rate limiter's tuning source are all unchanged. ClickDetector was rejected: the word buffer is client-side, so a server-side `MouseClick` would destroy blocks the client had already refused to buffer.

| Stage | Item |
|---|---|
| 1 | Input moves off `Tool.Activated` to `UserInputService.InputBegan` (MouseButton1 + Touch) in `src/client/BlockTapController.client.luau`; tunables to `shared/BlockShoot/BlockTapConfig`. **`gameProcessedEvent` guard is the whole risk** — the mouse is free during play and the HUD is click-driven, so without it every spell button press also pops the block behind it. |
| 2 | Delete `StarterPack/Spelling Staff/`, `shared/LetterBlaster/`, `BlockShoot.muzzlePosition`/`resolveHandle`, `BlockShootService.broadcastShot`. Keep `laserBeamEffect` — NPC `Actions.luau` still uses it. |
| 3 | ✅ **Done 2026-08-10 — all three layers.** `block_pop_{red,green,blue,wild}` + `resolveBlockPopId`, new `VfxBroadcast.collect` kind, shared `collectStream` module drawn by both the popper (prediction) and every other client (broadcast). Flight is deliberately **longer** than the tap cooldown — overlapping streams read as "that player is banking fast", which is the tell; the concurrent cap (`PERF.maxBlockPops`, which already existed) bounds cost instead. Verified against a **moving** collector: endpoint-to-HRP gap 0.00 studs over 25 frames while the character travelled 19.2 studs. Motes landed after stage 4: 8 per stream on one shared Heartbeat driver, quadratic Bézier with the endpoint re-read per frame, thinned 8 → 3 under load and distance-culled, with the local player's own stream exempt. Measured 8 peak / 24 frames / 34 distinct sizes / 0.27-stud closest approach / 0 leaked. **Receive path since verified** — testable single-client precisely because the popper's stream is *not* drawn locally, so anything on a client came over the wire: a server-side `VfxBroadcast.collect` produced 1 anchor + 8 motes, and an absent `collectorUserId` produced nothing, no error, no orphaned anchor. Only "a stream aimed at *another* player" still wants a second client, and `resolveCollector` has no local-player branch. |
| 4 | ✅ **Done 2026-08-10.** Rejection reply on `ConsumeBlock` carrying a **client-minted request id, not the block** — echoing the block fails precisely in the case that matters, because losing a race means the winner already destroyed it and a destroyed Instance reference is the nil-arrival trap. Rollback via new `WordBuffer:removeLastMatching` (6 unit cases). Cosmetics split rather than both gated: the burst stays predicted (true either way — the block popped), the **stream** is drawn only from the server's confirmed branch, since attribution is a hit-marker-class claim the prediction layer may not assert. Verified live: `[N,Y,W,T]`, reject the older W → `[N,Y,T]`. |
| 5 | ✅ **Done 2026-08-10, and diverged from the plan twice.** *Reach*: raised 200 → 1400 chasing a "range is too short" report, then reverted to 200 once the real cause surfaced — `BlockTapController` paired `input.Position` with `ViewportPointToRay`, two coordinate spaces one GUI inset apart, tilting every ray 7.7° and capping effective reach at ~30 studs no matter what the constant said. An *angular* error grows with distance and is indistinguishable from a range cap by feel; the tell was that a 7× raise changed nothing. Fixed to `ScreenPointToRay`, verified against the engine's `Mouse.Hit` at 0.00 studs and by sweep (buggy pairing hit 0/40 on-screen blocks, fixed 18/40, rest genuinely occluded). No `TAP_REACH_STUDS` — reach stayed the single `MAX_RAYCAST_DISTANCE` everything already derives from, so `blockshoot_range_and_rate` needed no retune. *Glow*: shipped as **one** hover outline with three states, not a glow per in-range block — Roblox renders a bounded number of `Highlight` instances (~31) against 40 blocks, and the question is only ever about the block under the cursor. First build tinted the outline with the block's own colour and was invisible against it; every property assertion passed and only a screenshot caught it. |
| 6 | ✅ **Done 2026-08-10.** `LetterBlaster` → REMOVED record; `BlockShoot`/`LetterBlock`/`AudioSFX`/Tutorial updated. Plus one the plan missed: [[design/client-server-boundary]] carried a `LetterBlaster` row citing two deleted files. Plans, dated audits and changelog entries describing what was true when written were left as history. |

**Attribution is a PvP requirement, not juice.** The beam was the only thing linking a taker to a block for other players. The collect stream replaces it and reads better: the beam said where a shot came from, the stream says who got it and which colour they banked — deliberately leaking that read, because "red has been flowing into him for ten seconds" is a tactical tell worth having. Destination is a `collectorUserId` re-resolved per frame, not a baked Vector3: the collector is running during the stream's flight. Layered ribbon → motes → arrival flash so a busy fight degrades to ribbon-only rather than losing the cue exactly when it matters most.

**Deferred, not dropped:** a cosmetic hand-held prop. Hands are empty after this; a non-functional staff can come back as a separate silhouette/polish item with no input logic attached.

**Milestone:** two clients, empty hands, no hotbar. Pointing at a block says whether a tap will land — and greys out past reach — blocks pop on **both screens**, and a colour-matched stream funnels onto whoever took it while they run. Both tap the same block on the same frame → exactly one letter, exactly one stream. Server logs do not verify stage 3; a second client does, and it has to be a moving one. *All of this is verified except the two-client line itself; see the stage 3 row for what a single client was able to establish.*

## Phase 5.8 — Hold-to-charge tier selection ✅ **Complete 2026-08-12**

Added and shipped 2026-08-12. Full system page: [[systems/ChargeCast]].

**The finding:** the game has four spell tiers per colour and **no way for the player to choose one**. A tap fired whatever was currently affordable, so "save big, fire small" — the decision [[design/gameplay-loop]] § "Spell economy" is built around — was unreachable in-game. The design doc's answer was a drag-from-reservoir tier menu; it was never built, and by the time it came up for building the objection was that it costs a *mode*. A menu that opens over the arena hides the arena, in a game whose other two verbs are single taps.

**The change:** press a colour panel and the charge climbs through the tiers you can afford; release to fire what you reached. Mana *flows* at `SpellRegistry.MANA_FLOW_PER_SEC`, so `chargeTimeFor(tier) = (cost − T1 cost) / flow` and there is no second tuning table — T4 costs 8× a Firebolt and therefore takes 8× as long to pour in.

| Chunk | Item |
|---|---|
| 1 | ✅ **Charge state machine.** `SpellRegistry.chargeTimeFor` / `tierCount` / exported `TIER_COSTS`; `CastAction.resolveSpecAtCharge` (pure, clamps at the affordability ceiling, nil below T1); `SpellMenuBuilder` swaps `MouseButton1Click` for the `BufferDisplayBuilder` press/release idiom plus a Heartbeat live only while held. `castRequested` **changed signature** to `(color, tier)`. |
| 2 | ✅ **Reservoir panel rework.** Tier notches at `TIER_COSTS[t] / FILL_MAX` (count from `tierCount`, so green gets three not four), desaturate-below-T1 off the **existing** `wasAffordable` edge flag, persistent numeral replacing the transient tap popup, charge reserve band + counting-down numeral, active-notch highlight, ceiling pulse, and `playFiredFlash` — written since Phase 4 and never called — finally wired. |
| 3 | ✅ **Charge orb over the character, for all players.** New `StatusVisuals/ChargeOrbVfx` + `client/Vfx/ChargeOrbController` + `_chargeColor`/`_chargeTier` attributes + `ChargeState` remote + `server/SpellCast/ChargeStateService`. The existing VFX lane could not do this: `spawnEffect` returns nothing and bakes its duration at author time, so there is no handle to grow or stop. Attribute-driven like `_shield`, which is what makes "everyone sees it" nearly free. |
| 4 | ✅ **Mana motes flowing into the orb.** `charge_motes_{red,green,blue}` + `resolveChargeMotesId`; convergence math lifted from `collectStream`, ring source, orb destination. The project's **only sustained emitter** — budgeted explicitly (6 halos / 48 mote Parts) rather than leaning on `PERF.maxEmitters`. |
| 5 | ✅ **Trust, tests, wiki.** No new trust hole — the client already picked the tier and the server already prices it. What the server *cannot* verify is hold duration, now recorded in [[systems/SpellCastService]] § "Not checked: hold duration" rather than left implied. Six new `CastAction/__tests` scenarios (15 total). |

**Reserve, spend on release** was the decision that kept the blast radius small. Nothing is drained while the charge is held; `castSpecific` drains exactly one tier cost on release. So cancelling is free, there is no refund path to get wrong, and [[systems/EnergyReservoirs]] needed **zero changes** — its `:drain` is all-or-nothing by contract, and a reservation model would have meant inventing a second, partial one.

**Milestone:** a quick tap is a Firebolt and a held press is a Volley, the panel shows which notch you are at and what it will cost, and a second player can see the orb over your head grow and pop. Verified live in Studio: 15/15 tests, tier clamping at the ceiling on a thin reservoir, a cancelled charge leaving the reservoir untouched, the grey→saturated flip landing exactly on the T2 notch, an orb rendered **from the Client datamodel** on a rig the local player does not own, and zero orphans after 20 charge cycles. *Owed:* the feel check — whether a 1.75 s T4 hold reads as commitment or as lag. `MANA_FLOW_PER_SEC` is expected to move.

> **Since shipped:** the panels in chunk 2 are no longer vertical bars. They are circles that fill from the centre, with the tier notches as concentric rings; the spell name moved off the panel and onto a label over the charge orb. And the feel check owed above has had its first pass — `MANA_FLOW_PER_SEC` went **20 → 5**, so a T4 is a 7 s hold rather than 1.75 s. See the follow-up entries in the changelog below, [[systems/ChargeCast]] § The charge model and § The name label.

## Phase 6 — Lobby & mode selection

Added 2026-08-20. Full plan in [[design/lobby]]. Prompted by the decision to add a PvP mode.

**The finding:** a welcome lobby reads like UI work and isn't. Mode choice is a **session-container** problem — `GameModeService` + `RoundManager` are a server-wide singleton (one round, one mode, everybody in it), `Modes/init.luau` registers only `NoOp` since `6610291`, and `BlockSpawner` pools every tagged `BlockSpawnVolume` globally. There is no way to express "these three are fighting the boss and those two are duelling". The menu is the cheap part.

**The decision:** a **hub place with in-place arena zones** — one `.rbxl`, lobby zone plus arena zones in the same server. Multi-place + `TeleportService` was rejected on a hard dependency, not on taste: cross-place identity needs [[design/persistence-progression]], which is Phase 5.5 and unbuilt, so a teleported player arrives with nothing — and it splits a pre-launch population across places, making a 1v1 queue unfillable. A whole-server mode vote (no hub, lobby as `RoundManager.Waiting`) was rejected for making PvE hostage to PvP: a solo player in an empty server could never start anything. Outgrowing the hub later changes *where a session lives*, not *what a session is*.

**Shape:** PvE is **co-op** — one boss arena, `minPlayers = 1`, everyone queued at round start goes in together, so a lone player never waits. PvP is **1v1 duels on a pool of authored pads** (2 for v1; the pad count *is* the concurrency limit). Selection is **diegetic portals with live queue counts**, not a menu screen — same argument that reshaped [[systems/ChargeCast]]: a menu costs a mode in a game whose verbs are all single taps.

| Stage | Item | Gate |
|---|---|---|
| 1 | ✅ **Done 2026-08-20 (`b38a99c`).** `RoundManager.new(deps)` with `arenaId` + roster + `:disable()`/`:destroy()`; `GameModeService` owns `sessions[arenaId]` + `playerSessions[player]`. Per-roster `FireClient` landed with it. `task.cancel` **removed** rather than kept — the old `stop()` never cleared `roundThread` on natural exit, so a second `stop()` would have thrown; a `_generation` counter covers the overlap case. Verified by a client-side listener + a two-session disjoint-roster cross-talk test. | — |
| 2 | **Arena binding.** `ArenaId` on `BlockSpawnVolume` + per-arena block pools; `LobbySpawn` / `PvEArenaSpawn` / `PvPArenaSpawn` tags. `SpawnManager.filterSpawnsForPlayer` already resolves by tag, so this is data. | — |
| 3 | **Broadcast audience** *(added 2026-08-20)*. Six HUD sites: `ScoreTracker`'s `ScoreUpdate` + `KillFeed` ×2, `BossService`'s `BossHealthChanged` ×3 / `BossPhaseChanged` ×2. Copy stage 1's roster pattern. VFX lane out of scope — see [[design/lobby]] § Broadcast audience. | Before stage 6 |
| 4 | **Hub greybox + player state.** Lobby zone, two portals, practice blocks, `InLobby/Queued/InArena` and the HUD suppression table. Still `NoOp` behind the portals. | — |
| 5 | **PvE mode.** `Modes/PvEBoss.luau` — co-op, objective win condition, boss arena slot. | — |
| 6 | **PvP duel.** `Modes/PvPDuel.luau` — exactly 2, pad pool, `PLAYER_VS_PLAYER_ENABLED = true`, timer + countdown back on. | **After 5.4** |
| 7 | **Wiki + tests.** `wiki/systems/Lobby.md`, rewrite the NoOp-only [[systems/GameMode]] record, session lifecycle tests. | — |

**The lobby does not unblock PvP, and shipping it must not be mistaken for shipping PvP.** Three live blockers, recorded in full in [[design/lobby]] § What this does *not* unblock:

- **`PLAYER_VS_PLAYER_ENABLED` does not gate the damage path players actually use.** It gates `applyDamage.process`; spells write `Humanoid.Health` directly. Flipping it changes nothing for spells. Deferred in 5.1 as "unify when 5.4 hardening moves casting server-side" — that debt comes due here.
- **Client-trusted affordability** (5.4 validated memorize). Already re-judged on 2026-08-10 for exactly this reason; in a 1v1 it is the most visible cheat there is.
- **`ROUND_TIMER_ENABLED` / `ROUND_COUNTDOWN_ENABLED` are both `false`.** A duel with no clock does not end.

Hence the gate column: stages 1–5 are safe against the current trust model (PvE co-op cheating is self-cheating); stage 6 lands after Phase 5.4.

**Interface change:** `GameModeDefinition` is kill-centric (`onPlayerKill`, `scoreLimit`, `checkWinCondition` over kills/deaths/assists). That fits a duel nearly unchanged and a boss fight badly — add an objective-shaped win condition rather than modelling "the boss died" as a player kill.

**Milestone:** two clients join, land in the lobby with no combat HUD, pop a practice block, and walk to different portals. One fights the boss solo while the other waits at a full duel pad **and can see why**. Both return to the lobby when their round ends, and the server never had more than one session per slot.

**Open:** mid-round leave/forfeit rules, duel disconnect handling, spectating. The progression board is deferred to Phase 5.5 — leave wall space.

## Plan changelog

- **2026-08-20** (follow-up): Phase 6 stage 1 shipped (`b38a99c`) and **the plan gained a stage**. Auditing the remaining `FireAllClients` sites after the refactor found eleven, not the one `RoundManager` owned — so the broadcast audience was a *class* of bug the original stage table had mistaken for a detail. New stage 3 covers the six that matter; hub/PvE/duel/wiki renumbered 3–6 → 4–7 (stages 1 and 2 unmoved). The useful split turned out not to be by system but by **what the consumer does with the payload**: HUD remotes (`BossHealthChanged`/`BossPhaseChanged`/`ScoreUpdate`/`KillFeed`) are screen-space and genuinely break — a duellist would get the boss's health bar — while the VFX lane (`VfxBroadcast`, `SkillDelivery`, boss windup) is world-positioned, so a player in another arena never sees it and only pays to instantiate it. That half stays with [[systems/VisualEffects]]' existing `PERF` guardrails rather than gaining a roster lookup on the hottest path in the game. Stage 1 also diverged once: `task.cancel` was removed, not preserved — the old `stop()` never cleared `roundThread` on natural exit, so a second `stop()` would have thrown.

- **2026-08-20**: Phase 6 added — lobby & mode selection ([[design/lobby]]). Planning the PvP mode surfaced that the welcome lobby is a session-container refactor, not UI: `RoundManager`/`GameModeService` are a server-wide singleton and `BlockSpawner` pools all volumes globally, so no two groups of players can be in different modes at once. Decided: hub place with in-place arena zones (multi-place blocked on unbuilt 5.5 persistence; whole-server vote makes PvE hostage to PvP), co-op queued PvE so solo players never wait, 1v1 duels on a 2-pad pool, diegetic portals over a menu screen. Also pinned the thing most likely to be assumed away: **`PLAYER_VS_PLAYER_ENABLED` does not gate spell damage** — spells bypass `applyDamage` entirely, so the 5.1 split-brain deferral is a Phase 6 prerequisite, alongside 5.4's client-trusted affordability and the two disabled round-timing flags. Stage 5 is explicitly gated behind 5.4; stages 1–4 are not.

- **2026-08-12** (follow-up): the 5.8 cast panels **became circles**. Mana fills a disc outward from the centre, the tier thresholds are concentric rings, the reserve is an annulus off the fill's outer edge, and the ceiling pulse is a rim halo. The argument is affordance, not decoration: a bar reads as a meter you watch, which was right while a tap fired whatever you could afford, and press-and-hold needs a panel that reads as something you push and keep pushing. It also matches the DASH button below it in the same column, already a circle, and echoes the charge orb. Costs: the spell name is gone (no room in a disc — a *second* bite out of the legend problem 5.8 already took one out of, and the replacement idea is filed in [[ideas]] with its weakness recorded), and under `FILL_RADIUS_EXPONENT = 1` the disc looks emptier than its numeral says while the T1/T2 rings are small enough to sit under it. That exponent is one lever with two documented settings; which reads better is a feel question. The arc gauge that would keep linear encoding *and* readable tick spacing is filed rather than built — Roblox has no radial fill, so it needs the two-half rotation mask, where the disc is nearly free.

- **2026-08-12**: Phase 5.8 added **and complete** — hold-to-charge tier selection ([[systems/ChargeCast]]). Supersedes the drag-from-reservoir tier menu that [[design/gameplay-loop]] has specified since the first design pass and that was never built: it costs a mode, and hiding the arena behind a panel to pick a tier is the wrong trade in a game whose other verbs are single taps. What is genuinely lost is the menu's *legend* — it named every tier and its price, and a hold does not; notches, a reserve band and a persistent numeral are weaker at teaching that to a first-time player, and the tutorial will have to carry it. Two secondary problems fixed alongside: a 0–60 reservoir bar moved 8% for a whole T1 cast (notches + saturate-at-castable), and there was no mid-charge feedback anywhere (reserve band, numeral, ceiling pulse, orb). The orb is deliberately a PvP tell — the same information leak as the collect stream in Phase 5.7.

- **2026-08-10**: Phase 5.7 **complete**, with two documented divergences. The planned in-range glow became a single hover outline (Highlight render budget, and the question is only ever about the block under the cursor). Reach was raised 7× and reverted to LetterBlaster's original 200 once the "range is too short" report turned out to be a screen/viewport coordinate mismatch capping effective reach at ~30 studs — a raise that changes nothing a player can feel is evidence about the cause, not an argument for raising further. Also closed the two-client verification carried since Phase 5.6, as far as one client can: the receive path is confirmed, a stream aimed at another player is not.
- **2026-08-10**: Phase 5.4's energy-ceiling ledger **redesigned into validated memorize** before any of it was built. The ledger's bound is informationally weak rather than badly tuned — `LENGTH_MULTIPLIER_EPIC` is the smallest multiplier that cannot reject real play, so the bound is already as tight as its inputs allow, and it still saturates at the 60 cap within ~8 s of shooting. The reframe: the useful question is whether the server ever learns a word was spelled. Validated memorize answers yes for roughly 2× the work, closes the shoot-but-never-spell cheat, hands Phase 5.5 the word its personal-best stats need, and is a stepping stone to a full authoritative economy rather than throwaway work. Ships in shadow mode first. Two couplings to Phase 5.7: the consume-rejection rollback from stage 4 keeps the client buffer and the server held-set in sync by construction, and PvP promotes this from a self-cheat to griefing — see [[systems/SpellCastService]].
- **2026-08-10**: Phase 5.7 amended for PvP — collect stream added as the replacement attribution cue (new `VfxBroadcast.collect` kind, userId destination so it tracks a running collector), and a new Stage 4 for contested blocks. Planning PvP surfaced a latent bug: the `WordBuffer` append is optimistic and unacknowledged, so the loser of a same-frame race for a block keeps a phantom letter for the round. Present in the current staff build; unreachable in solo play. Stage count 5 → 6.
- **2026-08-10**: Phase 5.7 added — tap-to-pop ([[design/tap-to-pop]]). Retires the Spelling Staff Tool and `LetterBlaster` in favour of direct click/tap on blocks, with a client-local in-range glow so the reach limit is legible. Input + presentation only; the `ConsumeBlock` trust surface is untouched. Cosmetic hand prop deferred.
- **2026-08-04**: Phase 5.6 added — client/server boundary refactor ([[design/client-server-boundary]]). Root-cause follow-up to the four VFX replication bugs; audit found the dual-VM simulation is confined to the Skills chain. Six stages, each independently shippable; stages 1–2 are pre-launch safe, 3–5 post-launch. Recommendation: server-only delivery as the destination, explicit `mode` field as the scaffold.
- **2026-08-03**: Phase 5.2 shield/wall/buff design pass + implementation landed. `shield` (40 HP absorb pool, no expiry, reusing Health's `_shield` modifier) and `buff` (timed `damageAmp`, first consumer Stasis) are real; `wall` deleted as a decoy handler; Stone Wall implemented as a server-only collidable barrier via `world_spawn`; Sanctuary restored to heal + shield; self-target identification moved from a colour heuristic to `SpellRegistry.selfTarget` / `needsEnemyTarget`, and the cast relay extended to target-less casts. 5.2 remains open on SFX assets + VFX gaps. Placement reticle and shield HUD explicitly deferred to 5.3.
- **2026-07-27**: Phase 5.1 complete — Skills leak fix (Died/HealthChanged/Destroying purge), stub-spell refunds (`unimplemented` failures incl. `world_spawn`), damage-path split documented (unify in 5.4), Skills test suite added (4/4 in playtest). Sanctuary temporarily heal-only. Next: friends-playtest checkpoint, then 5.2 + hardening.
- **2026-07-27**: Persistence & progression decided ([[design/persistence-progression]]) — mastery-first, ProfileStore-backed PlayerData, added as Phase 5.5 (first post-launch). One change to the 5.4 bar: AnalyticsService funnel + custom events pulled into the release gate so the soft launch can measure retention.
- **2026-07-27**: Release bar set — public soft launch. Added Phase 5.4 (release gate): server trust hardening un-deferred, game page assets added, rollout sequence pinned (5.1 → friends checkpoint → 5.2 + hardening → tutorial/tuning → listing). R-5..R-9 and Tier 3 debt explicitly excluded from the bar.
- **2026-07-15**: Phase 5 split into 5.1 (correctness sprint: Skills leak, stub-spell refund, damage-path unification), 5.2 (content: shield/wall/buff, real SFX, VFX gaps), 5.3 (tuning, UI R-5..R-9, tutorial). Server trust hardening explicitly deferred. Audit items re-verified live against `src/` before scheduling.
- **2026-06-05**: Phase 4.8 (UI architecture review) re-audited + complete — R-1..R-4 cleanup landed and verified by playtest; GO for Phase 5. R-5..R-9 (2 Medium / 3 Low) deferred.
- **2026-06-05**: Phase 4.7 (letter slot drag/tap-to-swap) confirmed complete — both interactions implemented in `BufferDisplayBuilder.luau`, mouse + touch supported.
- **2026-05-20**: added Phase 4.8 (UI architecture review) as a gate before Phase 5 polish.
- **2026-05-20**: HUD coordinator refactor landed — `PlayerHud` is now a ModuleScript; `GameplayHudGui` is the sole BottomCenter coordinator with a single `LAYOUT` table.
- **2026-05-15**: added Phase 4.7 (letter slot drag/tap-to-swap reorder).
- **2026-05-15**: added Phase 4.5 (bug sprint) and Phase 4.6 (LetterBlaster Tool) between Phase 4 and Phase 5.
- **2026-05-14**: initial plan written; 18 trackers created; Phase 1 spawn batch (Dictionary, EnergyEconomy, SpellRegistry) kicked off.
