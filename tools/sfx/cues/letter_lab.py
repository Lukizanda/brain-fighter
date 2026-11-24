"""Letter lab: three experiments in making the letter sounds come from the
spelling itself, instead of a generic casual-game pop (user, 2026-11-25:
"something a little more complex than just generic sound effects").

Each experiment tests one idea, in the 16-bit RPG kit:
  1. Colour instruments: the block's colour picks the instrument (red brass,
     green wood, blue glass, wild gold); pitch climbs with buffer position.
  2. Word melodies: each letter has its own fixed note, so every word has a
     tune; memorizing plays the word's tune back, then resolves.
  3. Singing letters: the chip sings each letter's phonics sound with FM
     formant synthesis (vowels sing, consonants are articulated).

Upload cost, since every file is an upload: in game the pitch can be set
with Sound.PlaybackSpeed, so 1 and 2 need about one file per instrument,
and 3 about one per letter.

Importing this module registers its cues into the kit (pilot_md.CUES).
"""

from __future__ import annotations

import numpy as np

import synth as s
import ym
from cues import pilot_md as base
from kit import SAMPLE_RATE, scale_hz, semitones
from ym import Op, Patch

FRAME = base.FRAME
LETTER_STEP_SEC = 0.24     # demo: time between popped letters
REPLAY_FRAMES = 4          # memorize replay: frames per letter
RARE_LETTERS = set("JQXZ") # Scrabble 8-10: get the value shimmer

# --- Shared: the pop's front ------------------------------------------------


def pop_front(seed: int = 11) -> np.ndarray:
    """The same tiny front on every letter: one frame of noise and a soft
    sampled knock. It is what makes each instrument a pop."""
    click = base.noise_burst([3, 9, 15], divider=512, seed=seed) * 0.3
    knock = base.dac_knock(play_rate=11000.0) * 0.35
    return ym.place(max(len(click), len(knock)), click, knock)


def with_front(tone: np.ndarray, seed: int = 11) -> np.ndarray:
    front = pop_front(seed)
    return ym.place(max(len(tone), len(front)), tone, front)


# --- 1. Colour instruments ----------------------------------------------------

# Red: a short brass stab (the BRASS voice, plucked).
RED_PLUCK = Patch(3, 5, [
    Op(mul=1, tl=24, ar=31, d1r=20, sl=5, d2r=12, rr=12),
    Op(mul=1, dt=1, tl=28, ar=31, d1r=18, sl=4, d2r=12, rr=12),
    Op(mul=2, tl=34, ar=31, d1r=22, sl=6, d2r=14, rr=12),
    Op(mul=1, tl=2, ar=31, d1r=17, sl=4, d2r=11, rr=10),
])


def colour_pop(colour: str, step: int) -> np.ndarray:
    hz = scale_hz(step, base.POP_OCTAVE)
    if colour == "red":
        tone = base.note(RED_PLUCK, hz, 3, ring_sec=0.18)
    elif colour == "green":
        tone = base.note(base.BAR, hz, 2, ring_sec=0.22)
    elif colour == "blue":
        tone = base.note(base.BELL, hz, 2, ring_sec=0.32, gain_db=-1.0)
    else:  # wild: gold, the bell plus an octave-and-fifth sparkle
        tone = ym.place(ym.chip_samples(0.4), base.note(base.BELL, hz, 2, ring_sec=0.32),
                        (base.note(base.BELL, hz * semitones(19), 2, ring_sec=0.25, gain_db=-6.0), 2 * FRAME))
    return base.out(with_front(tone))


def lab1_red() -> np.ndarray:
    return colour_pop("red", 0)


def lab1_green() -> np.ndarray:
    return colour_pop("green", 0)


def lab1_blue() -> np.ndarray:
    return colour_pop("blue", 0)


def lab1_wild() -> np.ndarray:
    return colour_pop("wild", 0)


def lab1_word() -> np.ndarray:
    """DEMO: B-R-A-I-N popped from mixed colours, rising, then memorized."""
    colours = ["red", "blue", "green", "wild", "blue"]
    layers = [(colour_pop(c, i), 1.0, i * LETTER_STEP_SEC) for i, c in enumerate(colours)]
    layers.append((base.memorize_success(), 1.0, len(colours) * LETTER_STEP_SEC + 0.2))
    return s.mix(*layers)


# --- 2. Word melodies -------------------------------------------------------

MELODY_NOTES = 10  # letters map onto two octaves of the pentatonic scale


