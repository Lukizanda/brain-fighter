---
type: design
description: Phased build plan for Brain Fighter's core gameplay systems — construction order, parallel vs sequential dependencies, parallel-session strategy
updated: 2026-08-03
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
| **Energy-ceiling ledger** | Added 2026-08-03 as the follow-up to the item above. Server tracks an upper bound on the energy each player could possibly have earned, credited from the `ConsumeBlock` traffic it already sees and debited on each accepted cast; rejects casts that exceed it. One-sided by construction so it can never reject legitimate play. Needs no change to [[systems/EnergyReservoirs]] or [[systems/SpellRegistry]] — `EnergyEconomy.letterValue` and `.lengthMultiplier` are already public. Own session: the bound has to be provably generous, so it wants its own suite plus a playtest. |
| **Game page assets** | Icon, thumbnails, description. Remember [[concepts/RobloxOpenCloudAuth]] and the `rbxthumb://` requirement for Open Cloud decals. |
| **Analytics** | Added 2026-07-27 (from the persistence discussion): `AnalyticsService` onboarding funnel (join → first shoot → first memorize → first cast → first boss damage → boss kill) + custom loop-health events. Pulled into the gate because the soft launch exists to observe retention — unobservable without it. See [[design/persistence-progression]]. |
| **Rollout** | Unlisted link → friends checkpoint → public listing. The friends checkpoint after 5.1 feeds tuning and the shield/wall/buff design pass before they're built. |

**Sequencing:** 5.1 → friends-playtest checkpoint → 5.2 + hardening (parallel) → tutorial + tuning (5.3) → store assets → listing.

**Milestone:** a cold player (no instructions) completes shoot → memorize → cast → boss damage inside their first session, with no placeholder audio and no client-trusted remotes.

> The "no client-trusted remotes" half of this milestone is **not** met yet, and won't be by hardening alone: a client can still cast a spell it never earned the energy for. Whether that blocks the soft launch is a judgement call — it's a self-cheat in a PvE game, not a way to grief other players — but it should be a conscious decision rather than an assumption. See [[systems/SpellCastService]] § Blocked.

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

**The recommendation:** an explicit **authority / prediction / presentation** split, with server-only delivery as the destination and an explicit `mode: "authoritative" | "predicted"` field as the scaffold that gets there safely. Viable because Brain Fighter has no hitscan — every offensive spell is a travelling projectile or a windup AoE, so prediction buys ~nothing.

| Stage | Item | Ship window |
|---|---|---|
| 1 | ✅ **Done 2026-08-04.** `mode` field on `DeliveryCtx`, set once at each entry point. No behaviour change — nothing reads it yet and every `IsServer()` guard is untouched. `SpellExecutor.cast` takes it as a required 4th arg (no default: a default would let a new call site silently pick a side). `CastAction` → `"predicted"`, `SpellCastService` + `BossStates` → `"authoritative"`. Verified: Skills suite 4/4, SpellExecutor 11/11, clean boot. | Pre-launch safe (can fold into 5.3) |
| 2 | ✅ **Done 2026-08-04.** Delete `casterUserIdFrom`; `DeliveryCtx.predictedBy` set from fact at the entry point (`SpellCastService` knows which player fired the relay). `SpellExecutor.cast`'s 4th arg became a `RunContext` table. Two plan corrections recorded in the design page: `SkillVisuals` keeps `drawnLocallyBy` and its `IsServer()` branch until Stage 4 (its presentation-layer callers have no run context), and the `ProjectileVfxEvent` payload key `casterUserId` was renamed `predictedBy`. Verified by suites + a live client-side wire check. Two-client visual confirmation still outstanding. | Pre-launch safe |
| 3 | `SkillEffects` / `SkillBuffs` early-return on `predicted` — damage/freeze/shield stop running twice. | Post-launch |
| 4 | `projectile` / `aoe` early-return on `predicted` (as `world_spawn` already does). Collapses the invisible-server-shot split; deletes the `IsServer()` branches in `SkillVisuals`. **The one stage that can regress feel** — needs a friends checkpoint. | Post-launch |
| 5 | Replace refund-on-failure with validate-before-drain. Every current `ok = false` reason is statically knowable from `(spec, target)`. | Post-launch |
| 6 | *Optional* — deliberate predicted cast feedback (muzzle flash / SFX / HUD drain only), if Stage 4 latency reads poorly. | Post-launch, only if needed |

**Not in scope:** the client-trusted affordability hole. That is a separate problem with a separate decided answer (the energy-ceiling ledger, Phase 5.4) and the two are compatible — the ledger prices casts at the remote boundary, which none of this changes.

**Survives untouched:** attribute-driven status visuals (`_shield`, `_frozen`), `VfxBroadcast`, the server-side refusals in `spawnEffect` / `FreezeVfx.start`, and server-owned gameplay objects like the Stone Wall slab.

**Milestone:** a two-client playtest shows exactly one projectile and one impact burst per cast on both screens, with no `RunService:IsServer()` guard remaining in `SkillVisuals`.

## Plan changelog

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
