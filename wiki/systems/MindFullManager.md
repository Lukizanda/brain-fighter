---
type: system
description: Phase 2 transition watcher over WordBuffer — emits rising-edge `mindFull` / falling-edge `mindFreed` signals so the shoot-gate and HUD only react when buffer fullness flips.
updated: 2026-05-14
---

# MindFullManager

Phase 2 observer that turns the WordBuffer's continuous `.changed` stream into discrete **rising-edge** / **falling-edge** signals around the "buffer full" predicate. Realizes the diegetic rule from [[design/gameplay-loop|gameplay-loop "Buffer & input"]]: *"Buffer-full blocks shooting — the wizard's mind is at capacity."*

Downstream consumers don't want to re-evaluate `buffer:isFull()` on every reorder or interior remove — they only care when the answer **changes**. This module is the edge detector that gives them that.

## Files

- `src/shared/MindFullManager/init.luau` — the module.
- `src/shared/MindFullManager/__tests.luau` — smoke tests (returns a `M.run()` function).

## API

`require(ReplicatedStorage.Shared.MindFullManager)` returns the module table.

| Member | Type | Notes |
|---|---|---|
| `.new(buffer)` | `(WordBuffer) -> MindFullManager` | Hooks `buffer.changed`. Seeds internal `_wasFull` from `buffer:isFull()` so constructing over an already-full buffer does not synthesize a phantom rising edge. |
| `:isMindFull()` | `() -> boolean` | Cheap; reads the live buffer. Safe to call from inside a `.mindFull` / `.mindFreed` handler. |
| `.mindFull` | `RBXScriptSignal` | Fires (no args) on the **rising edge** — buffer just transitioned to full. |
| `.mindFreed` | `RBXScriptSignal` | Fires (no args) on the **falling edge** — buffer was full and is no longer. |
| `:destroy()` | `() -> ()` | Disconnects from `buffer.changed`, destroys both BindableEvents. Idempotent. |

## Semantics

- **Transitions only, not level-triggered.** The manager tracks `_wasFull` internally; each `buffer.changed` fire computes `nowFull = buffer:isFull()` and emits only if `nowFull ≠ _wasFull`. Reorders, interior removes, and any append/remove that leaves the size on the same side of the cap produce **no** signal.
- **Two signals, not one.** Splitting rising-edge from falling-edge means downstream wiring is direct — BlockShoot connects `mindFull` to disable input and `mindFreed` to re-enable, no `if isMindFull()` branch needed. The HUD: MindFullIndicator does the same for show/hide.
- **Deferred dispatch.** Both signals are `BindableEvent.Event` instances; Roblox runs these in Deferred mode by default, so handlers fire on the next resumption cycle, not synchronously inside the buffer mutation that triggered the transition. Smoke tests `task.wait()` between mutating the buffer and asserting on fire counts. Handlers that need the current state should re-read `:isMindFull()` — do not assume the signal arrived "because of" any specific preceding `:append` / `:remove` call.
- **Born-full is silent.** Constructing the manager over an already-full buffer seeds `_wasFull = true`. The first observed transition is therefore a genuine falling edge (when the player frees a slot), not a phantom rising edge on the next `.changed` fire.
- **Over-cap append is silent.** [[systems/WordBuffer|WordBuffer]]`:append` returns `false` without firing `.changed` when the buffer is full. The manager therefore observes no event at all — `mindFull` is not re-fired on the 13th, 14th, 15th attempts. This is correct: rising-edge semantics only count the first one.

## Consumers

- **BlockShoot** (Phase 3) — subscribes to `mindFull` / `mindFreed` to gate shoot input. When `mindFull` fires, the shoot pipeline rejects hits with diegetic feedback (fizzle, greyed crosshair); `mindFreed` restores normal input.
- **HUD: MindFullIndicator** (Phase 4) — subscribes to both signals to flash and persist a "mind full" visual cue. Re-reads `:isMindFull()` on construction to render correct initial state.

Both consumers are write-once — the manager is constructed once per local player session, and `mgr.mindFull` / `mgr.mindFreed` are `:Connect`'d for the manager's lifetime.

## Construction pattern

```luau
local WordBuffer = require(ReplicatedStorage.Shared.WordBuffer)
local MindFullManager = require(ReplicatedStorage.Shared.MindFullManager)

local buffer = WordBuffer.new()
local mindFull = MindFullManager.new(buffer)

mindFull.mindFull:Connect(function()
    -- input gate / HUD indicator on
end)
mindFull.mindFreed:Connect(function()
    -- input gate / HUD indicator off
end)
```

When tearing the local session down: `mindFull:destroy()` first, then `buffer:destroy()`. The reverse order would leave the manager subscribed to a destroyed buffer; `destroy()` order matters because Roblox does not synchronously notify subscribers of `BindableEvent:Destroy()`.

## Why not put this logic in WordBuffer itself

Single Ownership ([[concepts/SingleOwnership]]) — WordBuffer owns *buffer state*. Whether-the-mind-is-full is a derived predicate, and the edge-detection bookkeeping (`_wasFull`) is a piece of stateful interpretation that does not belong in the data container. Splitting them keeps WordBuffer pure-state and lets the gameplay rule ("full blocks shooting") live in a module whose name announces the rule.

It also keeps the test surface small: WordBuffer's smoke tests do not need to assert edge counts, and MindFullManager's smoke tests do not need to re-prove buffer invariants — each module's tests are tightly scoped to its own contract.

## Test

`__tests.luau` exports a `M.run()` function. Invoke from MCP execute_luau:

```luau
require(ReplicatedStorage.Shared.MindFullManager.__tests).run()
```

Scenarios covered:

1. **Brief-pinned end-to-end** — fill 11 (no fires) → 12 (one `mindFull`) → 13th rejected (no fire) → remove (one `mindFreed`) → refill (second `mindFull`) → destroy + remove (no further `mindFreed`).
2. **Non-cap churn** — appends, reorders, and removes that all stay below the cap fire zero transitions.
3. **clear() from full** — one rising edge to reach full, then `clear()` produces exactly one falling edge.
4. **Born-full construction** — manager over an already-full buffer does not emit a phantom rising edge; the first observed transition is the falling edge on `remove(1)`.

## Cross-references

- [[design/gameplay-loop]] — the canonical design; especially "Buffer & input → buffer-full blocks shooting."
- [[systems/WordBuffer]] — the state container this watches.
- [[design/build-plan]] — Phase 2 module; one of three parallel-safe Phase 2 actions (with MemorizeAction and SpellExecutor).
- [[concepts/SingleOwnership]] — rationale for splitting edge-detection out of WordBuffer.
