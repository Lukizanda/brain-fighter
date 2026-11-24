"""A small model of the 16-bit console sound hardware: a YM2612-style
four-operator FM channel, an SN76489-style PSG (squares and noise), and an
8-bit DAC channel for samples.

This is not a cycle-accurate emulator. It keeps the parts that give the
hardware its character:
  * the chip's own envelope generator (rates 0-31, sustain level, the
    exponential attack), so patches written in chip terms sound right;
  * the eight operator algorithms and operator-1 self-feedback;
  * rendering at the chip's native rate with no oversampling, so bright
    patches alias the way the real thing does;
  * 9-bit output per FM channel, the analogue output filter, the PSG's
    2 dB volume steps and its shift-register noise;
  * a driver that updates pitch and volume once per 60 Hz frame.

Patch parameters follow the chip's register ranges, so a patch written here
can be checked against any YM2612 patch reference.

Numbers marked VERIFY come from memory of public emulator sources and are
being checked against documentation.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from scipy import signal

from kit import SAMPLE_RATE

TAU = 2.0 * np.pi

# --- Clocks -----------------------------------------------------------------

MASTER_CLOCK_HZ = 53_693_175          # NTSC
CHIP_RATE = MASTER_CLOCK_HZ / 7 / 144  # ~53,267 Hz FM output rate
EG_DIVIDER = 3                         # the envelope steps every 3 samples
PSG_CLOCK_HZ = MASTER_CLOCK_HZ / 15    # ~3.58 MHz
FRAME_HZ = 60.0                        # sound driver update rate (NTSC vblank)

# --- Operator ---------------------------------------------------------------

ATTEN_MAX = 1023                       # 10-bit attenuation
DB_PER_ATTEN_STEP = 96.0 / 1024.0      # 0.09375 dB
TL_STEP = 8                            # TL is 0.75 dB per step
SL_STEP = 32                           # SL is 3 dB per step
# Full-scale modulator output moves the carrier's phase by this much.
# VERIFY: 14-bit operator output into a 10-bit phase, halved.
MOD_RADIANS_FULL = 8.0 * np.pi
# Operator-1 feedback, levels 0-7: 0, pi/16, pi/8 ... 4pi.
FEEDBACK_RADIANS = (0.0,) + tuple(np.pi / 16.0 * 2 ** i for i in range(7))
MUL_HALF = 0.5                         # MUL = 0 means x0.5

# Envelope rate tables (YM2612 / OPN family). VERIFY against Nuked-OPN2.
_EG_SHIFT = [11] * 4 + [11 - (r - 4) // 4 for r in range(4, 48)] + [0] * 16
_EG_INC = [
    (0, 1, 0, 1, 0, 1, 0, 1),
    (0, 1, 0, 1, 1, 1, 0, 1),
    (0, 1, 1, 1, 0, 1, 1, 1),
    (0, 1, 1, 1, 1, 1, 1, 1),
]


def _eg_increments(rate: int) -> tuple[int, ...]:
    if rate < 48:
        return _EG_INC[rate & 3]
    scale = 1 << ((rate - 48) // 4)
    if rate >= 60:
        return (8,) * 8
    return tuple(v * scale for v in (
        (1, 1, 1, 1, 1, 1, 1, 1),
        (1, 1, 1, 2, 1, 1, 1, 2),
        (1, 2, 1, 2, 1, 2, 1, 2),
        (1, 2, 2, 2, 1, 2, 2, 2),
    )[rate & 3])


# Which operators feed which, for the eight algorithms. Operators are 0-3
# (the chip's 1-4). `mods[i]` lists the operators that modulate operator i;
# `carriers` are the ones that reach the output.
ALGORITHMS = {
    0: ({1: [0], 2: [1], 3: [2]}, [3]),
    1: ({2: [0, 1], 3: [2]}, [3]),
    2: ({2: [1], 3: [0, 2]}, [3]),
    3: ({1: [0], 3: [1, 2]}, [3]),
    4: ({1: [0], 3: [2]}, [1, 3]),
    5: ({1: [0], 2: [0], 3: [0]}, [1, 2, 3]),
    6: ({1: [0]}, [1, 2, 3]),
    7: ({}, [0, 1, 2, 3]),
}


@dataclass
class Op:
    """One operator, in register terms."""
    mul: int = 1        # 0-15 (0 = x0.5)
    dt: int = 0         # -3..3 detune
    tl: int = 0         # 0-127 total level, 0.75 dB per step
    ar: int = 31        # 0-31 attack rate
    d1r: int = 0        # 0-31 first decay rate
    sl: int = 0         # 0-15 sustain level, 3 dB per step
    d2r: int = 0        # 0-31 second decay rate
    rr: int = 15        # 0-15 release rate
    ks: int = 0         # 0-3 key scaling
    am: bool = False    # follows the LFO tremolo


@dataclass
class Patch:
    algorithm: int
    feedback: int
    ops: list[Op] = field(default_factory=list)
    lfo_hz: float = 0.0     # 0 = LFO off
    pms_cents: float = 0.0  # vibrato depth
    ams_db: float = 0.0     # tremolo depth on ops with am=True


# LFO settings the chip offers, for patches to pick from (plutiedev.com
# YM2612 register reference).
LFO_HZ = (3.82, 5.33, 5.77, 6.11, 6.60, 9.23, 46.11, 69.22)
PMS_CENTS = (0.0, 3.4, 6.7, 10.0, 14.0, 20.0, 40.0, 80.0)
AMS_DB = (0.0, 1.4, 5.9, 11.8)


def _keycode(hz: float) -> int:
    """Approximate key code (block * 4 + top fnum bits), 0-31."""
    return int(np.clip(round(4.0 * np.log2(max(hz, 1.0) / 32.7)), 0, 31))


def _rate(r: int, kc: int, ks: int) -> int:
    if r == 0:
        return 0
    return min(63, 2 * r + (kc >> (3 - ks)))


def envelope(op: Op, n: int, key_off: int, kc: int) -> np.ndarray:
    """Attenuation per sample (0 = loudest, 1023 = silent), stepped by the
    chip's envelope counter."""
    steps = n // EG_DIVIDER + 1
    off_step = key_off // EG_DIVIDER
    att = np.empty(steps)
    level = ATTEN_MAX
    phase = "attack"
    sustain = op.sl * SL_STEP if op.sl < 15 else ATTEN_MAX
    rates = {
        "attack": _rate(op.ar, kc, op.ks),
        "decay": _rate(op.d1r, kc, op.ks),
        "sustain": _rate(op.d2r, kc, op.ks),
        # RR is 4 bits; the chip scales it to the 6-bit rate as 4 * RR + 2.
        "release": min(63, 4 * op.rr + 2 + (kc >> (3 - op.ks))),
    }
    for counter in range(steps):
        if counter == off_step and phase != "release":
            phase = "release"
        rate = rates[phase]
        if phase == "attack" and rate >= 62:
            level = 0
        elif rate > 0:
            shift = _EG_SHIFT[rate]
            if counter % (1 << shift) == 0:
                inc = _eg_increments(rate)[(counter >> shift) & 7]
                if phase == "attack":
                    level += ((-level - 1) * inc) >> 4
                else:
                    level += inc
        if phase == "attack" and level <= 0:
            level = 0
            phase = "decay"
        if phase == "decay" and level >= sustain:
            phase = "sustain"
        level = min(level, ATTEN_MAX)
        att[counter] = level
    return np.repeat(att, EG_DIVIDER)[:n]


