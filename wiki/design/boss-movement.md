---
type: design
description: Phase 8 stage 11 plan (2026-11-18) for a boss whose movement says what it is about to do. The server keeps owning where the Brain is; each client animates its body on top through Motor6D.Transform (never replicated) from a few intent attributes. A rebuilt rig of native primitives (two lobes over a neon core, tracking eyes, a bending stem, orbiting neurons), one readable silhouette per attack, and two vulnerability windows (a stuck window after Ground Slam, a stagger when the ward breaks) where hits on the open core deal x1.5. Four stages; decisions made by the user the same day.
updated: 2026-11-18
---

# Boss movement

Companion to [[systems/Boss]], [[design/boss-arena]] and [[design/ai-playtest]].

## Why

The Brain is an invisible R15 Humanoid that walks, with a 9-stud sphere, a stem and
two neon eyes **welded** to its root (`ServerStorage.AIWorldData.Rigs.BossBrain`). It
can only slide and turn as one piece. Today:

- The windup is 0.5 s and the only warning is on the ground (`SkillVisuals.spawnTelegraph`).
  `BossStates` asks for `windup_*` animation tracks the rig does not have.
- `CurrentState` is published on the boss and read by no client.
- The spore lob deliberately winds up as the Volley (`windupSkillName`), although the
  right answer is the opposite: dodge a volley, run *to* spores.
- Phase 2's Crimson is configured but only read at spawn, so it is never shown.

Players should be able to read the fight from the body: where it is going, what it is
about to do, and when to punish it.

## The technique: server owns the root, the client owns the pose

1. The visible parts hang off the root on **Motor6Ds** instead of WeldConstraints.
2. `client/Vfx/BossPuppet.client.luau` writes each joint's `Motor6D.Transform` every
   frame. `Transform` is local to the client and never replicates, so the motion is
   free on the network and cannot fight the server.
