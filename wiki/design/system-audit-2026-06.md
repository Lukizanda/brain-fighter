---
type: design
description: Whole-repo architecture & tech-debt audit (2026-06-05) — template-era dormancy, Skills-layer liabilities, prioritized cleanup runway. Pick-up point for next session.
updated: 2026-06-05
---

# System Architecture Audit — 2026-06-05

Whole-repo audit (template-era + active gameplay), **architecture & tech-debt lens** (not a runtime-bug hunt). Run via three parallel domain auditors (gameplay chain / world+combat / template-era+core); the highest-impact and all deletion-recommending claims were hand-verified before recording. HUD was excluded — covered separately in [[design/ui-architecture-review]] (Phase 4.8).

## Headline

The **active Brain Fighter code** (spelling-combat chain) is in good shape: clean strictly-downstream data flow, single ownership respected, strong `:destroy()` coverage, well-tested upstream modules. Debt concentrates in two places: **inherited TPS-template dead weight** (~half the repo, dormant behind `GameConfig` flags) and the **`Skills/` layer** (untested, leaky, magic-number-heavy). Phase 5 is **not blocked**.

## Verified facts (spot-checked, not just agent claims)

- `GameConfig.luau`: `TEAMS_ENABLED=false`, `PLAYER_VS_PLAYER_ENABLED=false`, `ROUND_TIMER_ENABLED=false`, `ROUND_COUNTDOWN_ENABLED=false`, `TPS_CHARACTER_ENABLED=false`. → the template-dormancy finding holds.
- `SkillEffects._freezeState`, `SkillInterrupt._active`/`_silenced` are module-level Humanoid-keyed tables nil'd **only** by timer/finish paths — zero `Destroying`/`Died`/`AncestryChanged` cleanup. → leak is real.
- `shared/BossAdapter/init.luau` still syncs and is required by 3 Phase3 suites (`bossadapter_*`) + `server/BossAdapter/BossService.server.luau.disabled`. → two boss codebases.
- `shared/Weapon/CameraWeaponIntegrationGuide.luau` ends in `return {}` (prose guide as a runtime ModuleScript). → doc-as-code, trivial delete.

## Template-era reachability table

A single `GameConfig` flag block switches off the inherited TPS shooter. Status of each template system in the **shipped** (Spelling-Staff) build:

| System | Status | Evidence |
|---|---|---|
| Core (Logger / Cleanup / InputCategorizer / GameConfig) | **USED** | required across client/server/shared |
| Character/DashController | **USED** | active; drives Brain Fighter dash + mobile DASH button |
| Health (HealthService init/respawn/death events) | **USED** | boss attacks route through `applyDamage.process` |
| NPC (NPCService + StateMachine + Patroller) | **USED** | StateMachine also reused by `Boss/BossController` |
| Weapon/MeleeHitDetector | **USED** | reused by `NPC/Actions` |
| Character/CameraController (~446 L) | **VESTIGIAL** | gated by `TPS_CHARACTER_ENABLED=false` |
| Character/LocomotionController (~547 L) | **VESTIGIAL** | same gate; sole Motor6D/AutoRotate/AlignOrientation writer — never runs |
| Weapon firearm stack (Firearm/Weapon/Ammo/AimAssist/Blaster) | **VESTIGIAL** | reached only via `Templates/{Pistol,Rifle,LaserPistol}` clients not in StarterPack |
| Weapon player-melee swing (MeleeSwingController) | **VESTIGIAL** | only via `Templates/Sword` client, not in StarterPack |
| GameMode FFA/TDM modes + TeamService | **VESTIGIAL** | not registered; only `NoOpMode` runs (but RoundManager/ScoreTracker/SpawnManager still tick) |
| Loadout (LoadoutService/PickupStacker/Respawn*Manager) | **VESTIGIAL** | Spelling Staff has no `CATEGORY_ATTRIBUTE` → all handlers short-circuit |

Carrying cost: type-check + sync weight, and no-op `.server` scripts (`LoadoutService`, `GameModeService`) still wire per-player `ChildAdded`/`AncestryChanged` every spawn for features the build never uses.

## Tier 1 — Real liabilities (fix soon)

1. **[H] Per-Humanoid state leak in `Skills/`** — `SkillEffects._freezeState` + `SkillInterrupt._active`/`_silenced` keyed by live Humanoids, cleaned only on timer/finish. A frozen/casting character that dies/despawns/leaves before its timer fires leaks the entry forever (dead-reference accrual; reused-instance correctness risk). **Fix:** one-shot `Humanoid.Died`/`Destroying` cleanup purging both registries. Effort **S–M**. Files: `src/shared/Skills/SkillEffects.luau:53,104-124`, `src/shared/Skills/SkillInterrupt.luau:26,33`.

2. **[H] BossAdapter half-retired — two boss codebases** — `server/Boss/` is the real system; `shared/BossAdapter/` still ships to clients and is exercised by Phase3 tests + a `.disabled` script. **Fix:** delete `shared/BossAdapter/` + the 4 `bossadapter_*` Phase3 tests + `server/BossAdapter/BossService.server.luau.disabled`, update [[systems/BossAdapter]]; or document why it stays. Effort **S**.

