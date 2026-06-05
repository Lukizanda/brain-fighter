---
type: design
description: Phase 4.8 — pre-Phase-5 UI architecture audit; findings, severity, go/no-go. Re-audited 2026-06-05 after the mobile/DASH + VFX + Phase 4.7 reorder work.
updated: 2026-06-05
---

# UI Architecture Review — Phase 4.8

Pre-Phase-5 audit of the client UI layer against the six review questions in [[design/build-plan]] Phase 4.8 (single-ownership, coordinator clarity, Builder/Config compliance, lifecycle, dead code, coupling). Scope: `src/client/UI/*.client.luau` + `src/shared/Hud/*.luau`.

The full layout & data-flow diagram is on the system page: [[systems/HUD]] § System diagram.

> **Re-audit note (2026-06-05).** This supersedes the 2026-05-20 audit. The codebase changed materially since then: `src/client/PlayerHud/` was removed (commit `1cbfc09`, "strip PlayerHud indirection"), the mobile vertical right-column + DASH button trio landed (`DashButtonGui`/`Builder`/`Config`), spell FX converged onto one pipeline, and Phase 4.7 drag/tap-to-swap shipped in `BufferDisplayBuilder`. Findings were re-derived from current source via three independent read-only sweeps, with the destructive item (ReservoirBars deletion) and the two contested High findings hand-verified.

## Summary

- **Files audited:** 15 `src/client/UI/*.client.luau` + 26 `src/shared/Hud/*.luau` = 41 (now 24 `src/shared/Hud/*.luau` after R-2 deletion).
- **Findings:** H = 1, M = 5, L = 3.
- **Cleanup landed 2026-06-05:** R-1, R-2, R-3, R-4 **RESOLVED** and verified in a boot playtest (see § Cleanup verification). Remaining open: R-6, R-7 (Medium, magic-number extraction), R-5, R-8, R-9 (Low). **No High findings remain open.**
- **Phase 5 gate: GO.** Zero correctness defects that block polish work; the structural High (R-1) is now closed.
- **Since the 2026-05-20 audit:** F-5 (WeaponRolodex misplaced) and F-7 (stale `LayoutOrder = 2`) were already RESOLVED. Three new findings surfaced from the mobile/DASH work and SpellMenu growth (R-4 resolved; R-5/R-6/R-7 logged).

## Pass/fail per dimension

| # | Dimension | Result | Note |
|---|---|---|---|
| 1 | Single ownership | **MIXED** | One new break: `DashButtonGui` writes `region.Position` + `UIListLayout.Padding` on a HudLayoutManager-owned region (R-4). Top-level LayoutOrder ownership otherwise clean. |
| 2 | Coordinator clarity | **PASS (with documented exceptions)** | `GameplayHudGui` is sole stable BottomCenter coordinator; `LoadoutDropClient` toast stack is transient (documented). New latent overlap risk on TopCenter/TopRight (R-5). |
| 3 | Builder/Config compliance | **MIXED** | 15/15 client scripts delegate to Builders (one-off screens build inline, acceptable). 3 Builders carry inline magic numbers: BufferDisplay (R-3), SpellMenu (R-6), BuffTray (R-7). |
| 4 | Lifecycle completeness | **MOSTLY CLEAN** | All Builders expose `:destroy()`. BufferDisplay (Phase 4.7 input handlers), DashButton, BuffTray all clean. Minor untracked one-shot tween `Completed`/click connections in SpellMenu + AttributeBar (R-8, Low). |
| 5 | Dead code | **ONE ITEM** | `ReservoirBarsBuilder` + `ReservoirBarsConfig` unreferenced — hand-verified safe to delete (R-2). No other scaffolds. |
| 6 | Coupling | **ONE ITEM** | `SettingsMenuBuilder` reads `Players.LocalPlayer` (R-1, High). `HudLayoutManager` LocalPlayer use is the sanctioned ScreenGui-parent exception — NOT a violation. `_G.PlayerHud` still write-only, no shared reads (R-9, Low). |

## Findings

### R-1  [H] Coupling — `SettingsMenuBuilder` reads `Players.LocalPlayer`  *(carried over: NIM-19)*

- Location: `src/shared/Hud/SettingsMenuBuilder.luau:44` (`local player = Players.LocalPlayer`), parents its own ScreenGui to `player.PlayerGui` at `:71`.
- Observation: The only Builder in `src/shared/Hud/` that imports a client global and self-parents. Every other Builder returns a `gui` handle and lets the caller mount it.
- Why it matters: Breaks the "shared/Hud modules are pure" contract — non-reusable from tests / non-LocalScript contexts.
- Suggested fix: `build()` returns `{ gui = screenGui, ... }`; `SettingsMenuGui.client.luau` parents it to `LocalPlayer.PlayerGui`.
- Status: **RESOLVED (2026-06-05).** Removed `Players` import + `LocalPlayer`/`PlayerGui` parenting from `SettingsMenuBuilder`; the handle already exposed `gui`, so `SettingsMenuGui.client.luau:76` now does `handle.gui.Parent = player.PlayerGui`. Builder is now client-global-free. Verified: `SettingsMenuGui` present in PlayerGui at runtime. Closes NIM-19.

