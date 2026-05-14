---
type: system
description: Client input handler — left-click raycast consumes a LetterBlock and appends (letter, color) to the player's WordBuffer. Server validates and destroys the block.
updated: 2026-05-14
---

# BlockShoot

The input handler that turns "player clicked a floating letter block" into a `(letter, color)` tile in the player's [[systems/WordBuffer]]. Client-authoritative for append (the player's own buffer is local state); server-authoritative for block destruction (shared resource).

## Files

- `src/shared/BlockShoot/init.luau` — shared helpers: `findLetterBlock` (ancestor traversal), `readBlock` (attribute reader), `MAX_RAYCAST_DISTANCE` constant.
- `src/shared/BlockShoot/Remotes/ConsumeBlock.model.json` — RemoteEvent for client→server block destruction.
- `src/client/BlockShootBoot.client.luau` — LocalScript: wires `UserInputService.InputBegan` → raycast → consume → fire remote.
- `src/server/BlockShoot/BlockShootService.server.luau` — server handler: validates block is tagged, destroys it (triggers BlockSpawner auto-refill).
- `src/client/PlayerSession.luau` — ModuleScript: lazy-creates and caches the player's WordBuffer + MindFullManager + EnergyReservoirs.

## Flow

1. Player left-clicks.
2. `BlockShootBoot` checks `MindFullManager:isMindFull()` — blocks input when buffer is at 12/12.
3. Raycast from camera through mouse position, excluding the player's character.
4. If the hit instance is inside a tagged `LetterBlock` Model (ancestor walk via `findLetterBlock`), read `Block.Letter` + `Block.Color` attributes.
5. `WordBuffer:append(letter, color)` on the local session buffer.
6. Fire `ConsumeBlock` remote to the server with the block Model reference.
7. Server validates (Instance? Model? tagged?) and calls `block:Destroy()`.
8. The `CollectionService` removed signal triggers [[systems/BlockSpawner]]'s auto-refill to maintain target count.

## MindFull gate

When the buffer hits 12/12, [[systems/MindFullManager]] fires `mindFull`. BlockShootBoot simply polls `:isMindFull()` on each click — no signal wiring needed because the check is cheap and the gate is checked exactly once per input event. When the player removes tiles or memorizes a word, the buffer shrinks and `:isMindFull()` returns false, re-enabling input.

## PlayerSession

`PlayerSession.luau` is a client ModuleScript that lazy-creates and caches the player's per-session state:

| Field | Type | Notes |
|---|---|---|
| `wordBuffer` | `WordBuffer` | 12-slot buffer |
| `mindFullManager` | `MindFullManager` | Transition watcher over the buffer |
| `energyReservoirs` | `EnergyReservoirs` | 3-color energy store (for Phase 4 MemorizeAction + CastAction wiring) |

Any client system that needs player state calls `PlayerSession.get()` rather than constructing its own. Phase 4 HUD scripts will require the same module.

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
