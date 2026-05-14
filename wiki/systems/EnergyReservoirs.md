---
type: system
description: Pure-Luau state container for the three per-color energy bars (red/green/blue). Caps at 160 per color, emits a `changed(color)` signal on every value change.
updated: 2026-05-14
---

# EnergyReservoirs

Per-color persistent energy state. Memorizing a valid word deposits value-weighted energy into red/green/blue buckets; casting a spell drains the bucket of the spell's color by the tier cost. This module owns the numbers and nothing else — it doesn't know about tiers, spells, words, or HUD.

Phase 1 foundation module (see [[design/build-plan]]). Tracker [NIM-5](tracker://NIM-5).

## Files

- `src/shared/EnergyReservoirs/init.luau` — the module.
- `src/shared/EnergyReservoirs/__tests.luau` — self-contained smoke tests (see [Verification](#verification)).

## API

```luau
EnergyReservoirs.new() -> instance
:get(color) -> number
:add(color, amount: number)         -- caps at 160; non-positive is no-op
:canAfford(color, n: number) -> boolean
:drain(color, n: number) -> boolean -- false if can't afford; value unchanged on failure
:snapshot() -> { red, green, blue } -- defensive copy
:destroy()
.changed: RBXScriptSignal           -- fires :Fire(color) on every value change
EnergyReservoirs.CAP_PER_COLOR = 160
EnergyReservoirs.COLORS = { "red", "green", "blue" }
```

`color` is the string literal `"red" | "green" | "blue"`. Passing any other value raises `EnergyReservoirs: unknown color "..." (expected one of: red, green, blue)`.

## Cap rationale

`CAP_PER_COLOR = 160` = **2× T3 (80)**. This is the tightest cap that

- *absorbs* the overshoot from one huge single-color word — `EARTHQUAKES`=81 and `CHARACTERIZE`=84 both land entirely inside the cap, so the player isn't punished for occasionally landing a monster word, and
- *blocks* indefinite stockpiling — anyone who keeps Memorizing same-color words past 160 starts dropping energy on the floor, which is the design's deliberate brake on "hoard letters then nuke."

Pinned in `wiki/design/gameplay-loop.md` "Spell economy". The number is a tuning lever, not a load-bearing invariant — if playtest shows the cap is too tight (every long word overflows) or too loose (T3 stockpiling trivializes bosses), bump or pin it in code, then update both this page and the design doc.

## Signal semantics

`.changed` is implemented as a `BindableEvent.Event`. **Roblox runs BindableEvent connections in Deferred mode by default**, so a handler fires on the next resumption cycle, not synchronously inside `:add` / `:drain`. Practical consequences:

- HUD bars connected to `.changed` will visibly lag the underlying state by ≤ 1 frame. For an energy bar that's fine — and consistent with every other Roblox state-bar pattern.
- Tests that fire `.changed` and then assert on the side effects must `task.wait()` between the operation and the assertion. The smoke tests in `__tests.luau` are written this way.
- Handlers should re-read state via `:get(color)` rather than assume what value triggered the fire — by the time the handler runs, several more `:add`/`:drain` calls may have happened.

The signal fires **on net change only**:

- `:add` with `amount <= 0` does not fire.
- `:add` that hits the cap (`current = 160`, `:add("red", 50)`) does not fire — `nextValue` equals `current`.
- `:drain` that can't afford the cost (returns `false`) does not fire — the value is unchanged.

This means a `.changed` fire reliably indicates an *actual* numerical change, so listeners don't need a `previousValue == newValue` guard.

## Color is a string, not an enum

`"red" | "green" | "blue"` literal-typed strings. Luau's type system enforces this at the consumer site without needing an Enum module, and string comparison is what the rest of the project's color-tagged data (LetterBlock attributes, spell config keys) already uses. If a fourth color ever earns its place, expand `COLORS` and the `Color` type union in one place; the rest of the module derives from it.

## Dependencies

- `Logger` (`src/shared/Core/Logger.luau`) — diagnostic warn before erroring on unknown-color.

No Roblox-instance dependencies beyond the internal `BindableEvent`. No knowledge of tiers, spells, words, or HUD — those live in [[systems/SpellRegistry]] (planned), [[systems/MemorizeAction]] (planned), and the eventual `HUD: ReservoirBars` builder.

## Consumers (planned)

- **MemorizeAction** — deposits via `:add` on every valid word.
- **CastAction** — drains via `:drain` on every spell cast; precomputes affordable tiers via `:canAfford`.
- **HUD: ReservoirBars** — subscribes to `.changed`, repaints the affected color bar.
- **SpellRegistry** — does not consume; owns the tier-threshold numbers (10 / 30 / 80) that callers compare against `:get(color)` and `:canAfford(color, threshold)`.

## Verification

Smoke test lives at `src/shared/EnergyReservoirs/__tests.luau`. Each scenario covers one invariant (initial-state, add/cap/no-op, canAfford boundary, drain success/failure, snapshot is defensive, unknown-color rejects).

```luau
-- From MCP execute_luau or the Studio command bar, during a playtest:
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local tests = require(ReplicatedStorage.Shared.EnergyReservoirs.__tests)
tests.run()
```

**Run inside a playtest** (or after a Studio restart) so ModuleScript cache is fresh — edit-mode `require` will return the first-loaded `__tests` body and silently ignore source updates from Rojo. This caught me once during build; the smoke tests inline the operations themselves so re-loading `EnergyReservoirs` (the module under test) does pick up Rojo changes, but the `__tests` *runner* file may not.

A failed scenario raises `error([EnergyReservoirs.__tests] <scenario> — <message>)` with a stack pointing at the failed line.

## Cross-references

- [[design/gameplay-loop]] — Spell economy: per-color persistence, cap rationale, value-weighted color split.
- [[design/build-plan]] — Phase 1 foundation modules.
- [[systems/SpellRegistry]] — sibling foundation; owns the tier thresholds (10 / 30 / 80) callers compare against.
- [[concepts/SingleOwnership]] — only `MemorizeAction` writes via `:add`, only `CastAction` writes via `:drain`; HUD listens but never writes.