def letter_step(letter: str) -> int:
    """A fixed scale step per letter. Spread so neighbours in common words
    differ: the alphabet index times 3, folded into two octaves."""
    return (ord(letter.upper()) - ord("A")) * 3 % MELODY_NOTES


def melody_pop(letter: str) -> np.ndarray:
    hz = scale_hz(letter_step(letter), base.POP_OCTAVE - 1)
    tone = base.note(base.BLIP, hz, 3, ring_sec=0.2)
    if letter.upper() in RARE_LETTERS:
        shimmer = base.note(base.BELL, hz * semitones(24), 2, ring_sec=0.4, gain_db=-7.0)
        tone = ym.place(max(len(tone), len(shimmer)), tone, (shimmer, FRAME))
    return base.out(with_front(tone))


def melody_memorize(word: str) -> np.ndarray:
    """The word's tune played back quickly on the bell, landing on the
    resolving chord."""
    notes = [scale_hz(letter_step(c), base.POP_OCTAVE - 1) for c in word]
    replay = base.arpeggio(base.BELL, notes, REPLAY_FRAMES, ring_sec=0.35, gain_db=-2.0)
    at = len(notes) * REPLAY_FRAMES * FRAME
    chord = base.memorize_success()
    return s.mix(base.out(replay), (chord, 0.9, at))


def melody_word(word: str) -> np.ndarray:
    layers = [(melody_pop(c), 1.0, i * LETTER_STEP_SEC) for i, c in enumerate(word)]
    layers.append((melody_memorize(word), 1.0, len(word) * LETTER_STEP_SEC + 0.2))
    return s.mix(*layers)


def lab2_cat() -> np.ndarray:
    return melody_word("CAT")


def lab2_quiz() -> np.ndarray:
    return melody_word("QUIZ")


def lab2_brain() -> np.ndarray:
    return melody_word("BRAIN")


# --- 3. Singing letters -----------------------------------------------------
# FM formant synthesis: one modulator at the sung pitch feeds three carriers
# whose multipliers put them on the harmonics nearest each vowel's formants.
# The chip's voice is coarse, which is part of the period sound.

VOWEL_FORMANTS = {
    "a": (660.0, 1720.0, 2410.0),   # as in cat
    "e": (530.0, 1840.0, 2480.0),   # bed
    "i": (390.0, 1990.0, 2550.0),   # sit
    "o": (730.0, 1090.0, 2440.0),   # hot
    "u": (640.0, 1190.0, 2390.0),   # cup
    "ee": (270.0, 2290.0, 3010.0),  # y as in happy
    "oo": (300.0, 870.0, 2240.0),   # w
    "er": (490.0, 1350.0, 1690.0),  # r
    "uh": (500.0, 1500.0, 2500.0),  # the short neutral vowel after a consonant
}
FORMANT_TL = (0, 7, 15)          # each formant quieter than the last
VOICE_OCTAVE = 0                 # sung an octave below the pops: formants resolve better
VOWEL_FRAMES = 9
SCHWA_FRAMES = 4
BODY_TL = (6, 14)                # the first two harmonics, for a sung body
MAX_TL = 127


def _tl_for(weight: float, base_tl: int) -> int:
    """TL that scales an operator by `weight` (0.75 dB per TL step)."""
    if weight <= 1e-3:
        return MAX_TL
    return int(min(MAX_TL, base_tl + round(-20.0 * np.log10(weight) / 0.75)))


def voice_patches(f0: float, vowel: str) -> list[Patch]:
    """A sung vowel as eight sine operators on two channels (algorithm 7,
    every operator heard). Each formant sits on the two harmonics either side
    of it, weighted by how close each is, so a formant can fall between
    harmonics. One harmonic per formant (an earlier version) made 'a' and
    'e', and 'o' and 'u', identical at this pitch."""
    sines = [(1, BODY_TL[0]), (2, BODY_TL[1])]
    for formant, tl in zip(VOWEL_FORMANTS[vowel], FORMANT_TL):
        ratio = formant / f0
        low = int(np.floor(ratio))
        frac = ratio - low
        if low >= 1:
            sines.append((low, _tl_for(1.0 - frac, tl)))
        sines.append((low + 1, _tl_for(frac if low >= 1 else 1.0, tl)))
    sines = [(min(mul, 15), tl) for mul, tl in sines][:8]
    while len(sines) < 8:
        sines.append((1, MAX_TL))
    ops = [Op(mul=mul, tl=tl, ar=28, d1r=9, sl=2, d2r=5, rr=9) for mul, tl in sines]
    vibrato = dict(lfo_hz=ym.LFO_HZ[2], pms_cents=ym.PMS_CENTS[3])
    return [Patch(7, 0, ops[:4], **vibrato), Patch(7, 0, ops[4:], **vibrato)]


