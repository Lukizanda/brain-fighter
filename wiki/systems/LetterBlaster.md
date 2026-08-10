---
type: system
description: REMOVED (Phase 5.7, commit 14881d9). Historical record of the Spelling Staff Tool and its LetterBlaster controller — the weapon that wrapped block input from Phase 4.6 until tap-to-pop replaced it. Input now lives in BlockTapController.
updated: 2026-08-10
---

# LetterBlaster — **REMOVED**

Deleted in Phase 5.7 stage 2 (commit `14881d9`). Block input now lives in
`src/client/BlockTapController.client.luau`: the player clicks or taps a block
directly and it pops, with no weapon involved. See [[design/tap-to-pop]] and
[[systems/BlockShoot]].

This page is kept as the record of what the staff was and why it went.

## What it was

The controller behind the **Spelling Staff** — a Roblox `Tool` the player held to
shoot floating letter blocks. It replaced the raw `UserInputService.InputBegan`
handler from Phase 3 with a proper Tool carrying its own mesh and sounds. There
was no reticle; the player clicked directly on the block they wanted.

| File | Role |
|---|---|
| `src/shared/LetterBlaster/init.luau` | controller: `new(tool, session)`, `:mount()`, `:destroy()` |
| `src/shared/LetterBlaster/LetterBlasterConfig.luau` | `COOLDOWN`, sound names, `HANDLE_NAME`, `MUZZLE_ATTACHMENT_NAME` |
| `src/StarterPack/Spelling Staff/Scripts/SpellingStaff.client.luau` | boot LocalScript, mounted on `Tool.Equipped` |
| `src/StarterPack/Spelling Staff/` | Rojo-managed Tool template: `Handle/` MeshPart, Studio-managed `Muzzle` attachment, three Sound `.model.json` children |

On each `Tool.Activated`: cooldown gate → mind-full gate → camera-through-mouse
raycast → `readBlock` → `WordBuffer:append` → `ConsumeBlock:FireServer` → laser
beam from the `Muzzle` attachment → `HitSound`.

## Why it was removed

The staff was a wrapper around "click the thing you want". There was no aiming
skill, no reticle (by design), no ammo, no alternate fire, and nothing else in
the game is shot. What it cost:

- **A boot dependency chain no other input had.** `StarterPack` → `Backpack` →
  `Tool.Equipped` → `SpellingStaff.client.luau` → `:mount()`. With
  `GameConfig.SHOW_BACKPACK = false` the hotbar was hidden, so a *dev-only*
  server script (`DevAutoEquipTool`, keyed on `DEV_AUTO_EQUIP_TOOL = "Spelling
  Staff"`) existed purely to equip it. Core input in a shipped build depended on
  a dev helper firing.
- **A muzzle position two VMs had to agree on.** `BlockShoot.muzzlePosition` /
  `resolveHandle` and the `HANDLE_NAME` / `MUZZLE_ATTACHMENT_NAME` constants
  existed only so a beam left the right end of a prop.
- **A Studio-managed `Muzzle` attachment** outside the Rojo tree, and a
  duplicated fizzle `SoundId` in `.model.json` that `VfxConfig` carried a note
  about.

All of it deleted. The replacement is smaller than what it replaced.

## What survived the removal

- The **server contract**. `ConsumeBlock` still takes exactly one argument and
  `BlockShootValidation` still runs the same three checks — the migration was
  input and presentation only, never authority.
- The **cooldown**, at the same 0.25 s, in
  `src/shared/BlockShoot/BlockTapConfig.luau`. It had three consumers, not two:
  `BlockShootConstants`' rate limiter, the Hardening suite, and
  `SpellCastConstants.CAST_REFILL_PER_SEC` (the spell-cast flood guard is derived
  from the block cooldown because energy only enters a reservoir via popped
  blocks).
- The **fizzle cue**, now a client-local Sound built from `VfxConfig.SFX.fizzle`
  like every other refusal in the HUD — which resolved the duplicated asset id.
- `laserBeamEffect`, still used by NPC `Actions.luau`.

## Notes worth keeping

### The beam's replication fix (2026-08-05)

Late in its life the beam was drawn **only** by the client that fired it, into
that client's own Workspace. Client-created instances never replicate upward, so
every other player watched blocks silently vanish. The fix gave it the same
three-layer shape spells had — predicted local draw, authoritative validation,
`VfxBroadcast.beam` for everyone else — and moved the local draw *below* the
`WordBuffer:append` check, since a shot the buffer rejected drew a beam no other
player could ever have a matching one for.

That lesson outlived the staff: Phase 5.7's collect stream inherits the shape,
and gating cosmetics behind confirmation rather than behind the optimistic append
is exactly the Stage 4 problem.

### Why the Sounds moved to the Handle (2026-08-05)

They used to hang off the Tool. A Sound parented to something that is not a
`BasePart` is **non-positional** — full volume regardless of listener distance.
Moving them onto the Handle MeshPart made them 3D, which is what made the fire
sound safe to replicate at all. Rolloff was 20 → 200 studs: 20 so the wielder was
never attenuated (the audio listener is the *camera*, ~12–15 studs behind the
character), 200 because that was the weapon's own reach.

The general rule survives in [[systems/AudioSFX]].

## See also

- [[design/tap-to-pop]] — the migration that removed this.
- [[systems/BlockShoot]] — the shared helpers and server handler, still live.
- [[systems/LetterBlock]] — the entity it consumed.
- [[systems/Weapon]], [[systems/Loadout]] — other removed systems kept as records.