### R-2  [M] Dead code — `ReservoirBarsBuilder` + `ReservoirBarsConfig`  *(carried over, hand-verified)*

- Location: `src/shared/Hud/ReservoirBarsBuilder.luau`, `src/shared/Hud/ReservoirBarsConfig.luau`.
- Observation: `grep -rn "ReservoirBars" src/` returns only the two files themselves plus an explanatory comment in `SpellMenuBuilder.luau:6` ("replacing the separate ReservoirBars component"). **No `require` from any consumer.** SpellMenu owns mana fill now.
- Why it matters: Dead Builder+Config inflate search cost and risk accidental re-require.
- Suggested fix: Delete both files. **Verified non-destructive** — no callers, no Rojo meta references.
- Status: **RESOLVED (2026-06-05).** Both files deleted via `git rm`. Verified: no `ReservoirBars` instance in the runtime HUD; only a historical comment in `SpellMenuBuilder.luau:6` remains (kept — it explains why SpellMenu owns mana fill).

### R-3  [M] Builder/Config — `BufferDisplayBuilder` inline interaction constants  *(carried over)*

- Location: `src/shared/Hud/BufferDisplayBuilder.luau:32-40`.
- Observation: 9 Phase-4.7 interaction tunables (`DRAG_THRESHOLD_PX = 8`, `GHOST_TRANSPARENCY = 0.45`, `GHOST_ZINDEX = 20`, `SNAP_FLASH_DURATION = 0.18`, selection/pulse/valid-word stroke names + color + thickness) declared in the Builder instead of `BufferDisplayConfig.luau`. `VALID_WORD_STROKE_NAME` is duplicated across both files (Builder uses local; Config copy unread).
- Why it matters: These are exactly the values a Phase 5 tuning pass will want to touch; they belong in Config. Duplicate risks silent divergence.
- Suggested fix: Move all 9 into `BufferDisplayConfig.luau` under an `-- Interaction` block; delete the duplicate.
- Status: **RESOLVED (2026-06-05).** Added an `-- Interaction (Phase 4.7 …)` block to `BufferDisplayConfig.luau`; the Builder's locals now alias `Defaults.*` (usage sites unchanged, low-risk). `VALID_WORD_STROKE_NAME` duplicate removed — Builder reads the Config copy. Verified: BufferDisplay still builds (present in BottomCenter at runtime).

### R-4  [M] Single ownership — `DashButtonGui` mutates a HudLayoutManager-owned region  *(NEW)*

- Location: `src/client/UI/DashButtonGui.client.luau:33` (`regionLayout.Padding = …`) and `:35` (`region.Position = UDim2.new(1, -20, 1, -DashButtonConfig.BOTTOM_MARGIN)`).
- Observation: Reaches into the `BottomRight` region returned by `HudLayoutManager:getRegion()` and rewrites its `Position` and child `UIListLayout.Padding`. HudLayoutManager owns region placement (it sets region Position from `HudConstants` and re-applies layout on `AbsoluteSize` changes).
- Why it matters: Single-ownership break. Concrete risk: HudLayoutManager connects to viewport-resize signals — if it re-derives region Position on resize, this manual write is clobbered (DASH button jumps). Also clobbers any future second registrant on BottomRight.
- Suggested fix: Add a per-region offset/margin override to `HudLayoutManager` (or a `HudConstants` entry for the BottomRight vertical column) and have the manager apply it, rather than the client script mutating the region after registration.
- Status: **RESOLVED (2026-06-05).** Moved the column's screen margin (Y −260) and SpellMenu↔DASH gap (36) into `HudConstants.REGIONS.BottomRight` (`Position` + `stackPadding`) — HudLayoutManager applies them at region init. Removed the post-registration mutation block from `DashButtonGui` and the now-orphaned `BOTTOM_MARGIN`/`SPELL_GAP` from `DashButtonConfig`. Single-owner: HudConstants/HudLayoutManager own region geometry. Verified at runtime: `BottomRight.Position = {1,-20},{1,-260}`, `UIListLayout.Padding = 0,36` — pixel-identical to the prior behavior.

### R-5  [L] Coordinator — TopCenter / TopRight have 2 registrants with no vertical stacking  *(NEW)*

- Location: TopCenter ← `MindFullIndicatorGui.client.luau:22` + `TeamScoreGui.client.luau`; TopRight ← `BuffTrayGui.client.luau:25` + `KillFeedGui.client.luau`.
- Observation: Neither region enables `stackVertical`, so both registrants default to position 0,0 and would overlap if simultaneously visible.
- Why it matters: Latent only — today the pairs are effectively mutually exclusive (MindFull hides when buffer not full, TeamScore hides in non-team modes, BuffTray currently empty). But it's a layout landmine for whoever next makes both visible.
- Suggested fix: Either enable `stackVertical` on these regions or document the mutual-exclusion assumption inline.
- Status: **OPEN (new, latent)**.

