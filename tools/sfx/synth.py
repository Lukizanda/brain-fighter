"""Synthesis primitives. Everything returns a float64 numpy array in -1..1
at kit.SAMPLE_RATE. Cues are built only from these, which is what keeps the
whole set sounding like one instrument.
"""

from __future__ import annotations

import numpy as np
from scipy import signal

from kit import SAMPLE_RATE

TAU = 2.0 * np.pi


def n_samples(seconds: float) -> int:
    return max(1, int(round(seconds * SAMPLE_RATE)))


def silence(seconds: float) -> np.ndarray:
    return np.zeros(n_samples(seconds))


def times(seconds: float) -> np.ndarray:
    return np.arange(n_samples(seconds)) / SAMPLE_RATE


# ---------------------------------------------------------------------------
# Control curves
# ---------------------------------------------------------------------------

def glide(start: float, end: float, seconds: float, curve: float = 1.0) -> np.ndarray:
    """Exponential move from start to end (both > 0). curve > 1 gets there
    sooner, curve < 1 later."""
    x = np.linspace(0.0, 1.0, n_samples(seconds)) ** (1.0 / curve)
    return start * (end / start) ** x


def ramp(start: float, end: float, seconds: float) -> np.ndarray:
    return np.linspace(start, end, n_samples(seconds))


def decay(seconds: float, half_life: float, attack: float = 0.002) -> np.ndarray:
    """Percussive envelope: short linear attack, exponential fall."""
    t = times(seconds)
    env = 0.5 ** (t / half_life)
    rise = n_samples(attack)
    env[:rise] *= np.linspace(0.0, 1.0, rise)
    return env


def swell(seconds: float, power: float = 2.0) -> np.ndarray:
    """Rising envelope 0 -> 1, for telegraphs."""
    return np.linspace(0.0, 1.0, n_samples(seconds)) ** power


