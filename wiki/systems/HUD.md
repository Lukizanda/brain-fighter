---
type: system
description: Code-driven HUD — Builder + Config + LayoutManager pattern. Attribute bars, WeaponRolodex, BuffTray, reticle, settings menu, and 5 Phase 4 gameplay widgets (BufferDisplay, ReservoirBars, MemorizeButton, SpellMenu, MindFullIndicator).
updated: 2026-05-18
---

# HUD System

Every HUD element follows the [[concepts/BuilderConfigLayout]] pattern — a Builder constructs the GUI tree, a Config exposes tunable knobs, and `HudLayoutManager` places the result on screen. No `.rbxmx` GUI templates are checked into the repo.

## Team-score gate (2026-05-13)

`src/client/UI/TeamScoreGui.client.luau` is a top-of-script bail when `GameConfig.TEAMS_ENABLED` is false — the LocalScript still auto-runs on join but exits before building the container or hooking remotes. `KillFeedGui` is left on (NPC kills still display); its team-tinted name colours fall back to `NEUTRAL_NAME_COLOR` naturally because every player is team-less while the gate is off.

## Files

```
src/shared/Hud/
  HudLayoutManager.luau           — places elements at named regions (BottomLeft, BottomRight, TopRight, etc.)
  HudConstants.luau               — shared sizes / colors / margins
  AttributeBarBuilder.luau        — Health / Stamina / Shield bars
  AttributeBarConfig.luau
  WeaponRolodexBuilder.luau       — single weapon card with cycling
  WeaponRolodexConfig.luau        — gradient, corner radius, pill positions
  BuffTrayBuilder.luau            — top-right buff icons (scaffold)
  BuffIconConfig.luau
  TouchControlBuilder.luau        — mobile touch overlay
  TouchControlConfig.luau
  SettingsMenuBuilder.luau
  SettingsMenuConfig.luau
  -- Phase 4 gameplay widgets:
  BufferDisplayBuilder.luau       — letter-tile row from WordBuffer.tiles()
  BufferDisplayConfig.luau
  ReservoirBarsBuilder.luau       — R/G/B energy bars (reuses AttributeBarBuilder)
  ReservoirBarsConfig.luau
  MemorizeButtonBuilder.luau      — Memorize action button (calls MemorizeAction.tryMemorize)
  MemorizeButtonConfig.luau
  SpellMenuBuilder.luau           — 3-color spell cast panel (tap → CastAction.tapReservoir)
  SpellMenuConfig.luau
  MindFullIndicatorBuilder.luau   — warning banner when WordBuffer is full
  MindFullIndicatorConfig.luau

src/client/PlayerHud/
  init.client.luau                — entry point, mounts all HUD elements
  Adapters/
    HealthAdapter.luau            — subscribes to Humanoid.HealthChanged → updates AttributeBar
    ShieldAdapter.luau            (scaffold)
    StaminaAdapter.luau           (scaffold)

src/client/UI/
  DamageFeedbackGui.client.luau   — directional damage indicators
  DeathScreenGui.client.luau      — death overlay
  SettingsMenuGui.client.luau     — settings menu mount
  -- Phase 4 gameplay widgets:
  BufferDisplayGui.client.luau    — BottomCenter; wired to wordBuffer.changed
  ReservoirBarsGui.client.luau    — BottomLeft; wired to energyReservoirs.changed
  MemorizeButtonGui.client.luau   — BottomCenter; fires tryMemorize on click
  SpellMenuGui.client.luau        — BottomRight; fires tapReservoir on color tap
  MindFullIndicatorGui.client.luau — TopCenter; shows/hides on mindFull/mindFreed
  BossHudGui.client.luau          — TopCenter; boss health bar + phase label; hidden until a boss spawns
```

## Phase 4 gameplay widgets

All five read state through `PlayerSession.get()` and subscribe to signals from the session objects.

| Widget | Region | Signal source | Action |
|---|---|---|---|
| BufferDisplay | BottomCenter | `wordBuffer.changed` | display tiles |
| ReservoirBars | BottomLeft | `energyReservoirs.changed` | show R/G/B energy |
| MemorizeButton | BottomCenter | `wordBuffer.changed` | `MemorizeAction.tryMemorize` |
| SpellMenu | BottomRight | `energyReservoirs.changed` | `CastAction.tapReservoir` |
| MindFullIndicator | TopCenter | `mindFull` / `mindFreed` | show/hide warning |

## Adapter pattern (attribute bars)

Each attribute bar has an Adapter that subscribes to a game-state source and forwards updates to the bar. `HealthAdapter` listens to `Humanoid.HealthChanged`. Adding a new bar = new Builder Config entry + new Adapter.

## WeaponRolodex

Single card that always shows the equipped weapon. Cycles via Tab / Shift+Tab or touch swipe. Reads `_ammo` / `_reserveAmmo` Tool attributes for live firearm ammo, `WeaponIcon` for icon swaps, `_cooldownEnd` for the special-weapon cooldown overlay.

Current visual iterating — gradient rotation, card corner radius, and pill positions are active dial-ins.

## Reticle

White `+` crosshair, red `X` hitmarker (CanvasGroup with a Rotation quirk — fade via `Visible = false` at completion, not transparency tween). Reactive spread: shot bumps spread, Heartbeat decays it back.

## Cross-references

- Pattern → [[concepts/BuilderConfigLayout]]
- Weapon icons (asset pipeline) → `reference_weapon_icon_pipeline.md` in auto-memory
