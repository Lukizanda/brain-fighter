---
type: design
description: Phase 4.8 — pre-Phase-5 UI architecture audit; findings, severity, go/no-go.
updated: 2026-05-20
---

# UI Architecture Review — Phase 4.8

Pre-Phase-5 audit of the client UI layer against the six review questions in [[design/build-plan]] Phase 4.8 (modularity, single-ownership, Builder/Config compliance, lifecycle, dead code, coupling).

The full layout & data-flow diagram is on the system page: [[systems/HUD]] § System diagram.

## Summary

- **Files audited:** 39 (14 `src/client/UI/*.client.luau` + 5 `src/client/PlayerHud/**` + 22 `src/shared/Hud/*.luau` + 2 sibling `src/client/*.client.luau` that register with `HudLayoutManager`)
- **Findings:** H = 1, M = 6, L = 4
- **Phase 5 gate: GO.** The single High is isolated and doesn't intersect Phase 5 polish (tuning, audio, particles, tutorial). One tracker opened. Recommended to land H-1 + M-1 + M-2 as a small cleanup pass before Phase 5 work begins.

## Pass/fail per dimension

| # | Dimension | Result | Note |
|---|---|---|---|
| 1 | Single ownership | **CLEAN** | No double-writes on Frames / LayoutOrder. Coordinator owns top-level LayoutOrder (`GameplayHudGui.client.luau:49-51`); Builders own internal LayoutOrder of their own children. |
| 2 | Coordinator clarity | **PASS (with documented exception)** | `GameplayHudGui` is the sole **stable** BottomCenter coordinator. `LoadoutDropClient` registers a transient toast stack — see L-1. |
| 3 | Builder/Config compliance | **MIXED** | 11/11 Builders pair with a Config. 8 LocalScripts build UI inline (M-3). One Builder has inline interaction constants (M-1). One key duplicated across Builder + Config (L-3). |
| 4 | Lifecycle completeness | **CLEAN** | All 11 Builders in `shared/Hud/` expose `:destroy()`. All 3 PlayerHud adapters expose `:destroy()`. `PlayerSession.destroy()` exists. |
| 5 | Dead code | **MIXED** | `ReservoirBarsBuilder` + `ReservoirBarsConfig` unused — see M-2. `BuffTrayGui` is a scaffold awaiting adapter wiring (documented inline, acceptable). |
| 6 | Coupling | **MIXED** | One Builder reads `Players.LocalPlayer` (H-1). `HudLayoutManager` legitimately needs it to parent the ScreenGui (only place this is acceptable). `_G.PlayerHud.*` writes from 4 client scripts; no reads from shared/Hud (L-2). |

## Findings

### F-1  [H] Coupling — `SettingsMenuBuilder` reads `Players.LocalPlayer`

- Location: `src/shared/Hud/SettingsMenuBuilder.luau:44, :71`
- Observation: The Builder calls `Players.LocalPlayer` and parents its own `ScreenGui` to `player.PlayerGui` inside `.build()`. Every other Builder returns a `gui` Frame and lets the caller decide where to mount it (coordinator → `HudLayoutManager:register(...)` → region). This one Builder is the only one importing a client global; it matches the H pattern in the build-plan severity defs ("Builder importing client globals").
- Why it matters: Makes the Builder non-reusable from tests or non-LocalScript contexts, and breaks the contract that `src/shared/Hud/*` modules are pure (no side-effects on require, no client-only references).
- Suggested fix: Have `SettingsMenuBuilder.build()` return `{ gui = screenGui, ... }` and accept either an explicit `parentGui` parameter or no parent at all. `SettingsMenuGui.client.luau` parents the returned `ScreenGui` to `LocalPlayer.PlayerGui` itself.
- Suggested owner: Builder (signature change) + the SettingsMenuGui LocalScript (parenting move).
- Tracker: **NIM-19**.

### F-2  [M] Dead code — `ReservoirBarsBuilder` + `ReservoirBarsConfig`

- Location: `src/shared/Hud/ReservoirBarsBuilder.luau`, `src/shared/Hud/ReservoirBarsConfig.luau`
- Observation: Grep across `src/` shows `ReservoirBars` only required by itself. Wiki page [[systems/HUD]] (commit bebe5b2) already notes "SpellMenu owns mana fill, ReservoirBars unused".
- Why it matters: Carries a `:destroy()`-bearing Builder + 29-line Config that contribute to mental search cost and risk being re-required by mistake.
- Suggested fix: Delete both files. No callers, no Rojo meta references.
- Suggested owner: Cleanup commit.

