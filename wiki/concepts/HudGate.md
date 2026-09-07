---
type: concept
description: How HUD elements are suppressed by player state (lobby vs arena). A declared policy per element, enforced by a required argument on register — because the failure mode is silent leakage, not an error.
updated: 2026-09-07
---

# HudGate

Phase 6 stage 4 needs the combat HUD to disappear in the lobby and come back in
an arena. This page records why that is more than an `if` statement, and what
shape the answer takes. Companion to [[design/lobby]] § Player state and
[[concepts/BuilderConfigLayout]].

## The problem is the silent failure mode

A HUD element that wrongly *hides* is reported in the first playtest. A HUD
element that wrongly *shows* in the lobby is a cosmetic wart nobody files, and
there will be one for every element somebody forgot. So the design goal is not
"a way to hide things" — it is **making it impossible to add a HUD element
without deciding what it does in the lobby.**

That is why the policy is a *required argument* rather than an optional call.

## Two obvious approaches that do not work

**Gate whole layout regions.** Dead on arrival: the regions mix policies.
`DashButtonGui` and `SpellMenuGui` both register to `BottomRight`, and the
lobby keeps movement while suppressing casting. `TopRight` mixes `BuffTrayGui`
with `KillFeedGui`. Region granularity is coarser than the decision.

**Call `:disable()` on each controller.** There is nothing to call it on. Every
file in `src/client/UI/` is a top-level LocalScript that builds, registers,
connects and ends; none constructs a lifecycle object. `PlayerSession.luau` is
the only client file carrying the project's `disable`/`destroy` pair. The
convention in [[CLAUDE.md]] does not reach the HUD.

## The HUD is split down the middle

An audit of how the 14 scripts in `src/client/UI/` attach to the screen — the
thing that determines where a gate can even be applied:

| Attachment | Scripts | Gate point |
|---|---|---|
| `HudLayoutManager:register` into a region frame | 7 scripts, **9 elements** (`GameplayHudGui` registers three) | `element.Visible` |
| Own `ScreenGui` parented to `PlayerGui` | 6 — `BossHudGui`, `DamageFeedbackGui`, `DeathScreenGui`, `GameStateGui`, `RoundTimerGui`, `ScoreboardGui` | `screenGui.Enabled` |
| Builder handle straight to `PlayerGui` | 1 — `SettingsMenuGui` | n/a, policy is `Always` |

So a required argument on `register` alone would cover **9 of 16** gate points.
The other half needs a second entry point. This is not two idioms — it is one
idiom (*declare a policy*) with two adapters, because two attachment styles
already exist in the codebase.

> **Stale wiki note:** `wiki/systems/Boss.md` still says `BossHudGui` is
> "registered with HudLayoutManager TopCenter". It was moved to its own
> `ScreenGui` (see `wiki/log.md`, DisplayOrder 15, `IgnoreGuiInset`) and the
> page was never updated. Fix when touching that page.

## The design

**Vocabulary** — `Arena.STATE_ATTRIBUTE` / `Arena.PlayerState`
(`InLobby | Queued | InArena`), living in `Arena.luau` alongside the arena
identity it travels with, per [[design/lobby]] § Stage 4 detail decision 3.
Server-authoritative via `player:SetAttribute` — the pattern `SettingsMenuGui`
already uses. On the **Player**, not the character, so it survives respawn;
`ScreenGui.ResetOnSpawn` is already `false`.

**The gate is binary; the state is tri.** A queued player is standing in the
lobby, so `Queued` reads as lobby for visibility purposes. The three-way
distinction lives in `PlayerState`, where the portal actually needs it. The HUD
never asks a three-way question, which keeps policies to:

| Policy | Meaning |
|---|---|
| `Always` | visible in lobby and arena |
| `ArenaOnly` | hidden unless `InArena` |
| `LobbyOnly` | hidden when `InArena` — the portal panel and queue counts |

**Two adapters, one policy table:**

```lua
HudLayoutManager:register(region, element, policy)   -- required 3rd arg; sets .Visible
HudGate.bindScreenGui(screenGui, policy)             -- sets .Enabled
```

`HudLayoutManager` keeps owning layout and delegates the policy to `HudGate`,
which owns the attribute subscription. Making the argument required breaks all
9 existing call sites on purpose: each one becomes a deliberate decision, and
Luau flags any new element that skips it.

`Visible = false` is safe inside the stacked regions — `UIListLayout` excludes
invisible children, so a hidden element leaves no gap.

## Nil means visible

Before the server sets the attribute it is `nil`, and `nil` degrades to
**today's behaviour: shown**. Never to hidden.

This is the third time this project has faced the same fork and answered it the
same way — `Arena.idOf` treats a missing `ArenaId` as `Default` rather than an
error, and `BroadcastAudience` treats an unresolved roster as *everyone* rather
than nobody. In all three the reasoning is identical: the degraded path should
land on what already shipped, because a system that fails to silence is
debuggable and a system that fails to silence is not. Worth promoting to a
house rule if it comes up a fourth time.

