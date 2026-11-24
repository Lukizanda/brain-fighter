"""Collect lab: sounds for popping a letter block and drawing its mana in,
built on what the player sees (wiki/design/tap-to-pop.md; seen in a
playtest 2026-11-25).

The visual has three moments, and the game would trigger each separately:
  * pop: a small burst at the block, on the tap (BlockTapController);
  * draw-in: a curved ribbon sweeping round into the player for 0.4 s, with
    3-8 sparks swirling after it and landing one by one between ~0.26 s and
    0.4 s (collectStream.luau). It starts when the server confirms, so
    online it begins one round trip after the tap;
  * arrival: the stream lands on the player. The design's arrival flash is
    not built; the sound would be the first cue for it.

Three takes on that structure, one idea each: A vacuum, B comet, C spin-in.
These are rewards, so they stay in the key. Pop and arrival use the colour
instruments from letter_lab (lab 1).

Importing this module registers its cues into the kit (pilot_md.CUES).
"""

from __future__ import annotations

import numpy as np

import synth as s
import ym
from cues import letter_lab as lab
from cues import pilot_md as base
from kit import SAMPLE_RATE, scale_hz, semitones

FLIGHT_SEC = 0.4            # collectStream.FLIGHT_SEC
MOTE_COUNT = 8              # the popper's own stream: MOTE_COUNT_MAX
MOTE_FIRST_SEC = 0.26       # FLIGHT_SEC * (1 - MOTE_FLIGHT_JITTER)
CONFIRM_SEC = 0.08          # a typical online round trip, tap to draw-in
FAST_SPELL_SEC = 0.3        # demo: a fast speller, a little over the 0.25 s cooldown
COLOURS = ("red", "blue", "green", "wild")
# The draw-in starts audible and grows. Measured on the first render, a
# swell from silence left it inaudible for most of the flight under the
# pop's tail; only the sparks at the end were heard.
DRAW_IN_FLOOR = 0.6


def colour_note(colour: str, hz: float, gain_db: float = 0.0, fade=None) -> np.ndarray:
    """A short note on the colour's instrument (lab 1), chip-rate. `fade`
    is a per-sample TL offset applied to every operator."""
    tl = None if fade is None else {i: fade for i in range(4)}
    if colour == "red":
        return base.note(lab.RED_PLUCK, hz, 2, ring_sec=0.16, gain_db=gain_db, tl_offset=tl)
    if colour == "green":
        return base.note(base.BAR, hz, 2, ring_sec=0.2, gain_db=gain_db, tl_offset=tl)
    tone = base.note(base.BELL, hz, 2, ring_sec=0.28, gain_db=gain_db, tl_offset=tl)
    if colour == "wild":
        sparkle = base.note(base.BELL, hz * semitones(19), 2, ring_sec=0.2, gain_db=gain_db - 6.0, tl_offset=tl)
        tone = ym.place(max(len(tone), len(sparkle)), tone, (sparkle, base.FRAME))
    return tone


# The pop hands over to the draw-in. Measured on the first render, lab 1's
# pop (the bell especially) rang at full level for ~350 ms and buried the
# draw-in. Here the driver steps every operator's level down each frame, as
# old drivers faded a note: same attack, gone within about 0.1 s.
POP_FADE_TL_PER_FRAME = 9   # 6.75 dB a frame
POP_FADE_FRAMES = 14


def pop(colour: str, step: int = 0) -> np.ndarray:
    """The tap: the colour pop, fading out fast so the draw-in is heard."""
    hz = scale_hz(step, base.POP_OCTAVE)
    fade = ym.frames(np.minimum(np.arange(POP_FADE_FRAMES) * POP_FADE_TL_PER_FRAME, 127))
    return base.out(lab.with_front(colour_note(colour, hz, fade=fade)))