def _detune_hz(dt: int, kc: int) -> float:
    """Small fixed offset that grows with pitch, like the chip's DT table.
    Approximate: the chip's table is per key code."""
    if dt == 0:
        return 0.0
    max_units = (0.0, 8.0, 16.0, 22.0)[min(abs(dt), 3)]
    units = max_units * kc / 31.0
    return float(np.sign(dt)) * units * CHIP_RATE / (1 << 20)


def chip_samples(seconds: float) -> int:
    return max(1, int(round(seconds * CHIP_RATE)))


def frames(pitches_hz, seconds: float | None = None) -> np.ndarray:
    """A per-sample pitch curve from one value per 60 Hz driver frame. The
    last value holds until `seconds`."""
    hold = int(round(CHIP_RATE / FRAME_HZ))
    curve = np.repeat(np.asarray(pitches_hz, dtype=float), hold)
    if seconds is not None:
        n = chip_samples(seconds)
        curve = np.concatenate([curve, np.full(max(0, n - len(curve)), curve[-1])])[:n]
    return curve


def fm_note(patch: Patch, pitch_hz, seconds: float, key_off_sec: float, gain_db: float = 0.0,
            tl_offset: dict | None = None) -> np.ndarray:
    """Render one FM channel at CHIP_RATE. `pitch_hz` is a number or a
    per-sample curve (see `frames`). `tl_offset` maps an operator index to
    extra TL steps per sample: how a driver opens or closes a modulator
    frame by frame to make a sound brighten or dull."""
    n = chip_samples(seconds)
    if np.isscalar(pitch_hz):
        pitch = np.full(n, float(pitch_hz))
    else:
        pitch = np.asarray(pitch_hz, dtype=float)
        pitch = np.concatenate([pitch, np.full(max(0, n - len(pitch)), pitch[-1])])[:n]
    t = np.arange(n) / CHIP_RATE
    if patch.lfo_hz > 0 and patch.pms_cents > 0:
        pitch = pitch * 2.0 ** (patch.pms_cents / 1200.0 * np.sin(TAU * patch.lfo_hz * t))
    tremolo_db = 0.0
    if patch.lfo_hz > 0 and patch.ams_db > 0:
        tremolo_db = patch.ams_db * 0.5 * (1.0 - np.cos(TAU * patch.lfo_hz * t))

    kc = _keycode(float(np.median(pitch)))
    key_off = chip_samples(key_off_sec)
    amps, phases = [], []
    for index, op in enumerate(patch.ops):
        att = envelope(op, n, key_off, kc) + op.tl * TL_STEP
        if tl_offset and index in tl_offset:
            att = att + _fit(tl_offset[index], n) * TL_STEP
        db = np.minimum(att, ATTEN_MAX) * DB_PER_ATTEN_STEP
        if op.am:
            db = db + tremolo_db
        amps.append(10.0 ** (-db / 20.0))
        mul = MUL_HALF if op.mul == 0 else float(op.mul)
        freq = pitch * mul + _detune_hz(op.dt, kc)
        phases.append(TAU * np.cumsum(freq) / CHIP_RATE)

    mods, carriers = ALGORITHMS[patch.algorithm]
    out = [None] * 4
    # Operator 1 with self-feedback: the one serial loop.
    fb = FEEDBACK_RADIANS[patch.feedback]
    y = np.zeros(n)
    y1 = y2 = 0.0
    a0, p0 = amps[0], phases[0]
    for i in range(n):
        v = a0[i] * np.sin(p0[i] + fb * 0.5 * (y1 + y2))
        y[i] = v
        y2, y1 = y1, v
    out[0] = y
    for i in (1, 2, 3):
        mod = sum((out[m] for m in mods.get(i, [])), np.zeros(n))
        out[i] = amps[i] * np.sin(phases[i] + MOD_RADIANS_FULL * 0.5 * mod)
    channel = np.clip(sum(out[c] for c in carriers), -1.0, 1.0)
    return dac9(channel) * 10.0 ** (gain_db / 20.0)