3. **One writer per property** ([[concepts/SingleOwnership]]): the server (Humanoid +
   `Actions.FaceTarget`'s AlignOrientation) owns the root's position and facing; the
   puppet owns the joints' `Transform`; nothing else touches either.
4. The server says what it *means* through attributes on the boss Model, and the
   puppet turns intent into poses. Times are `workspace:GetServerTimeNow()`, because
   `os.clock()` is per-VM.

| Attribute | Written by | Meaning |
|---|---|---|
| `CurrentState` | `StateMachine` (exists) | Idle / Patrol / AttackPrep / Attack / Cooldown |
| `PendingAttack` | `BossStates` AttackPrep (**built**) | FireballVolley / GroundSlam / SporeLob, cleared on entering Cooldown |
| `WindupEndsAt` | `BossStates` AttackPrep (**built**) | When the hit lands (prep + an aoe's own windup), so every pose peaks with it |
| `ExposedUntil` | stage 11c | End of a vulnerable window |
| `StunnedUntil` | stage 11c | End of a stun (the boss stands still) |
| `Phase` | `BossSpawner` / `BossController` (**built**) | Current phase index |
| `WardUp`, `WardLettersLeft` | `BossWard` (**built**) | The ward is holding; letters still orbiting |
| `EatingAt` | `BossHunger` (stage 11b) | Position of the letter being eaten, while it pulls |

All names are `BossConstants.*_ATTRIBUTE`.

### Foundation for 11b–11d (built 2026-11-18)

Laid down before the three stages were split across parallel sessions, so each owns
its own files:

- **Per-attack prep.** `BossTypeSpec.attackPrepSec` (by attack name, `SporeLob`
  included) replaces the single `attackWindupSec` where listed. The Brain: Volley 0.8 s,
  SporeLob 0.9 s, GroundSlam 1.0 s (+0.8 s delivery windup = 1.8 s of warning). The
  ground telegraph runs for the same window.
- **Stun hold.** `BossBlackboard.stunnedUntil` (server `os.clock()`): while it is in the
  future the boss stands still in Cooldown and cannot leave it. Nothing sets it yet.
- **Attack-finished hook.** `BossBlackboard.onAttackFinished(attack)` is called on
  entering Cooldown. Nothing sets it yet.
- **Pose layers.** `client/Vfx/BossPoses/`: `PoseTypes` (the `Pose` a layer writes:
  root offset, lobe opening and scale, stem, eye target/offset, core light, neuron
  orbit, synapse glow, body tint, a motion scale) and three layers applied in order,
  `Telegraph` (11b), `Exposed` (11c), `Ceremony` (11d), stubs until built. The puppet
  stays the one writer of joints, scales, lights, beams and the flash; a dead boss's
  idle motion stops but the layers still run (for the death sequence).

The collision body stays the invisible skeleton, so a float or a lean is purely visual.

## The rig (native primitives only)

Built at spawn by `Shared/Boss/BrainBody` (chosen over a generator for the Studio-only
template, so the body lives on disk and the template needs no edit): the template's four
welded parts are replaced when the type spec says `body = "Brain"`.

- **Two hemisphere lobes** (left, right) that close over a **neon core** and can part
  like a clamshell. An open core is the one signal that always means "hit me now".
- **Eyes with pupils** that track the target.
- A **stem** that bends, swells and stretches; a cerebellum behind.
- **Three to five neuron spheres** orbiting the brain, joined by `Beam`s that flash
  before an attack.
- Colours come from the boss's phase, not the level-art palette (the palette reserves
  them).

## The movement vocabulary

| Moment | Movement | Player reads |
|---|---|---|
| Idle | Slow breathing scale, hover bob, eyes on the nearest player | It is watching me |
| Moving | Leans into its velocity; bob frequency rises with speed | Where it is going |
| Volley tell | Draws back and up, lobes glow red, recoils on every shot | Strafe |
| Slam tell | Rises high, hangs while a ground shadow grows, drops with squash and stretch | Leave the circle |
| Spore tell | Stem swells, the body gulps, then spits | Go *to* the landing rings |
| Eating | Leans toward the letter, stem reaches out | Take the letter first |
| Hit | Wobble scaled by the damage; a freeze stops all procedural motion | My hit landed |
| Ward up | Lobes clamp shut, shell plates glow; each ward letter popped blows a plate off | Pop the orbiting letters |
| Phase 2 | Crimson, jerkier and faster, pulsing cracks | It is angry |
| Death | Deflates, spins, bursts | Win |

## Vulnerability windows (decided 2026-11-18)

- **After a Ground Slam** the boss is stuck about 1.5 s: sunk, lobes open, core
  exposed, eyes spinning. Rewards fighting up close.
- **When the ward breaks** it staggers with its core open: the payoff for popping the
  four letters.
- Damage taken while `ExposedUntil` is in the future is **x1.5**, applied in
  `applyDamage` (the one damage path), not by the boss.
- Both are swept in the fight simulator (`src/shared/Playtest/`) before they ship, so
  the novice and strong-speller results do not drift ([[design/ai-playtest]]).

## Stages

| Stage | Item | Changes gameplay? |
|---|---|---|
| 11a | Puppet foundation: the body (lobes, core, eyes, stem, neurons on Motor6Ds), `BossPuppet` with idle / moving / hit / freeze motion, `Phase` attribute and phase colour. **Built 2026-11-18** — [[systems/Boss]] § Boss Model | no |
| 11b | Attack tells: `PendingAttack` / `WindupEndsAt` / `EatingAt`, a pose per attack, the spore lob's own tell, per-attack windup lengths so the slam's rise reads | timing only |
| 11c | Vulnerability: stuck window after Ground Slam, ward-break stagger, x1.5 in `applyDamage`, simulator sweep, tests | yes |
| 11d | Ceremony: entrance landing, ward plates, death sequence | no |

Each stage ends with a playtest and a screen capture of the motion on a client.

## Decisions (user, 2026-11-18)

1. Both vulnerability windows, x1.5, tuned in the simulator first.
2. The spore lob gets its own tell.
3. Rebuild BossBrain as lobes + core + orbiting neurons.