### F-3  [M] Builder/Config compliance — `BufferDisplayBuilder` inline interaction constants

- Location: `src/shared/Hud/BufferDisplayBuilder.luau:32-40`
- Observation: 9 interaction constants (`DRAG_THRESHOLD_PX = 8`, `GHOST_TRANSPARENCY = 0.45`, `GHOST_ZINDEX = 20`, `SELECTION_STROKE_NAME`, `SELECTION_STROKE_COLOR`, `SELECTION_STROKE_THICKNESS = 2`, `SNAP_FLASH_DURATION = 0.18`, `PULSE_STROKE_NAME`, `VALID_WORD_STROKE_NAME`) declared locally rather than in `BufferDisplayConfig.luau`. The Config already covers styling but not these interaction tunables.
- Why it matters: Phase 4.7 (drag/tap-to-swap) tunables (drag threshold, ghost styling) are the kind of values a tuning pass in Phase 5 will want to adjust; having them in the Config keeps the surface uniform.
- Suggested fix: Move the 9 constants into `BufferDisplayConfig.luau` under a `-- Interaction` block. Resolves L-3 too.
- Suggested owner: Builder + Config (mechanical move).

### F-4  [M] Builder/Config compliance — 8 LocalScripts build UI inline

- Location: `src/client/UI/{KillFeedGui,ScoreboardGui,TeamScoreGui,GameStateGui,RoundTimerGui,DeathScreenGui,DamageFeedbackGui,BossHudGui}.client.luau`
- Observation: Each constructs its UI inline within the LocalScript (named constants at the top, `Instance.new` blocks below), bypassing the `Builder.build() → :register(...)` pattern used elsewhere in `src/shared/Hud/`.
- Why it matters: Soft pattern inconsistency. Modal/one-off screens (DeathScreen, GameState, Scoreboard) are reasonable inline. Smaller persistent HUD elements (KillFeed, TeamScore, RoundTimer, BossHud) could be Builder + Config for uniformity but it's not a correctness issue — they obey the no-magic-numbers rule (named constants at the top).
- Suggested fix: Decide per-element. Likely keep modals inline; promote `KillFeed`, `TeamScore`, `RoundTimer`, `BossHud` to Builder + Config during Phase 5 polish if/when their tuning surfaces.
- Suggested owner: Per-element decision deferred.

### F-5  [M] Placement — `WeaponRolodex.client.luau` lives in `src/client/`, not `src/client/UI/`

