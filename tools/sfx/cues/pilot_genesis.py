"""Pilot family, kit C: 16-bit console FM.

Four-operator FM in the style of early-90s 16-bit consoles: every voice is
sines modulating sines, with fast envelopes on the modulators so a sound
starts bright and settles pure. That is why this style can pass for real
instruments (marimba, bell, slap bass, brass) while staying synthetic. A
square-wave noise channel adds the hiss. The output is low-passed and
slightly driven, like the console's analogue stage.
"""

import numpy as np

import synth as s
from kit import TRITONE_SEMITONES, scale_hz, semitones

# Trimmed so the kit sits at the same loudness as the others in an A/B.
KIT = {"id": "genesis", "label": "16-bit console FM", "trimDb": -4.5}

POP_OCTAVE = 1
SPELL_STEP_SEC = 0.26
MEMORIZE_CHORD_STEPS = (0, 2, 3, 5)  # D F# A D
MEMORIZE_STAGGER_SEC = 0.05
OUTPUT_LOWPASS_HZ = 9000.0
OUTPUT_DRIVE = 1.4
OUTPUT_BITS = 10
TELEGRAPH_FLOOR = 0.2

# Modulator-to-carrier frequency ratios that give each FM instrument its
# character. Whole numbers sound harmonic, the others sound struck or glassy.
RATIO_MARIMBA = 4.0
RATIO_BELL = 3.5
RATIO_CRYSTAL = 7.1
RATIO_WOOD = 2.4
RATIO_CORK = 1.41


def finish(x: np.ndarray) -> np.ndarray:
    x = s.lowpass(x, OUTPUT_LOWPASS_HZ)
    x = s.drive(x / max(1e-9, np.max(np.abs(x))), OUTPUT_DRIVE)
    return s.crush(x, OUTPUT_BITS)


def marimba(hz: float, sec: float, bright: float = 3.0) -> np.ndarray:
    mod = s.op(hz * RATIO_MARIMBA, bright * s.decay(sec, 0.012, attack=0.0005))
    return s.op(hz, s.decay(sec, 0.06, attack=0.001), mod)


def bell(hz: float, sec: float, ratio: float = RATIO_BELL, bright: float = 2.5, ring: float = 0.12) -> np.ndarray:
    mod = s.op(hz * ratio, bright * s.decay(sec, ring * 0.6, attack=0.0005))
    return s.op(hz, s.decay(sec, ring, attack=0.001), mod)


def chirp(start_hz: float, end_hz: float, sec: float, click: float = 2.0) -> np.ndarray:
    """A sine that jumps in pitch, with an FM click on the front. Rising, it
    is a bubble; falling, a thump."""
    pitch = s.glide(start_hz, end_hz, sec, curve=2.0)
    mod = s.op(pitch * RATIO_CORK, click * s.decay(sec, 0.003, attack=0.0002))
    return s.op(pitch, s.decay(sec, sec * 0.3, attack=0.0008), mod)


# --- Letter -----------------------------------------------------------------

def block_pop(step: int = 0) -> np.ndarray:
    """A bubble that bursts onto a marimba note. The note carries the
    musical-spelling pitch; the bubble is what makes it a pop."""
    hz = scale_hz(step, POP_OCTAVE)
    bubble = chirp(hz * 0.4, hz * 1.25, 0.05)
    note = marimba(hz, 0.22)
    return finish(s.mix((bubble, 1.0), (note, 0.75, 0.012)))


def pop_bubble() -> np.ndarray:
    """Watery: two rising chirps, the second smaller, no note."""
    first = chirp(380.0, 1500.0, 0.06, click=1.0)
    second = chirp(700.0, 2100.0, 0.04, click=0.5)
    return finish(s.mix(first, (second, 0.45, 0.055)))


def pop_cork(step: int = 0) -> np.ndarray:
    """Hollow tok: a falling thump through a woody resonance."""
    hz = scale_hz(step, POP_OCTAVE - 1)
    thump = chirp(hz * 2.2, hz, 0.07, click=5.0)
    wood_mod = s.op(hz * RATIO_WOOD, 4.0 * s.decay(0.09, 0.006, attack=0.0003))
    wood = s.op(hz, s.decay(0.09, 0.02, attack=0.0005), wood_mod)
    return finish(s.mix(thump, (wood, 0.6)))


def pop_chime(step: int = 0) -> np.ndarray:
    """A pickup: two quick bell notes, the root then its fifth above."""
    hz = scale_hz(step, POP_OCTAVE + 1)
    low = bell(hz, 0.16, ring=0.05)
    high = bell(hz * semitones(7), 0.30, ring=0.09)
    return finish(s.mix(low, (high, 0.9, 0.055)))


def pop_slap(step: int = 0) -> np.ndarray:
    """Funky: a slap-bass pluck. Bright bite, round body."""
    hz = scale_hz(step, POP_OCTAVE - 1)
    sec = 0.20
    bite = s.op_feedback(hz, 3.0 * s.decay(sec, 0.012, attack=0.0003), 1.2)
    body = s.op(hz, s.decay(sec, 0.05, attack=0.001), bite)
    return finish(body)