def mote_times(rng, accelerate: bool = False) -> np.ndarray:
    """When each spark lands. Even spread over the sparks' window, jittered;
    or, for the spin-in, closing up toward the end."""
    if accelerate:
        x = 1.0 - np.linspace(1.0, 0.0, MOTE_COUNT) ** 0.6
    else:
        x = np.sort(rng.uniform(0.0, 1.0, MOTE_COUNT))
    return MOTE_FIRST_SEC * 0.75 + x * (FLIGHT_SEC - MOTE_FIRST_SEC * 0.75)


def tinkles(times: np.ndarray, rising: bool, gain_db: float = -9.0) -> np.ndarray:
    """A tiny high ping per spark as it lands, walking up the scale."""
    pings = []
    for i, t in enumerate(times):
        step = i if rising else int(np.random.default_rng(i).integers(0, 5))
        hz = scale_hz(step, base.POP_OCTAVE + 2)
        level = gain_db + 4.0 * i / max(1, len(times) - 1)   # louder as they close in
        pings.append((base.note(base.BELL, hz, 1, ring_sec=0.06, gain_db=level), float(t)))
    return ym.place(ym.chip_samples(FLIGHT_SEC + 0.15), *pings)


def arrival_chime(colour: str) -> np.ndarray:
    """The landing: the colour's instrument on the chord's top note, with a
    soft low thump under it."""
    chime = colour_note(colour, scale_hz(5, base.POP_OCTAVE), gain_db=-2.0)
    thump = base.note(base.ROUND, scale_hz(0, base.POP_OCTAVE - 2), 1, ring_sec=0.12, gain_db=-6.0)
    return ym.place(max(len(chime), len(thump)), chime, thump)


# --- The three draw-ins ------------------------------------------------------

def draw_in_vacuum(seed: int) -> np.ndarray:
    """Suction: air pulled in, its pitch rising as it goes, swelling then
    cut off as it lands."""
    sec = FLIGHT_SEC
    air = s.swept_bandpass(s.noise(sec, seed), s.glide(500.0, 6000.0, sec, curve=0.8), q=1.4)
    air = air / np.max(np.abs(air)) * (DRAW_IN_FLOOR + (1.0 - DRAW_IN_FLOOR) * s.swell(sec, 1.3))
    air = ym.dac_sample(air, SAMPLE_RATE, 16000.0) * 1.2
    frames_on = int(round(sec * ym.FRAME_HZ))
    hiss = base.noise_burst(list(np.linspace(10, 4, frames_on).round().astype(int)),
                            shift_hz=ym.frames(np.geomspace(2000.0, 14000.0, frames_on)), seed=seed + 1) * 0.4
    return ym.place(ym.chip_samples(sec), air, hiss)


def draw_in_comet() -> np.ndarray:
    """Comet: a tuned shimmer gliding up an octave along the arc."""
    frames_on = int(round(FLIGHT_SEC * ym.FRAME_HZ))
    start = scale_hz(0, base.POP_OCTAVE)
    pitch = ym.frames(start * semitones(np.linspace(0.0, 12.0, frames_on)))
    swell = ym.frames(np.linspace(4.0, 0.0, frames_on))
    glide = base.note(base.CRYSTAL, pitch, frames_on, ring_sec=0.05, gain_db=8.0, tl_offset={1: swell, 3: swell})
    return glide


def draw_in_spin(seed: int) -> np.ndarray:
    """Spin-in: a sweep that rotates faster as it closes in, the way the
    ribbon curls round into the player."""
    sec = FLIGHT_SEC
    t = s.times(sec)
    turns = 2.0 * np.pi * np.cumsum(s.glide(4.0, 16.0, sec, curve=1.2)) / SAMPLE_RATE
    centre = s.glide(700.0, 3500.0, sec) * (1.0 + 0.45 * np.sin(turns))
    whirl = s.swept_bandpass(s.noise(sec, seed), centre, q=3.0)
    whirl = whirl / np.max(np.abs(whirl)) * (DRAW_IN_FLOOR + (1.0 - DRAW_IN_FLOOR) * s.swell(sec, 1.2)) * (0.75 + 0.25 * np.sin(turns + 1.0))
    return ym.dac_sample(whirl, SAMPLE_RATE, 16000.0) * 1.2


