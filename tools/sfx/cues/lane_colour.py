"""Colour lab: can the player hear a spell's colour?

User, 2026-11-28, after the first in-game listen: "there is no real audio
differentiated between the red, blue, and green spells. The player can't tell
the difference, and use that as additional information in the game?"

Measured before building anything: the nine shipped casts differ MORE inside a
colour than across colours (spectral-shape distance 0.87 within, 0.77 across).
Each sound was designed around its own spell; nothing is shared per colour.

This lab keeps every spell's own sound (several are the user's picks) and adds
what a colour shares, in two strengths:

  now   the nine casts as shipped, for comparison
  mat   material: every cast of a colour opens with the same short signature
        (a "stamp") and is tilted toward that colour's register
          red    one strike: a spark, crackle, a low whump       low
          blue   two quick glass ticks and a cold hiss           high
          green  a hollow wooden knock-knock and a leaf rustle   middle
        The stamps differ in rhythm (one, two fast, two slow) as well as in
        tone, because rhythm survives a phone speaker.
  note  the same, plus one short pitched tone per colour (red low, blue high,
        green middle). Clearest, but nearer the "reward chime" and style-clash
        problems the user raised earlier.

Two alternatives, built ahead of the listen for the objections the director
expected:

  light the signature in front and NO register tilt. The spell's own sound is
        held down for the first 0.14 s so the signature is heard, then is
        exactly as shipped. For "you changed a sound I picked".
  woven no signature in front. The colour's material is scattered through the
        whole cast instead, following the spell's own loudness (fire crackle
        and a low rumble; glass tinkles and hiss; wood ticks and rustle), with
        the register tilt. For "the signature sounds stuck on the front".

    python tools/sfx/render.py --lane colour
    python tools/sfx/lint.py --dir build/sfx/lanes/colour
    python tools/sfx/audition.py --dir build/sfx/lanes/colour --out build/sfx/lanes/colour/audition.html
"""

from __future__ import annotations

import importlib
import json
from pathlib import Path

import numpy as np

import synth as s
from kit import SAMPLE_RATE, scale_hz, semitones

LANE = {"id": "colour", "label": "Colour lab: telling red, blue and green apart"}

TAKES = [
    {"id": "now", "label": "As shipped"},
    {"id": "mat", "label": "Material signature"},
    {"id": "note", "label": "Material + a note"},
    {"id": "light", "label": "Signature only, spell untouched"},
    {"id": "woven", "label": "Woven through, no front signature"},
]

# cue id -> (colour, spell, upload name of the shipped cast)
CASTS = {
    "cast_red_t1": ("red", "Firebolt", "BF_Firebolt_Cast"),
    "cast_red_t2": ("red", "Fireball", "BF_Fireball_Cast"),
    "cast_red_t3": ("red", "Inferno", "BF_Inferno_Cast"),
    "cast_blue_t1": ("blue", "Frost Nip", "BF_FrostNip_Cast"),
    "cast_blue_t2": ("blue", "Shield", "BF_Shield_Cast"),
    "cast_blue_t3": ("blue", "Stasis", "BF_Stasis_Cast"),
    "cast_green_t1": ("green", "Mend", "BF_Mend_Cast"),
    "cast_green_t2": ("green", "Stone Wall", "BF_StoneWall_Cast"),
    "cast_green_t3": ("green", "Sanctuary", "BF_Sanctuary_Cast"),
}

_CHOSEN_PATH = Path(__file__).resolve().parents[1] / "chosen.json"


def _shipped_builders() -> dict:
    """The builder behind each shipped cast, found through chosen.json."""
    by_name = {e["name"]: e for e in json.loads(_CHOSEN_PATH.read_text(encoding="utf-8"))["sounds"]}
    out = {}
    for cue_id, (_, _, name) in CASTS.items():
        entry = by_name[name]
        if entry.get("lane"):
            module = importlib.import_module(f"cues.lane_{entry['lane']}")
            out[cue_id] = module.CUES[entry["kit"]][entry["cue"]]
        else:
            module = importlib.import_module(f"cues.pilot_{entry['kit']}")
            out[cue_id] = module.CUES[entry["cue"]]
    return out


SHIPPED = _shipped_builders()


# ── helpers ────────────────────────────────────────────────────────────

def norm(x: np.ndarray) -> np.ndarray:
    peak = np.max(np.abs(x))
    return x / peak if peak > 0 else x


def place(total_sec: float, *layers) -> np.ndarray:
    """(samples, gain, start_sec) layers summed into one buffer."""
    out = np.zeros(s.n_samples(total_sec))
    for x, gain, start in layers:
        i = s.n_samples(start)
        n = min(len(x), len(out) - i)
        if n > 0:
            out[i:i + n] += x[:n] * gain
    return out


