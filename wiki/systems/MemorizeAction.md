---
type: system
description: Phase 2 action — validates the buffered word, deposits value-weighted per-color energy into the reservoirs, and clears the buffer on success. Fizzle on empty/invalid; buffer preserved on fizzle.
updated: 2026-05-14
---

# MemorizeAction

The "Memorize" step of the gameplay loop (see [[design/gameplay-loop]] step 5). When the player taps the Memorize button, this module decides whether the buffered word transmutes into mana — and runs the deposit if it does.

MemorizeAction is a pure-Luau action module with no state of its own. It is a thin seam over four Phase 1 modules ([[systems/Dictionary]], [[systems/EnergyEconomy]], `WordBuffer`, [[systems/EnergyReservoirs]]) — Phase 2 deliberate placement so the action contract is in one file rather than scattered across a UI handler.

Phase 2 ([[design/build-plan]]) — tracker [NIM-6](tracker://NIM-6).

## Files

- `src/shared/MemorizeAction/init.luau` — the module (single function `tryMemorize`).
- `src/shared/MemorizeAction/__tests.luau` — smoke suite covering the four behaviors below; exports `M.run()`.

## API

```luau
local MemorizeAction = require(ReplicatedStorage.Shared.MemorizeAction)

MemorizeAction.tryMemorize(
    buffer: WordBuffer,
    reservoirs: EnergyReservoirs
) -> Result

export type Reason = "empty" | "invalid"

export type Result = {
    ok: boolean,
    reason: Reason?,                                  -- only on ok=false
    energyByColor: { [Color]: number }?,              -- only on ok=true
    word: string?,                                    -- only on ok=true
}
```

`Color` is `"red" | "green" | "blue"` per [[systems/EnergyReservoirs]] and [[systems/EnergyEconomy]].

## Behavior

| Buffer state | Word valid? | Result | Side effects |
|---|---|---|---|
| empty | — | `{ ok = false, reason = "empty" }` | none |
| non-empty | no  | `{ ok = false, reason = "invalid" }` | none — **buffer preserved** |
| non-empty | yes | `{ ok = true, energyByColor = split, word = word }` | reservoirs += split; buffer cleared |

### Failure modes

- **Empty** — fast-path; logged at `info` (not warn — it's not abnormal, just a no-op the HUD may also visualize as a soft fizzle).
- **Invalid** — the dictionary rejected the word. The buffer is **not cleared** so the player can correct typos without retyping. This is a deliberate design call (see [[design/gameplay-loop|"Memorize (commit button)"]]).

### Success path

The success path runs in this order:

1. Compute `word = buffer:asWord()` (uppercase — `WordBuffer:asWord` already uppercases).
2. Snapshot tiles via `buffer:tiles()` (defensive copy — caller mutation is safe).
3. Split via `EnergyEconomy.splitByColor(tiles)` — the floor-reconciled algorithm that guarantees `Σ split values == computeWordEnergy(word)` exactly. See [[systems/EnergyEconomy#splitByColor]].
4. For each `(color, amount)` in the split: `reservoirs:add(color, amount)`. Per [[systems/EnergyReservoirs]] each add caps at 160 silently; overshoot is design-intentional.
5. `buffer:clear()` AFTER the split has been computed.
6. Return `{ ok = true, energyByColor = split, word = word }`.

The clear happens last because `tiles()` and `asWord()` both read buffer state. Reservoir adds also precede the clear, but only because there is no observable consequence — both must succeed.

## Signal ordering caveat

This module calls synchronous methods only — `tryMemorize` returns once `add` and `clear` have run. But the `.changed` signals those calls emit on `WordBuffer` and `EnergyReservoirs` are backed by `BindableEvent`s in **Deferred mode** — handlers fire on the *next* resumption cycle, not synchronously. Practical consequences:

- A caller that connects to `buffer.changed` or `reservoirs.changed` to observe the deposit will **not** see the handler run before `tryMemorize` returns. The handler runs on the next yield.
- Tests that wire up such a listener must `task.wait()` between `tryMemorize` and asserting handler-side effects. The smoke tests here do not connect to either signal so they remain synchronous.
- HUD code (BufferDisplay, ReservoirBars) inherits this lag, but ≤ 1 frame is fine for a bar paint.

See [[systems/EnergyReservoirs#Signal semantics]] and `WordBuffer`'s "Why a BindableEvent" note for the underlying reason.

## Consumers (planned)

- **HUD: MemorizeButton** ([[design/build-plan]] Phase 4) — calls `tryMemorize`, dispatches to the shake/flash animation on `ok = false`, and emits the visible letters-flowing-into-bars effect on `ok = true`.
- **Tutorial / first-cast prompt** — may inspect the returned `word` to confirm the player Memorized the tutorial-target word.

This module deliberately does **not** call any other system. It does not emit signals, does not touch the HUD, does not write to attributes — the HUD reads `Result` from the caller. Per [[concepts/SingleOwnership]], the HUD listens to `WordBuffer.changed` / `EnergyReservoirs.changed` to repaint, NOT to anything from MemorizeAction.

## Verification

Run the smoke suite from MCP `execute_luau` or the Studio command bar during a playtest:

```luau
require(game.ReplicatedStorage.Shared.MemorizeAction.__tests).run()
```

A passing run prints `[MemorizeAction.__tests] all scenarios passed`. A failed assertion errors with the scenario's message.

The four scenarios mirror the NIM-6 brief exactly:

| # | Scenario | Pinned outcome |
|---|---|---|
| 1 | empty buffer | `ok=false, reason="empty"`, no mutation |
| 2 | invalid "XYZ" | `ok=false, reason="invalid"`, buffer preserved at "XYZ" |
| 3 | valid mono-color "FIRE" (all red) | `red=7`, buffer cleared |
| 4 | valid mixed-color "FLAME" (F-L-M red, A-E green) | `red=12, green=3`; reservoir accumulates on top of pre-existing red |

The "FIRE" and "FLAME" expected values come from the pinned tables in [[design/gameplay-loop#Worked examples]] and [[design/gameplay-loop#Color-split worked examples]]. If they drift here, the formula is wrong — fix the implementation, not the test.

## Cross-references

- [[design/gameplay-loop]] — Memorize step (#5); "Memorize (commit button)" subsection; worked-examples tables.
- [[design/build-plan]] — Phase 2 placement; parallel-safe with `SpellExecutor` and `MindFullManager`.
- [[systems/Dictionary]] — supplies `isWord(word)`.
- [[systems/EnergyEconomy]] — supplies `splitByColor(tiles)`.
- WordBuffer (`src/shared/WordBuffer/init.luau`) — read via `:size`, `:asWord`, `:tiles`; mutated via `:clear` on success.
- [[systems/EnergyReservoirs]] — mutated via `:add(color, amount)` on success.
- [[concepts/SingleOwnership]] — only MemorizeAction writes via `:add` on the reservoirs; only MemorizeAction issues `:clear` on the buffer.
