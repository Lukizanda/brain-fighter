---
type: design
description: Sound direction — a 16-bit console RPG heard as a physical world; world sounds are noise-led and real, only the player's own progress is musical, and nothing gets busy. Every decision cites the user's words.
updated: 2026-11-25
---

# Audio Direction

The sound counterpart of [[design/ArtDirection]]. Read this before designing or judging any sound. Each rule says which user decision it comes from. A rule without one is a proposal, and is marked as such.

How sounds are made, auditioned and measured is in [docs/agents/audio-sfx.md](../../docs/agents/audio-sfx.md). The history of every round is in [[design/audio-sfx-synthesis]].

## The theme in one line

**A 16-bit console RPG, heard as a physical world.** The hardware gives the character. The world sounds real. Only the player's own progress sings, and it sings quietly.

## 1. One palette: the console

Every sound is synthesized and rendered through the model of the 16-bit console sound hardware in `tools/sfx/ym.py`: FM, square and noise channels, 8-bit samples, changes once per 60 Hz frame, a muffled analogue output. This shared character is what holds the world and the music together, so no sound leaves this palette. Never mix in a recorded sample or a clean modern synth.

*From:* the user asked for synthesized sounds "so that stylistically they are the same", then for 16-bit over 8-bit: "sega genesis kind of game sound effects compared to NES games ... it did sound somewhat close to what the real sound would sound like". The references are Phantasy Star IV and Shining Force II, for character only. Nothing is copied from them.

## 2. Two layers

| | World layer | Progress layer |
|---|---|---|
| **What** | Spells, impacts, explosions, fire, ice, the boss, the arena, popping a block, mana being drawn in | The word being built, memorizing, rewards, menus |
| **Sounds like** | Physical. Noise-led textures: cracks, air, roar, crackle, rumble | Musical: notes, chimes, chords |
| **Pitch** | No melody. If it has pitch at all, it is out of key for attacks and a tritone for the boss | In key: the pentatonic scale in `kit.py` |
| **Measure** | Pitch clarity at most about 0.45 (the chosen spells are 0.16-0.46) | No limit, but it must stay sparse (rule 4) |

A sound belongs to the world layer if it happens *in* the world, even when the player caused it. Popping a block is the block cracking. It is not a reward jingle.

*From:* the user, on take C of the collect sound: "I'm a little worried the style might clash with the realistic spell and explosion effects". Then they chose the fully physical version over the hybrid, which had a quiet note underneath.

## 3. The world, element by element

These are decided. Each points at the chosen sound in `tools/sfx/chosen.json`.

- **Explosion: "tch-ba-boom".** A bright spark, a muffled noise-led hit, then a second, bigger boom that swells in and rolls on for about 1.5 s. The hit stands clear of its tail. It must not sound like a drum (no tuned note under the hit). *From:* "no distinct boom ... just starts and tapers off", "sounds like a drum tom a little", "doesn't sound as big", "tch-ba-boom". Chosen: big fireball #3.
- **Ice: an attack, not a chime.** A hard, clanking strike a semitone out of key, with a clashing second note, a noise crack in front, a cold rush, and crackle. No ring, no echo. *From:* "frost nip sounds more like a reward chime rather than an ice attack". Chosen: Frost Nip take B.
- **Fire: noise that breathes.** Slow, uneven swells and irregular crackles, no pitch, no steady pulse. *From:* "sounds a little like a lawn mower", said of a pitched, evenly pulsing burn. Chosen: Burning take B, roaring.
- **Round and boomy means low weight that a phone can still play.** Energy between 150 Hz and 2 kHz, with little hiss on top. *From:* "more round and boomy". The phone condition is a proposal (many players are on mobile); the user has not ruled on it.
- **Collecting a letter: crack, swirl, gust.** The block cracks apart, with its colour carried by the crack's texture (warm red, woody green, glassy blue, bright gold). A whirl draws the mana in, turning faster as it closes. A rush of air lands on the player. *From:* the user chose take C (spin-in), then its fully physical version.
- **The boss: low, detuned, tritone.** Every attack has a rising tell as long as its windup, so it can be heard from cover. *A proposal* from the plan; the user has heard one tell and has not ruled on it.

## 4. Sparse beats clever

The sounds players hear most must stay simple. A layer that is pleasant alone becomes clutter when a fast speller triggers it four times a second.

- Judge every frequent sound in its **fast-speller demo** (four in 0.3 s steps), not alone.
- When in doubt, remove a layer rather than adding one.
- A sound that repeats often is short, and gets out of the way of the next one.

*From:* the user chose the physical collect over the hybrid because "the hybrid sounds too busy especially when fast spelling".

## 5. Rewards are a different family from attacks

Reward sounds are in key, consonant, may ring, and may echo. Attack sounds use none of those. This keeps the progress layer from leaking into the world layer, and keeps a hit from ever reading as a prize. *From:* the Frost Nip feedback (rule 3).

## 6. Impacts read clearly

An impact has a moment. Its hit stands about 10 dB above what follows within 200 ms, and saturation must not flatten that. *From:* "no distinct boom".

## Open questions

Each of these needs a user decision before it becomes a rule.

- **Where does musical spelling live now?** The user said yes to it (a rising note per letter, resolving on memorize), but the chosen collect sound has no note. The progress layer could carry it: the letter landing in the word buffer, and memorize. *Proposal:* a short note when the tile appears in the buffer, judged in a fast-speller demo.
- **The letter experiments** (colour instruments, word melodies, singing letters) are all progress-layer ideas. Which, if any, survive rule 4?
- **The boss's tritone tell**, and how loud the boss sits relative to the player's own sounds.
- **The phone floor** in rule 3.