def burst(seconds: float, band, half_life: float, seed: int, attack: float = 0.001) -> np.ndarray:
    """A short band of noise that dies away: the grain every stamp is made of."""
    return s.bandpass(s.noise(seconds, seed), band[0], band[1]) * s.decay(seconds, half_life, attack)


# ── the three stamps ───────────────────────────────────────────────────
# Each is about 0.14 s and sits at the very start of the cast.

STAMP_SEC = 0.16

RED_SPARK_BAND = (900.0, 3200.0)
RED_WHUMP_HZ = (150.0, 70.0)
BLUE_TICK_BAND = (5200.0, 9500.0)
BLUE_HISS_BAND = (3500.0, 9000.0)
BLUE_TICK_GAP_SEC = 0.045
GREEN_KNOCK_BAND = (320.0, 950.0)
GREEN_LEAF_BAND = (1800.0, 4200.0)
GREEN_KNOCK_GAP_SEC = 0.085


def stamp_red() -> np.ndarray:
    """One strike. A spark, three crackle pops after it, and a low whump."""
    spark = burst(0.05, RED_SPARK_BAND, 0.008, seed=4101)
    pops = [(burst(0.012, (1500.0, 4500.0), 0.002, seed=4110 + i), g, t)
            for i, (t, g) in enumerate([(0.030, 0.55), (0.052, 0.4), (0.081, 0.3)])]
    whump = s.sine(s.glide(RED_WHUMP_HZ[0], RED_WHUMP_HZ[1], 0.12)) * s.decay(0.12, 0.03, 0.004)
    return norm(place(STAMP_SEC, (spark, 1.0, 0.0), *pops, (whump, 0.9, 0.0)))


def stamp_blue() -> np.ndarray:
    """Two quick glass ticks, close together, and a breath of cold hiss."""
    tick = burst(0.03, BLUE_TICK_BAND, 0.004, seed=4201, attack=0.0005)
    tick2 = burst(0.03, BLUE_TICK_BAND, 0.004, seed=4202, attack=0.0005)
    hiss = burst(0.14, BLUE_HISS_BAND, 0.035, seed=4203, attack=0.01)
    return norm(place(STAMP_SEC, (tick, 1.0, 0.0), (tick2, 0.8, BLUE_TICK_GAP_SEC), (hiss, 0.35, 0.0)))


def stamp_green() -> np.ndarray:
    """A hollow wooden knock-knock, slower than the ice ticks, and a rustle."""
    knock = burst(0.07, GREEN_KNOCK_BAND, 0.012, seed=4301)
    knock2 = burst(0.07, GREEN_KNOCK_BAND, 0.012, seed=4302)
    rustle = burst(0.15, GREEN_LEAF_BAND, 0.05, seed=4303, attack=0.02)
    return norm(place(STAMP_SEC, (knock, 1.0, 0.0), (knock2, 0.7, GREEN_KNOCK_GAP_SEC), (rustle, 0.22, 0.0)))


STAMPS = {"red": stamp_red, "blue": stamp_blue, "green": stamp_green}


# ── register tilt ──────────────────────────────────────────────────────
# The spell's own sound split in three bands and re-weighted, so the body
# leans toward its colour's register without losing what the spell is.

SPLIT_LOW_HZ = 450.0
SPLIT_HIGH_HZ = 2400.0

#            low   mid   high
TILT = {
    "red":   (1.5, 1.0, 0.35),
    "blue":  (0.3, 0.8, 1.7),
    "green": (0.55, 1.5, 0.6),
}


def tilt(x: np.ndarray, colour: str, amount: float = 1.0) -> np.ndarray:
    """`amount` 0 leaves the sound as it is; 1 is the full tilt."""
    low = s.lowpass(x, SPLIT_LOW_HZ)
    high = s.highpass(x, SPLIT_HIGH_HZ)
    mid = x - low - high
    wl, wm, wh = (1.0 + (w - 1.0) * amount for w in TILT[colour])
    return low * wl + mid * wm + high * wh


# ── woven texture (take "woven") ───────────────────────────────────────
# The colour's material as grains scattered through the whole cast. How
# loud each grain is follows the spell's own loudness at that moment, so
# the texture swells and dies with the spell instead of sitting on top.

ENVELOPE_SMOOTH_SEC = 0.02