3. **[M, correctness] Split-brain damage path** — `SkillEffects` writes `Humanoid.Health` directly for spell damage but routes boss attacks through `applyDamage.process`, bypassing `DamageModifierRegistry`, `getHitZone`, and the `PlayerDamaged` event (UI/GameMode feedback sees a subset). **Fix:** funnel all damage through `applyDamage`, or document hit-zones as firearm-only. Effort **M**. File: `src/shared/Skills/SkillEffects.luau:74-87`.

4. **[M] Server trust gaps** — `ConsumeBlock` (`server/BlockShoot/BlockShootService.server.luau:21-32`) and `SpellCastServer` accept client input with no range/ownership/rate validation; WordBuffer append is client-only. Conscious decision needed if anti-cheat matters near-term. Effort **M**.

## Tier 2 — Quick wins (cheap, verified-safe)

- **Doc-as-code:** `shared/Weapon/CameraWeaponIntegrationGuide.luau` (`return {}`) → move to `wiki/`, delete the `.luau`.
- **Duplicate Spelling Staff script:** `shared/Weapon/Templates/Spelling Staff/Scripts/SpellingStaff.client.luau` differs from the live StarterPack copy only by a comment → delete the dead Templates copy.
- **`LetterBlocks/init.luau` missing `--!strict`** — the one block-creation module running nonstrict.
- **Malformed pragmas:** `CameraController.luau:1` has `----!nocheck` (four dashes = inert comment, file runs nonstrict); `WeaponController.luau:1` + `WeaponAnimationController.luau:1` use forbidden `--!nocheck` (only worth fixing if firearm stack is kept).
- **DevDebug stale header:** `DevDebug.client.luau` documents a `;` boss-phase-label binding with no matching handler case. (Note: a `;` binding was later re-described in [[concepts/DevDebugHotkeys]] — reconcile doc vs handler.)

## Tier 3 — Pervasive secondary debt

- **Color/`Color` type duplicated ×4** — `{red,green,blue}` + validation + `export type Color` live independently in `WordBuffer`, `EnergyEconomy`, `EnergyReservoirs`, `SpellRegistry`. Promote one `shared/Spelling/Colors.luau` (or reuse the already-exported `EnergyReservoirs.COLORS`).
- **Magic numbers** — codebase names constants carefully *except* `SkillEffects`/`SkillDelivery` (freeze/knockup/projectile/aoe defaults), `SpellRegistry` T4 Volley + green/blue spec tuning, and `Vfx` (placeholder `rbxassetid://0` ×6, `spawnEffect` `0.5`/`+0.1`, BossStates `or 4`). Inconsistent with the project's own No-Magic-Numbers rule.
- **`Skills/` layer has zero `__tests`** — the most side-effecting code (freeze, interrupt, splash) is the least tested while every upstream pure module has tests. `SkillInterrupt` is trivially unit-testable (token cancel/finish/silence).
- **Lifecycle convention drift** — `FreezeVfx`, `VfxController`, `SkillDelivery` allocate state/connections without `:destroy()`/`:disable()`/flush APIs (mostly session-lived → low practical risk).
- **`(bb :: any)` casting** throughout the Boss AI path defeats strict typing on the hottest loop (`BossStates.luau` ~30 sites).
- **Dead config field** `SpellRegistry … damageAmpMultiplier` (Stasis) — never read by any handler.
- **Silent `ok=true` stubs** — `shield`/`buff`/`wall` SkillEffects handlers no-op but return success → CastAction drains mana with no effect and no refund. Make them `ok=false, reason="unimplemented"` so CastAction refunds, or implement.

## Strategic decision (highest leverage)

**Commit to the template or cut it.** It's currently in limbo — gated off but fully present. Clean paths:
- **Cut:** delete firearm stack, FFA/TDM, TeamService, Loadout, Camera/Locomotion controllers → repo shrinks ~40%, faster type-check/sync, clearer mental model.
- **Keep for future PvP:** move it all under a clearly-marked `Legacy/` folder excluded from default sync, with a one-line re-enable README.

Leaving it inline is the only bad option. This decision gates how much Tier 3 is even worth doing.

⚠️ **Forward trap:** if `TPS_CHARACTER_ENABLED` is ever flipped on, `LocomotionController`'s WalkSpeed writes (`:118,:327,:387`) will collide with `SkillEffects` freeze (`WalkSpeed=0`, `:125`) — a single-ownership fight. Resolve ownership before re-enabling TPS.

## Recommended next-session order

1. **Tier 2 quick wins** (low-risk verified deletions/fixes) — fast signal-to-noise.
2. **Template keep-or-cut decision** (the strategic call) — gates Tier 3 scope.
3. **Tier 1 #1 (Skills leak)** + **#2 (BossAdapter retirement)** — the two real liabilities.
4. Tier 3 as Phase 5 polish surfaces touch each area.

Notes: not yet turned into trackers; no code changed this session (assessment only). When acting, re-verify against current `src/` per the memory-freshness rule.
