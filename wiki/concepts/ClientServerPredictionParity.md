---
type: concept
description: When the client predicts state changes the server validates, the prediction must use identical math — not an optimistic approximation
updated: 2026-04-30
---

# Client-Server Prediction Parity

In a server-authoritative architecture, the client often *predicts* state mutations to keep input feeling responsive (firing, reloading, equipping). The prediction is correct only if it computes the same result the server will. An "approximation" creates a desync that won't surface until an edge case — and when it does, the symptoms are misleading because the user-facing state (HUD, animations, FX) all run off the client's lying state.

## The trap

The pattern that bites:

1. Client maintains a local copy of state (`self.ammo`).
2. Server is the source of truth via a Tool attribute (`_ammo`).
3. Both sides decrement on action, both sides recompute on reload.
4. **Client uses an optimistic shortcut** for one of the recomputes (e.g. "reload always refills to magazine size").
5. **Server uses the real math** that has reject conditions (e.g. "reload transfers `min(needed, reserve)`").
6. When the reject condition fires, server silently rejects the request → client's prediction now diverges from server's truth.
7. Subsequent client actions pass client-side gates but fail server-side validation. The client sees its own optimistic FX (tracers, hitmarkers, animations) but the server says "no" to every one — looks like the world is broken.

## The case study

A TDM debugging session on this project — `fix(weapon): client reload mirrors server reserve math`. Symptom: "after first respawn the enemy appears invulnerable." Real cause: when reserve ammo hit 0, server's `Ammo.performReload` transferred 0 rounds while client's `FirearmController:startReload` did `self.ammo = magazineSize`. Client thought it had 30 rounds; server still had 0. Every subsequent shot was rejected at `validateShot(ammo <= 0)` server-side. The respawn timing was a red herring — players just happened to run out of reserve around the time of their first respawn.

Two-part fix:
- **Compute identically.** `FirearmController:startReload` now reads `_reserveAmmo` and applies `transfer = math.min(needed, reserve)`, matching `Ammo.performReload`.
- **Pre-gate identically.** `WeaponController:canReload()` now requires `reserve > 0`, matching server `validateReload`. The optimistic prediction never gets kicked off when the server is going to reject.

## How to apply

When you find yourself adding client-side prediction:

1. **Factor the math into a shared module** so client and server both call the same function. (This project's `Ammo.performReload` is shared but the client wasn't calling it — same bug.)
2. **Mirror server validation as client gates.** Every "silently reject" branch the server has should have a matching `canX()` check on the client.
3. **Don't refresh the local copy of state from local guesses** — refresh it from the server-replicated source of truth (Tool attribute, `AttributeChanged` signal) when possible. Pure prediction is OK; *fabrication* is not.

## Diagnostic shape

When a feature "works on my screen but the server disagrees":

- "Shots not registering" / "enemy invulnerable" / "the action plays but nothing happens"
- Look at the request's server-side validation for **silent reject branches**. Compare each branch to what the client predicted just before sending the request.
- If you find a server reject path with no matching client gate, that's where the parity broke.

## Related

- [[concepts/SingleOwnership]] — different problem (two writers fighting over one state) but same root cause: unclear authority.
- Memory `feedback_client_server_predict_parity.md` — same lesson in feedback form.
- Memory `feedback_remote_client_visual_checklist.md` — when a multiplayer FX silently doesn't work, walk this checklist.
