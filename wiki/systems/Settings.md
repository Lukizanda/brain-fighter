---
type: system
description: Client-side player preferences (2026-09-20, BRA.21) — SFX volume, Reduced effects, letter palette. `Settings` (pure module: keys, defaults, normalize, attribute read/write on a holder), `SettingsController` (one SoundGroup every Sound is routed into; palette applied through Colors + LetterBlock repaint), `SettingsGui` + `SettingsBuilder`/`SettingsConfig` (gear button + panel, LobbyOnly). `Colors` owns the palettes; `spawnEffect`/`ScreenImpact` read the reduced flag at draw time. Not persisted until Phase 5.5.
updated: 2026-09-20
---

# Settings

The settings surface that refactor chunk 12 cut (F25: a menu writing
`Settings_*` attributes nothing read) came back on 2026-09-20 with three
settings that each have a consumer — and nothing else. Tracker BRA.21 holds
the re-judgement; the short version is that sensitivity, FOV, crosshair and
aim assist had no reader because tap-to-pop removed the aiming verb they
served, while a per-pop sound effect, screen shake on big hits, and a
colour-typed core verb each had a real complaint waiting.

| Setting | Attribute | Range / default | Read by |
|---|---|---|---|
| Sound effects | `Settings_SfxVolume` | 0–100 in steps of 5, default 80 | `SettingsController` → `SoundGroup.Volume` |
| Reduced effects | `Settings_ReducedVfx` | boolean, default false | `spawnEffect` (no lights, bursts thinned by `VfxConfig.PERF.reducedVfxEmitScale`), `ScreenImpact` (skipped outright) |
| Letter colours | `Settings_Palette` | `default` \| `high_contrast`, default `default` | `SettingsController` → `Colors.setPalette`; block faces, buffer tiles and spell-menu discs draw through `Colors.tint` |

## Ownership

| Thing | Owner | Lives in |
|---|---|---|
| Keys, defaults, the normalize rule, attribute read/write/changed | `Settings` (ModuleScript, pure) | `src/shared/Settings/init.luau` |
| The palettes and the active one; `tint(color)`; `paletteChanged` | `Colors` | `src/shared/Core/Colors.luau` |
| The `Sfx` SoundGroup, routing every Sound into it, applying the palette and repainting blocks | `SettingsController` (LocalScript) | `src/client/SettingsController.client.luau` |
| Gear button + panel, wiring the panel to `Settings.write` | `SettingsGui` (LocalScript) | `src/client/UI/SettingsGui.client.luau` |
| Panel and gear construction | `SettingsBuilder` + `SettingsConfig` | `src/shared/Hud/` |
| Honouring Reduced effects | `spawnEffect`, `ScreenImpact` | `src/shared/Vfx/` |

**Values are attributes on the LocalPlayer**, written by the client. A
client-side attribute write does not replicate to the server, which is
correct today — nothing server-side cares what volume a player runs at —
and is what Phase 5.5 persistence ([[design/persistence-progression]]
`PlayerData.settings`) will carry over a remote when settings start to
follow the player. `Settings.read` normalizes on every read as well as
every write, so a stale or hand-edited attribute can never leak an illegal
value into a consumer.

`Settings` is holder-agnostic (`read(holder, key)`), which is what makes it
testable on the server VM with a Folder. `Settings.localHolder()` is the
LocalPlayer and asserts on the client; `localHolderIfAny()` is the nil-safe
form the two shared VFX modules use, since they are required on both VMs.

## SFX volume — one SoundGroup, one writer

`SettingsController` creates `SoundService.Sfx` and sets its `Volume` from
the setting. Every `Sound` on the client is routed into it by a scan of
`SoundService` and `workspace` plus `DescendantAdded` on both, adopting any
Sound whose `SoundGroup` is nil. That catches the three HUD fizzle Sounds
(parented to `SoundService`), the per-cast Sounds `spawnEffect` parents to
anchor parts, and Sounds the server authored on replicated parts. A Sound's
`SoundGroup` property therefore has exactly one writer
([[concepts/SingleOwnership]]); no play site knows the group exists.

