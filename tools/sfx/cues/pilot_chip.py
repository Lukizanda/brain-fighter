"""Pilot family, kit B: retro chiptune.

Three channels, as on an 8-bit console: pulse waves at fixed duty cycles,
a triangle for bass, and sample-and-hold noise. Pitch and volume move in
60 Hz frames, which is where the arcade character comes from.
"""

import numpy as np

import synth as s
from kit import TRITONE_SEMITONES, scale_hz, semitones

# Square waves carry more energy than mallets at the same peak, so the kit is
# trimmed to sit at the same loudness as the others in an A/B.
KIT = {"id": "chip", "label": "Retro chiptune", "trimDb": -5.0}

FRAME_HZ = 60.0          # control rate: pitch and volume change per frame
FRAME_SEC = 1.0 / FRAME_HZ
VOLUME_LEVELS = 15       # 4-bit volume
DUTY_THIN = 0.125
DUTY_REEDY = 0.25
DUTY_SQUARE = 0.5
OUTPUT_BITS = 8
TELEGRAPH_FLOOR = 0.2   # a telegraph starts audible, then swells
POP_OCTAVE = 1
POP_SEC = 0.20
SPELL_STEP_SEC = 0.26
MEMORIZE_ARP_STEPS = (0, 2, 3, 5)  # D F# A D
ARP_NOTE_FRAMES = 4


def env(seconds: float, half_life: float) -> np.ndarray:
    """Volume envelope held in frames and snapped to 4-bit levels."""
    # No attack ramp: a frame-held ramp would start on a silent frame.
    return s.stepped(0.5 ** (s.times(seconds) / half_life), FRAME_HZ, VOLUME_LEVELS)


def frames(count: int) -> float:
    return count * FRAME_SEC


def notes(freqs: list[float], frames_each: int) -> np.ndarray:
    """A pitch curve that holds each frequency for a number of frames."""
    hold = s.n_samples(frames(frames_each))
    return np.concatenate([np.full(hold, f) for f in freqs])


def hold_last(curve: np.ndarray, seconds: float) -> np.ndarray:
    extra = s.n_samples(seconds) - len(curve)
    return np.concatenate([curve, np.full(max(0, extra), curve[-1])])


def finish(x: np.ndarray) -> np.ndarray:
    return s.crush(x / max(1e-9, np.max(np.abs(x))), OUTPUT_BITS)


def block_pop(step: int = 0) -> np.ndarray:
    hz = scale_hz(step, POP_OCTAVE)
    # One frame an octave up, then the note: the classic pickup blip.
    pitch = hold_last(notes([hz * 2.0, hz], 1), POP_SEC)
    return finish(s.pulse(pitch, duty=DUTY_REEDY) * env(POP_SEC, 0.045))


def block_pop_wild() -> np.ndarray:
    hz = scale_hz(0, POP_OCTAVE)
    run = [hz, hz * semitones(7), hz * semitones(12), hz * semitones(16), hz * semitones(19), hz * semitones(24)]
    sec = 0.42
    pitch = hold_last(notes(run, 2), sec)
    lead = s.pulse(pitch, duty=DUTY_THIN) * env(sec, 0.11)
    return finish(lead)


def buffer_tile() -> np.ndarray:
    hz = scale_hz(0, POP_OCTAVE + 1)
    sec = 0.13
    return finish(s.pulse(hz, sec, duty=DUTY_SQUARE) * env(sec, 0.014))


def memorize_success() -> np.ndarray:
    arp = [scale_hz(step, POP_OCTAVE) for step in MEMORIZE_ARP_STEPS]
    sec = 0.95
    pitch = hold_last(notes(arp, ARP_NOTE_FRAMES), sec)
    arp_end = frames(ARP_NOTE_FRAMES * len(arp))
    # Vibrato only on the held top note.
    t = s.times(sec)
    wobble = np.where(t > arp_end, 1.0 + 0.012 * np.sin(s.TAU * 6.5 * t), 1.0)
    lead = s.pulse(pitch * wobble, duty=DUTY_REEDY)
    lead_env = np.where(t < arp_end, 1.0, 0.5 ** ((t - arp_end) / 0.16))
    lead = lead * s.stepped(lead_env, FRAME_HZ, VOLUME_LEVELS)
    bass = s.triangle(scale_hz(0, POP_OCTAVE - 2), sec) * env(sec, 0.25)
    return finish(s.mix(lead, (bass, 0.7)))


def fizzle() -> np.ndarray:
    sec = 0.30
    pitch = s.stepped(s.glide(scale_hz(3, POP_OCTAVE - 1), scale_hz(0, POP_OCTAVE - 2), sec, curve=0.8), FRAME_HZ)
    body = s.pulse(pitch, duty=DUTY_SQUARE) * env(sec, 0.10)
    tick = s.held_noise(2500.0, 0.05, 21) * env(0.05, 0.012)
    return finish(s.mix(body, (tick, 0.4)))


def cast_red_t1() -> np.ndarray:
    sec = 0.28
    hiss = s.held_noise(s.glide(9000.0, 600.0, sec, curve=1.5), sec, 22) * env(sec, 0.06)
    zap = s.pulse(s.stepped(s.glide(620.0, 140.0, sec, curve=1.4), FRAME_HZ), duty=DUTY_SQUARE) * env(sec, 0.05)
    return finish(s.mix(hiss, (zap, 0.6)))


def cast_green_t1() -> np.ndarray:
    sec = 0.40
    root = scale_hz(0, 0)
    climb = [root * semitones(n) for n in (0, 4, 7, 12, 16, 19, 24)]
    pitch = hold_last(notes(climb, 2), sec)
    body = s.triangle(pitch) * env(sec, 0.16)
    glint = s.pulse(pitch * 2.0, duty=DUTY_THIN) * env(sec, 0.05)
    return finish(s.mix(body, (glint, 0.3)))


def cast_blue_t1() -> np.ndarray:
    sec = 0.38
    hz = scale_hz(0, 2)
    # A fast trill between the root and its fifth: brittle, icy.
    trill = notes([hz, hz * semitones(7)] * 12, 1)[: s.n_samples(sec)]
    pitch = hold_last(trill, sec)
    glass = s.pulse(pitch, duty=DUTY_THIN) * env(sec, 0.09)
    frost = s.held_noise(14000.0, sec, 23) * env(sec, 0.035)
    return finish(s.mix(glass, (frost, 0.25)))


def boss_telegraph() -> np.ndarray:
    sec = 1.25
    low = 55.0
    rise = s.stepped(s.glide(low, low * semitones(5), sec, curve=0.6), FRAME_HZ / 2.0)
    bass = s.triangle(rise)
    buzz = s.pulse(rise * 2.0, duty=DUTY_SQUARE) + s.pulse(rise * 2.0 * semitones(TRITONE_SEMITONES), duty=DUTY_REEDY)
    gate = s.pulse(s.glide(5.0, 19.0, sec), duty=DUTY_SQUARE) * 0.5 + 0.5
    rumble = s.held_noise(s.glide(300.0, 2400.0, sec), sec, 24)
    level = s.stepped(TELEGRAPH_FLOOR + (1.0 - TELEGRAPH_FLOOR) * s.swell(sec, 1.6), FRAME_HZ, VOLUME_LEVELS)
    body = s.mix((bass, 0.9), (buzz * gate, 0.35), (rumble * gate, 0.3)) * level
    return finish(body)


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
