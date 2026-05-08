---
type: concept
description: HUD architecture — Builder constructs, Config tunes, LayoutManager places. No .rbxmx GUI templates checked into the repo.
updated: 2026-04-30
---

# Builder + Config + LayoutManager

The pattern that all HUD elements follow. Three roles, three files per element.

## Roles

- **Builder** (`<Element>Builder.luau`) — pure constructor. Takes a Config table, returns a GUI subtree. No state, no subscriptions.
- **Config** (`<Element>Config.luau`) — data-only file that exposes every visual knob (sizes, colors, gradients, margins, falloffs). The Config is what the user iterates on.
- **LayoutManager** (`HudLayoutManager.luau`) — places built elements at named regions (`BottomLeft`, `BottomRight`, `TopRight`, etc.). One layout manager for the whole HUD.

## Why three files

- The Config is where the **visual iteration** happens. Pulling it out of the Builder means we can tune without touching code that handles event wiring or layout.
- The Builder is the only file that reads the Config — the LayoutManager and Adapters never do. That keeps the dependency graph one-way.
- The LayoutManager is element-agnostic: it knows about screen regions, not specific HUD elements.

## Adapter sidecar (for live data)

For HUD elements that subscribe to game-state, an **Adapter** sits between the data source and the Builder's output. The Builder still has no state; the Adapter holds connections and pushes updates.

```
Game state (Humanoid.HealthChanged)
  ↓
Adapter (HealthAdapter)
  ↓ updates
Builder output (AttributeBar instance)
```

Example: `src/client/PlayerHud/Adapters/HealthAdapter.luau` listens to `Humanoid.HealthChanged` and updates the attribute bar built by `AttributeBarBuilder`.

## Where this is in use

- AttributeBar (Health / Stamina / Shield) — [[systems/HUD]]
- WeaponRolodex
- BuffTray
- TouchControl (mobile)
- SettingsMenu

## Anti-pattern: don't check in `.rbxmx` GUI templates

We don't ship `.rbxmx` GUI hierarchies. The Builder constructs everything in code. This is partly aesthetic (one source of truth) and partly practical (Studio merges of `.rbxmx` are awful).