def voice_note(f0: float, vowel: str, pitch, frames_on: int, ring_sec: float, gain_db: float = 0.0) -> np.ndarray:
    a, b = (base.note(patch, pitch, frames_on, ring_sec=ring_sec, gain_db=gain_db) for patch in voice_patches(f0, vowel))
    return a + b


def sing(vowel: str, hz: float, frames_on: int, gain_db: float = 0.0) -> np.ndarray:
    """A sung vowel with a small scoop up into the note."""
    pitch = ym.frames([hz * 0.97, hz * 0.99, hz])
    return voice_note(hz, vowel, pitch, frames_on, 0.12, gain_db)


def noise_shape(sec: float, low: float, high: float, seed: int, attack: float, half_life: float,
                rate: float = 16000.0) -> np.ndarray:
    x = s.bandpass(s.noise(sec, seed), low, min(high, rate * 0.45))
    x = x / np.max(np.abs(x)) * s.decay(sec, half_life, attack=attack)
    return ym.dac_sample(x, SAMPLE_RATE, rate)


# Plosive bursts by where the mouth closes, fricative noise bands.
PLOSIVE_BAND = {"lips": (400.0, 1500.0), "tip": (3000.0, 7000.0), "back": (1500.0, 3500.0)}
FRICATIVE_BAND = {"s": (4000.0, 7500.0), "f": (1500.0, 6000.0), "h": (800.0, 3000.0), "sh": (2000.0, 5000.0)}
# How each letter is articulated: (kind, detail, voiced). Vowels sing.
LETTER_SOUND = {
    "A": ("vowel", "a", True), "E": ("vowel", "e", True), "I": ("vowel", "i", True),
    "O": ("vowel", "o", True), "U": ("vowel", "u", True), "Y": ("vowel", "ee", True),
    "B": ("plosive", "lips", True), "P": ("plosive", "lips", False),
    "D": ("plosive", "tip", True), "T": ("plosive", "tip", False),
    "G": ("plosive", "back", True), "K": ("plosive", "back", False),
    "C": ("plosive", "back", False), "Q": ("plosive", "back", False),
    "F": ("fricative", "f", False), "V": ("fricative", "f", True),
    "S": ("fricative", "s", False), "Z": ("fricative", "s", True),
    "H": ("fricative", "h", False), "J": ("fricative", "sh", True),
    "X": ("cluster", "ks", False),
    "M": ("nasal", "m", True), "N": ("nasal", "n", True),
    "L": ("liquid", "oo", True), "R": ("liquid", "er", True), "W": ("liquid", "oo", True),
}


def articulate(letter: str, hz: float, seed: int) -> tuple[np.ndarray, float]:
    """The consonant part of a letter, and when the vowel after it starts."""
    kind, detail, voiced = LETTER_SOUND[letter]
    def hum(sec: float) -> np.ndarray:
        return voice_note(hz * 0.5, "uh", hz * 0.5, max(1, round(sec / FRAME)), 0.02, -10.0)
    if kind == "plosive":
        low, high = PLOSIVE_BAND[detail]
        burst = noise_shape(0.03, low, high, seed, 0.0005, 0.006)
        parts = [burst, (hum(0.04), 0.0)] if voiced else [burst]
        return ym.place(ym.chip_samples(0.05), *parts), 0.02
    if kind == "fricative":
        low, high = FRICATIVE_BAND[detail]
        hiss = noise_shape(0.12, low, high, seed, 0.02, 0.05) * (0.6 if detail in ("f", "h") else 0.9)
        parts = [hiss, (hum(0.1), 0.0)] if voiced else [hiss]
        return ym.place(ym.chip_samples(0.13), *parts), 0.08
    if kind == "cluster":  # X: k then s
        k = noise_shape(0.03, *PLOSIVE_BAND["back"], seed, 0.0005, 0.006)
        sss = noise_shape(0.12, *FRICATIVE_BAND["s"], seed + 1, 0.01, 0.05) * 0.9
        return ym.place(ym.chip_samples(0.16), k, (sss, 0.03)), 0.12
    if kind == "nasal":
        # A closed-mouth hum, darker for M than for N.
        mm = voice_note(hz, "oo" if detail == "m" else "uh", hz, 6, 0.02, -4.0)
        return ym.place(len(mm), mm), 0.07
    # liquid: a short glide out of its own vowel colour
    glide = sing(detail, hz, 3, gain_db=-3.0)
    return ym.place(len(glide), glide), 0.04