# --- Output stage -----------------------------------------------------------

DAC_BITS = 9
# Crossover offset of the discrete chip in early consoles: values near zero
# are pushed apart, which roughens quiet sounds. VERIFY the size.
LADDER_OFFSET_STEPS = 0.5


def dac9(x: np.ndarray) -> np.ndarray:
    levels = 2 ** (DAC_BITS - 1)
    q = np.round(x * levels)
    q = q + np.where(q >= 0, LADDER_OFFSET_STEPS, -LADDER_OFFSET_STEPS)
    return q / levels


# Analogue output low-pass. First order on early consoles (forum claim, not
# measured); the cutoff is a by-ear choice until a measured figure is found.
OUTPUT_LOWPASS_HZ = 3800.0
OUTPUT_LOWPASS_ORDER = 1


def to_output(x: np.ndarray, lowpass_hz: float = OUTPUT_LOWPASS_HZ) -> np.ndarray:
    """Chip-rate mix -> analogue filter -> 48 kHz."""
    sos = signal.butter(OUTPUT_LOWPASS_ORDER, lowpass_hz, "lowpass", fs=CHIP_RATE, output="sos")
    x = signal.sosfilt(sos, x)
    return signal.resample(x, int(round(len(x) * SAMPLE_RATE / CHIP_RATE)))


