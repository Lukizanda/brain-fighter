"""Pilot family, kit A: clean mallet and synth.

Tuned, bright and toy-like. Letters are a mallet (a sine with two
inharmonic partials), spells are soft synths, the boss is low and detuned.
"""

import numpy as np

import synth as s
from kit import TRITONE_SEMITONES, scale_hz, semitones

KIT = {"id": "mallet", "label": "Clean mallet and synth", "trimDb": 0.0}

# Mallet voice: partial ratio, level, half-life in seconds. The 4x partial
# is what makes a bar sound like a marimba instead of a beep.
MALLET_PARTIALS = (
    (1.0, 1.00, 0.070),
    (4.0, 0.28, 0.022),
    (9.2, 0.10, 0.009),
)
POP_OCTAVE = 1          # pops start at D5
POP_SEC = 0.30
SPELL_STEP_SEC = 0.26   # demo: time between letters
MEMORIZE_CHORD_STEPS = (0, 2, 3, 5)  # D F# A D
MEMORIZE_STAGGER_SEC = 0.045
TELEGRAPH_FLOOR = 0.2   # a telegraph starts audible, then swells


def mallet(hz: float, seconds: float, seed: int = 1) -> np.ndarray:
    tone = sum(
        s.sine(hz * ratio, seconds) * level * s.decay(seconds, half_life)
        for ratio, level, half_life in MALLET_PARTIALS
    )
    strike = s.bandpass(s.noise(0.012, seed), 2500.0, 7000.0) * s.decay(0.012, 0.003, attack=0.0005)
    return s.mix(tone, (strike, 0.25))


def block_pop(step: int = 0) -> np.ndarray:
    hz = scale_hz(step, POP_OCTAVE)
    # The "pop": a quick bubble rising under the note.
    bubble = s.sine(s.glide(hz * 0.45, hz * 1.1, 0.045)) * s.decay(0.045, 0.012)
    return s.room(s.mix(mallet(hz, POP_SEC), (bubble, 0.45)), seconds=0.18, mix=0.10)


def block_pop_wild() -> np.ndarray:
    hz = scale_hz(0, POP_OCTAVE)
    base = block_pop(0)
    sparkle_a = mallet(hz * semitones(12), 0.22, seed=2)
    sparkle_b = mallet(hz * semitones(19), 0.26, seed=3)
    shimmer = s.sine(hz * semitones(24), 0.35) * s.decay(0.35, 0.08) * (0.5 + 0.5 * s.sine(11.0, 0.35))
    return s.room(s.mix(base, (sparkle_a, 0.55, 0.055), (sparkle_b, 0.50, 0.110), (shimmer, 0.12, 0.110)), mix=0.16)


def buffer_tile() -> np.ndarray:
    hz = scale_hz(0, POP_OCTAVE + 1)
    tick = s.sine(hz, 0.13) * s.decay(0.13, 0.016)
    knock = s.lowpass(s.noise(0.010, 4), 1800.0) * s.decay(0.010, 0.003, attack=0.0005)
    return s.mix(tick, (knock, 0.5))


def memorize_success() -> np.ndarray:
    notes = [
        (mallet(scale_hz(step, POP_OCTAVE), 0.55, seed=10 + i), 0.8, i * MEMORIZE_STAGGER_SEC)
        for i, step in enumerate(MEMORIZE_CHORD_STEPS)
    ]
    pad_sec = 0.9
    pad = sum(
        s.triangle(scale_hz(step, POP_OCTAVE - 1), pad_sec) for step in MEMORIZE_CHORD_STEPS[:3]
    ) / 3.0
    pad = s.lowpass(pad, 1800.0) * s.decay(pad_sec, 0.22, attack=0.06)
    return s.room(s.mix(*notes, (pad, 0.35, 0.03)), seconds=0.5, mix=0.2)