def sung_letter(letter: str, step: int, seed: int = 21) -> np.ndarray:
    letter = letter.upper()
    hz = scale_hz(step, VOICE_OCTAVE)
    kind, detail, _ = LETTER_SOUND[letter]
    if kind == "vowel":
        x = sing(detail, hz, VOWEL_FRAMES)
    else:
        front, at = articulate(letter, hz, seed)
        vowel = sing("uh", hz, SCHWA_FRAMES, gain_db=-2.0)
        x = ym.place(ym.chip_samples(at) + len(vowel), front, (vowel, at))
    return base.out(x)


def choir_chord(vowel: str = "a") -> np.ndarray:
    """Memorize, sung: the resolving chord on a vowel, notes entering one
    frame apart, held and swelling a little."""
    steps = (0, 2, 3, 5)
    hold = 30
    voices = [(sing(vowel, scale_hz(st, VOICE_OCTAVE), hold, gain_db=-3.0), i * FRAME) for i, st in enumerate(steps)]
    return base.out(base.with_echo(ym.place(ym.chip_samples(hold * FRAME + 0.5), *voices), repeats=1))


def sung_word(word: str) -> np.ndarray:
    layers = [(sung_letter(c, i, seed=21 + i), 1.0, i * LETTER_STEP_SEC) for i, c in enumerate(word)]
    layers.append((choir_chord(), 1.0, len(word) * LETTER_STEP_SEC + 0.2))
    return s.mix(*layers)


def lab3_a() -> np.ndarray:
    return sung_letter("A", 0)


def lab3_s() -> np.ndarray:
    return sung_letter("S", 0)


def lab3_t() -> np.ndarray:
    return sung_letter("T", 0)


def lab3_m() -> np.ndarray:
    return sung_letter("M", 0)


def lab3_brain() -> np.ndarray:
    return sung_word("BRAIN")


def lab3_quiz() -> np.ndarray:
    return sung_word("QUIZ")


CUES = {
    "lab1_red": lab1_red, "lab1_green": lab1_green, "lab1_blue": lab1_blue, "lab1_wild": lab1_wild,
    "lab1_word": lab1_word,
    "lab2_cat": lab2_cat, "lab2_quiz": lab2_quiz, "lab2_brain": lab2_brain,
    "lab3_a": lab3_a, "lab3_s": lab3_s, "lab3_t": lab3_t, "lab3_m": lab3_m,
    "lab3_brain": lab3_brain, "lab3_quiz": lab3_quiz,
}
base.CUES.update(CUES)

SHEET = [
    ("lab1_red", "Red block pop (brass)", "Lab 1: colour instruments", False, "The colour picks the instrument; you hear which mana you got."),
    ("lab1_green", "Green block pop (wood)", "Lab 1: colour instruments", False, "Marimba-like."),
    ("lab1_blue", "Blue block pop (glass)", "Lab 1: colour instruments", False, "Bell-like."),
    ("lab1_wild", "Wildcard pop (gold)", "Lab 1: colour instruments", False, "Bell plus a sparkle an octave and a fifth up."),
    ("lab1_word", "DEMO: BRAIN from mixed colours", "Lab 1: colour instruments", True, "Red, blue, green, wild, blue, rising, then memorized."),
    ("lab2_cat", "DEMO: CAT", "Lab 2: word melodies", True, "Each letter has its own note, so the word has a tune. Memorize plays the tune back, then resolves."),
    ("lab2_quiz", "DEMO: QUIZ", "Lab 2: word melodies", True, "A different tune. Q and Z are rare letters: listen for their shimmer."),
    ("lab2_brain", "DEMO: BRAIN", "Lab 2: word melodies", True, "A third tune, to hear that words differ."),
    ("lab3_a", "Sung letter: A", "Lab 3: singing letters", False, "The chip sings the phonics vowel, 'a' as in cat."),
    ("lab3_s", "Sung letter: S", "Lab 3: singing letters", False, "A hiss, then a short 'uh'."),
    ("lab3_t", "Sung letter: T", "Lab 3: singing letters", False, "A tongue click, then 'uh'."),
    ("lab3_m", "Sung letter: M", "Lab 3: singing letters", False, "A closed-mouth hum, then 'uh'."),
    ("lab3_brain", "DEMO: BRAIN, sung", "Lab 3: singing letters", True, "b-r-a-i-n, rising, then the memorize sung as a chord."),
    ("lab3_quiz", "DEMO: QUIZ, sung", "Lab 3: singing letters", True, "q-u-i-z."),
]