def block_pop_wild() -> np.ndarray:
    hz = scale_hz(0, POP_OCTAVE)
    run = (12, 16, 19, 24)
    sparkles = [(bell(hz * semitones(n), 0.28, ring=0.08), 0.55, 0.05 + i * 0.045) for i, n in enumerate(run)]
    return finish(s.echo(s.mix(block_pop(0), *sparkles), 0.11, 0.35, 2))


def buffer_tile() -> np.ndarray:
    hz = scale_hz(0, POP_OCTAVE + 1)
    sec = 0.12
    mod = s.op(hz * RATIO_WOOD, 3.5 * s.decay(sec, 0.004, attack=0.0003))
    return finish(s.op(hz, s.decay(sec, 0.012, attack=0.0005), mod))


def memorize_success() -> np.ndarray:
    notes = [
        (bell(scale_hz(step, POP_OCTAVE), 0.9, bright=2.0, ring=0.22), 0.7, i * MEMORIZE_STAGGER_SEC)
        for i, step in enumerate(MEMORIZE_CHORD_STEPS)
    ]
    # A brass-like swell underneath: the modulator opens as the note grows.
    sec = 0.7
    root = scale_hz(0, POP_OCTAVE - 1)
    rise = np.minimum(1.0, s.times(sec) / 0.06) * (0.5 ** (s.times(sec) / 0.25))
    brass = sum(s.op(f, rise, s.op(f, 2.2 * rise)) for f in (root, root * semitones(7) * 1.003)) * 0.5
    return finish(s.echo(s.mix(*notes, (brass, 0.4, 0.02)), 0.14, 0.3, 2))


def fizzle() -> np.ndarray:
    sec = 0.32
    pitch = s.glide(scale_hz(3, POP_OCTAVE - 2), scale_hz(0, POP_OCTAVE - 2) * 0.7, sec, curve=0.8)
    # The brightness drains away with the pitch: an instrument running down.
    mod = s.op(pitch, 3.0 * s.decay(sec, 0.07, attack=0.001))
    body = s.op(pitch, s.decay(sec, 0.12, attack=0.003), mod)
    puff = s.highpass(s.held_noise(3000.0, 0.08, 31), 1200.0) * s.decay(0.08, 0.02)
    return finish(s.mix(body, (puff, 0.2)))


# --- Spells -----------------------------------------------------------------

def cast_red_t1() -> np.ndarray:
    sec = 0.34
    # Heavy self-feedback breaks a falling tone into a roar of flame.
    flame = s.op_feedback(s.glide(900.0, 160.0, sec, curve=1.6), s.decay(sec, 0.07, attack=0.004), 3.2)
    boom = chirp(240.0, 55.0, 0.16, click=3.0)
    return finish(s.mix((flame, 0.8), (boom, 0.8)))


def cast_green_t1() -> np.ndarray:
    # A harp run up the scale, ending on a soft held bell.
    run = [(marimba(scale_hz(step, 0), 0.20, bright=1.5), 0.6, i * 0.04) for i, step in enumerate(range(5))]
    top = bell(scale_hz(5, 0), 0.5, ratio=2.0, bright=1.2, ring=0.16)
    return finish(s.echo(s.mix(*run, (top, 0.9, 0.2)), 0.12, 0.3, 2))


def cast_blue_t1() -> np.ndarray:
    sec = 0.42
    hz = scale_hz(0, 2)
    crystal = bell(hz, sec, ratio=RATIO_CRYSTAL, bright=3.0, ring=0.10)
    shard = bell(hz * semitones(7), 0.25, ratio=RATIO_CRYSTAL, bright=2.0, ring=0.05)
    frost = s.highpass(s.held_noise(16000.0, 0.12, 32), 5000.0) * s.decay(0.12, 0.025)
    return finish(s.echo(s.mix(crystal, (shard, 0.5, 0.06), (frost, 0.18)), 0.09, 0.3, 2))


# --- Brain ------------------------------------------------------------------

def boss_telegraph() -> np.ndarray:
    sec = 1.25
    rise = s.glide(55.0, 55.0 * semitones(5), sec, curve=0.6)
    level = TELEGRAPH_FLOOR + (1.0 - TELEGRAPH_FLOOR) * s.swell(sec, 1.6)
    # The classic FM growl: the modulator opens as the sound swells, so it
    # gets nastier, not just louder.
    growl_mod = s.op_feedback(rise * 0.5, 1.0 + 5.0 * s.swell(sec, 1.2), 0.9)
    growl = s.op(rise, level, growl_mod)
    foe = rise * 2.0 * semitones(TRITONE_SEMITONES)
    snarl = s.op(foe, level, s.op(foe, 3.0 * s.swell(sec, 2.0)))
    throb = 0.6 + 0.4 * s.sine(s.glide(5.0, 19.0, sec))
    return finish(s.mix((growl, 1.0), (snarl * throb, 0.45)))


def demo_spell_word() -> np.ndarray:
    letters = [block_pop(step) for step in range(5)]
    layers = [(x, 1.0, i * SPELL_STEP_SEC) for i, x in enumerate(letters)]
    layers.append((memorize_success(), 1.0, len(letters) * SPELL_STEP_SEC + 0.25))
    return s.mix(*layers)


CUES = {
    "block_pop": block_pop,
    "pop_bubble": pop_bubble,
    "pop_cork": pop_cork,
    "pop_chime": pop_chime,
    "pop_slap": pop_slap,
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