def stepped(curve: np.ndarray, step_hz: float, levels: int = 0) -> np.ndarray:
    """Hold a control curve in steps of 1/step_hz seconds, and optionally
    snap it to a number of levels. This is the chiptune 'frame' feel."""
    hold = max(1, int(SAMPLE_RATE / step_hz))
    index = (np.arange(len(curve)) // hold) * hold
    out = curve[index]
    if levels > 0:
        out = np.round(out * levels) / levels
    return out


# ---------------------------------------------------------------------------
# Oscillators. `freq` is a number or a per-sample array.
# ---------------------------------------------------------------------------

def _phase(freq, seconds: float | None) -> np.ndarray:
    if np.isscalar(freq):
        freq = np.full(n_samples(seconds), float(freq))
    return np.cumsum(freq) / SAMPLE_RATE


def sine(freq, seconds: float | None = None) -> np.ndarray:
    return np.sin(TAU * _phase(freq, seconds))


def triangle(freq, seconds: float | None = None) -> np.ndarray:
    p = _phase(freq, seconds) % 1.0
    return 4.0 * np.abs(p - 0.5) - 1.0


def saw(freq, seconds: float | None = None) -> np.ndarray:
    p = _phase(freq, seconds) % 1.0
    return 2.0 * p - 1.0


def pulse(freq, seconds: float | None = None, duty: float = 0.5) -> np.ndarray:
    p = _phase(freq, seconds) % 1.0
    return np.where(p < duty, 1.0, -1.0)


def fm(carrier, ratio: float, index, seconds: float | None = None) -> np.ndarray:
    """Two-operator FM. `index` may be an array, to let the tone go from
    bright to pure as it decays."""
    cp = _phase(carrier, seconds)
    return np.sin(TAU * cp + index * np.sin(TAU * cp * ratio))


def noise(seconds: float, seed: int) -> np.ndarray:
    return np.random.default_rng(seed).uniform(-1.0, 1.0, n_samples(seconds))


def held_noise(rate_hz, seconds: float, seed: int) -> np.ndarray:
    """Sample-and-hold noise: a new random value `rate_hz` times a second.
    Low rates rumble, high rates hiss. The chiptune noise channel."""
    if np.isscalar(rate_hz):
        rate_hz = np.full(n_samples(seconds), float(rate_hz))
    ticks = np.floor(np.cumsum(rate_hz) / SAMPLE_RATE).astype(int)
    values = np.random.default_rng(seed).choice([-1.0, 1.0], size=ticks[-1] + 2)
    return values[ticks]


# ---------------------------------------------------------------------------
# Filters and shaping
# ---------------------------------------------------------------------------

def lowpass(x: np.ndarray, hz: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(signal.butter(order, hz, "lowpass", fs=SAMPLE_RATE, output="sos"), x)


def highpass(x: np.ndarray, hz: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(signal.butter(order, hz, "highpass", fs=SAMPLE_RATE, output="sos"), x)


def bandpass(x: np.ndarray, low_hz: float, high_hz: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, [low_hz, high_hz], "bandpass", fs=SAMPLE_RATE, output="sos")
    return signal.sosfilt(sos, x)


def swept_bandpass(x: np.ndarray, centre_hz: np.ndarray, q: float = 4.0, blocks: int = 48) -> np.ndarray:
    """Resonant band-pass whose centre follows a curve, done in short
    cross-faded blocks. Gives the wet 'squelch' of the Brain voice."""
    out = np.zeros(len(x))
    edges = np.linspace(0, len(x), blocks + 1).astype(int)
    for a, b in zip(edges[:-1], edges[1:]):
        centre = float(np.mean(centre_hz[a:b]))
        bcoef, acoef = signal.iirpeak(centre, q, fs=SAMPLE_RATE)
        lo = max(0, a - (b - a))
        seg = signal.lfilter(bcoef, acoef, x[lo:b])
        out[a:b] = seg[a - lo:]
    return out


def drive(x: np.ndarray, amount: float) -> np.ndarray:
    """Soft saturation. amount 1 is nearly clean, 6 is gritty."""
    return np.tanh(x * amount) / np.tanh(amount)


def crush(x: np.ndarray, bits: int) -> np.ndarray:
    levels = 2 ** (bits - 1)
    return np.round(x * levels) / levels


def echo(x: np.ndarray, delay_sec: float, feedback: float, repeats: int, tail: bool = True) -> np.ndarray:
    d = n_samples(delay_sec)
    out = np.concatenate([x, np.zeros(d * repeats if tail else 0)])
    for i in range(1, repeats + 1):
        start = d * i
        end = min(len(out), start + len(x))
        out[start:end] += x[: end - start] * feedback ** i
    return out


def room(x: np.ndarray, seconds: float = 0.35, mix: float = 0.18, seed: int = 7) -> np.ndarray:
    """A small, bright room: the dry signal convolved with decaying noise.
    One shared room is part of the kit's sameness."""
    tail = noise(seconds, seed) * (0.5 ** (times(seconds) / (seconds / 6.0)))
    tail = highpass(lowpass(tail, 7000.0), 300.0)
    wet = signal.fftconvolve(x, tail)
    wet /= max(1e-9, np.max(np.abs(wet)))
    out = np.concatenate([x, np.zeros(len(wet) - len(x))])
    return out * (1.0 - mix) + wet * mix * np.max(np.abs(x))


# ---------------------------------------------------------------------------
# Arranging
# ---------------------------------------------------------------------------

def mix(*layers: tuple[np.ndarray, float] | np.ndarray) -> np.ndarray:
    """Sum layers of different lengths. A layer is an array, or
    (array, gain), or (array, gain, start_seconds)."""
    placed = []
    for layer in layers:
        if isinstance(layer, np.ndarray):
            layer = (layer, 1.0, 0.0)
        elif len(layer) == 2:
            layer = (layer[0], layer[1], 0.0)
        placed.append(layer)
    length = max(n_samples(start) - 1 + len(x) for x, _, start in placed)
    out = np.zeros(length)
    for x, gain, start in placed:
        at = n_samples(start) - 1 if start > 0 else 0
        out[at:at + len(x)] += x * gain
    return out


def sequence(parts: list[np.ndarray], gap_sec: float) -> np.ndarray:
    gap = silence(gap_sec)
    out = []
    for i, part in enumerate(parts):
        if i:
            out.append(gap)
        out.append(part)
    return np.concatenate(out)


# ---------------------------------------------------------------------------
# FM operators (the 16-bit console voice). An operator is a sine whose phase
# is pushed around by another operator's output, in radians.
# ---------------------------------------------------------------------------

def op(freq, env: np.ndarray, mod=0.0) -> np.ndarray:
    """One FM operator: env * sin(phase + mod). `freq` is a number or a
    per-sample array; its length follows `env`."""
    if np.isscalar(freq):
        freq = np.full(len(env), float(freq))
    return env * np.sin(TAU * np.cumsum(freq) / SAMPLE_RATE + mod)


def op_feedback(freq, env: np.ndarray, feedback: float) -> np.ndarray:
    """An operator that modulates itself. Low feedback turns the sine into
    a saw-like buzz; high feedback breaks it up into pitched noise."""
    if np.isscalar(freq):
        freq = np.full(len(env), float(freq))
    phase = TAU * np.cumsum(freq) / SAMPLE_RATE
    out = np.zeros(len(env))
    y1 = y2 = 0.0
    for i in range(len(env)):
        y = env[i] * np.sin(phase[i] + feedback * 0.5 * (y1 + y2))
        out[i] = y
        y2, y1 = y1, y
    return out
