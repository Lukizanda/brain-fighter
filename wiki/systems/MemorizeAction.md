---
type: system
description: Phase 2 action — validates the buffered word, deposits value-weighted per-color energy into the reservoirs, and clears the buffer. Fizzle on empty (no mutation) or invalid (buffer cleared — letters consumed regardless).
updated: 2026-07-27
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
    word: string?,                                    -- only on ok=true; the CONCRETE word, e.g. "DOG"
    pattern: string?,                                 -- what was buffered, e.g. "D*G"; also set on reason="invalid"
}
```

`Color` keys in `energyByColor` are `"red" | "green" | "blue"` per [[systems/EnergyReservoirs]] and [[systems/EnergyEconomy]]. Tile colors additionally include `"wild"`, which is never a key here — see [[systems/Wildcard]].

`word` vs `pattern`: with no wildcards they are equal. With wildcards, `pattern` is what the player assembled (`D*G`) and `word` is what it resolved to (`DOG`). `pattern` is populated on an invalid result too, so the HUD can show what fizzled.

## Behavior

| Buffer state | Word valid? | Result | Side effects |
|---|---|---|---|
| empty | — | `{ ok = false, reason = "empty" }` | none |
| non-empty | no  | `{ ok = false, reason = "invalid", pattern = pattern }` | **buffer cleared** — letters consumed |
| non-empty | yes | `{ ok = true, energyByColor = split, word = word, pattern = pattern }` | reservoirs += split; buffer cleared |

### Failure modes

- **Empty** — fast-path; logged at `info` (not warn — it's not abnormal, just a no-op the HUD may also visualize as a soft fizzle). No state mutation.
- **Invalid** — the buffer content could not be resolved to any dictionary word. The buffer is **cleared anyway** — letters are consumed regardless, so a bad commit costs the player the collected letters and they must re-collect. This is a deliberate design call (see [[design/gameplay-loop|"Memorize (commit button)"]]).

### Success path

The success path runs in this order:

1. Compute `pattern = buffer:asWord()` (uppercase). With [[systems/Wildcard]] tiles in the buffer this is a pattern like `D*G`, not necessarily a word.
2. `word = Dictionary.resolve(pattern, EnergyEconomy.computeWordEnergy)` — collapses the pattern to the concrete match worth the most energy, or `nil` to fail. Every candidate is the same length, so maximizing whole-word energy is exactly maximizing the letters the stars stand in for. A wildcard-free pattern resolves to itself via an O(1) lookup, so this is also the plain path.
3. Snapshot tiles via `buffer:tiles()` (defensive copy — caller mutation is safe).
4. **Stamp the resolved letter onto every tile** (`tile.letter = word:sub(i, i)`), so wildcards score as the letter they became. Colors are deliberately left alone — a wild tile stays `"wild"` so the split still spreads its energy across all three reservoirs rather than banking it in one.
5. Split via `EnergyEconomy.splitByColor(tiles)` — the floor-reconciled algorithm that guarantees `Σ split values == computeWordEnergy(word)` exactly. See [[systems/EnergyEconomy#splitByColor]].
6. For each `(color, amount)` in the split: `reservoirs:add(color, amount)`. Per [[systems/EnergyReservoirs]] each add caps at 60 silently; overshoot is design-intentional.
7. `buffer:clear()` AFTER the split has been computed.
8. Return `{ ok = true, energyByColor = split, word = word, pattern = pattern }`.

Step 4 is the hinge of the wildcard feature: stamping the letter but *not* the color is what lets a star score as a real letter and still spread three ways.

The clear happens last because `tiles()` and `asWord()` both read buffer state. Reservoir adds also precede the clear, but only because there is no observable consequence — both must succeed.

## Signal ordering caveat

This module calls synchronous methods only — `tryMemorize` returns once `add` and `clear` have run. But the `.changed` signals those calls emit on `WordBuffer` and `EnergyReservoirs` are backed by `BindableEvent`s in **Deferred mode** — handlers fire on the *next* resumption cycle, not synchronously. Practical consequences:

- A caller that connects to `buffer.changed` or `reservoirs.changed` to observe the deposit will **not** see the handler run before `tryMemorize` returns. The handler runs on the next yield.
- Tests that wire up such a listener must `task.wait()` between `tryMemorize` and asserting handler-side effects. The smoke tests here do not connect to either signal so they remain synchronous.
- HUD code (BufferDisplay, ReservoirBars) inherits this lag, but ≤ 1 frame is fine for a bar paint.

See [[systems/EnergyReservoirs#Signal semantics]] and `WordBuffer`'s "Why a BindableEvent" note for the underlying reason.

## Consumers

- **HUD: MemorizeButton** (shipped — [[systems/HUD]]) — calls `tryMemorize`, dispatches to the shake/flash animation on `ok = false`, and emits the visible letters-flowing-into-bars effect on `ok = true`.
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
| 2 | invalid "XYZ" | `ok=false, reason="invalid"`, buffer cleared |
| 3 | valid mono-color "FIRE" (all red) | `red=7`, buffer cleared |
| 4 | valid mixed-color "FLAME" (F-L-M red, A-E green) | `red=12, green=3`; reservoir accumulates on top of pre-existing red |

The "FIRE" and "FLAME" expected values come from the pinned tables in [[design/gameplay-loop#Worked examples]] and [[design/gameplay-loop#Color-split worked examples]]. If they drift here, the formula is wrong — fix the implementation, not the test.

## Cross-references

- [[design/gameplay-loop]] — Memorize step (#5); "Memorize (commit button)" subsection; worked-examples tables.
- [[design/build-plan]] — Phase 2 placement; parallel-safe with `SpellExecutor` and `MindFullManager`.
- [[systems/Dictionary]] — supplies `resolve(pattern, scoreFn)`.
- [[systems/Wildcard]] — why resolution and letter-stamping exist at all.
- [[systems/EnergyEconomy]] — supplies `splitByColor(tiles)`.
- WordBuffer (`src/shared/WordBuffer/init.luau`) — read via `:size`, `:asWord`, `:tiles`; mutated via `:clear` on success.
- [[systems/EnergyReservoirs]] — mutated via `:add(color, amount)` on success.
- [[concepts/SingleOwnership]] — MemorizeAction writes via `:add` on the reservoirs (CastAction also `:add`s on its refund path); MemorizeAction issues `:clear` on the buffer on both the success and invalid paths.
