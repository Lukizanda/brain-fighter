"""Shared constants for every synthesized cue: sample rate, the one musical
key, and the mix targets. A cue never picks its own key or loudness.

Plan: wiki/design/audio-sfx-synthesis.md
"""

SAMPLE_RATE = 48000

# The one key. Every pitched cue takes its notes from this major pentatonic
# scale so overlapping cues are consonant.
ROOT_HZ = 293.665  # D4
PENTATONIC_SEMITONES = (0, 2, 4, 7, 9)
SEMITONES_PER_OCTAVE = 12

# Hostile (boss) cues sit a tritone off the key: the friend-or-foe rule.
TRITONE_SEMITONES = 6

# Peak level of the loudest band, and how far below it the others sit.
PEAK_DBFS = -1.0
BAND_GAIN_DB = {
    "boss": 0.0,
    "gameplay": -3.0,
    "ui": -8.0,
    # Sustained loops sit under the one-shots that play over them.
    "loop": -6.0,
}

# Edge fades that stop a cue starting or ending on a click.
FADE_IN_SEC = 0.001
FADE_OUT_SEC = 0.008

# Moderation guard: nothing shorter than this is rendered.
MIN_DURATION_SEC = 0.12


def semitones(n: float) -> float:
    """Frequency ratio for an interval of n semitones."""
    return 2.0 ** (n / SEMITONES_PER_OCTAVE)


def scale_hz(step: int, octave: int = 0) -> float:
    """Frequency of a pentatonic scale step. Step 0 is the root; steps past
    the fifth note wrap into the next octave."""
    size = len(PENTATONIC_SEMITONES)
    wraps, index = divmod(step, size)
    semis = PENTATONIC_SEMITONES[index] + SEMITONES_PER_OCTAVE * (wraps + octave)
    return ROOT_HZ * semitones(semis)
