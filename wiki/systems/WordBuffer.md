---
type: system
description: 12-slot color-tagged word buffer — pure-Luau state container for the word being spelled. Append-on-shot, drag-to-reorder, double-tap-to-destroy. Drains on Memorize.
updated: 2026-05-14
---

# WordBuffer

Pure-Luau state container for the word currently being spelled. The buffer is the only place words are constructed — letter blocks shot in the arena append here, the player rearranges tiles into a real word, and [[systems/MemorizeAction]] validates + drains the buffer into the color reservoirs.

Capacity is **12 tiles** (`DEFAULT_CAP`), wide enough for any word a curated K-12 dictionary realistically contains while bounding letter hoarding. Each tile carries the color of the block it came from so energy can be split value-weighted across the three reservoirs — see [[design/gameplay-loop|gameplay-loop "Buffer & input"]].

## Files

- `src/shared/WordBuffer/init.luau` — the module.
- `src/shared/WordBuffer/__tests.luau` — smoke tests (returns a `runTests()` function).

## API

`require(ReplicatedStorage.Shared.WordBuffer)` returns the module table.

| Member | Type | Notes |
|---|---|---|
| `.new(cap?: number)` | constructor | Default cap `12`. Returns a fresh `WordBuffer` instance. |
| `:append(letter, color)` | `(string, "red" \| "green" \| "blue") -> boolean` | Returns `false` if full or color invalid. Fires `.changed` on success. |
| `:remove(index)` | `(number) -> ()` | 1-based. Out-of-range = warn + no-op. Subsequent tiles shift down. |
| `:reorder(fromIdx, toIdx)` | `(number, number) -> ()` | 1-based on both sides. Out-of-range = warn + no-op. `from == to` is a no-op (no fire). |
| `:clear()` | `() -> ()` | Empties all slots. Fires `.changed` only if there was something to clear. |
| `:asWord()` | `() -> string` | Concatenates letters in order, uppercased. Empty buffer → `""`. |
| `:colorBag()` | `() -> {[color]: number}` | Tile counts per color. Colors with 0 tiles **do not appear** as keys. |
| `:isFull()` | `() -> boolean` | `size() >= cap`. |
| `:size()` | `() -> number` | Current tile count. |
| `:tiles()` | `() -> {{letter, color}}` | Defensive copy — caller can mutate freely. |
| `.changed` | `RBXScriptSignal` | Fires *after* the mutation completes. Backed by a `BindableEvent` — `Connect`/`Once`/`Wait` all work. |
| `:destroy()` | `() -> ()` | Disconnects internal state. Idempotent. |

## Semantics

- **Append-on-shot, append-only.** The buffer is filled by [[systems/BlockShoot]] consuming letter-blocks. Tiles cannot be inserted at arbitrary positions — they always land at the end.
- **Drag-to-reorder, double-tap-to-destroy.** The HUD (see [[systems/HUD]] / `wiki/design/hud.mockup.html`) is the only consumer that exposes these gestures. The module just provides `:reorder` and `:remove` as the underlying primitives.
- **Buffer-full blocks shooting.** When `:isFull()`, the shoot pipeline should reject the hit with diegetic feedback (fizzle / "mind full" indicator); see [[systems/MindFullManager]]. The buffer itself just returns `false` from `:append` — feedback is the caller's job.
- **Per-color split happens elsewhere.** `:colorBag()` is informational. The actual energy split lives in [[systems/EnergyEconomy]] (`splitByColor(tiles)`), which the MemorizeAction calls with `buffer:tiles()`.
- **`.changed` fires once per successful mutation.** No-op operations (out-of-range index, full append, clear-when-empty, `reorder(i,i)`) do not fire. This matters for HUD subscribers that re-render on each signal.

## Consumers

- [[systems/MemorizeAction]] — reads `asWord()` for dictionary lookup, reads `tiles()` for color-split, calls `clear()` on valid commit.
- [[systems/MindFullManager]] — subscribes to `.changed` to flip the "mind full" HUD indicator when `isFull()` flips.
- HUD: BufferDisplay — subscribes to `.changed`, reads `tiles()` for tile rendering, wires the drag-to-reorder + double-tap-to-destroy gestures to `:reorder` / `:remove`.
- [[systems/BlockShoot]] — calls `:append(letter, color)` on each successful letter-block hit.

## Test

`__tests.luau` exports a `runTests()` function that runs the smoke spec from [[NIM-4]] inline:

```luau
local runTests = require(ReplicatedStorage.Shared.WordBuffer.__tests)
runTests()  -- throws on assertion failure, prints "[TEST PASS]" otherwise
```

Covers: empty-state queries, three-append change-count, color-bag, reorder, remove, clear, fill-to-cap rejection, out-of-range guards, invalid-color rejection, destroy.

## Why a BindableEvent and not a custom Signal class

The project does not have a shared signal helper in `src/shared/Core/` or `src/utility/`, and the sibling [[systems/EnergyReservoirs]] module being built in parallel uses the same `BindableEvent` pattern for its per-color signals. Keeping both modules on the same primitive avoids divergence and means HUD code can subscribe to `.changed` on either with identical idioms.

## Cross-references

- [[design/gameplay-loop]] — the canonical design; especially the "Buffer & input" subsection.
- [`wiki/design/hud.mockup.html`](../design/hud.mockup.html) — visual reference for the buffer strip + tile interactions.
- [[design/build-plan]] — phased construction order; WordBuffer is a Phase 1 foundation module with zero dependencies.
- [[concepts/SingleOwnership]] — only this module mutates buffer state; HUD reads via `tiles()`, never writes to the internal array.
