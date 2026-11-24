---
type: design
description: Phase 8 stage 12 plan (2026-11-21) for the scramble bomb, which replaces the boss's spore lob. The boss lobs one bomb carrying a scrambled 3- or 4-letter word; tapping the tiles in a spelling order defuses it and sends it back at the boss, a wrong tap costs fuse time, and a bomb left alone bursts. Chosen by the user after a design pass found that spores carry no risk and that every way of making the pop harder cost the novice its win. Holds the rule, the starting numbers, the simulator results, the contract and a six-stage build plan. Nothing is built.
updated: 2026-11-25
---

# Scramble bomb

Companion to [[systems/Boss]] § Spore letters, [[design/ai-playtest]] and
[[design/boss-movement]]. **Status: the static bomb was built and run once on 2026-11-21; the user then chose letter missiles instead (§ Revision), being built. Not committed,
not yet seen by a person** (§ Built and first runs). Spores are switched off for the
Brain but their code and tests remain (stage 6 is not done).

## As committed (2026-11-25)

This is what the code does now; the sections below are the history that led here.

**The rule.** In every second volley slot (never under the word ward) the Brain lobs
one puzzle: 1.5 s in the air, landing within 12 studs of its target. It rests on a
timer (6 s for 3 letters, 8 s for 4; 3 letters before the ward, 4 after) with its
letters in a camera-facing row. Tap them in a spelling order: a letter locks, a wrong
tap is refused and costs 1 s, a hint marks the next letter after 2 s. Solved, the
word's energy is credited without touching the word buffer. If the timer ends, locked
letters vanish and each unlocked one hatches into a **fireball** that chases the
nearest living player.

