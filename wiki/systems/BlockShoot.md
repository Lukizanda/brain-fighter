---
type: system
description: Shared helpers and server handler for block consumption. Client input is handled by LetterBlaster (Phase 4.6) — see [[systems/LetterBlaster]].
updated: 2026-06-05
---

# BlockShoot

Shared library and server handler for the letter-block consume pipeline. The client-side input wiring (Phase 3: `BlockShootBoot`) was replaced in Phase 4.6 by the [[systems/LetterBlaster]] Tool — see that page for the current input flow. This page covers the shared helpers and server handler, which are unchanged.

## Files

- `src/shared/BlockShoot/init.luau` — shared helpers: `findLetterBlock` (ancestor traversal), `readBlock` (attribute reader), `MAX_RAYCAST_DISTANCE` constant.
- `src/shared/BlockShoot/Remotes/ConsumeBlock.model.json` — RemoteEvent for client→server block destruction.
- `src/server/BlockShoot/BlockShootService.server.luau` — server handler: validates block is tagged, destroys it (triggers BlockSpawner auto-refill).
- `src/client/PlayerSession.luau` — ModuleScript: lazy-creates and caches the player's WordBuffer + MindFullManager + EnergyReservoirs.

> **Phase 4.6:** `src/client/BlockShootBoot.client.luau` was deleted. The `ConsumeBlock` remote is now fired by [[systems/LetterBlaster]].

## Flow

The input side now runs inside the [[systems/LetterBlaster]] controller (`LetterBlaster:_onActivated`); the steps below describe the end-to-end consume path. Only steps 4–8 (the helpers + server handler) live in this module.

1. Player activates the Spelling Staff Tool (`Tool.Activated`).
2. `LetterBlaster` checks `MindFullManager:isMindFull()` — blocks the shot when the buffer is at 12/12.
3. Raycast from camera through mouse position, excluding the player's character.
4. If the hit instance is inside a tagged `LetterBlock` Model (ancestor walk via `findLetterBlock`), read `Block.Letter` + `Block.Color` attributes (`readBlock`).
5. `WordBuffer:append(letter, color)` on the local session buffer.
6. Fire `ConsumeBlock` remote to the server with the block Model reference.
7. Server handler validates (Instance? Model? tagged?) and calls `block:Destroy()`.
8. The `CollectionService` removed signal triggers [[systems/BlockSpawner]]'s auto-refill to maintain target count.

## MindFull gate

When the buffer hits 12/12, [[systems/MindFullManager]] fires `mindFull`. `LetterBlaster` simply polls `:isMindFull()` on each activation — no signal wiring needed because the check is cheap and the gate is checked exactly once per input event (a blocked shot plays `FizzleSound`). When the player removes tiles or memorizes a word, the buffer shrinks and `:isMindFull()` returns false, re-enabling input.

## PlayerSession

`PlayerSession.luau` is a client ModuleScript that lazy-creates and caches the player's per-session state:

| Field | Type | Notes |
|---|---|---|
| `wordBuffer` | `WordBuffer` | 12-slot buffer |
| `mindFullManager` | `MindFullManager` | Transition watcher over the buffer |
| `energyReservoirs` | `EnergyReservoirs` | 3-color energy store (consumed by MemorizeAction + CastAction) |

Any client system that needs player state calls `PlayerSession.get()` rather than constructing its own — the HUD gameplay widgets (BufferDisplay, MemorizeButton, SpellMenu) and LetterBlaster all share this one instance.

## Security

The server handler validates every remote payload:
- `typeof(block) == "Instance"` — rejects non-Instance garbage.
- `block:IsA("Model")` — rejects arbitrary instances.
- `CollectionService:HasTag(block, "LetterBlock")` — rejects untagged models.

No rate-limiting for Phase 3 (PvE single-player). For multiplayer, add a per-player cooldown or claimed-set to prevent double-consume races.

## See also

- [[systems/LetterBlock]] — the entity BlockShoot consumes.
- [[systems/BlockSpawner]] — auto-refills when blocks are destroyed.
- [[systems/WordBuffer]] — destination for consumed tiles.
- [[systems/MindFullManager]] — input gate when buffer is full.
- [[design/gameplay-loop]] — "Buffer & input" section.