# --- PSG --------------------------------------------------------------------

PSG_DB_STEP = 2.0
PSG_NOISE_DIVIDERS = (512, 1024, 2048)  # the three fixed noise clocks
PSG_LFSR_TAPS = 0x0009                  # white noise feedback taps
PSG_LFSR_BITS = 16


def psg_volume(steps) -> np.ndarray:
    """PSG attenuation in 2 dB steps (0 loudest, 15 off), one per frame."""
    steps = np.asarray(steps, dtype=float)
    amp = np.where(steps >= 15, 0.0, 10.0 ** (-steps * PSG_DB_STEP / 20.0))
    return frames(amp)


def _fit(curve, n: int) -> np.ndarray:
    if np.isscalar(curve):
        return np.full(n, float(curve))
    c = np.asarray(curve, dtype=float)
    return np.concatenate([c, np.full(max(0, n - len(c)), c[-1])])[:n]


def psg_square(pitch_hz, volume, seconds: float) -> np.ndarray:
    n = chip_samples(seconds)
    pitch = _fit(pitch_hz, n)
    # The PSG can only make pitches from a 10-bit divider.
    divider = np.clip(np.round(PSG_CLOCK_HZ / (32.0 * pitch)), 1, 1023)
    real = PSG_CLOCK_HZ / (32.0 * divider)
    phase = np.cumsum(real) / CHIP_RATE
    return np.where(phase % 1.0 < 0.5, 1.0, -1.0) * _fit(volume, n)


def psg_noise(volume, seconds: float, divider: int = 512, periodic: bool = False,
              shift_hz=None, seed: int = 1) -> np.ndarray:
    """Shift-register noise. `divider` picks one of the fixed clocks;
    `shift_hz` (a curve) follows a tone channel instead, which is how
    drivers sweep noise. Periodic mode gives a buzzy pitched tone."""
    n = chip_samples(seconds)
    rate = _fit(shift_hz if shift_hz is not None else PSG_CLOCK_HZ / divider, n)
    ticks = np.floor(np.cumsum(rate) / CHIP_RATE).astype(int)
    count = int(ticks[-1]) + 2
    reg = (1 << (PSG_LFSR_BITS - 1)) ^ (seed & 0x7FFF)
    bits = np.empty(count)
    for i in range(count):
        bits[i] = reg & 1
        if periodic:
            fb = reg & 1
        else:
            fb = bin(reg & PSG_LFSR_TAPS).count("1") & 1
        reg = (reg >> 1) | (fb << (PSG_LFSR_BITS - 1))
    return (bits[ticks] * 2.0 - 1.0) * _fit(volume, n)


# --- DAC (sample playback) --------------------------------------------------

DAC_SAMPLE_BITS = 8


def dac_sample(x: np.ndarray, source_rate: float, play_rate: float) -> np.ndarray:
    """Play a sample the way a driver feeds the DAC: decimated to
    `play_rate`, 8-bit, held between writes (no smoothing). `x` is at
    `source_rate`."""
    held_count = max(1, int(round(len(x) * play_rate / source_rate)))
    coarse = signal.resample(x, held_count)
    coarse = np.round(np.clip(coarse, -1, 1) * 127) / 127
    n = chip_samples(len(x) / source_rate)
    index = np.minimum((np.arange(n) * play_rate / CHIP_RATE).astype(int), held_count - 1)
    return coarse[index]


def place(n_total: int, *layers) -> np.ndarray:
    """Mix chip-rate layers. Each layer is (array, start_sec) or an array."""
    out = np.zeros(n_total)
    for layer in layers:
        x, start = (layer, 0.0) if isinstance(layer, np.ndarray) else layer
        at = chip_samples(start) if start > 0 else 0
        end = min(n_total, at + len(x))
        out[at:end] += x[: end - at]
    return out
