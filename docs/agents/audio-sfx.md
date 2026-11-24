# Making sound effects

Load this when a task creates, changes or reviews a sound effect. Getting a sound to play in the game (server vs client, verifying it on a client) is [vfx-sfx.md](vfx-sfx.md). The plan and each round's history are in [wiki/design/audio-sfx-synthesis.md](../../wiki/design/audio-sfx-synthesis.md). The commands are in [tools/sfx/README.md](../../tools/sfx/README.md).

## Start with the theme
**Read [wiki/design/AudioDirection.md](../../wiki/design/AudioDirection.md) before designing or judging any sound.** It is the user's sound direction: one console palette, a world layer and a progress layer, element by element, and sparse beats clever. This page covers how to work; that page covers what the game sounds like.
- Say which layer a new cue belongs to (world or progress) before you build it, and design within that layer's rules.
- When a cue would break a rule, raise it with the user rather than bending the rule quietly.
- A rule enters the theme only through a user decision, written with the user's own words and the date. Your own ideas go under its Open questions, or are marked as proposals.
- Each time the user chooses a sound, add the decision to the theme's element list. Each time the user's feedback reveals a preference, add it as a rule with the quote.

## How sounds are made here
- Every sound is synthesized offline in Python, numpy and scipy only, and uploaded to Roblox. Nothing comes from a sound library. Roblox has no oscillator or noise generator a published game can use.
- The chosen style is a 16-bit console RPG (the user's references: Phantasy Star IV, Shining Force II). `tools/sfx/ym.py` models that hardware: FM patches in chip register terms, the PSG's squares and noise, 8-bit DAC samples, and a driver that changes pitch and level once per 60 Hz frame. Cues live in `tools/sfx/cues/pilot_md.py`. The other kits (mallet, chip, genesis) are kept only for reference.
- The loop: `render.py` → `lint.py` → `audition.py` → the user listens on `build/sfx/audition.html` → feedback → change → repeat. `screen.py` adds a step that measures many variants and shortlists a few.
- When the user picks a sound, copy its exact settings into a constant in the kit (as with `FIREBALL_EXPLOSION_PARAMS`), so re-running the screen can't change it.
- **Hand-off to upload:**
  - Add the chosen sound to `tools/sfx/chosen.json`, with the game event it plays on and its hook in `VfxConfig`.
  - Run `package.py`. It puts named, versioned, linted files in `build/sfx/upload/` with an `UPLOAD.md` checklist.
  - The user imports them in Studio (decided 2026-11-25: by hand for now, to see how tedious it is) and pastes back the asset ids.
  - Write each id into `chosen.json`, then wire it into the game. A re-render bumps `version`, because the upload is a new asset.

## You cannot hear
- Never say a sound is good, punchy or close. Say what you changed and what you measured. Every summary says no one has listened yet, until the user has.
- Measurements stand in for listening, and only where they agree with the user. Before ranking anything, measure the takes the user already judged and show that the numbers separate them as the user did. `screen.py` prints that table first.
- If a measurement doesn't separate the rated takes, it isn't the right measurement yet. Say so. Don't tune it until it does.
- Every target cites the user's words it stands for. A limit you chose yourself is labelled as your judgement until the user confirms it.

## Turning feedback into a measurement
These come from real feedback (the wiki page has the takes and numbers). All are in `tools/sfx/metrics.py`.

| The user said | What it meant | Measure |
|---|---|---|
| "no distinct boom", "just starts and tapers off" | no moment of impact | `punch_db`: the loudest moment vs 100–200 ms later. 1–2 dB meant no boom; 9 dB or more is a hit. |
| "sounds like a drum tom" | a tuned note under a hit | `pitch_clarity`: tuned sounds score about 0.7, noise about 0.15. The liked explosions were about 0.3. |
| "more round and boomy" | too bright | `centroid_hz` (the "not round" take was 449 Hz) and `above_4k` |
| "not as big" | ends too soon, no second wave | `structure()` → `late_level_db`, `boom_vs_hit_db`, and `ring_sec` |
| "tch-ba-boom" (sounding it out) | three events: spark, hit, boom | `structure()` → `spark_hz`, and `two_events_db` (keep it between 4 and 10 dB: more is near-silence, which sounds like two separate sounds) |
| "like a lawn mower" | a steady pitch plus an even pulse reads as an engine | the largest spectral peak vs the median: plain noise is about 10 dB |
| "a reward chime, not an ice attack" | it used reward ingredients | no metric; AudioDirection rule 5 |
| "worried the style might clash" with the spells | a layer is tonal where the world is physical | `pitch_clarity` per layer; the world layer is at most about 0.45 |
| "too busy, especially when fast spelling" | too many layers for how often it plays | judge in the fast-speller demo; remove a layer |

When the user describes a sound phonetically, split it into events and give each one a measurement.

## Applying the theme in practice
The style rules live in the theme. These are the working habits that serve them:
- **Check the layer by measurement.** World-layer cues should measure at most about 0.45 for pitch clarity. When the user says styles clash, measure each layer of the sound separately; usually one layer is the culprit, not the whole sound (take C's pop and landing measured 0.88 and 0.90, while its whirl measured 0.16).
- **Progress-layer pitches** come from `kit.scale_hz`, the one pentatonic key. Attacks sit off it (`ICE_HZ` is a semitone up), and the boss sits a tritone away (`kit.TRITONE_SEMITONES`).
- **Build frequent sounds for the fast-speller demo first.** Render four in 0.3 s steps beside the single take. Show the demo to the user alongside the single take.
- **Check that it's heard on a phone:** `phone_band` (150 Hz to 2 kHz). Saturating the punch layer alone lets its overtones carry.
- **Keep what the user liked.** When the user calls one part close, freeze it exactly (`BA_PARAMS`) and vary only the rest.
- **Ship the exact sound the user heard.** A chosen sequence is split into the files the game plays, using the same seeds. Show that the split files rebuild the approved sequence sample for sample before packaging. A different seed is a different crack, even from the same recipe.

## Traps you will hit
- **Saturation flattens punch.** `hot()` / `drive` normalises and raises the tail toward the peak. On an impact, keep the final drive near 1.0.
- **Punchy sounds play quieter.** The peak sets the normalisation, so a sharp hit can sit about 6 dB under the other cues on average. Say so on the page, or the user hears it as weak.
- **The chip envelope is slow at gentle values.** A percussive carrier needs D1R around 18–28. Below about 14 a pop barely decays. Release is `4 * RR + 2` internally, not `2 * RR + 1`; that bug once made pops fall only 4 dB in 200 ms.
- **Formants need two harmonics.** With one carrier per formant on the nearest harmonic, vowels collapse together at a sung pitch: 'a' = 'e' and 'o' = 'u' at D4. Weight each formant across the two harmonics either side of it (`letter_lab.voice_patches`), and measure that the vowels differ before showing them.
- **Approved sounds can drift.** Chosen cues are code that later edits can change, often through a shared patch. `package.py` stores each chosen file's sha256 and refuses a render that differs. Never clear a fingerprint to silence the check; bump `version` only when the change is meant to ship.
- **Check sequences as a timeline.** A layer that sounds right alone can bury the next one. Lab 1's bell pop rang at full level for about 350 ms and hid the collect draw-in entirely, which measured fine on its own. Measure loudness and brightness in 50 ms steps across the whole sequence. When one layer hands over to another, fade the first by stepping its TL down every frame, as old drivers did.
- **Build from the picture.** For a visual effect, read its code for the real timings (flight time, stagger, when it starts) and look at it in a playtest. The effect code is client-side drawing, so `execute_luau` on the Client can call it directly beside the character, with no need to reach the game state that normally triggers it. Never take a positioned capture during Play.
- **Changes happen in 60 Hz steps.** Pitch and level move once per frame (16.7 ms). Anything faster, such as a 50 ms kick dive or a 15 ms spark, is a DAC sample built at 48 kHz.
- **Loops.** Mark the cue `"loop": true`. `render.py` then keeps its exact edges and `lint.py` checks the wrap instead. Build the seam with an equal-power crossfade, and saturate before building it, not after. Add a `"demo": true` row that plays the loop three times so the user can hear the seam. Demo rows are exempt from the 6 s upload cap.
- **Screening degenerates.** It finds the loophole in every target. Give each target a ceiling as well as a floor where one makes sense (the near-silence gap), and give each family its own tie-break. The default tie-break favours punch, which picked the smallest booms when "big" was the goal.
- **The shell breaks on long inline Python.** Heredocs containing quotes have failed several times. Write the patch script to a file with the Write tool, run it, then delete it.

## Showing the user
- Show at most three takes per question, each different from the others, plus the previous liked take as a comparison row.
- Describe each take in plain words first ("soft spark, swelling boom"), then the one or two numbers that matter.
- Name the next settings you would move if it is still wrong, so the user's next note maps straight to a change.

## Roblox constraints
These are verified 2026-11-23; details are on the wiki page.
- **No in-place updates.** An uploaded audio asset can't be replaced, so every re-render is a new upload and a new asset id. Iterate locally and upload only the chosen sound.
- **The upload quota is unresolved.** The docs say 100 per month in one place and 2,000 per 30 days in another, for ID-verified accounts.
- **Short or quiet files may be rejected,** and a sound-effect rejection can't be appealed. `lint.py` guards duration, peak, loudness, DC offset and edge clicks for that reason.
- **Uploading publishes outside the repo.** Ask the user before every upload.
