# Player-facing output (VFX / SFX)

**The server has no screen and no speakers. Every client draws anything a player must see or hear; the server never does.**

This has shipped as a bug three times (see `wiki/log.md`, 2026-08-04) because the engine only fails *partially*:

| Server-side call | Reaches players? |
|---|---|
| `ParticleEmitter:Emit()` | **No**, it isn't replicated. Most of `VfxConfig.EFFECTS` works this way. |
| Emitter with `Enabled = true` (rate-based) | Yes, because it's a property write |
| `Sound:Play()` on a workspace part | Yes |
| Creating the anchor Part or a cosmetic Part | Yes, one replication frame late |

So a server-spawned effect delivers the anchor, the ring and the audio but not the burst. It looks about 80% right in a playtest and 100% right in Studio's server view. Trust neither.

## The rule
- `spawnEffect` refuses to run on the server and warns with a traceback. Don't work around it.
- Server code that needs players to see something calls `VfxBroadcast.playAt` / `playOn` / `shockwave`, or the `SkillVisuals` primitives that wrap them. The routing lives in `SkillVisuals`, not at the call site.
- Delivery handlers that run on **both** VMs (`projectile`, `aoe`) pass `drawnLocallyBy = casterUserId` so the caster's client doesn't draw the effect twice. Server-only paths (`world_spawn`, boss fire) pass nothing.
- Gameplay-authoritative objects are still created on the server. A collidable Stone Wall has to be one solid object for everyone. Split such objects: the server owns the Part, and the broadcast owns the cosmetic overlay (`SkillVisuals.spawnBarrier`).
- An Instance the server created *this frame* arrives as `nil` on clients that haven't replicated it yet. For fresh Parts, use `playAt` with a position. `playOn` is for long-lived targets such as a character's HRP.

## Verification
Server logs, `[Server]` console output and Studio's server view **do not** verify a VFX/SFX change. Only what a client renders does: a client-side count, a client screenshot (`execute_luau` with datamodel_type `Client`), or the effect showing up for a second player. The last three bugs all had clean server logs while players saw nothing.
