---
type: decision
description: Melee hit detection — client detects via blade CFrame, server sanity-validates within reach × 1.5. Locked + shipped 2026-04-17.
updated: 2026-04-30
---

# Decision — Hybrid Melee Hit Detection

**Status**: Shipped (2026-04-17).

**Context**: Melee weapons need responsive hit feel. Server-only detection was sweeping from the attacker's `HumanoidRootPart` and missing visually-clean blade-through-enemy hits, because the server can't accurately know mid-animation blade position (animations are client-side with replication lag/jitter).

## Decision

**Client detects, server sanity-validates.**

| Concern | Authority |
|---|---|
| Hit detection (which humanoids were hit) | Client — sweeps `Handle.CFrame` on Heartbeat during the Active state |
| Damage application | Server (`HealthService.applyDamage`) |
| Cooldown | Server (authoritative); client keeps a UI-responsiveness mirror |
| Distance sanity check | Server — accepts claimed hits within `reach * SERVER_SANITY_REACH_MULTIPLIER` (1.5) |
| Target alive check | Server |
| Hit FX broadcast | Server → all clients |
| NPC melee | Server end-to-end (no client; reuses `MeleeHitDetector.sweep` directly) |

**Cheater bound**: max upside is hits up to 1.5× real reach. Distance cap prevents map-wide teleport hits.

## Alternatives considered

1. **Pure server detection** (status quo before 2026-04-17). Failed: blade pose isn't authoritatively known server-side.
2. **Pure client detection + trust**. Rejected: trivially exploitable. No distance bound = "click anywhere = hit."
3. **Lag compensation (rewind server state to client timestamp)**. Rejected: overkill for this project's pace; revisit if competitive play emerges.

## Implementation scope

4-file change. NPC path untouched. Tests untouched (they call `MeleeHitDetector.sweep` directly, bypassing the remote).

- `src/shared/Weapon/Melee/MeleeConstants.luau` — `SERVER_SANITY_REACH_MULTIPLIER = 1.5`, `MAX_CLAIMS_PER_SWING = 16`, `STALE_CLAIM_THRESHOLD = 2.0`.
- `src/shared/Weapon/Melee/MeleeSwingController.luau` (client) — `_claimedHits` dedupe set; Heartbeat sweep during Active; fire `swingRequestRemote:FireServer(weapon, clientTime, claimList)` on Active → Recovery transition.
- `src/server/Weapon/MeleeSwingService.server.luau` — receive `(weapon, clientTime, claimedHumanoids[])`, validate per-claim (type, alive, has root, distance ≤ sanityDist), apply damage to validated subset.
- `src/shared/Weapon/Melee/MeleeHitDetector.luau` — unchanged.

## Pre-shipping cross-VM time bug found and fixed

`os.clock()` is per-VM. Cross-wire timestamps must use `workspace:GetServerTimeNow()`. Recorded in `feedback_cross_process_testing.md` (auto-memory).

## Follow-ups (open)

- Per-weapon `HitboxAttachment` instead of attribute-derived box (needed for invisible-Handle + welded-blade pattern like AutoRifle-style melee).
- Optional server LOS raycast to the target.
- Sub-step interpolation on the client for ultra-fast blades.