## Triage

**The lobby teaches the full loop** (decided 2026-09-07): tap a block, buffer
letters, memorize for energy, cast at a target dummy. That collapses most of
the suppression list — everything the core verb touches has to be on screen, and
what stays hidden is only the round/competition chrome.

`GameplayHudGui` is still the case that justifies per-element granularity: it
registers **three** elements and they do not agree.

| Element | Policy | Why |
|---|---|---|
| `GameplayHudGui` → BufferDisplay (letter tiles) | `Always` | the buffer is the first half of the verb |
| `GameplayHudGui` → MemorizeButton | `Always` | the second half; the lobby grants real energy |
| `GameplayHudGui` → health bar | `ArenaOnly` | the dummy does not fight back |
| `SpellMenuGui` | `Always` | you cannot cast at the dummy without it |
| `MindFullIndicatorGui` | `Always` | part of the memorize loop |
| `DashButtonGui` | `Always` | movement is not mode-specific |
| `SettingsMenuGui` | `Always` | per [[design/lobby]] |
| `BuffTrayGui` | `Always` | self-buff spells are castable in the lobby. Moot today — the tray is unwired, exposed on `_G.PlayerHud.BuffTray` awaiting a BuffAdapter |
| `BossHudGui` | `ArenaOnly` | own ScreenGui, gated via `.Enabled` |
| `DamageFeedbackGui` | `ArenaOnly` | fires on damage *taken*; nothing in the lobby damages you |
| `KillFeedGui`, `ScoreboardGui`, `RoundTimerGui`, `GameStateGui`, `DeathScreenGui`, `TeamScoreGui` | `ArenaOnly` | round and competition surfaces with no lobby meaning |
| portal confirm panel, queue counts | `LobbyOnly` | arrive with stage 4 geometry |

`TeamScoreGui` is additionally suppressed at boot by `TEAMS_ENABLED`; the
policy is what it gets when teams return.

### The target dummy is nearly free

A lobby dummy needs **no new server code**. `DeathHandler` already watches the
`Damageable` tag: it clones a template on first sight, and on death respawns the
model at its remembered position after `RespawnTime`. So the dummy is an
authored model plus a tag plus an attribute — Studio work, not code.

It belongs to the `Lobby` arena, which means a lobby kill routes its kill-feed
entry to the lobby roster rather than the whole server. That already works:
`ScoreTracker.recordBotKill` anchors on the killer, and [[systems/GameMode]]
§ Broadcast audience resolves the audience from there.

### Practice blocks need no special case

The original plan said practice blocks "pop and buffer but grant no energy",
which would have needed a marker on the block. It was specifying the wrong seam
regardless: **the player-facing grant happens at memorize, not at pop** —
`MemorizeAction` calls `reservoirs:add(color, amount)` once a buffered word
validates. A pop does credit `EnergyLedger.creditBlock` server-side, but that is
the Phase 5.4 shadow ledger used to *price* a later memorize, not energy the
player can spend.

That distinction inverts the original plan. Because the lobby grants real
energy, lobby pops must reach the ledger **too** — a pop the ledger never saw
would make the memorize it feeds unaffordable the moment
`EconomyConstants.ENFORCE` flips true. So lobby blocks are ordinary blocks on
both paths, and there is nothing to special-case.

## Not covered by HudGate

`BlockTapController` is not a `GuiObject` and cannot be gated by visibility. It
reads `PlayerState` directly and adds the practice-block exception. Clean split:
**`HudGate` handles GuiObjects, `PlayerState` is the raw read anything can use.**

`ReticleBuilder` needs no policy — nothing in `src/` calls `build`, so it is
dead template code.

## Resolved: lobby energy does not follow you into the arena

Decided that the lobby grants **real** energy, which raises a balance question
the old no-energy plan sidestepped: a player can stand in the lobby filling
every reservoir to `CAP_PER_COLOR`, then queue and enter a duel already loaded.

`EnergyReservoirs` has `add` / `drain` / `destroy` and **no reset**, and nothing
clears it today.

**Decided 2026-09-07: reset at round start, not at arena entry** — because this
is not really a lobby problem. `RoundManager._activeRound`
already resets scores and does not reset energy, so round 2 of any multi-round
session inherits round 1's mana — a latent gap the lobby merely makes visible.
Fixing it where rounds begin fixes both.

Mechanically that is cheap: energy lives client-side in `PlayerSession`, and the
round already broadcasts its state to the session roster via `GameStateChanged`
(Phase 6 stage 1). The client can clear on the transition into `Active` using
plumbing that already exists. It needs `EnergyReservoirs:reset()` added.

Scheduled as stage 4 work — see [[design/lobby]] § Stage 4 detail.