- Location: `src/client/WeaponRolodex.client.luau`
- Observation: This LocalScript registers with `HudLayoutManager`, builds GUI, wires UI input — it is unambiguously a UI script. Yet it sits in `src/client/` next to character/replication scripts.
- Why it matters: New contributors looking for "where is the weapon rolodex UI?" will miss it. Pattern-breaks the audit scope itself (the build-plan scoped UI work to `src/client/UI/`).
- Suggested fix: Move to `src/client/UI/WeaponRolodex.client.luau`. Pure file rename — no requires affected (it's a LocalScript, not required by anyone).
- Suggested owner: Single git mv.

### F-6  [M] Region IDs — string literals vs `HudConstants` symbols

- Location: `src/client/UI/{KillFeed,BuffTray,MindFullIndicator,SpellMenu,TeamScore,LoadoutDropClient,GameplayHud}*.client.luau` use string literals (`"TopRight"`, `"TopCenter"`, `"BottomRight"`, `"BottomCenter"`). `src/client/WeaponRolodex.client.luau:42` uses `HudConstants.WEAPON_PANEL_REGION`. `src/shared/Weapon/Scripts/WeaponTouchInputController/init.luau:17` uses `HudConstants.TOUCH_CONTROLS_REGION`.
- Why it matters: A typo in any string literal silently warns ("Unknown region") and the element doesn't appear. `HudConstants` symbols catch this at require-time.
- Suggested fix: Add named constants for all 6 region IDs to `HudConstants.luau` (e.g. `BOTTOM_CENTER`, `TOP_RIGHT`, …) and migrate the literals. Mechanical.
- Suggested owner: One commit, no behavior change.

### F-7  [M] Dimension 3 — `SpellMenuGui` writes `LayoutOrder = 2` with no peer

- Location: `src/client/UI/SpellMenuGui.client.luau:77`
- Observation: `menu.gui.LayoutOrder = 2` is set, but `SpellMenuGui` is the only script registering to `BottomRight`. The `2` is a stale carryover with no effect.
- Why it matters: Dead value that signals "there's a stack here" when there isn't. Easy to mis-edit during future layout changes.
- Suggested fix: Delete the line.
- Suggested owner: One-line cleanup, fold into the same commit as F-5 or F-6.

### F-8  [L] BottomCenter exception — `LoadoutDropClient` toast stack

- Location: `src/client/UI/LoadoutDropClient.client.luau:56`
- Observation: Registers a `LoadoutDropToastStack` Frame to `BottomCenter` outside of `GameplayHudGui`. Toasts are transient (2 s visible + 0.4 s fade, self-destructed). Not a stable HUD element.
- Why it matters: Doesn't break the coordinator pattern (toasts have their own internal UIListLayout and self-manage), but does technically register a second BottomCenter element. Worth documenting so future readers don't see this as a violation.
- Suggested fix: Comment in `LoadoutDropClient` referencing this finding; no behavior change.
- Suggested owner: 1-line comment.

### F-9  [L] `_G.PlayerHud.*` debug registry

- Location: `BuffTrayGui:27-28`, `MindFullIndicatorGui:37-38`, `GameplayHudGui:88-91`, `SpellMenuGui:125-126`
- Observation: 4 client scripts write to `_G.PlayerHud.{BufferDisplay, MemorizeButton, AttributeStack, SpellMenu, MindFullIndicator, BuffTray}`. Grep confirms **no reads** from `_G.PlayerHud.*` anywhere in `src/shared/Hud/` — so the namespace is debug/inspection-only.
- Why it matters: `_G` writes are forever. If a future test imports any of these scripts twice (multi-VM tests, hot-reload), the second `_G.PlayerHud = _G.PlayerHud or {}` clobbers the first via reference juggling. Low risk today.
- Suggested fix: Move to a `src/client/PlayerHud/ClientHudRegistry.luau` ModuleScript with `:register(name, handle)` / `:get(name)`. Keeps the inspect-from-console capability without `_G` pollution.
- Suggested owner: Optional; defer until Phase 5 surfaces a need.

### F-10  [L] Duplicate constant — `VALID_WORD_STROKE_NAME`

- Location: `src/shared/Hud/BufferDisplayBuilder.luau:40` and `src/shared/Hud/BufferDisplayConfig.luau:50`
- Observation: Both files declare `VALID_WORD_STROKE_NAME = "ValidWordStroke"`. The Builder uses the local one; the Config one is unread.
- Why it matters: Silent divergence risk if one is edited and the other isn't.
- Suggested fix: Delete the local one in `BufferDisplayBuilder.luau` and use `Defaults.VALID_WORD_STROKE_NAME` (this is naturally subsumed by F-3).
- Suggested owner: Folded into F-3.

### F-11  [L] Placeholder fizzle-sound TODOs

- Location: `src/client/UI/GameplayHudGui.client.luau:32`, `src/client/UI/SpellMenuGui.client.luau:69`
- Observation: `fizzleSound.SoundId = "rbxassetid://0" -- TODO: replace with fizzle SFX asset ID`
- Why it matters: Phase 5 audio polish, not architecture.
- Suggested fix: Pick / publish a fizzle SFX during Phase 5 audio pass.
- Suggested owner: Phase 5 audio work.

## Out of scope (logged, not fixed in 4.8)

- Per-platform UI scaling refinement beyond the existing UIScale strategy.
- The 8-LocalScript-vs-Builder decision (F-4) is documented as pattern guidance; per-element refactors will happen as Phase 5 surfaces tuning needs.
- `_G.PlayerHud` is documented in F-9 but not scheduled — debug-only, no callers.

## Go/no-go rationale

The audit found **zero correctness defects**: no double-writes, no leaked connections, no missing `:destroy()` methods, no Builders held by removed character references. The one High finding (F-1: SettingsMenuBuilder reads `Players.LocalPlayer`) is structural — it matches the build-plan H pattern — but it's isolated to a single Builder that runs once per client, doesn't leak, and doesn't intersect any Phase 5 polish workstream (tuning, audio, particles, tutorial). All other findings are pattern uniformity / dead-code housekeeping that can be cleaned in passing.

**Decision: GO.** Recommended cleanup before Phase 5 commits start: F-2 (delete ReservoirBars) + F-3 (move BufferDisplay interaction constants into Config) + F-7 (drop stale `LayoutOrder = 2`) + F-1 (decouple SettingsMenuBuilder). Combined, these are a single small cleanup commit, ~30 minutes.