Roblox has no master SFX volume without a SoundGroup, and a group with one
volume knob is also where a future music bus would sit beside it.

## Reduced effects — read at the moment of drawing

Not a controller: `spawnEffect` and `ScreenImpact.play` read the flag per
call through `Settings.localHolderIfAny()`. A burst is cheap next to a
subscription those modules would then have to own, and the panel flips it
live.

- `spawnEffect`: `PointLight` skipped (alongside `PERF.allowLights`), every
  `emitCount` scaled by `VfxConfig.PERF.reducedVfxEmitScale` (0.5, minimum
  1). Sound and rate-based emitters untouched — a cast still lands.
- `ScreenImpact`: returns before allocating anything. The whole lane is
  motion and flash on the viewer's screen, which is exactly what the
  preference asks to be spared; scaling it would be a half-answer.
- `VfxConfig.PERF`'s fps-adaptive guardrails are a separate mechanism and
  still run.

## Letter palette — one table, four surfaces

Spells are colour-typed, so a player who cannot tell the default red from
the default green is locked out of the core read. Fixing one surface does
not help while the other three keep their own literals — which they did
(Phase 5.3's "colour type dedup ×4"). `Colors` now owns the palette:

- `Colors.PALETTES.default` — the shipped tints (`#dc2626` / `#16a34a` /
  `#2563eb` / `#eab308`, LetterBlocks' originals).
- `Colors.PALETTES.high_contrast` — Okabe–Ito: vermillion `(213,94,0)`,
  bluish-green `(0,158,115)`, blue `(0,114,178)`, yellow `(240,228,66)`.
  Distinguishable under protanopia, deuteranopia and tritanopia while each
  still reads as the colour its name says.
- `Colors.tint(color)` is the one way a drawing site gets a Color3 for
  `"red"`; unknown keys fall back to red so a broken key is visible rather
  than blank. `Colors.setPalette(name)` switches and fires
  `Colors.paletteChanged`.

Surfaces that draw through `tint`, and how each repaints on a switch:

| Surface | Draws via | Repaint |
|---|---|---|
| Block faces (`LetterBlocks.applyVisualState`) | `Colors.tint` | `SettingsController` re-applies `applyVisualState` to every tagged block; blocks arriving later while a non-default palette is active are painted on `GetInstanceAddedSignal` (deferred so face GUIs have replicated). Client-local property writes over the server's default-palette paint. |
| Hover highlight fill (`BlockTapController`) | `Colors.tint` | Next hover |
| Buffer tiles (`BufferDisplayBuilder`) | `Colors.tint` at render | `GameplayHudGui` re-renders on `Colors.paletteChanged` |
| Spell-menu discs (`SpellMenuBuilder`) | `Colors.tint` darkened by `SpellMenuConfig.DISC_TINT_DARKEN`, lit by `LIT_LIGHTEN` | `SpellMenuGui` calls `menu:repaint()` on `Colors.paletteChanged`, keeping each colour's castable/drained state |

Deliberately **not** on the palette: `VfxConfig.COLORS` (bursts are felt,
not read — they stay the brighter VFX set), the reservoir numerals, and
anything server-side. `LetterBlocks.COLOR_TINTS` survives as an alias of
the default palette for the two server-side readers (the collect stream's
colour in `BlockShootService`, the spawn assert) — the server never
switches palette.

## The panel

`SettingsGui` builds a gear button into the `TopRight` region stack
(`LayoutOrder` −1, ahead of the kill feed and buff tray) and a panel in its
own `ScreenGui` at `LAYERS.Modal`. Both are **`LobbyOnly`** — the first
users of that HudGate policy ([[concepts/HudGate]]): settings live on the
hub wall beside the portals, and entering an arena gates them off. Leaving
the hub also closes the panel so a return visit does not start with last
time's panel open. No keybind — mobile has none, and the hub button is the
same reach on every platform.

The panel is a view. Every change goes through `Settings.write`, and the
panel is painted from what was *stored*: a dragged 43 reads back as 45 and
the knob snaps with it. Any other writer (a debug hotkey, a future
persistence load) shows on the panel through `Settings.changed` without the
panel knowing who.

Controls: a slider (drag anywhere on the track, mouse or touch), an On/Off
toggle, a two-way palette choice with a four-swatch strip under it drawn
from the chosen palette so the colours are visible before they land on a
block, and Done.

## Files

```
src/shared/Settings/
  init.luau        — keys, defaults, normalize, read/write/changed, localHolder(IfAny), volumeToGain
  __tests.luau     — defaults, clamp/snap, garbage → default, changed count, palette round-trip
src/shared/Core/Colors.luau          — PALETTES, Palette names, setPalette/getPalette/tint/isPalette, paletteChanged
src/client/SettingsController.client.luau — Sfx SoundGroup + routing; palette apply + block repaint
src/client/UI/SettingsGui.client.luau     — gear + panel coordinator
src/shared/Hud/SettingsBuilder.luau · SettingsConfig.luau
src/shared/Vfx/spawnEffect.luau · ScreenImpact.luau — reduced-effects reads
src/shared/Vfx/VfxConfig.luau        — PERF.reducedVfxEmitScale
src/shared/Tests/Suites/Unit/settings_tests.luau
```

## Verification

Two playtests on 2026-09-20 (the second after a build-time nil in
`SpellMenuBuilder` — the loop's `bgColor` had been removed with the old
literal and the ready-glow still read it; caught by the client console,
fixed, re-run).

- **Unit suite** (`RunTests = Unit`): 9/9 including `settings_tests` —
  defaults, clamp/snap (999 → 100, 43 → 45), garbage → default, changed
  fired exactly twice across two real writes and one no-op, palette
  round-trip through `Colors` with `paletteChanged` firing twice.
- **Client, hub:** `SettingsGui` present and enabled; gear built into
  `TopRight`, visible; panel hidden until opened. `SoundService.Sfx`
  exists at 0.80; **12 of 12** Sounds on the client carried the group.
- **Palette switch** (attribute set to `high_contrast` on the client): a red
  block's `Cube.Color` went `(220,38,38) → (213,94,0)`, 58 blocks
  repainted per the controller log; the spell menu's red disc base went
  `(120,78,84) → (118,91,75)`, ready glow `(250,101,101) → (245,147,70)`,
  mote `(255,161,161) → (255,207,130)`; the panel's red swatch read
  `(213,94,0)` and the High-contrast button lit. Restoring `default` put
  every value back. Buffer tiles use the same `Colors.tint` at render and
  re-render on `paletteChanged`; not exercised with a live tile (the
  harness cannot reach the HUD's `PlayerSession` instance).
- **Volume:** writing 43 stored 45, `Sfx.Volume` 0.45, value label "45",
  knob at 0.45; 80 restored 0.80.
- **Reduced effects:** toggle read "On" after the write; no burst was
  spawned in this pass, so the thinning is verified by code, not by count.
- **Gate:** forcing `PlayerState = InArena` on the client hid the gear and
  disabled the ScreenGui; `InLobby` restored both. `LobbyOnly` works.
- Console clean on the second run: no errors, `[SettingsController] ready`
  and `[SettingsGui] ready — sfx=80 reduced=false palette=default`.

## Not built

- **Persistence.** Phase 5.5 (`PlayerData.settings`). The attributes are
  the hand-off: persist by reading them, restore by writing them.
- **Music volume.** No music yet; a second SoundGroup beside `Sfx` when
  there is.
- **Reduced effects on the charge orb / status visuals.** Sustained
  emitters (`ChargeOrbVfx`, `StatusVisuals`) budget themselves and are not
  thinned; only bursts and the screen lane honour the flag today.
- **Sensitivity / FOV / crosshair / aim assist.** No consumer.

## Cross-references

- HUD pattern and the element list → [[systems/HUD]], [[concepts/BuilderConfigLayout]]
- Gate policy table → [[concepts/HudGate]] § Triage
- Block tints → [[systems/LetterBlock]] § Color tints
- VFX lanes the reduced flag touches → [[systems/VisualEffects]]
- Why these three settings → tracker BRA.21; plan → [[design/build-plan]] Phase 5.3