# grains a second, band, grain length, half-life, and a bed of filtered
# noise under them: (band, gain).
WEAVE = {
    "red":   {"per_sec": 38.0, "band": (1500.0, 4500.0), "length": 0.012, "half_life": 0.002,
              "bed": ((40.0, 220.0), 0.9)},
    "blue":  {"per_sec": 26.0, "band": (5200.0, 9500.0), "length": 0.03, "half_life": 0.004,
              "bed": ((3500.0, 9000.0), 0.3)},
    "green": {"per_sec": 14.0, "band": (320.0, 950.0), "length": 0.06, "half_life": 0.010,
              "bed": ((1800.0, 4200.0), 0.22)},
}


def envelope(x: np.ndarray) -> np.ndarray:
    k = s.n_samples(ENVELOPE_SMOOTH_SEC)
    env = np.convolve(np.abs(x), np.ones(k) / k, mode="same")
    peak = np.max(env)
    return env / peak if peak > 0 else env


def weave(body: np.ndarray, colour: str, seed: int) -> np.ndarray:
    spec = WEAVE[colour]
    seconds = len(body) / SAMPLE_RATE
    env = envelope(body)
    rng = np.random.default_rng(seed)
    out = np.zeros(len(body))
    count = max(3, int(seconds * spec["per_sec"]))
    # The first grain is always at the start, so the colour is heard at once.
    starts = np.concatenate([[0.0], np.sort(rng.uniform(0.0, max(seconds - spec["length"], 0.01), count - 1))])
    for i, start in enumerate(starts):
        grain = burst(spec["length"], spec["band"], spec["half_life"], seed=seed + 1 + i, attack=0.0005)
        at = s.n_samples(start)
        n = min(len(grain), len(out) - at)
        if n <= 0:
            continue
        level = 1.0 if i == 0 else max(env[min(at, len(env) - 1)], 0.15) * rng.uniform(0.5, 1.0)
        out[at:at + n] += grain[:n] * level
    band, bed_gain = spec["bed"]
    bed = s.bandpass(s.noise(seconds, seed + 900), band[0], band[1])[:len(body)]
    return norm(norm(out) + norm(bed * env[:len(bed)]) * bed_gain)


# ── the note (take "note" only) ────────────────────────────────────────
# One short tone per colour, an octave or more apart. Red and blue are
# attacks, so they sit a semitone off the key (AudioDirection rule 5: an
# attack never uses a reward ingredient). Green is support and sits on it.

NOTE_SEC = 0.16
NOTE_HZ = {
    "red": scale_hz(0, -2) * semitones(1),     # low
    "green": scale_hz(2, 0),                   # middle
    "blue": scale_hz(0, 2) * semitones(1),     # high
}


def note(colour: str) -> np.ndarray:
    hz = NOTE_HZ[colour]
    if colour == "red":
        # A rough low tone that sags: FM with a hard index.
        x = s.fm(s.glide(hz, hz * semitones(-2), NOTE_SEC), 1.0, 2.5) * s.decay(NOTE_SEC, 0.05, 0.004)
    elif colour == "blue":
        # A glass ping: an inharmonic ratio, very short.
        x = s.fm(hz, 3.53, 1.2, NOTE_SEC) * s.decay(NOTE_SEC, 0.025, 0.001)
    else:
        # A wooden bar: nearly pure, short.
        x = s.fm(hz, 4.0, 0.4, NOTE_SEC) * s.decay(NOTE_SEC, 0.035, 0.002)
    return norm(x)


# ── assembling a cast ──────────────────────────────────────────────────

STAMP_GAIN = 0.9
BODY_GAIN = 0.8
NOTE_GAIN = 0.45


# "light" first had a quieter signature (0.55) and measured 3 of 9: the
# spell's own start buried it. The signature is now at full level and the
# spell's sound is held down under it, then let up; after DUCK_SEC it is
# exactly as shipped.
DUCK_SEC = 0.14
DUCK_FLOOR = 0.25
WEAVE_GAIN = 0.6

# take -> what goes on top of the spell's own sound
RECIPES = {
    "mat":   {"tilt": 1.0, "stamp": STAMP_GAIN, "note": False, "weave": False},
    "note":  {"tilt": 1.0, "stamp": STAMP_GAIN, "note": True, "weave": False},
    "light": {"tilt": 0.0, "stamp": STAMP_GAIN, "note": False, "weave": False, "duck": True},
    "woven": {"tilt": 1.0, "stamp": 0.0, "note": False, "weave": True},
}