def gulp() -> np.ndarray:
    """The spin-in's landing: a quick drop-and-rise, like being swallowed."""
    pitch = ym.frames([scale_hz(0, base.POP_OCTAVE), scale_hz(0, base.POP_OCTAVE - 1), scale_hz(2, base.POP_OCTAVE)])
    return base.note(base.BAR, pitch, 3, ring_sec=0.12, gain_db=-3.0)


# --- Takes: stream (draw-in + sparks + arrival), from the moment it starts ---

def stream_vacuum(colour: str, seed: int = 301) -> np.ndarray:
    rng = np.random.default_rng(seed)
    return ym.place(ym.chip_samples(FLIGHT_SEC + 0.4), draw_in_vacuum(seed),
                    tinkles(mote_times(rng), rising=False), (arrival_chime(colour), FLIGHT_SEC))


def stream_comet(colour: str, seed: int = 302) -> np.ndarray:
    rng = np.random.default_rng(seed)
    chord = [scale_hz(st, base.POP_OCTAVE) for st in (0, 2, 3, 5)]
    land = ym.place(ym.chip_samples(0.4), *[(colour_note(colour, hz, gain_db=-5.0), 0.0) for hz in chord])
    return ym.place(ym.chip_samples(FLIGHT_SEC + 0.45), draw_in_comet(),
                    tinkles(mote_times(rng), rising=True, gain_db=-12.0), (land, FLIGHT_SEC))


def stream_spin(colour: str, seed: int = 303) -> np.ndarray:
    rng = np.random.default_rng(seed)
    land = ym.place(ym.chip_samples(0.35), gulp(), colour_note(colour, scale_hz(5, base.POP_OCTAVE), gain_db=-6.0))
    return ym.place(ym.chip_samples(FLIGHT_SEC + 0.4), draw_in_spin(seed),
                    tinkles(mote_times(rng, accelerate=True), rising=True), (land, FLIGHT_SEC))


STREAMS = {"vacuum": stream_vacuum, "comet": stream_comet, "spin": stream_spin}


def full_sequence(take: str, colour: str = "blue", seed: int = 0) -> np.ndarray:
    """One letter: the pop, then the stream starting one round trip later."""
    stream = base.out(STREAMS[take](colour, seed=310 + seed))
    return s.mix(pop(colour), (stream, 1.0, CONFIRM_SEC))


def fast_speller(take: str) -> np.ndarray:
    """DEMO: four letters 0.3 s apart, so the streams overlap as in play."""
    layers = []
    for i, colour in enumerate(COLOURS):
        # Each letter a step higher, as in musical spelling.
        letter = s.mix(pop(colour, i), (base.out(STREAMS[take](colour, seed=320 + i)), 1.0, CONFIRM_SEC))
        layers.append((letter, 1.0, i * FAST_SPELL_SEC))
    return s.mix(*layers)


# --- Take C, made physical (2026-11-25) --------------------------------------
# The user chose take C and worried its style clashes with the realistic
# spells. Measured: take C's whirl is as noise-led as the chosen spells (pitch
# clarity 0.16; spells 0.16-0.46), but its pop (0.88) and landing (0.90) are
# pure chip notes. So the ends become physical: the block cracking apart, and
# a rush of air into the player. Colour is carried by the crack's texture
# (the 'texture without pitch' rule). The hybrid keeps a quiet note under
# the physical layers, which still carries the colour's instrument and the
# rising pitch of musical spelling.

# Crack band per colour: warm for red, woody for green, glassy for blue,
# wide and bright for gold.
CRACK_BAND = {"red": (700.0, 3200.0), "green": (450.0, 2400.0), "blue": (2200.0, 7500.0), "wild": (1200.0, 7500.0)}
CRACK_GRAINS = 5           # small fragments after the main crack
TAG_DB = -12.0             # the hybrid's musical note, under the physical layers
CHOSEN_CRACK_SEED = 360    # the crack in the row the user chose from