def fizzle() -> np.ndarray:
    sec = 0.32
    start = scale_hz(3, POP_OCTAVE - 1)   # A4
    end = scale_hz(0, POP_OCTAVE - 1) * 0.75
    pitch = s.glide(start, end, sec, curve=0.7)
    body = (s.triangle(pitch) + s.triangle(pitch * 1.012)) * 0.5
    body = s.lowpass(body, 1400.0) * s.decay(sec, 0.11, attack=0.004)
    puff = s.lowpass(s.noise(sec, 5), 900.0) * s.decay(sec, 0.05, attack=0.01)
    return s.mix(body, (puff, 0.35))


def cast_red_t1() -> np.ndarray:
    sec = 0.30
    pitch = s.glide(540.0, 150.0, sec, curve=1.6)
    body = s.drive(s.lowpass(s.saw(pitch), 2600.0), 3.5) * s.decay(sec, 0.06, attack=0.003)
    crackle = s.highpass(s.noise(sec, 6), 3500.0) * s.decay(sec, 0.035, attack=0.001)
    thump = s.sine(s.glide(180.0, 70.0, 0.12)) * s.decay(0.12, 0.03)
    return s.room(s.mix(body, (crackle, 0.35), (thump, 0.6)), seconds=0.15, mix=0.08)


def cast_green_t1() -> np.ndarray:
    sec = 0.42
    root = scale_hz(0, 0)
    pitch = s.glide(root, root * 2.0, sec * 0.6, curve=1.4)
    pitch = np.concatenate([pitch, np.full(s.n_samples(sec) - len(pitch), root * 2.0)])
    body = (s.sine(pitch) + 0.4 * s.triangle(pitch)) * s.decay(sec, 0.12, attack=0.025)
    bell = s.sine(pitch * 2.76) * s.decay(sec, 0.05, attack=0.01)
    return s.room(s.mix(body, (bell, 0.18)), seconds=0.3, mix=0.2)


def cast_blue_t1() -> np.ndarray:
    sec = 0.40
    hz = scale_hz(0, 2)
    index = 4.0 * s.decay(sec, 0.05)
    glass = s.fm(hz, 3.5, index, sec) * s.decay(sec, 0.09, attack=0.001)
    hiss = s.highpass(s.noise(sec, 8), 6500.0) * s.decay(sec, 0.06, attack=0.002)
    return s.room(s.mix(glass, (hiss, 0.22)), seconds=0.3, mix=0.2)


def boss_telegraph() -> np.ndarray:
    sec = 1.25
    low = 55.0
    rise = s.glide(low, low * semitones(5), sec, curve=0.6)
    sub = s.sine(rise)
    # Two saws a tritone apart: the interval the player kit never uses.
    growl = s.saw(rise * 2.0) + s.saw(rise * 2.0 * semitones(TRITONE_SEMITONES))
    growl = s.drive(s.lowpass(growl * 0.5, 700.0), 2.5)
    throb = 0.55 + 0.45 * s.sine(s.glide(5.0, 19.0, sec))
    squelch = s.swept_bandpass(s.noise(sec, 9), s.glide(180.0, 1100.0, sec), q=6.0)
    squelch /= np.max(np.abs(squelch))
    body = s.mix((sub, 0.9), (growl * throb, 0.6), (squelch * throb, 0.35))
    body = body * (TELEGRAPH_FLOOR + (1.0 - TELEGRAPH_FLOOR) * s.swell(sec, 1.6))
    # Cut hard at the top so the attack that follows lands in the gap.
    cut = s.n_samples(0.02)
    body[-cut:] *= np.linspace(1.0, 0.0, cut)
    return body


def demo_spell_word() -> np.ndarray:
    letters = [block_pop(step) for step in range(5)]
    layers = [(x, 1.0, i * SPELL_STEP_SEC) for i, x in enumerate(letters)]
    layers.append((memorize_success(), 1.0, len(letters) * SPELL_STEP_SEC + 0.25))
    return s.mix(*layers)


CUES = {
    "block_pop": block_pop,
    "block_pop_wild": block_pop_wild,
    "buffer_tile": buffer_tile,
    "demo_spell_word": demo_spell_word,
    "memorize_success": memorize_success,
    "fizzle": fizzle,
    "cast_red_t1": cast_red_t1,
    "cast_green_t1": cast_green_t1,
    "cast_blue_t1": cast_blue_t1,
    "boss_telegraph": boss_telegraph,
}
