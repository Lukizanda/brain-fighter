"""Measurements that stand in for a listener when screening many variants.

Each one is a proxy for a judgement the user made by ear, and is only
trusted where it agrees with those judgements (see screen.py, which checks
them against the takes the user already rated before ranking anything).
None of this replaces listening; it narrows what the user has to listen to.

All functions take a mono float array at kit.SAMPLE_RATE.
"""

from __future__ import annotations

import numpy as np

from kit import SAMPLE_RATE

WINDOW_SEC = 0.02
EPS = 1e-12


def envelope_db(x: np.ndarray, window_sec: float = WINDOW_SEC) -> np.ndarray:
    """Loudness in consecutive windows, dB."""
    w = max(1, int(window_sec * SAMPLE_RATE))
    n = len(x) // w
    frames = x[: n * w].reshape(n, w)
    return 10.0 * np.log10(np.mean(frames ** 2, axis=1) + EPS)


def punch_db(x: np.ndarray) -> float:
    """How far the loudest moment stands above the sound 100-200 ms later.
    'No distinct boom' measured 1.8 dB; a clear hit is 9 dB or more."""
    env = envelope_db(x)
    peak = int(np.argmax(env))
    later = env[peak + 5: peak + 10]
    if len(later) == 0:
        return float(env[peak] - env[-1])
    return float(env[peak] - np.mean(later))


def pitch_clarity(x: np.ndarray, low_hz: float = 50.0, high_hz: float = 250.0,
                  start_sec: float = 0.0, window_sec: float = 0.06, windows: int = 3) -> float:
    """0..1: how strongly the opening repeats at a pitch between low_hz and
    high_hz (normalised autocorrelation peak), averaged over a few short
    windows from the loudest point. A tuned drum or a tone scores high;
    noise scores low. This is the 'sounds like a drum tom' proxy."""
    env = envelope_db(x)
    at = int(np.argmax(env)) * int(WINDOW_SEC * SAMPLE_RATE) + int(start_sec * SAMPLE_RATE)
    w = int(window_sec * SAMPLE_RATE)
    lo, hi = int(SAMPLE_RATE / high_hz), int(SAMPLE_RATE / low_hz)
    scores = []
    for k in range(windows):
        seg = x[at + k * w // 2: at + k * w // 2 + w]
        if len(seg) < hi + 1:
            break
        seg = seg - np.mean(seg)
        ac = np.correlate(seg, seg, "full")[len(seg) - 1:]
        if ac[0] <= EPS:
            continue
        # Normalise each lag by how many samples overlap.
        ac = ac / ac[0] * len(seg) / (len(seg) - np.arange(len(seg)))
        scores.append(float(np.max(ac[lo:hi])))
    return float(np.mean(scores)) if scores else 0.0


def spectrum(x: np.ndarray):
    power = np.abs(np.fft.rfft(x)) ** 2
    freqs = np.fft.rfftfreq(len(x), 1.0 / SAMPLE_RATE)
    return freqs, power


def band_share(x: np.ndarray, low_hz: float, high_hz: float) -> float:
    f, p = spectrum(x)
    return float(p[(f >= low_hz) & (f < high_hz)].sum() / (p.sum() + EPS))


def centroid_hz(x: np.ndarray) -> float:
    f, p = spectrum(x)
    return float((f * p).sum() / (p.sum() + EPS))


def ring_sec(x: np.ndarray, below_db: float = 30.0) -> float:
    """Time from the loudest window until the sound stays `below_db` under it."""
    env = envelope_db(x)
    peak = int(np.argmax(env))
    quiet = np.nonzero(env[peak:] > env[peak] - below_db)[0]
    return float((quiet[-1] + 1) * WINDOW_SEC) if len(quiet) else 0.0


def describe(x: np.ndarray) -> dict:
    return {
        "punch_db": round(punch_db(x), 1),
        "pitch_clarity": round(pitch_clarity(x), 2),
        "centroid_hz": round(centroid_hz(x)),
        "above_4k": round(band_share(x, 4000.0, 24000.0), 3),
        "phone_band": round(band_share(x, 150.0, 2000.0), 3),
        "ring_sec": round(ring_sec(x), 2),
    }


STRUCTURE_WINDOW_SEC = 0.01
HIT_SEARCH_SEC = 0.12        # the hit is the loudest point in this opening
BOOM_SEARCH_SEC = (0.12, 0.5)


def structure(x: np.ndarray) -> dict:
    """For a 'tch-ba-boom': is there a bright spark first, are the hit and
    the boom two events with a dip between them, and how big is the boom.

    spark_hz: brightness of the first 30 ms (a 'tch' is bright).
    two_events_db: how far the quieter of hit and boom stands above the dip
      between them (0 means one smooth event).
    boom_vs_hit_db: the boom's peak relative to the hit's.
    late_level_db: average level 0.3-0.8 s after the start, relative to
      the loudest point (a big explosion is still going).
    """
    env = envelope_db(x, STRUCTURE_WINDOW_SEC)
    per = int(1.0 / STRUCTURE_WINDOW_SEC)
    head = x[: int(0.03 * SAMPLE_RATE)]
    hit_end = int(HIT_SEARCH_SEC * per)
    hit = int(np.argmax(env[:hit_end]))
    b0, b1 = int(BOOM_SEARCH_SEC[0] * per), int(BOOM_SEARCH_SEC[1] * per)
    boom = b0 + int(np.argmax(env[b0:b1])) if len(env) > b1 else hit
    dip = float(np.min(env[hit:boom + 1])) if boom > hit else float(env[hit])
    late = env[int(0.3 * per): int(0.8 * per)]
    return {
        "spark_hz": round(centroid_hz(head)),
        "two_events_db": round(float(min(env[hit], env[boom]) - dip), 1),
        "boom_vs_hit_db": round(float(env[boom] - env[hit]), 1),
        "late_level_db": round(float(np.mean(late) - np.max(env)), 1) if len(late) else -99.0,
    }