def block_crack(colour: str, seed: int) -> np.ndarray:
    """The block bursting: a sharp crack in the colour's band, a few small
    fragments after it, and a short low thud for the cube's body. Chip-rate."""
    rng = np.random.default_rng(seed)
    low, high = CRACK_BAND[colour]
    sec = 0.12
    x = np.zeros(s.n_samples(sec))
    crack = s.bandpass(s.noise(0.04, seed), low, min(high, 7800.0))
    crack = crack / np.max(np.abs(crack)) * s.decay(0.04, 0.007, attack=0.0003)
    x[: len(crack)] += crack
    for _ in range(CRACK_GRAINS):
        at = s.n_samples(rng.uniform(0.012, 0.07))
        grain = s.bandpass(s.noise(0.006, int(rng.integers(1 << 30))), low, min(high, 7800.0))
        grain = grain / np.max(np.abs(grain)) * s.decay(0.006, 0.0015, attack=0.0002) * rng.uniform(0.25, 0.6)
        x[at:at + len(grain)] += grain[: len(x) - at]
    thud = s.sine(s.glide(170.0, 70.0, 0.05, curve=1.5)) * s.decay(0.05, 0.012, attack=0.0005)
    x[: len(thud)] += thud * 0.5
    return ym.dac_sample(x / np.max(np.abs(x)), SAMPLE_RATE, 16000.0)


def physical_pop(colour: str, step: int = 0, tag_db: float | None = None, seed: int = 401) -> np.ndarray:
    crack = block_crack(colour, seed)
    layers = [crack]
    if tag_db is not None:
        hz = scale_hz(step, base.POP_OCTAVE)
        fade = ym.frames(np.minimum(np.arange(POP_FADE_FRAMES) * POP_FADE_TL_PER_FRAME, 127))
        layers.append(colour_note(colour, hz, gain_db=tag_db, fade=fade))
    return base.out(ym.place(max(len(l) for l in layers), *layers))


def absorb(seed: int) -> np.ndarray:
    """The landing: a short rush of air into the body and a muffled thump,
    like a gust hitting a coat. Chip-rate."""
    sec = 0.22
    air = s.lowpass(s.noise(sec, seed), 900.0, order=2)
    air = air / np.max(np.abs(air)) * s.decay(sec, 0.04, attack=0.012)
    thump = s.sine(s.glide(130.0, 60.0, 0.06, curve=1.5)) * s.decay(0.06, 0.015, attack=0.001)
    x = air
    x[: len(thump)] += thump * 0.7
    return ym.dac_sample(x / np.max(np.abs(x)), SAMPLE_RATE, 11000.0)


def stream_spin_real(colour: str, seed: int = 303, tag_db: float | None = None) -> np.ndarray:
    """Take C with physical ends. The whirl and the spark ticks are kept."""
    rng = np.random.default_rng(seed)
    land_layers = [absorb(seed + 7)]
    if tag_db is not None:
        land_layers.append(colour_note(colour, scale_hz(5, base.POP_OCTAVE), gain_db=tag_db))
    land = ym.place(max(len(l) for l in land_layers), *land_layers)
    return ym.place(ym.chip_samples(FLIGHT_SEC + 0.4), draw_in_spin(seed),
                    tinkles(mote_times(rng, accelerate=True), rising=True, gain_db=-14.0), (land, FLIGHT_SEC))


def real_sequence(colour: str, step: int, seed: int, tag_db: float | None) -> np.ndarray:
    stream = base.out(stream_spin_real(colour, seed=seed, tag_db=tag_db))
    return s.mix(physical_pop(colour, step, tag_db, seed=seed + 50), (stream, 1.0, CONFIRM_SEC))


def real_fast(tag_db: float | None) -> np.ndarray:
    layers = [(real_sequence(c, i, 330 + i, tag_db), 1.0, i * FAST_SPELL_SEC) for i, c in enumerate(COLOURS)]
    return s.mix(*layers)