def coloured(cue_id: str, take: str) -> np.ndarray:
    recipe = RECIPES[take]
    colour = CASTS[cue_id][0]
    shipped = norm(SHIPPED[cue_id]())
    body = norm(tilt(shipped, colour, recipe["tilt"]))
    if recipe.get("duck"):
        n = min(s.n_samples(DUCK_SEC), len(body))
        body = body.copy()
        body[:n] *= np.linspace(DUCK_FLOOR, 1.0, n) ** 2
    total = max(len(body) / SAMPLE_RATE, STAMP_SEC)
    layers = [(body, BODY_GAIN, 0.0)]
    if recipe["stamp"] > 0:
        layers.append((STAMPS[colour](), recipe["stamp"], 0.0))
    if recipe["note"]:
        layers.append((note(colour), NOTE_GAIN, 0.0))
    if recipe["weave"]:
        seed = 5000 + 100 * list(CASTS).index(cue_id)
        layers.append((weave(shipped, colour, seed), WEAVE_GAIN, 0.0))
    return place(total, *layers)


def _take_builders(take: str) -> dict:
    if take == "now":
        return dict(SHIPPED)
    return {cue_id: (lambda c=cue_id: coloured(c, take)) for cue_id in CASTS}


# ── demo rows ──────────────────────────────────────────────────────────

DEMO_STEP_SEC = 1.1
# The test: six casts, colours shuffled. Can you call each colour?
MIXED_ORDER = ["cast_blue_t2", "cast_red_t1", "cast_green_t1", "cast_red_t3", "cast_green_t2", "cast_blue_t1"]
FAMILY = {
    "red": ["cast_red_t1", "cast_red_t2", "cast_red_t3"],
    "blue": ["cast_blue_t1", "cast_blue_t2", "cast_blue_t3"],
    "green": ["cast_green_t1", "cast_green_t2", "cast_green_t3"],
}


def in_a_row(builders: dict, order) -> np.ndarray:
    parts = [norm(builders[c]()) for c in order]
    starts, t = [], 0.0
    for p in parts:
        starts.append(t)
        t += max(DEMO_STEP_SEC, len(p) / SAMPLE_RATE + 0.25)
    return place(t, *[(p, 1.0, st) for p, st in zip(parts, starts)])


def stamps_alone() -> np.ndarray:
    """The three signatures on their own: red, blue, green, then again."""
    order = ["red", "blue", "green", "red", "blue", "green"]
    return place(len(order) * 0.5, *[(STAMPS[c](), 1.0, i * 0.5) for i, c in enumerate(order)])


def notes_alone() -> np.ndarray:
    order = ["red", "blue", "green", "red", "blue", "green"]
    return place(len(order) * 0.5, *[(place(STAMP_SEC, (STAMPS[c](), STAMP_GAIN, 0.0), (note(c), NOTE_GAIN, 0.0)), 1.0, i * 0.5)
                                      for i, c in enumerate(order)])


# ── sheet ──────────────────────────────────────────────────────────────

def _cue(cid, label, group, note_text, **extra):
    return {"id": cid, "label": label, "group": group, "band": "gameplay", "note": note_text, **extra}


TEST = "Start here: the test (demos, not uploaded)"
GROUPS = {"red": "Red casts", "blue": "Blue casts", "green": "Green casts"}

SHEET = [
    _cue("demo_mixed", "Six casts, colours shuffled", TEST,
         "Play without looking at the order and call each colour. The order is: blue (Shield), red (Firebolt), "
         "green (Mend), red (Inferno), green (Stone Wall), blue (Frost Nip).", demo=True),
    _cue("demo_stamps", "The three signatures alone", TEST,
         "Red, blue, green, then again. Red is one strike with a low whump; blue is two quick glass ticks; "
         "green is a slower hollow knock-knock. (As shipped and Woven have none, so those columns are empty.)", demo=True),
    _cue("demo_red", "All three red casts in a row", TEST, "Firebolt, Fireball, Inferno. Do they sound like one family?", demo=True),
    _cue("demo_blue", "All three blue casts in a row", TEST, "Frost Nip, Shield, Stasis.", demo=True),
    _cue("demo_green", "All three green casts in a row", TEST, "Mend, Stone Wall, Sanctuary.", demo=True),
] + [
    _cue(cue_id, f"{spell} cast", GROUPS[colour], "As shipped, then four ways of adding the colour. Signature only leaves the spell's own sound exactly as shipped; Woven has no front signature.")
    for cue_id, (colour, spell, _) in CASTS.items()
]


def _with_demos(take: str) -> dict:
    b = _take_builders(take)
    out = dict(b)
    out["demo_mixed"] = lambda: in_a_row(b, MIXED_ORDER)
    for colour, order in FAMILY.items():
        out[f"demo_{colour}"] = lambda o=order: in_a_row(b, o)
    if take in ("mat", "light"):
        out["demo_stamps"] = stamps_alone
    elif take == "note":
        out["demo_stamps"] = notes_alone
    return out


CUES: dict[str, dict] = {take["id"]: _with_demos(take["id"]) for take in TAKES}

# Nothing chosen yet: the user picks a take by ear.
CHOSEN: dict = {}