**The fireballs** (the user's tuning, by feel, 2026-11-25):

| Value | Now |
|---|---|
| Arming pause, then one launch every | 1 s, 0.7 s |
| Launch arc | 5 studs up over the first second |
| Chase | 30 studs a second, turning at most 70 degrees a second |
| Final approach | 30 studs out it locks onto where the player stands, stops tracking and flies straight at 100 studs a second for at most 50 studs |
| Burst | 15 within 6 studs, set off within 3 studs of its player, on a wall, when the dash is spent, or after 9 s; not through walls or more than 8 studs of height |
| Pop | from 45 studs: removed, no reward |

**Two switches, both off for the user's trial:** `bombTapReachEnabled = false` (a
resting puzzle can be solved from the ordinary 200-stud tap range instead of 20) and
`bombDefuseDamageEnabled = false` (a solve no longer takes 9% or 12% off the boss;
the reward is the word's energy alone, raised from half to the full word). Whether
either stays off is undecided.

**Where it lives.** Boss system: `Boss/Scripts/BossBombs` (one object per boss),
`BombRegistry`, `Boss/BombTapService`, server events in `Boss/Events`, the contract
in `Shared/Boss/BombConstants`, the shared tap rules in `Shared/Boss/BombRules`,
numbers in `BossConfig` (`bomb*`). Economy: `EnergyLedger.creditWordGrant`, the
`WordGranted` remote and server event, client `EnergyGrantReceiver`. Client:
`Vfx/BombVisuals`, `BombTapController`. Playtest tooling: bot, recorder, simulator.

**Checked:** full suite 137/138, then the one failure (a test's own assumption) fixed
and Economy 4/4; Arena 69/69 (18 `bomb_*` suites). One Average bot fight won in 102 s
on 2026-11-24, before the fireball look, the turn limit, the final dash, the launch
stagger, the arc and the two switches. The user has played it and tuned the flight;
their finding that plain strafing avoided the fireballs led to the dash numbers above.

**Known gaps.**
- The test fixture switches the arming pause, turn limit, final dash, launch stagger,
  arc and both switches to their old behaviour, so **no test covers any of them**.
- The simulator and the bot model none of the fireball flight changes and assume a
  solve hurts the boss; their numbers do not describe this build.
- Spores are still in the code and tested, switched off for the Brain by precedence
  (stage 12f not done). The lob still publishes `SporeLob` as the pending attack.
- No strict type check has been run (no Luau analyzer is installed here).
- Not seen on a phone; co-op untested.

## Why

The user, 2026-11-20: spore letters pose no risk, the player simply pops every spore
before it bursts. A design pass on 2026-11-21 (a combat designer, a gameplay engineer
and a balance analyst as agents, led by a senior-designer session) found:

- **The cause is the timeline, not the fuse.** Spores land 2.4 s after the lob is
  picked and can be popped at once from 200 studs. The boss then sits in its 4 s
  cooldown, so the next volley's first hits arrive about 8.0 s in and the fuse runs
  out at 8.4 s. The player has about five quiet seconds with nothing else to do.
  Read from the code, not measured in a fight.
- **Distance alone changes nothing** while a tap reaches 200 studs.
- **Making the pop harder takes the novice's win away.** A pop is worth the same to
  everyone and the Novice sits against the 300 s clock. In the simulator a short
  reach with spores landing away from the player gave the Novice 17 to 21% wins, a
  timed "ripe" pop with no early reward 0 to 1%, three taps a pop 0%.
- Spore pops are 76% of the Novice's boss damage and 52 to 56% of the others', so
  popping, not spelling, is what kills the boss.

The user was offered three pop-tuning packages, asked for more creative ideas (their
example was a time bomb with a letter puzzle to rearrange), and chose the scramble
bomb from five. They also said the 3% a pop rule of 2026-11-17 may be replaced.
Not chosen: a popped spore that ticks in the word buffer, a missing-letter bomb,
spores that rot nearby letters for the boss to eat, a bomb only a spell of its colour
defuses. None of those four was costed or simulated.

## The rule

The boss lobs a bomb with a scrambled word on it. Tap the letters in the right order
and it flies back at the boss. Leave it and it blows up.

- **Lob.** The same slot as the spore lob it replaces: every second attack that would
  have been a FireballVolley, 0.9 s prep, 1.5 s flight. One bomb, landing within 12
  studs of the target. No lob while the word ward is up, so a player never faces two
  letter puzzles at once.
- **Puzzle.** 3 tiles before the word ward, 4 after, orbiting the bomb. They are a
  scrambled word from the key-word lists (`WordKits.keyWords`), all in one colour,
  red or blue. The bomb keeps the letter count and fuse it was thrown with.
- **Tap.** A player within reach taps one tile at a time. A tap is accepted when the
  letters accepted so far plus this one begin at least one allowed word that uses
  exactly the bomb's letters (T-A-C is solved by CAT or ACT). An accepted tile locks
  in. A rejected tap keeps the progress and takes 1 s off the fuse. Tapping a locked
  tile does nothing.
- **Allowed words** are the anagrams that are in the key-word and kit lists, not the
  whole dictionary, which has no filter for words unsuitable for children.
- **Defuse.** The last tile accepted: the bomb flies back at the boss and the solved
  word is credited as if memorized, without passing through the 12-slot word buffer,
  so a half-built word is not disturbed.
- **Fail.** The fuse runs out: the bomb bursts and hurts every player of the arena
  inside its radius. Cover does not stop it, as with the slam.
- **Hint.** A fixed time after landing the next correct tile glows, and keeps doing
  so for each tile after it. This is what lets a young reader finish.
- **Co-op.** Anyone in the arena may tap and progress is shared. The damage and the
  word are credited to the player with the most accepted taps, so a defuse cannot be
  stolen with the last tap.
- No line-of-sight check on a tap. A bomb behind cover can still be solved.

Where the risk comes from: solving means standing still next to a live bomb while
the boss's next attack arrives, and a wrong tap shortens the fuse.

## Starting numbers

All are the session's choices from the simulator, to be tuned after real fights.

| Value | Start | Note |
|---|---|---|
| Bombs a lob / cadence | 1 / every second volley slot | two a lob made the kill too fast for everyone |
| Landing radius | 12 studs | |
| Tiles by phase | 3, then 4 | |
| Fuse | 8 s for 3 tiles, 10 s for 4 | |
| Hint | 3 s after landing | a fixed delay, not a share of the fuse (below) |
| Wrong tap | −1 s of fuse | |
| Defuse damage | 9% of the boss's health for 3 tiles, 12% for 4 | |
| Word credit | half the word's energy | the knob that slows Average and Strong |
| Burst | 25 damage within 10 studs | |
| Tap reach | 20 studs from the bomb's centre | open: the engineer suggests 14, so a solver stands inside the burst |

## Simulator results (2026-11-21)

100 fights per persona on `IslandReview`, two seeds, **with the word ward on** (the
game as built has it). Cells are win % / median time to kill / deaths.

| Row | Novice | Average | Strong |
|---|---|---|---|
| Spores as built | 90–94 / 226–237 / 3.0 | 136–138 s | 135–146 s |
| Bomb, hint at half fuse, full word credit | 74 / 221 / 3.7 | 134–144 s | 122–133 s |
| + fuse 6 and 8 | 76 / 191–207 / 3.6 | 132–133 s | 124–133 s |
| + fuse 6 and 8, half credit | 51–57 / 228–238 / 4.0 | 146–161 s | 146–148 s |
| Hint at 3 s, full credit | 84–88 / 187–195 / 3.5 | 131–134 s | 123–131 s |
| **Hint at 3 s, half credit (the starting numbers)** | **63–70 / 229–240 / 4.0** | **148–156 s** | **134–150 s** |
| Hint at 2.5 s, half credit, damage 11% and 14% | 78–90 / 209–215 / 3.6 | 122–140 s | 137–139 s |

Bands: Novice win 60% or more in 220 to 290 s with 1 to 2.5 deaths, Average 150 to
220 s, Strong 80 to 130 s.

- **The starting row is the closest to every band at once**: Novice wins and is in
  its time band, Average is at the edge of its band, Strong is a little slow. With
  the full word credit the Novice wins more often (84 to 88%) but everyone kills too
  fast. That trade is the user's to make after real fights.
- **No row clears every band.** A defuse is worth the same to every persona, the
  same wall the spore sweep hit.
- **Defuses are 40 to 54% of boss damage** against 52 to 76% for spore pops (measured
  with the ward off). The rest is spelling.
- **The Novice cannot defuse without the hint**: 0% wins with it off. Its first tap
  comes when the hint lights. That is why a shorter fuse helped it when the hint was
  tied to half the fuse, and why the hint is now a fixed delay.
- **It is a real risk for the Novice only.** Ward off, as drafted: about 3 bursts hit
  it a fight (80 damage) and about 95 damage comes from volleys while it stands
  solving; it stands still about 48 s a fight. For Average and Strong the bomb is a
  time trade (a burst hits Strong once in ten fights).
- **Novice deaths stay near 3.5 to 4** (band 1 to 2.5). They come from the volley and
  were 2.9 to 3.1 with spores.
- A lob in every volley slot is not a fair row: the lob replaces the volley, so the
  boss never fires.

What the result leans on, all guesses: the Novice notices 65% of bombs (at 100% it
wins 89 to 94%, at 50% about 40%), unscrambles at 1.5 s a letter, taps wrong at its
invalid-word rate, and gives a bomb up at 40 health or less. Unscramble time and the
wrong-tap rate hardly move the Novice because the hint arrives first. Not modelled:
the bomb as an object in the world, tapping while moving, casting during a solve,
co-op.

## Architecture (the engineer's recommendation)

**The bomb is its own object, not letter blocks.** The pop path destroys a block on
the first accepted pop, credits the letter to the ledger and puts it in the buffer on
the client before the server answers. An ordered tap that can be refused while
keeping progress fights all three.

| Piece | Owner |
|---|---|
| The word, the scramble, the colour, the landing, the fuse, judging a tap, the damage, the published progress | Boss system: `BossBombs` (grown from `BossSpores`) |
| The tap remote, with rate, arena and range checks (reusing `BlockShootValidation`) | Boss system |
| Accept-or-reject rule, used by server and client alike | a shared `BombRules` module ([[concepts/ClientServerPredictionParity]]) |
| Tiles, lock-in, fuse ring, hint, tap input and its prediction | client: `BombVisuals`, `BombTapController` |
| The word credit | Economy: `EnergyLedger.creditWordGrant` and a server-to-client grant, fired by `EconomyService` only |
| Nothing | BlockSpawner: the bomb is in no pool or count |

Published on the bomb model, written by `BossBombs` only: the tile letters in orbit
order, the colour, the count and set of locked tiles, the burst time in
`workspace:GetServerTimeNow()` (it moves when a tap is refused), the hint tile, the
reach, and the allowed words. Publishing the allowed words (changed 2026-11-21 when
the build started; the engineer had kept them on the server) lets the client predict
a tap with the same `BombRules` the server judges with. A client could read the
answer; for a co-op fight against the boss over a 3-letter anagram that is accepted.

**The word credit is about half the work and the one place a fault costs trust.** The
client owns the reservoirs and the server a mirror ceiling; `reportMemorize` clears
the held letters, which a bomb must not. The grant adds the same scored amounts on
both sides with the same clamp at 60, guarded by a per-bomb resolved flag, and marks
`WordMemorized` with its source so the onboarding funnel and the tutorial do not
count it as a first memorize.

Spores are replaced, not kept behind a switch. The lob selection, the pods in flight,
the landing markers and the burst ring carry over. `spawnSpore`, `isSpore`, the
`wasSpore` flag and the pop-damage rule go in the last stage.

Edge cases settled: the boss dying or the round ending clears the bomb with no burst
and no credit; a credited player who has left gets no word and the boss is still
hurt; the landing probe gains guards (a real walkable hit, inside the arena, not on a
roof or in a wall, a few retries, then the target's own ground).

## Stages

| # | Stage | Size | Depends on |
|---|---|---|---|
| 1 | Greybox bomb: `BossBombs`, config, the tap remote, `BombRules`, plain tile parts, defuse and burst damage | L | none |
| 2 | Word credit: ledger, `EconomyService`, client reservoirs, analytics source | M | 1 |
| 3 | Landing guards, edge cases, no lob under the ward | S | 1 |
| 4 | Phone-readable look: orbiting tiles, lock-in, fuse ring, hint glow, large tap targets | M | 1 |
| 5 | Bot and recorder: a solve routine through `BombRules`, bomb events in the report | M | 1, 2 |
| 6 | Retire spores: registry calls, `isSpore`, `wasSpore`, the `spore_*` suites become `bomb_*` | S | 1 to 5 |

Stages 1, 3 and 6 are one after another (they edit the Boss system). Stages 2, 4 and 5
can run beside each other once stage 1's contract is merged.

## Revision: letter missiles (user, 2026-11-21, after playing the bomb)

The user played the static bomb: the tiles overlapped and blocked each other
depending on the camera angle, and were hard to tap in order. A first fix put the
tiles in a camera-facing row above the bomb (client only, compiled, unseen). The user
then chose **letter missiles** over a chasing bomb or keeping the bomb: the letters
stop floating and come for the player. **This replaces the static bomb**; everything
above about the tap rule, allowed words, the word credit and ownership still holds
unless this section says otherwise. Numbers are starting guesses, to be swept.

- **Salvo.** In the lob's slot the boss fires one missile per letter (3 before the
  ward, 4 after), a short stagger apart. They fan out, then home on the boss's target
  at a speed well under a walk, each keeping its own side offset so they never line
  up on screen. If the target dies they take the nearest living player of the arena.
- **Pop in order.** A missile is tapped like a tile. The same rule decides: the
  letters popped so far plus this one must begin an allowed word. An accepted pop
  removes the missile and locks its letter. The last one fires the word back at the
  boss: the defuse damage and the word credit, as before.
- **Pop out of order.** The missile is destroyed and harmless, the chain is broken,
  and the salvo pays nothing. The rest still come and can still be popped to be safe.
  This is the safe route for a player who cannot read the word: tap everything.
- **Ignore.** A missile that reaches its target explodes for area damage. It also
  explodes on a wall or the floor, so cover works, and after a lifetime.
- **Hint.** As before: after a fixed delay the next correct missile is marked.
- **Where the risk is.** The letter needed first is often not the nearest, so earning
  the reward means letting a wrong missile get closer. Nobody has to stand still.
- No fuse and no fuse penalty: the missiles' approach is the clock.

| Value | Start |
|---|---|
| Missiles | 3, then 4 after the ward; launched 0.4 s apart |
| Speed | 8 studs a second (a walk is 16) |
| Lifetime | 14 s, then it bursts where it is |
| Explosion | 15 damage within 6 studs, set off within 3 studs of the target or on a wall |
| Tap reach | 45 studs from the missile |
| Hint | 3 s after launch |
| Defuse damage / word credit | 9% and 12% / half, unchanged |
| Side offset between missiles | 6 studs, closing in the last 10 studs |

### Letter missiles in the simulator (2026-11-21)

100 fights per persona, ward on, two seeds. `tune.bomb.missiles` switches the bomb's
delivery; the knobs are listed above `FightSim.run`. **Nothing of the missiles is
built**: the server rework was stopped before it changed a file.

| Row | Novice win / time / deaths | Average | Strong |
|---|---|---|---|
| Static bomb as built | 61–69% / 234–237 s / 3.9 | 147–157 s | 143–152 s |
| Missiles as written above | 9–10% / 243–246 s / 3.5 | 140–159 s | 158–163 s |
| Everyone only sweeps (never tries for the word) | 0% | 61–75% wins, 211–218 s | 69–70% wins |
| Out-of-order pop refused instead of breaking the chain | 31–40% / 204–214 s / 3.2 | 139–146 s | 155–157 s |
| Refused, speed 6 | 34–39% / 190–218 s / 3.0 | 135–140 s | 155–156 s |
| **Refused, speed 6, taps pass through cover** | **60–61% / 208–216 s / 2.9** | 126–132 s | 139–150 s |

- **As written the Novice loses nine fights in ten.** What costs it is not damage but
  word-search time (45 to 55 s a fight) and salvos that never complete: it finishes
  14% of them.
- **Three changes get it back to 60%**: an out-of-order pop is refused (the missile
  stays, nothing breaks), speed 6, and a tap reaches a missile through cover. Refusing
  is worth 25 to 30 points, taps through cover about 20, speed about 8.
- **The missiles are a small danger in the model.** A salvo hurts the Novice in 12 to
  14% of salvos, Strong in 2 to 3%; missile damage is about 60 a fight for the Novice
  and 7 for Strong. Deaths still come from volleys.
- **35 to 45% of missiles end on a wall**, because players stand behind cover and the
  model's missiles do not steer round rock. A letter lost that way ends the word.
- No row meets every band; Novice ÷ Strong time is 1.4 to 1.5 (band 2.0 to 3.0).
- Leans on guesses: the Novice notices 65% of salvos (50% gives 35 to 43% wins, 100%
  gives 86 to 90%) and tries for the word 40% of the time. Not modelled: steering
  round cover, retargeting, co-op, more than one valid word, touch.

### Letter seekers: the rule being built (user, 2026-11-23)

The user asked to try the chasing letters: with the static bomb they could simply run
away when they could not spell the word in time, so there was no risk to weigh. The
build restarted under the name **letter seekers**, with the rule changed from the
table above by the sweep and by that feedback:

- **An out-of-order pop is refused**: the seeker stays and keeps coming, nothing
  breaks. (The sweep: +25 to 30 points of Novice wins.)
- **A tap reaches a seeker through cover.**
- **Seekers speed up with age**, from 6 studs a second at release to 18 at the end of
  their 14 s life (a walk is 16), so there is time to read at first and running stops
  working later. The session's choice, **not simulated**.
- A seeker that bursts (on a player, a wall, or at the end of its life) takes its
  letter with it: the word is lost, and the rest can only be popped away for safety.
- Unchanged: one seeker per letter, 0.4 s apart; 15 damage within 6 studs; reach 45;
  hint at 3 s; 9% and 12% to the boss and half the word's energy for a finished word.

### The two-phase puzzle: rest, then hatch (user, 2026-11-23) — **the current design**

Shown the seeker playtest, the user said what they had meant all along: the boss
launches the letters at you, they **land and you solve them within a time**, and only
if you fail do they **turn into seekers that chase you and burst**. The chase is the
penalty for failing, not the whole attack. This supersedes both the static bomb that
burst in place and the chase-from-launch seekers above.

- **Lob and land** as the first build: 1.5 s in the air, within 12 studs of the
  target, with landing guards.
- **Rest.** Tap the letters in a spelling order from within 20 studs of the puzzle's
  centre. A wrong tap is refused and costs 1 s. A locked letter stays in place.
  Solved: 9% or 12% to the boss and half the word's energy, as before.
- **Hatch.** When the timer ends, locked letters vanish and every unlocked letter
  becomes a seeker, 0.3 s apart. Solving part of the word means fewer seekers.
- **Seekers** chase the nearest living player at 20 studs a second (a walk is 16) for
  up to 6 s and burst for 15 within 6 studs on reaching that player, on a wall, or at
  the end of their life. One can be popped from 45 studs: removed, no reward. Cover
  works.
- The client draws the resting letters in a camera-facing row 5.2 studs apart (a
  glyph is 4.6), which is the fix for the overlap the user hit.

| Value | Now | Note |
|---|---|---|
| Timer | 6 s for 3 letters, 8 s for 4 | from the sweep; 8 and 10 gave the Novice 50 to 54% |
| Hint | 2 s after landing | from the sweep |
| Seeker speed / life | 20 studs a second / 6 s | the session's choice |
| Burst | 15 within 6 studs | the sweep's own pick was 10; kept at 15 for the user's "real risk" |

Simulator, 100 fights per persona, ward on, two seeds (win / median time / deaths):

| Row | Novice | Average | Strong |
|---|---|---|---|
| Static bomb, burst in place | 59–63% / 223 s / 4.0 | 144–160 s | 140–146 s |
| Hatch, timer 8 and 10, hint 3 s | 50–54% / 231–235 s / 5.5 | 146–150 s | 152 s |
| Timer 6 and 8 | 70–73% / 230–238 s / 5.1 | 145–148 s | 148–151 s |
| Hint at 2 s | 60–70% / 210–228 s / 4.9 | 134–143 s | 142–148 s |
| Timer 6 and 8, hint 2 s, burst 20 | 72–81% / 212–228 s / 5.5 | 133–152 s | 148–150 s |
| Timer 6 and 8, hint 2 s, burst 10 | 74–85% / 220–233 s / 4.3 | 139–150 s | 150 s |

- **Failing now costs something real.** With nobody solving, the Novice wins 0% and
  Average and Strong under half; with everybody trying, 97 to 100%. A hatched puzzle
  costs 15 to 21 health.
- Seeker speed hardly matters in the model (14, 20 and 24 give the same Novice), and
  about a third of seekers end on a wall.
- A shorter timer helps the Novice, because it stands exposed for less time and the
  hint arrives sooner in proportion.
- The Novice fails about 62% of puzzles (it misses some and gives up when hurt), so
  the cost falls hardest on it: deaths rise from about 4 to about 5, 2.7 of them from
  seekers. No row brings deaths under 3.9.
- The exact numbers now in the config (timer 6 and 8, hint 2 s, burst 15) were not run
  as one row; they sit between the last two.

**Built 2026-11-23 and run 2026-11-24. Not committed; no person has played it.**

- **Tests:** full run 136/138; the two failures were tests reading a deferred event
  in the same frame, fixed. Arena suite re-run after all fixes: **69/69**.
- **One Average bot fight on `IslandReview`: won in 102 s, 2 deaths.** 7 puzzles
  landed, 5 solved, 2 hatched; 6 seekers hatched, 3 burst on the bot, 1 popped.
  Puzzle solves were 47% of boss damage. The simulator has Average at about 146 to
  150 s with half the puzzles solved, so it is again the harder of the two.
- Seen working: lobs alternate with volleys, none under the ward, all seven landings
  on flat floor within 12 studs of where the bot stood at the throw; a forced wrong
  tap moved the timer exactly 1.00 s; hint at 2.0 s; 135 and 180 off the boss; the
  word credit on both sides; only unlocked letters hatched, 0.30 to 0.32 s apart;
  seekers at 20 studs a second, hovering 5 studs up; 15 a burst.
- **A player cannot walk away.** A seeker gains 4 studs a second on a walker and a
  player in tap reach starts at most about 23 studs from any letter. Each failed
  puzzle cost the bot 15 to 30 health, and one set up a volley death.
- **Too abrupt as first built:** the first burst came 0 to 0.7 s after the hatch, so
  there was no time to pop or reach cover, and the burst measured horizontal distance
  only, so cover and ledges did not protect. Changed after the fight, covered by the
  69/69 run but **not seen in a fight**: a hatched seeker hangs still for 1 s
  (`bombSeekerArmSec`), life 6 to 7 s to keep 6 s of chase, and a burst no longer
  hurts a player behind a wall or more than 8 studs above or below it.
- The client's row was read from instances: 4 studs above the centre, facing the
  camera, letters 5.2 apart against a 4.6 glyph. **Nobody has seen the pixels.**
- Open: puzzle solves may be too strong (47% of the kill, 102 s against a 150 to
  220 s band; one fight); the Novice and Strong bots and a 4-letter hatch are unrun;
  the recorder's old `bombBurst*` counts read 0 under this rule (use `seeker*`).

### Letter seekers built and run (2026-11-23)

Built the same day (server, client, bot, recorder, simulator) and run by a playtest
session. Not committed; no person has seen it.

- **Tests 135/135**, including 15 `bomb_*` suites and the ledger grant. The five
  unexplained failures of 2026-11-21 did not recur.
- **Two bot fights (Average, `IslandReview`): won in 71 s and 124 s.** 12 of 14 salvos
  completed, **no seeker ever hurt the bot**, words were 40% and 66% of boss damage.
  The simulator had Average at about 130 s with half the salvos completed, so it
  overstates the difficulty.
- Seen working: salvos alternate with volleys, releases 0.4 s apart, 3 letters then 4,
  measured speed following the ramp, hover exactly 5 studs, no seeker lost the ground
  or left the island; in-order pops accepted, a forced out-of-order pop refused with
  nothing changed; 9% and 12% to the boss; the word credit matched on both sides.
- **Walking away is free.** The boss stands about 68 studs off, so a seeker needs
  about 9 s to arrive; about 55 studs of walking (3.5 s) defeats a salvo, and leftover
  seekers expire far away. No sensible speed fixes this: from that distance even a
  seeker ramping from 12 to 20 would need about 19 s to catch a walker.
- **A player who can spell is never threatened**: at a reach of 45 the bot popped every
  seeker as it came into reach, 21 to 45 studs away, with the hint already showing.
- Seekers fan in rather than holding their spacing: 3.5 studs apart at pop range
  against glyphs 4.6 wide, so the letters overlap again where taps happen.
- Fixed: a dead character counted as a wall (a seeker burst on the bot's body and the
  word was lost); `BombVisuals` drew nothing in a bot-driven client because it ran on
  `RenderStepped`, now `Heartbeat`.
- Changed after the run, **not re-run**: tap reach 45 to 28. Before it: speed 4 to 14
  and the hint at 2 s (from the sweep: a 6 to 18 ramp gave the Novice 22 to 26% wins).
- Not exercised in a fight: a burst on a living player, a wall hit, a seeker expiring,
  the broken-salvo look. Unseen by anyone: the pixels.

## Built and first runs (2026-11-21)

Stages 1 to 5 were written the same day by four builder agents and run by a playtest
session. What exists:

- **Boss:** `Boss/Scripts/BossBombs` (one object per boss, as `BossSpores`),
  `BombRegistry`, `Boss/BombTapService`, server events `BombLanded` / `BombDefused` /
  `BombBurst`, the remote `Shared.Boss.BossEvents.BombTap`, the contract in
  `Shared/Boss/BombConstants` and the shared rules in `Shared/Boss/BombRules`. The
  bomb is a model tagged `ScrambleBomb` in `workspace.ScrambleBombs`; its state is
  attributes (`BombLetters`, `BombWords`, `BombAccepted`, `BombBurstAt`, `BombHintAt`…).
  A bomb lob still publishes `SporeLob` as the pending attack, so the lob tell plays.
- **The Brain keeps `sporeEveryNthAttack`**: a type with both configured lobs the bomb
  only (`bombs or spores` in `BossStates`), which keeps the spore tests meaningful
  until stage 6.
- **Economy:** `EnergyLedger.creditWordGrant` (same scoring as a memorize, share
  rounded down, same clamp, held letters untouched), the remote and server event
  `WordGranted`, client `EnergyGrantReceiver`. The ceiling is raised before the client
  is told. `WordMemorized` does not fire for a grant, so the funnel and the recorder's
  word count are not misled. The share is read from the default boss type; the event
  should carry it.
- **Client:** `Vfx/BombVisuals` (letter tiles, order badges, countdown and word slots
  above the bomb, ground ring, hint marker, a get-closer state for touch),
  `BombTapController` (prediction through `BombRules`, rollback, a Studio-only
  `RequestBombTap` for the bot). A tap reaches a tile through cover.
  `BlockTapController` now checks cooldown and mind-full only once a letter block is
  under the pointer, so a missed tap no longer starts the pop cooldown.
- **Playtest tooling:** the bot solves bombs with the simulator's persona model; the
  recorder writes a `bomb` object in the fight report; the simulator models the game
  as built by default (bomb from `BossConfig`, no spores) and its report has bomb
  columns.

Tests: 10 `bomb_*` Arena suites and `ledger_grants_bomb_word`. First run 130/131 (the
one failure was a fault in the new ledger test, fixed). Second run after the fixes
126/131: every bomb, ledger and spore test passed; `NPC deals damage to player` and
four `gate_*` tests failed ("the player has no character", straight after
`gate_zone_ignores_the_dead`). None touches bomb code and all five passed in the first
run; the cause is not found.

One real fight (Average bot, `IslandReview`): **won in 142 s with 3 deaths.**

| | Real fight | Simulator, Average |
|---|---|---|
| Bombs landed / defused / burst (hit) | 9 / 5 / 3 (1) | 48% defused, 11% burst hits |
| Landing to defuse | 4.35 s for 3 letters, 5.0 s for 4 | |
| Wrong taps | 0 (one forced: fuse −1.00 s, progress kept) | |
| Defuse share of boss damage | 47% | 42% |
| Damage taken near a live bomb / deaths near one | 55 / 2 of 3 | |
| Defuse damage | 135 (9%) and 180 (12%) of 1500 | |
| Word credit | ZOO gave blue +6, server ceiling and client reservoir both 9 → 15; the next cast was accepted | |

- Lobs alternated with volleys, none landed with the ward up, all landed on floor
  0.2 to 13.4 studs from the bot with no fallback.
- **Standing still to solve is where the risk is.** Volleys killed the bot twice while
  it waited beside a bomb, and those bombs then burst.
- **The hint may make the puzzle free.** The bot's first tap came at 3.0 s on every
  bomb. Not changed; one fight.
- Half credit is small: 5 or 6 energy, about one tier-1 cast.
- **Nobody has seen the letters.** `screen_capture` does not draw BillboardGuis; the
  tiles report real sizes but no image shows them. The header measured 885 by 553 px
  at 7 studs, most of the screen, and was changed to a fixed 280 by 170 px; that
  change is unseen too.
- Not exercised: a human click or tap, a tap through cover, a touch device, co-op.
- The bot gives a bomb up when hurt but does not leave the burst radius.

## Open

- Tap reach 20 or 14.
- Full or half word credit, after real fights.
- How fast a young child unscrambles a given 3-letter word and how often they notice
  the bomb. The simulator's answer rests on both.
- A defuse does not use the buffer, so it does not teach pop, arrange, memorize.
  Whether that matters for the tutorial is undecided.
- The spore telegraph and the hunger rework are still uncommitted and waiting for the
  user's playtest; stage 1 builds on the telegraph.

## Running the simulator with a bomb

As [[design/ai-playtest]] § How to run the simulator, with
`tuning = { ward = { atHp = 0.5, letters = 4, orbitRadius = 10, cooldown = 3, walkSpeed = 9 }, bomb = { hintAfterSec = 3, energyScale = 0.5 } }`.
An empty `bomb = {}` is the first draft; the knobs are listed above `FightSim.run`.
The ward is only in the simulator when `tune.ward` is passed. The bomb's own counts
(`bombDefused`, `bombBurstHit`, `bombShare`…) are in the aggregates from
`PlaytestMetrics`, not in `SimRunner`'s text report. `tune.spore` also gained opt-in
knobs the same day (`popReach`, `landMinRadius`, `landTowardBoss`, `fuseSecs`,
`ripeWindowSec`, `popTaps`, `withVolley`), used for the rows in § Why.