### R-6  [M] Builder/Config — `SpellMenuBuilder` inline magic numbers  *(NEW)*

- Location: `src/shared/Hud/SpellMenuBuilder.luau` — color-lighten amount `55` (:78), popup size `72×22` (:184-185), color/spell label offsets and popup bg/corner (:140, :154-155, :186, :193).
- Observation: The SpellMenu grew (2× sizing, mana reservoir fill, tier popup) and accreted inline literals not present in `SpellMenuConfig.luau`.
- Why it matters: Phase 5 will tune spell-button legibility; these should be in Config per the no-magic-numbers rule.
- Suggested fix: Extract into `SpellMenuConfig.luau`. Mechanical.
- Status: **OPEN (new)**.

### R-7  [M] Builder/Config — `BuffTrayBuilder` inline padding/offset literals  *(NEW)*

- Location: `src/shared/Hud/BuffTrayBuilder.luau:82, :101-102` — icon padding `-4`/`2`, stack-text margin `-2`, size `16`.
- Observation: Inline geometry literals with no entry in `BuffIconConfig.luau`.
- Why it matters: Same no-magic-numbers rule; BuffTray is a scaffold awaiting adapter wiring, so cleaning now is cheap.
- Suggested fix: Move into `BuffIconConfig.luau`.
- Status: **OPEN (new)**.

### R-8  [L] Lifecycle — untracked one-shot tween `Completed` / click connections  *(NEW, minor)*

- Location: `SpellMenuBuilder.luau` (tween `Completed:Connect` in fade/affordBounce/firedFlash; per-button `MouseButton1Click`), `AttributeBarBuilder.luau` (sweep/ripple `Completed:Connect`), `MemorizeButtonBuilder.luau:75` (click not stored).
- Observation: These connections aren't stored in the Builders' `connections` arrays, so `:destroy()` doesn't explicitly disconnect them.
- Why it matters: Low impact — all are GUI-scoped one-shots; when the parent GUI is destroyed the instances and their tweens are collected. No per-frame leak, no growth during play. Worth tidying for consistency, not a gate.
- Suggested fix: Store and disconnect in `:destroy()` for uniformity. Optional.
- Status: **OPEN (new, low)**.

### R-9  [L] `_G.PlayerHud` debug registry  *(carried over, unchanged)*

- Location: writes in `DashButtonGui:53-54`, `SpellMenuGui:125-126`, `GameplayHudGui:114-117`, `MindFullIndicatorGui:37-38`, `BuffTrayGui:27-28`.
- Observation: Still write-only; grep confirms **no reads** from `_G.PlayerHud.*` in `src/shared/`. Debug/inspection namespace only. (The `src/client/PlayerHud/` directory that prompted the old F-9 framing is gone; the `_G` table is unrelated and remains.)
- Suggested fix: Optional — move to a `ClientHudRegistry` ModuleScript with `:register/:get`. Defer until a real consumer appears.
- Status: **OPEN (low, deferred)**.

## Resolved since 2026-05-20

- **F-5 (WeaponRolodex misplaced):** RESOLVED — UI logic now lives in `WeaponRolodexBuilder.luau` + `WeaponRolodexConfig.luau` under `src/shared/Hud/`.
- **F-7 (stale `LayoutOrder = 2` in SpellMenuGui):** RESOLVED — line removed; `grep "LayoutOrder = 2"` returns nothing.
- **HudLayoutManager LocalPlayer:** confirmed NOT a violation (sanctioned ScreenGui-parent exception).

## Cleanup verification (2026-06-05)

The R-1/R-2/R-3/R-4 cleanup was applied and verified with a single boot playtest (no static linter is installed — `selene.toml` exists but selene is not in the toolchain). Console showed no errors from any HUD module (only pre-existing CoreGui `CornerRadius` StyleRule warnings). Runtime assertions via `execute_luau`:

- `SettingsMenuGui` present in PlayerGui → R-1 LocalScript parenting works.
- `BottomRight.Position = {1,-20},{1,-260}`, `UIListLayout.Padding = 0,36` → R-4 values intact from HudConstants.
- `BottomCenter` has its 5 children (incl. BufferDisplay) → R-3 module loads.
- No `ReservoirBars` instance in the HUD tree → R-2 deletion clean.

## Go/no-go rationale

Re-audit found **zero correctness defects**: no double-writes on shared properties (R-4 is a single-writer boundary break, not an active conflict), no leaked per-frame connections, every Builder has a working `:destroy()`. The one High (R-1) is structural, runs once per client, doesn't leak, and doesn't intersect any Phase 5 polish workstream.

**Decision: GO.** The recommended pre-Phase-5 cleanup (R-1, R-2, R-3, R-4) **landed and is verified** — no High findings remain open. R-6/R-7 (magic-number extraction) and R-5/R-8/R-9 (Low) are deferred to fold into Phase 5 tuning as those surfaces get touched.
