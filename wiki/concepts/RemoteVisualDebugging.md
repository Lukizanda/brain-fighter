---
type: concept
description: 5-layer diagnostic checklist for multiplayer visual bugs — "works for me but not for other clients"
updated: 2026-05-14
---

# Remote Visual Debugging

When a multiplayer FX, animation, or sound "works for the actor but doesn't replicate to other clients," walk this checklist top-to-bottom with a log at each step. Don't guess — instrument.

## The 5-layer chain

**1. Server fires the replication remote.**
Log at the `:FireClient(otherPlayer, ...)` site: recipient name, payload size, key args. If this log is missing, the server-side code path never reached the broadcast — validation failed silently, a loop excluded everyone, etc.

**2. The receiving client's handler script is actually loaded.**
Log at the script's top level (`log:info("loaded as LocalPlayer=...")`) and at the `OnClientEvent:Connect` line. If those don't appear, the script isn't running — most often because a `.client.luau` was placed in `src/shared/` (ReplicatedStorage) where Roblox doesn't auto-run LocalScripts. Move to `src/client/` or wrap in a runner. See [[concepts/LocalScriptPlacement]].

**3. The remote signal arrives.**
Log at the start of the `OnClientEvent` handler with the same args. If step 1 logs but step 3 doesn't, the remote isn't replicating — check that `:FireClient` is targeting the right Player, the RemoteEvent path matches between sender and receiver, and the sending script isn't erroring before the `FireClient` call.

**4. Required modules and lookups resolve.**
Log every `FindFirstChild`, attribute read, and `require` result that gates the visual. Wrong-path bugs surface here. If a Tool is referenced, log `IsDescendantOf(game)` — streaming or Backpack-vs-Character placement can leave the tool unstreamed on remote clients.

**5. Effect actually instantiates.**
Log entry and exit of the draw/play function, plus any early-returns inside it. The effect module may bail on `distance < epsilon`, a missing template instance, or missing attachments.

## How to apply

- The moment a multiplayer visual "works for me but not for others," reach for this checklist before forming theories. Every guess without logs costs a playtest cycle (~minutes); every log added costs seconds.
- For Tool-attached visuals (muzzle flashes, ribbon trails), the tool may not be streamed in on remote clients. Always nil-check `Handle`, `MuzzleAttachment`, `Sounds.Shoot` etc. via `FindFirstChild` rather than direct indexing — direct indexing throws and aborts the whole replication handler silently.
- Remove diagnostic logs once the bug is pinned. Per-shot/per-frame logs left in place degrade future debugging signal-to-noise.

## Cross-references

- [[concepts/LocalScriptPlacement]] — where `.client.luau` files must live to auto-run
- [[concepts/ClientServerPredictionParity]] — shared module logic must match on both sides
- [[systems/Weapon]] — `ReplicateShot` UnreliableRemote is the canonical example of this pattern
