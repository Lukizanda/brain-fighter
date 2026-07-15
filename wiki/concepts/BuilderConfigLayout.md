---
type: concept
description: HUD architecture — Builder constructs, Config tunes, LayoutManager places. No .rbxmx GUI templates checked into the repo.
updated: 2026-06-05
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

## Live data (inline connections)

For HUD elements that subscribe to game-state, the wiring lives **inline in the coordinator LocalScript** (`src/client/UI/<Element>Gui.client.luau`), which holds the connections and pushes updates into the Builder's output. The Builder itself still has no state.

```
Game state (Humanoid.HealthChanged)
  ↓
Coordinator GUI script (GameplayHudGui — healthConnections table)
  ↓ updates
Builder output (AttributeBar instance from AttributeBarBuilder)
```

> Historical note: this used to be a standalone **Adapter** sidecar module (`src/client/PlayerHud/Adapters/HealthAdapter.luau`). That `PlayerHud/` indirection was stripped on 2026-05-20 — the health bar is now built directly in `GameplayHudGui.client.luau` with an inline `healthConnections` table. See [[systems/HUD]].

## Where this is in use

- AttributeBar (Health) — [[systems/HUD]]
- BufferDisplay, MemorizeButton, SpellMenu, MindFullIndicator, DashButton (Phase 4 gameplay widgets)
- BuffTray
- TouchControl (mobile)
- SettingsMenu

## Anti-pattern: don't check in `.rbxmx` GUI templates

We don't ship `.rbxmx` GUI hierarchies. The Builder constructs everything in code. This is partly aesthetic (one source of truth) and partly practical (Studio merges of `.rbxmx` are awful).