CUES = {
    "col_vacuum": lambda: full_sequence("vacuum"),
    "col_comet": lambda: full_sequence("comet"),
    "col_spin": lambda: full_sequence("spin"),
    "col_vacuum_fast": lambda: fast_speller("vacuum"),
    "col_comet_fast": lambda: fast_speller("comet"),
    "col_spin_fast": lambda: fast_speller("spin"),
    "col_spin_real": lambda: real_sequence("blue", 0, 310, None),
    "col_spin_hybrid": lambda: real_sequence("blue", 0, 310, TAG_DB),
    "col_spin_real_fast": lambda: real_fast(None),
    "col_spin_hybrid_fast": lambda: real_fast(TAG_DB),
    # Chosen 2026-11-25: take C, physical. The game triggers the two halves at
    # different moments, so they are separate files: the crack on the tap
    # (one per colour, since the crack's band carries the colour) and the
    # stream when the server confirms. The stream has no note, so it is the
    # same for every colour. Its landing is baked in at FLIGHT_SEC: if
    # collectStream.FLIGHT_SEC changes, re-render and re-upload the stream.
    # The crack the user heard in the one-letter row (real_sequence seed 310 + 50).
    "collect_pop_red": lambda: physical_pop("red", seed=CHOSEN_CRACK_SEED),
    "collect_pop_green": lambda: physical_pop("green", seed=CHOSEN_CRACK_SEED),
    "collect_pop_blue": lambda: physical_pop("blue", seed=CHOSEN_CRACK_SEED),
    "collect_pop_wild": lambda: physical_pop("wild", seed=CHOSEN_CRACK_SEED),
    "collect_stream": lambda: base.out(stream_spin_real("blue", seed=310)),
}
base.CUES.update(CUES)

GROUP = "Collect: pop, draw-in, arrival"
GROUP_REAL = "Collect take C, more physical"
SHEET = [
    ("col_spin_real", "C, physical: one blue letter", GROUP_REAL, False,
     "No musical notes. The block cracks apart (a glassy crack for blue), the whirl draws it in, a rush of air lands on you."),
    ("col_spin_hybrid", "C, hybrid: one blue letter", GROUP_REAL, False,
     "The same physical sounds, with a quiet note underneath that still tells colour and climbs as you spell."),
    ("col_spin_real_fast", "DEMO: C physical, fast speller", GROUP_REAL, True,
     "Red, blue, green, wild. Colour is heard only in the crack's texture."),
    ("col_spin_hybrid_fast", "DEMO: C hybrid, fast speller", GROUP_REAL, True,
     "As above, with the quiet notes climbing."),
    ("col_spin", "C as you heard it (for comparison)", GROUP_REAL, False, "The take you picked: chip-note pop and landing."),
    ("collect_pop_red", "Crack, red (on the tap)", "Collect (chosen): the files the game plays", False, "Warm band."),
    ("collect_pop_green", "Crack, green (on the tap)", "Collect (chosen): the files the game plays", False, "Woody band."),
    ("collect_pop_blue", "Crack, blue (on the tap)", "Collect (chosen): the files the game plays", False, "Glassy band."),
    ("collect_pop_wild", "Crack, gold wildcard (on the tap)", "Collect (chosen): the files the game plays", False, "Wide, bright band."),
    ("collect_stream", "Stream: swirl, spark ticks, landing (on confirm)", "Collect (chosen): the files the game plays", False,
     "Same for every colour. The landing is at 0.4 s, when the ribbon reaches you."),
    ("col_vacuum", "Take A, vacuum: one blue letter", GROUP, False,
     "Pop, then (one round trip later) air sucked in rising in pitch, a ping per spark as it lands, a soft thump and chime as it reaches you."),
    ("col_comet", "Take B, comet: one blue letter", GROUP, False,
     "Pop, then a tuned shimmer gliding up an octave along the arc, pings climbing the scale, landing on a chord."),
    ("col_vacuum_fast", "DEMO: take A, fast speller", GROUP, True,
     "Four letters (red, blue, green, wild) 0.3 s apart. Streams overlap in play; listen for mush."),
    ("col_comet_fast", "DEMO: take B, fast speller", GROUP, True, "As above, take B."),
    ("col_spin_fast", "DEMO: take C, fast speller", GROUP, True, "As above, take C."),
]
