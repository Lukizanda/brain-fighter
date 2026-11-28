"""Production lane: ice, life and earth (the blue and green spells, and the
stone that Stone Wall and the arena's breakable walls share).

Owned by the "Audio: ice, life and earth lane" session (spawned 2026-11-28).
It replaces the stand-in sounds the game plays today. Rules:
wiki/design/AudioDirection.md (read it first); method: docs/agents/audio-sfx.md.

    python tools/sfx/render.py --lane nature
    python tools/sfx/lint.py --dir build/sfx/lanes/nature
    python tools/sfx/audition.py --dir build/sfx/lanes/nature --out build/sfx/lanes/nature/audition.html

Each cue id is the VfxConfig.EFFECTS id it replaces. Already chosen and frozen
(do not change; listen for the family sound): the Frost Nip cast (pilot_md
frost_blast). The Frost Nip take A shatter (pilot_md cast_blue_t1) was liked
too and is a natural candidate for impact_freeze. Reuse helpers from pilot_md
/ collect_lab by import; never edit those files.

Every cue here is in the world layer (AudioDirection rule 2): noise-led,
no melody, no echo, no ring. Ice keeps the Frost Nip ingredients (the ICE
patch a semitone off the key, PSG crack noise, DAC crackle). Life is air,
leaves and wood. Stone is low DAC thuds, PSG rumble and gritty rubble.

Game timings these are built on (read from src/, 2026-11-28):
  * Stone Wall: rumble at the tell, wall solid at BARRIER_TELL_SEC +
    BARRIER_RISE_SEC = 0.73 s, impact_wall then. Cracks: up to 12 snaps in
    the last CRACK_LEAD_SEC = 2.5 s, spread over 85% of it, easing in
    (exponent 1.3), one sound per frame.
  * Shield: the cast plays on the caster (predicted), impact_shield on the
    caster from the server about one round trip later.
  * shield_block: boss and player volleys stagger shots about 0.12 s apart.
  * Sanctuary fires impact_heal and impact_shield together; Stasis fires
    impact_freeze and impact_buff (its damage amp) on the frozen target.
"""

from __future__ import annotations

import numpy as np

import synth as s
import ym
from cues import pilot_md as base  # read-only: patches and helpers
from kit import SAMPLE_RATE, semitones

LANE = {"id": "nature", "label": "Ice, life and earth"}

TAKES = [
    {"id": "a", "label": "Take A"},
    {"id": "b", "label": "Take B"},
    {"id": "c", "label": "Take C"},
]

F = base.FRAME
ICE_HZ = base.ICE_HZ
LOW_ICE_HZ = ICE_HZ / 2.0        # the bigger ice events strike an octave down

# Bands (Hz) that carry each material's colour, as the collect cracks do.
GLASS_BAND = (2200.0, 7500.0)    # collect_lab blue crack
LEAF_BAND = (1400.0, 6000.0)
WOOD_BAND = (450.0, 2400.0)      # collect_lab green crack
STONE_BAND = (350.0, 2600.0)
GRIT_BAND = (900.0, 4500.0)

GLASS_RATE = 16000.0             # DAC playback: glass stays bright
STONE_RATE = 10000.0             # stone is crunchier
AIR_RATE = 8000.0

# Game timings (see the module docstring).
SHIELD_CONFIRM_SEC = 0.08        # cast to impact_shield, one round trip
VOLLEY_STAGGER_SEC = 0.12
VOLLEY_SHOTS = 6
WALL_SETTLE_SEC = 0.73
WALL_RUMBLE_AFTER_CAST_SEC = 0.05
CRACK_LEAD_SEC = 2.5
CRACK_STAGGER_SPAN = 0.85
CRACK_PROGRESS_EXPONENT = 1.3
CRACK_COUNT = 12
CRACK_TIMING_JITTER = 0.06
# The demo plays each crack at a random speed in this range, standing in
# for the pitchRange the game will give it (a guess until it is wired).
CRACK_DEMO_SPEED = (0.9, 1.1)
FROST_IMPACT_AFTER_CAST_SEC = 0.15   # Frost Nip's strike lands at 0.1 s in the cast


# --- Small primitives (48 kHz unless named chip-rate) ------------------------

def norm(x: np.ndarray) -> np.ndarray:
    return x / max(1e-9, float(np.max(np.abs(x))))


def dac(x: np.ndarray, rate: float) -> np.ndarray:
    """A 48 kHz sample played through the 8-bit DAC. Chip-rate."""
    return ym.dac_sample(norm(x), SAMPLE_RATE, rate)


def swell_env(seconds: float, attack: float, half_life: float, power: float = 2.0) -> np.ndarray:
    """Rises over `attack` (eased), then falls with `half_life`."""
    t = s.times(seconds)
    rise = np.clip(t / max(attack, 1e-6), 0.0, 1.0) ** power
    fall = 0.5 ** (np.maximum(t - attack, 0.0) / half_life)
    return rise * fall


def air(seconds: float, cut_hz: float, attack: float, half_life: float, seed: int,
        low_hz: float = 0.0) -> np.ndarray:
    """Low-passed noise that swells and dies: breath, wind, pushed air."""
    x = s.lowpass(s.noise(seconds, seed), cut_hz, order=2)
    if low_hz > 0:
        x = s.highpass(x, low_hz, order=1)
    return norm(x) * swell_env(seconds, attack, half_life)


def grains(seconds: float, per_sec: float, band, seed: int, length=(0.004, 0.012),
           sigma: float = 0.5, density=None, level=None, attack_frac: float = 0.05,
           decay_frac: float = 0.2) -> np.ndarray:
    """A random scatter of tiny noise grains in `band`: crackle, rustle,
    pebbles, depending on band and length. `density` and `level` are
    functions of progress 0..1."""
    rng = np.random.default_rng(seed)
    x = np.zeros(s.n_samples(seconds))
    t = rng.exponential(1.0 / per_sec)
    lo, hi = band
    while t < seconds:
        p = t / seconds
        n = rng.uniform(*length)
        g = s.bandpass(s.noise(n, int(rng.integers(1 << 30))), lo, hi)
        g = norm(g) * s.decay(n, n * decay_frac, attack=n * attack_frac)
        g = g * rng.lognormal(0.0, sigma) * (level(p) if level else 1.0)
        at = s.n_samples(t)
        end = min(len(x), at + len(g))
        x[at:end] += g[: end - at]
        d = density(p) if density else 1.0
        t += rng.exponential(1.0 / (per_sec * max(d, 0.05)))
    return x


def thud(seconds: float = 0.3, cut_hz: float = 500.0, half_life: float = 0.04, sub: float = 0.25,
         start_hz: float = 120.0, end_hz: float = 45.0, seed: int = 1, drive: float = 2.0) -> np.ndarray:
    """A low hit led by muffled noise, with only a little falling sine under
    it so it reads as mass, not a drum."""
    burst = norm(s.lowpass(s.noise(seconds, seed), cut_hz, order=2)) * s.decay(seconds, half_life, attack=0.001)
    dive = s.sine(s.glide(start_hz, end_hz, seconds, curve=3.0)) * s.decay(seconds, half_life * 0.8, attack=0.0005)
    return s.drive(norm(burst + sub * dive), drive)


def snap(seconds: float, band, seed: int, half_life: float = 0.006) -> np.ndarray:
    """One sharp crack in a band."""
    return norm(s.bandpass(s.noise(seconds, seed), *band)) * s.decay(seconds, half_life, attack=0.0003)


def rumble(frames_on: int, vol_start: float, vol_end: float, seed: int, wobble: float = 0.0):
    """The PSG's slowest noise clock: a low rumble. Chip-rate."""
    k = np.arange(frames_on)
    vols = np.linspace(vol_start, vol_end, frames_on) + wobble * np.sin(k / 2.3)
    vols = list(np.clip(np.round(vols), 0, 15).astype(int))
    return base.noise_burst(vols, divider=base.RUMBLE_DIVIDER, seed=seed)


def at(x48: np.ndarray, seconds: float) -> tuple:
    return (x48, 1.0, seconds)


def chip(total_sec: float, *layers) -> np.ndarray:
    """Mix chip-rate layers and send them through the output stage."""
    return base.out(ym.place(ym.chip_samples(total_sec), *layers))


def ice_clank(hz: float, frames_on: int = 3, ring: float = 0.12, dull_to: float = 20.0, gain_db: float = 0.0):
    """One ICE note with no clashing second note (the clash marks an
    attack), its modulators closing so it clanks dull. Chip-rate."""
    drop = [1.25, 1.05, 1.0, 0.95, 0.92]
    dull = ym.frames(np.linspace(0.0, dull_to, 6))
    return base.note(base.ICE, ym.frames([hz * d for d in drop]), frames_on, ring_sec=ring,
                     gain_db=gain_db, tl_offset={0: dull, 1: dull, 2: dull})


# --- Ice and wards (blue) ----------------------------------------------------

def freeze_a() -> np.ndarray:
    """The liked Frost Nip take A shatter, as it was."""
    return base.cast_blue_t1()


def freeze_b() -> np.ndarray:
    """Icing over: frost creeping across the target (crackle thickening
    for 0.25 s), locking with a hard ice strike."""
    creep = grains(0.28, 90.0, GLASS_BAND, 501, length=(0.002, 0.005), density=lambda p: 0.3 + 3.0 * p ** 2,
                   level=lambda p: 0.25 + 0.75 * p)
    lock_at = 0.26
    hit = base.ice_hit(ICE_HZ)
    tail = base.dac_crackle(0.2, 50.0, seed=502) * base.ICE_CRACKLE_GAIN
    return norm(chip(0.62, dac(creep, GLASS_RATE) * 0.7, (hit, lock_at), (tail, lock_at + 2 * F)))


def block_a() -> np.ndarray:
    """Clank: one short, high ice clank and a crack, gone in 0.15 s."""
    clank = ice_clank(ICE_HZ, frames_on=2, ring=0.06, dull_to=30.0)
    crack = base.noise_burst([0, 3, 8, 15], shift_hz=ym.frames([14000.0, 9000.0, 6000.0, 4000.0]), seed=581) * 0.5
    return base.hot(chip(0.16, clank, crack), 1.6)


# --- Life (green) ------------------------------------------------------------

def mend_b() -> np.ndarray:
    """Leaves: a quick rustle of leaves that gathers and settles, over a
    soft low breath."""
    rustle = grains(0.42, 160.0, LEAF_BAND, 711, length=(0.006, 0.02), attack_frac=0.3, sigma=0.6,
                    density=lambda p: np.sin(np.pi * min(1.0, p * 1.3)) + 0.1, level=lambda p: np.sin(np.pi * p) ** 0.7)
    under = air(0.45, 500.0, 0.12, 0.1, 712, low_hz=100.0)
    return chip(0.5, dac(rustle, GLASS_RATE) * 0.8, dac(under, AIR_RATE) * 0.6)


def heal_b() -> np.ndarray:
    """Taken in: a soft gust drawn into the body, a muffled thump of it
    landing, a fading warm breath after."""
    gust = norm(s.swept_bandpass(s.noise(0.25, 741), s.glide(2500.0, 600.0, 0.25), q=1.4)) * swell_env(0.25, 0.2, 0.03)
    land = thud(0.15, cut_hz=500.0, half_life=0.02, sub=0.2, start_hz=140.0, end_hz=70.0, seed=742, drive=1.3)
    after = air(0.6, 700.0, 0.05, 0.15, 743, low_hz=120.0)
    return chip(0.95, dac(gust, GLASS_RATE) * 0.8, (dac(land, STONE_RATE) * 0.6, 0.2), (dac(after, AIR_RATE) * 0.5, 0.22))


def sanctuary_b() -> np.ndarray:
    """Canopy gust: a gust through a whole canopy, its colour lifting and
    falling over 1.6 s, the leaves riding it."""
    sec = 1.7
    centre = 500.0 * np.exp(1.4 * np.sin(np.pi * np.linspace(0.0, 1.0, s.n_samples(sec))))
    gust = norm(s.swept_bandpass(s.noise(sec, 771), centre, q=1.0, blocks=96)) * swell_env(sec, 0.45, 0.4, power=1.5)
    leaves = grains(sec, 200.0, LEAF_BAND, 772, length=(0.005, 0.02), attack_frac=0.3, sigma=0.6,
                    density=lambda p: np.sin(np.pi * p) ** 2 + 0.05, level=lambda p: np.sin(np.pi * p))
    return chip(1.8, dac(gust, AIR_RATE), dac(leaves, GLASS_RATE) * 0.5)


# --- Earth: Stone Wall and breakable walls ----------------------------------

def stone_snap(seed: int, half_life: float = 0.008, body: float = 0.6) -> np.ndarray:
    """A stone crack: a dull, gritty snap with a short low body. 48 kHz."""
    sec = 0.09
    crack = snap(sec, STONE_BAND, seed, half_life=half_life)
    tok = thud(sec, cut_hz=900.0, half_life=0.012, sub=0.1, start_hz=200.0, end_hz=90.0, seed=seed + 1, drive=1.5)
    return norm(crack + body * tok)


def rubble(seconds: float, per_sec: float, seed: int, density=None, level=None, size=(0.006, 0.03)) -> np.ndarray:
    """Pieces of stone landing: gritty grains of mixed size. 48 kHz."""
    return grains(seconds, per_sec, (300.0, 3000.0), seed, length=size, sigma=0.7,
                  density=density, level=level, decay_frac=0.15)


def wall_cast_b() -> np.ndarray:
    """Heave: a short gritty scrape lifting upward, stone being pulled."""
    sec = 0.32
    scrape = norm(s.swept_bandpass(s.noise(sec, 911), s.glide(250.0, 1400.0, sec), q=1.6)) * swell_env(sec, 0.2, 0.06, power=1.2)
    grit = rubble(sec, 120.0, 912, density=lambda p: 0.3 + p, size=(0.003, 0.01))
    return chip(0.42, dac(scrape, STONE_RATE), dac(grit, STONE_RATE) * 0.45)


RISE_SEC = 0.9


def crack_b() -> np.ndarray:
    """Strain and snap: a brief gritty grind of stress, then the snap."""
    grind = rubble(0.07, 400.0, 1011, density=lambda p: 0.5 + p, level=lambda p: 0.3 + 0.7 * p, size=(0.002, 0.005))
    return chip(0.2, dac(grind, STONE_RATE) * 0.35, (dac(stone_snap(1012), STONE_RATE), 0.07))


def crack_c() -> np.ndarray:
    """Snap and trickle: the snap, then a few grains of grit running down."""
    trickle = rubble(0.25, 60.0, 1022, level=lambda p: 1.0 - p, size=(0.002, 0.006))
    return chip(0.34, dac(stone_snap(1021, body=0.4), STONE_RATE), (dac(trickle, STONE_RATE) * 0.3, 0.03))


def break_b() -> np.ndarray:
    """Crack, crumble, thud: a sharp crack, a short crumble, then four heavy
    chunks landing one after another, dust trailing."""
    crack = dac(stone_snap(1111, half_life=0.015, body=0.8), STONE_RATE)
    crumble = dac(rubble(0.3, 220.0, 1112, size=(0.003, 0.012)), STONE_RATE) * 0.5
    layers = [crack, (crumble, 0.04)]
    for i, (t, g) in enumerate(((0.28, 1.0), (0.42, 0.75), (0.58, 0.85), (0.8, 0.55))):
        chunk = thud(0.3, cut_hz=550.0, half_life=0.035, sub=0.25, start_hz=110.0, end_hz=40.0, seed=1113 + i, drive=2.0)
        layers.append((dac(chunk, STONE_RATE) * g, t))
    dust = dac(rubble(0.8, 40.0, 1120, level=lambda p: 1.0 - p, size=(0.003, 0.01)), STONE_RATE) * 0.3
    layers.append((dust, 0.3))
    return chip(1.4, *layers)


# --- Round 2 (user feedback 2026-11-28) -------------------------------------
# Wards: "instead of a woosh, it should be like an energy 'wooom' humming in",
#   "it should be humming while it's still up", and the break "match this
#   stylistically". A ward is energy, so it hums: a sustained chip tone a
#   semitone off the key (the ice family's pitch, three octaves down), two
#   copies BEAT_HZ apart so it throbs. This is tonal by request, so its pitch
#   clarity is high; it stays off the key and plays no melody.
# Stasis: "ice forming and freezing the boss, like glacial ice big sound".
# Mend and heal: "magical and tinkly". Sanctuary: take B "layered with
#   magical sounds tinkling". Tinkles are short chip bell pings on the
#   pentatonic key in random order (no tune, no echo).
# Rise: take B "needs to sound more like earth rumbling up, it sounds like a
#   fire now". Settle: take A, "something more bassy".

from kit import scale_hz  # noqa: E402

# Frequencies are multiples of 0.5 Hz so a 2 s loop of the hum wraps in phase.
HUM_HZ = round(ICE_HZ / 8.0 * 2.0) / 2.0     # D#3, 155.5 Hz
BEAT_HZ = 1.5
HUM_LOOP_SEC = 2.0
HUM_LOOP_PREROLL_SEC = 0.25
HUM_SEAM_SEC = 0.1
TINKLE_OCTAVE = 2        # TINK sounds an octave above its note (carrier MUL 2)
HUM_BEAT_GAIN = 0.5      # the beating copy, under the main tone: a gentle throb, not a full null

# Ward: a sustained, slightly buzzy tone. Two 2-op pairs, carriers at the
# pitch and the octave; the modulators set how bright (how "electric") it
# is, and a driver moves them frame by frame.
WARD = ym.Patch(4, 2, [
    ym.Op(mul=1, tl=36, ar=31, d1r=0, sl=0, d2r=0, rr=9),
    ym.Op(mul=1, tl=0, ar=31, d1r=0, sl=0, d2r=0, rr=7),
    ym.Op(mul=3, tl=48, ar=31, d1r=0, sl=0, d2r=0, rr=9),
    ym.Op(mul=2, tl=12, ar=31, d1r=0, sl=0, d2r=0, rr=7),
])

# Tinkle: a short bell ping that dies on its own (fast decay and release,
# unlike BELL, which rings and would be cut off).
TINK = ym.Patch(4, 2, [
    ym.Op(mul=7, dt=3, tl=38, ar=31, d1r=22, sl=8, d2r=18, rr=14),
    ym.Op(mul=2, tl=2, ar=31, d1r=15, sl=5, d2r=13, rr=12),
    ym.Op(mul=5, dt=-2, tl=42, ar=31, d1r=22, sl=9, d2r=18, rr=14),
    ym.Op(mul=1, tl=10, ar=31, d1r=14, sl=5, d2r=12, rr=12),
])
TINK_FADE_SEC = 0.004


def _curve(values) -> np.ndarray:
    return ym.frames(np.asarray(values, dtype=float))


def hum(pitch, seconds: float, key_off_sec: float, level=0.0, bright=0.0) -> np.ndarray:
    """The ward tone, chip-rate. `pitch` is Hz or a per-sample curve;
    `level` and `bright` are TL offsets (steps, 0 = full) on the carriers
    and the modulators, numbers or per-sample curves."""
    tl = {1: level, 3: level, 0: bright, 2: bright}
    p = pitch if np.isscalar(pitch) else np.asarray(pitch)
    a = ym.fm_note(WARD, p, seconds, key_off_sec, tl_offset=tl)
    b = ym.fm_note(WARD, p + BEAT_HZ, seconds, key_off_sec, tl_offset=tl)
    return (a + HUM_BEAT_GAIN * b) / (1.0 + HUM_BEAT_GAIN)


def tinkles(times, octave: int = TINKLE_OCTAVE, seed: int = 1, gain_db: float = -4.0, spread_db: float = 6.0,
            steps=None, ring: float = 0.14) -> np.ndarray:
    """One short ping per time, on a random pentatonic step (or `steps`).
    Chip-rate, as long as the last ping."""
    rng = np.random.default_rng(seed)
    parts = []
    fade = ym.chip_samples(TINK_FADE_SEC)
    for i, t in enumerate(times):
        step = int(steps[i]) if steps is not None else int(rng.integers(0, 7))
        g = gain_db - rng.uniform(0.0, spread_db)
        ping = base.note(TINK, scale_hz(step, octave), 1, ring_sec=ring, gain_db=g)
        ping[-fade:] *= np.linspace(1.0, 0.0, fade)
        parts.append((ping, float(t)))
    total = ym.chip_samples(max(times) + F + ring + 0.01)
    return ym.place(total, *parts)


def scatter_times(seconds: float, per_sec: float, seed: int, density=None, start: float = 0.0) -> list[float]:
    rng = np.random.default_rng(seed)
    out, t = [], start + rng.exponential(1.0 / per_sec)
    while t < start + seconds:
        out.append(t)
        d = density((t - start) / seconds) if density else 1.0
        t += rng.exponential(1.0 / (per_sec * max(d, 0.05)))
    return out


# --- Wards that hum ----------------------------------------------------------

def hum_cast_a() -> np.ndarray:
    """Hums in: the tone swells up from silence and rises into its pitch
    over 0.3 s, opening as it comes, then eases off."""
    n = 18
    pitch = _curve(HUM_HZ * np.geomspace(0.75, 1.0, n))
    level = _curve(np.linspace(40.0, 0.0, n))
    bright = _curve(np.concatenate([np.linspace(30.0, 0.0, n), np.linspace(0.0, 12.0, 12)]))
    return chip(0.9, hum(pitch, 0.9, 0.45, level, bright))


def hum_form_a() -> np.ndarray:
    """Locks on: a bright glint, then the steady hum settling to a lower
    colour and fading over about a second."""
    bright = _curve(np.concatenate([np.zeros(3), np.linspace(0.0, 14.0, 12)]))
    tone = hum(HUM_HZ, 1.2, 0.3, 0.0, bright)
    glint = base.dac_crackle(0.12, 90.0, seed=1321) * base.ICE_CRACKLE_GAIN * 0.5
    return chip(1.2, tone, glint)


def shield_hum_loop() -> np.ndarray:
    """While the shield is up: the hum held, its colour breathing once
    every 2 s. A 2 s loop (the game cannot play loops yet)."""
    total = HUM_LOOP_PREROLL_SEC + HUM_LOOP_SEC + HUM_SEAM_SEC
    k = np.arange(int(total * ym.FRAME_HZ) + 2)
    t = k / ym.FRAME_HZ - HUM_LOOP_PREROLL_SEC
    bright = _curve(10.0 + 6.0 * np.sin(2.0 * np.pi * t / HUM_LOOP_SEC))
    raw = base.out(hum(HUM_HZ, total + 0.1, total + 1.0, 0.0, bright))
    raw = raw[s.n_samples(HUM_LOOP_PREROLL_SEC):]
    body, seam = s.n_samples(HUM_LOOP_SEC), s.n_samples(HUM_SEAM_SEC)
    loop = raw[:body].copy()
    # Every frequency repeats every 2 s, so the two ends are in phase and a
    # plain linear cross-fade keeps the level steady across the seam.
    fade = np.linspace(0.0, 1.0, seam)
    loop[:seam] = raw[:seam] * fade + raw[body:body + seam] * (1.0 - fade)
    return loop


def hum_break_a() -> np.ndarray:
    """Powers down: a glass crack, and the hum dropping an octave as it
    dies, shards falling."""
    n = 20
    pitch = _curve(HUM_HZ * np.geomspace(1.0, 0.5, n))
    level = _curve(np.linspace(0.0, 30.0, n))
    tone = hum(pitch, 0.6, n * F, level, 4.0)
    crack = dac(snap(0.05, GLASS_BAND, 1341, half_life=0.008), GLASS_RATE)
    shards = base.dac_crackle(0.5, 90.0, seed=1342) * base.ICE_CRACKLE_GAIN * 0.8
    return chip(0.8, crack, tone, (shards, F))


# --- Stasis: glacial ice -----------------------------------------------------

def groan(seconds: float, seed: int, rate=(25.0, 60.0), band=(150.0, 900.0), level=None) -> np.ndarray:
    """Ice under strain: a stick-slip train of low clicks whose rate drifts,
    jittered so it groans rather than hums. 48 kHz."""
    rng = np.random.default_rng(seed)
    x = np.zeros(s.n_samples(seconds))
    t = 0.0
    while t < seconds:
        p = t / seconds
        c = snap(0.006, band, int(rng.integers(1 << 30)), half_life=0.0015)
        a = s.n_samples(t)
        x[a:a + len(c)] += c[: len(x) - a] * rng.uniform(0.5, 1.0) * (level(p) if level else 1.0)
        r = rate[0] * (rate[1] / rate[0]) ** p
        t += rng.uniform(0.6, 1.4) / r
    return s.lowpass(x, band[1] * 1.5)


def ice_boom(seed: int) -> np.ndarray:
    """A thick sheet of ice cracking through: a deep thud, a sharp crack.
    Chip-rate."""
    deep = dac(thud(0.6, cut_hz=380.0, half_life=0.09, sub=0.3, start_hz=90.0, end_hz=30.0, seed=seed, drive=2.2), STONE_RATE)
    crack = dac(snap(0.06, (1500.0, 7500.0), seed + 1, half_life=0.01), GLASS_RATE) * 0.8
    return ym.place(len(deep), deep, crack)


# --- Life: magic that tinkles ------------------------------------------------

def mend_rustle_tinkle() -> np.ndarray:
    """Take B's leaf rustle, with magic tinkles scattered through it,
    thickening as it goes."""
    leaves = mend_b()
    sparkle = base.out(tinkles(scatter_times(0.4, 22.0, 1501, density=lambda p: 0.4 + 1.2 * p), seed=1502))
    return s.mix(norm(leaves) * 0.6, (norm(sparkle), 0.8, 0.02))


def heal_gust_tinkle() -> np.ndarray:
    """Take B (a gust drawn into the body, a thump), then tinkles drifting
    down into the target and settling."""
    gust = norm(heal_b())
    times = scatter_times(0.9, 14.0, 1531, density=lambda p: 1.0 - 0.7 * p, start=0.2)
    rng = np.random.default_rng(1532)
    steps = [int(6 - i * 6 / max(1, len(times)) + rng.integers(0, 2)) for i in range(len(times))]
    sparkle = base.out(tinkles(times, seed=1533, steps=steps, gain_db=-6.0))
    return s.mix((gust, 0.6, 0.0), (norm(sparkle), 0.7, 0.0))


def sanctuary_gust_tinkle(per_sec: float, octave: int, seed: int, gain: float) -> np.ndarray:
    gust = norm(sanctuary_b())
    times = scatter_times(1.5, per_sec, seed, density=lambda p: np.sin(np.pi * p) ** 1.5 + 0.05, start=0.05)
    sparkle = base.out(tinkles(times, octave=octave, seed=seed + 1, spread_db=9.0))
    return s.mix((gust, 0.75, 0.0), (norm(sparkle), gain, 0.0))


def sanctuary_light() -> np.ndarray:
    """Take B's canopy gust with sparse tinkles following its swell."""
    return sanctuary_gust_tinkle(9.0, TINKLE_OCTAVE, 1601, 0.6)


def sanctuary_dense() -> np.ndarray:
    """Take B's gust with a dense shimmer of tinkles riding it."""
    return sanctuary_gust_tinkle(30.0, TINKLE_OCTAVE, 1611, 0.7)


def sanctuary_low() -> np.ndarray:
    """Take B's gust with tinkles an octave lower, rounder and fewer."""
    return sanctuary_gust_tinkle(14.0, TINKLE_OCTAVE - 1, 1621, 0.65)


# --- Earth: a rumble, not a fire; a bassier settle ---------------------------

EARTH_RATE = 6000.0      # the DAC played slow: dark and crunchy


def earth_rumble(seconds: float, seed: int, cut=(150.0, 400.0), sway_hz: float = 9.0) -> np.ndarray:
    """Ground moving: very low noise whose top end opens as it rises and
    whose level lurches unevenly. 48 kHz."""
    raw = s.noise(seconds, seed)
    lo = norm(s.lowpass(raw, cut[0], order=4))
    hi = norm(s.lowpass(raw, cut[1], order=4))
    p = np.linspace(0.0, 1.0, len(raw))
    x = lo * (1.0 - p) + hi * p
    sway = base.breath(seconds, sway_hz, seed + 1)
    return s.drive(norm(x * (0.45 + 0.55 * sway)), 2.0)


def clods(times, seed: int, gain: float = 0.7) -> list:
    """Big pieces of earth knocking, chip-rate layers at their times."""
    out = []
    for i, t in enumerate(times):
        c = thud(0.2, cut_hz=450.0, half_life=0.025, sub=0.15, start_hz=120.0, end_hz=60.0, seed=seed + i, drive=1.6)
        out.append((dac(c, EARTH_RATE) * gain, t))
    return out


def rise_earth() -> np.ndarray:
    """Earth rumbling up: a deep rumble that swells and opens as the wall
    climbs, lurching unevenly, a few heavy clods knocking. No high grit."""
    sec = RISE_SEC
    body = earth_rumble(sec, 1701) * swell_env(sec, 0.6, 0.06, power=1.2)
    return chip(sec + 0.15, dac(body, EARTH_RATE), *clods((0.2, 0.42, 0.6), 1702, 0.5))


def rise_lurch() -> np.ndarray:
    """Earth lurching up: the same deep rumble with four heavy shoves in
    it (the stepped climb you picked in the Stone Wall demo)."""
    sec = RISE_SEC
    body = earth_rumble(sec, 1711) * swell_env(sec, 0.55, 0.06, power=1.0)
    shoves = []
    for i, t in enumerate((0.02, 0.2, 0.36, 0.52)):
        j = thud(0.22, cut_hz=380.0, half_life=0.035, sub=0.2, start_hz=100.0, end_hz=45.0, seed=1712 + i, drive=1.8)
        shoves.append((dac(j, EARTH_RATE) * (0.55 + 0.12 * i), t))
    return chip(sec + 0.15, dac(body, EARTH_RATE) * 0.8, *shoves)


def rise_grind() -> np.ndarray:
    """Stone grinding up through earth: the deep rumble with a low,
    juddering scrape of rock on rock rising inside it."""
    sec = RISE_SEC
    body = earth_rumble(sec, 1721, cut=(130.0, 320.0)) * swell_env(sec, 0.6, 0.06, power=1.2)
    judder = base.breath(sec, 30.0, 1722) ** 2
    scrape = norm(s.bandpass(s.noise(sec, 1723), 180.0, 700.0)) * judder * swell_env(sec, 0.55, 0.05, power=1.0)
    return chip(sec + 0.15, dac(body, EARTH_RATE), dac(s.drive(norm(scrape), 2.5), EARTH_RATE) * 0.6)


def deep_thud(seed: int, cut_hz: float = 320.0, sub: float = 0.38, half_life: float = 0.05) -> np.ndarray:
    return thud(0.5, cut_hz=cut_hz, half_life=half_life, sub=sub, start_hz=90.0, end_hz=30.0, seed=seed, drive=2.5)


def settle_deep() -> np.ndarray:
    """Take A, deeper: the thud darker and heavier, more low weight under
    it, the same dust."""
    hit = dac(deep_thud(1801), EARTH_RATE)
    dust = dac(air(0.4, 2500.0, 0.03, 0.08, 1802, low_hz=600.0), AIR_RATE) * 0.1
    return chip(0.6, hit, (dust, 0.06))


def settle_deep_bloom() -> np.ndarray:
    """Take A, deeper, with a short low bloom of air and rumble after the
    hit, so the weight hangs a moment."""
    hit = dac(deep_thud(1811), EARTH_RATE)
    bloom = dac(air(0.5, 250.0, 0.02, 0.1, 1812), AIR_RATE) * 0.45
    low = rumble(20, 8, 15, seed=1813) * 0.25
    return chip(0.7, hit, (bloom, 0.03), (low, 0.02))


def settle_double() -> np.ndarray:
    """Take A, deeper, in two layers: the thud, and a lower boom 30 ms
    behind it, 'dmmf'."""
    hit = dac(deep_thud(1821, cut_hz=480.0, sub=0.3, half_life=0.035), EARTH_RATE)
    boom = dac(thud(0.5, cut_hz=220.0, half_life=0.07, sub=0.3, start_hz=70.0, end_hz=28.0, seed=1822, drive=3.0), EARTH_RATE) * 0.7
    return chip(0.65, hit, (boom, 0.03))


# --- Director's review (2026-11-28) -----------------------------------------
# The director measured the unheard round-2 picks against the theme:
#   * the shield family was a sustained pure tone (clarity 1.0), the cast
#     the loudest sound in the set, and cast and form two long hums 0.08 s
#     apart;
#   * Mend and heal leaned on in-key tinkles (clarity 0.65, 0.95), and the
#     heal peaked at 0.9 s although health returns when it lands;
#   * Stasis is instant (SpellRegistry: delivery "instant", the freeze in
#     onImpact), but its lock came 0.7 s in.
# The revisions: the ward is texture (pressed air, the picked shield_block
# clank as the shell, a faint shimmer held), with the hum the user asked for
# kept underneath at WARD_HUM_DB; the cast is the event and the form a short
# accent; tinkles are buried at TINKLE_BURY under the physical layers; the
# heal and the Stasis lock land at the start. The audible-hum family the
# user asked for is kept as take b, with the overlap and level fixed.

WARD_HUM_DB = -12.0            # the hum under the ward's texture
WARD_FRONT_GAIN = 2.0          # the cast's frost crack over its body: sets the peak, lowers RMS
TINKLE_BURY = 0.22             # tinkles under the physical layers (about -13 dB)
HEAL_LAND_SEC = 0.06           # when the heal's thump lands
STASIS_LOCK_SEC = 0.05         # Stasis locks this soon after the cast starts
HELD_LOW_BAND = (250.0, 800.0)
HELD_TOP_BAND = (2500.0, 6500.0)


def db(gain_db: float) -> float:
    return 10.0 ** (gain_db / 20.0)


def woom(seconds: float, seed: int, attack: float = 0.12, half_life: float = 0.1) -> np.ndarray:
    """Air pressed outward round the caster: low noise whose band opens
    from 220 to 600 Hz as it swells, 'wooom'. 48 kHz."""
    centre = s.glide(220.0, 600.0, seconds, curve=1.6)
    x = norm(s.swept_bandpass(s.noise(seconds, seed), centre, q=1.2)) * swell_env(seconds, attack, half_life, power=1.3)
    return s.drive(norm(x), 1.6)


def shell_accent(seed: int = 1901) -> np.ndarray:
    """The shell locking: the picked shield_block clank's recipe an octave
    down and shorter, with a few crackles. Chip-rate."""
    clank = ice_clank(LOW_ICE_HZ, frames_on=2, ring=0.08, dull_to=30.0)
    front = base.noise_burst([0, 3, 8, 15], shift_hz=ym.frames([12000.0, 8000.0, 5000.0, 3000.0]), seed=seed) * 0.45
    settle = base.dac_crackle(0.12, 40.0, seed=seed + 1) * base.ICE_CRACKLE_GAIN * 0.4
    return ym.place(ym.chip_samples(0.22), clank, front, (settle, 2 * F))


def ward_cast() -> np.ndarray:
    """Shield cast, the event: a frost crack, cold air pressed outward
    ('wooom'), the shell's surface crackling into being, the hum faint
    underneath."""
    sec = 0.55
    front = dac(snap(0.03, GLASS_BAND, 1911, half_life=0.004), GLASS_RATE) * WARD_FRONT_GAIN
    body = dac(woom(sec, 1912), AIR_RATE)
    n = 12
    hum_part = hum(_curve(HUM_HZ * np.geomspace(0.8, 1.0, n)), sec, 0.3, _curve(np.linspace(30.0, 0.0, n)), 12.0) * db(WARD_HUM_DB)
    sheen = dac(grains(0.4, 60.0, GLASS_BAND, 1913, length=(0.002, 0.004), density=lambda p: 0.3 + p,
                       level=lambda p: np.sin(np.pi * p)), GLASS_RATE) * 0.35
    return chip(sec + 0.05, front, body, hum_part, (sheen, 0.05))


def ward_form() -> np.ndarray:
    """Shield forms, the accent: the shell locking, 0.22 s."""
    return chip(0.25, shell_accent())


def ward_held_loop() -> np.ndarray:
    """While the shield is up: a faint shimmer of filtered noise, a low
    breath of air, the hum faint underneath. A 2 s loop."""
    total = HUM_LOOP_PREROLL_SEC + HUM_LOOP_SEC + HUM_SEAM_SEC
    n = s.n_samples(total)
    low = norm(s.bandpass(s.noise(total, 1921), *HELD_LOW_BAND)) * (0.6 + 0.4 * base.breath(total, 1.2, 1922)[:n])
    top = norm(s.bandpass(s.noise(total, 1923), *HELD_TOP_BAND)) * (0.5 + 0.5 * base.breath(total, 3.0, 1924)[:n])
    texture = 0.8 * low + 0.25 * top
    body, seam = s.n_samples(HUM_LOOP_SEC), s.n_samples(HUM_SEAM_SEC)
    pre = s.n_samples(HUM_LOOP_PREROLL_SEC)
    texture = texture[pre:]
    # Noise is uncorrelated with itself 2 s later: equal-power cross-fade.
    fade = np.linspace(0.0, np.pi / 2.0, seam)
    tex = texture[:body].copy()
    tex[:seam] = texture[:seam] * np.sin(fade) + texture[body:body + seam] * np.cos(fade)
    tone = norm(shield_hum_loop())   # in phase every 2 s, cross-faded linearly inside
    return norm(tex) + tone * db(WARD_HUM_DB)


def ward_break() -> np.ndarray:
    """Shield breaks: the shell shattering, its pressed air let out in a
    low whumpf, shards falling, the hum dropping away faintly under it."""
    crack = dac(snap(0.05, GLASS_BAND, 1931, half_life=0.008), GLASS_RATE) * 0.6
    clank = ice_clank(LOW_ICE_HZ, frames_on=2, ring=0.1, dull_to=24.0, gain_db=-4.0)
    whumpf = dac(thud(0.4, cut_hz=600.0, half_life=0.06, sub=0.2, start_hz=110.0, end_hz=40.0, seed=1932, drive=1.8), STONE_RATE)
    n = 18
    drop = hum(_curve(HUM_HZ * np.geomspace(1.0, 0.5, n)), 0.45, n * F, _curve(np.linspace(0.0, 30.0, n)), 6.0) * db(WARD_HUM_DB)
    shards = base.dac_crackle(0.5, 100.0, seed=1933) * base.ICE_CRACKLE_GAIN * 1.2
    return chip(0.7, crack, clank, whumpf, drop, (shards, F))


# The audible-hum family (take b): the user's "wooom humming in", with the
# overlap and level fixed. The cast is the event and short; the form is the
# same accent as take a.

def hum_cast_event() -> np.ndarray:
    """Hum cast, shortened: a frost crack, then the hum swelling up into
    its pitch and gone by 0.55 s."""
    n = 12
    pitch = _curve(HUM_HZ * np.geomspace(0.8, 1.0, n))
    level = _curve(np.linspace(30.0, 0.0, n))
    front = dac(snap(0.03, GLASS_BAND, 1941, half_life=0.004), GLASS_RATE) * WARD_FRONT_GAIN
    return chip(0.6, front, hum(pitch, 0.6, 0.25, level, 10.0) * db(-1.0))


# --- Life, revised: physical first, tinkles buried ---------------------------

def mend_buried() -> np.ndarray:
    """Mend: the leaf rustle (round-1 take B), with tinkles buried under it
    as a faint glint."""
    leaves = mend_b()
    sparkle = base.out(tinkles(scatter_times(0.4, 22.0, 1501, density=lambda p: 0.4 + 1.2 * p), seed=1502))
    return s.mix(norm(leaves), (norm(sparkle), TINKLE_BURY, 0.02))


def heal_landing() -> np.ndarray:
    """Heal lands: a short gust drawn in and a soft thump at 0.06 s, warmth
    falling away after, a faint glint of tinkles in the tail."""
    gust = norm(s.swept_bandpass(s.noise(0.1, 1951), s.glide(2500.0, 700.0, 0.1), q=1.4)) * swell_env(0.1, 0.08, 0.02)
    land = thud(0.15, cut_hz=500.0, half_life=0.02, sub=0.2, start_hz=140.0, end_hz=70.0, seed=1952, drive=1.3)
    after = air(0.7, 700.0, 0.01, 0.12, 1953, low_hz=120.0)
    body = chip(0.85, dac(gust, GLASS_RATE) * 0.7, (dac(land, STONE_RATE), HEAL_LAND_SEC),
                (dac(after, AIR_RATE) * 1.0, HEAL_LAND_SEC))
    times = scatter_times(0.6, 12.0, 1954, density=lambda p: 1.0 - 0.8 * p, start=0.12)
    sparkle = base.out(tinkles(times, seed=1955, gain_db=-6.0))
    return s.mix(norm(body), (norm(sparkle), TINKLE_BURY, 0.0))


# --- Stasis, revised: the lock lands with the cast ---------------------------

def stasis_lock() -> np.ndarray:
    """Stasis: a two-frame cold rush, the whole mass locking in one deep
    crack at 0.05 s, then the ice groaning and crystallising as the tail."""
    rush = base.noise_burst([8, 3], shift_hz=ym.frames([4000.0, 12000.0]), seed=1961) * 0.5
    lock = STASIS_LOCK_SEC
    boom = ice_boom(1962)
    strike = base.ice_hit(LOW_ICE_HZ / 2.0, gain_db=-3.0)
    tail = 1.3
    g = dac(groan(tail, 1963, rate=(50.0, 20.0), level=lambda p: (1.0 - p) ** 1.2 * 0.8), STONE_RATE) * 0.55
    grow = dac(grains(tail, 70.0, GLASS_BAND, 1964, length=(0.002, 0.005), density=lambda p: 1.5 * (1.0 - p) + 0.1,
                      level=lambda p: (1.0 - p) ** 0.8), GLASS_RATE) * 0.45
    return base.hot(chip(lock + tail + 0.1, rush, (boom, lock), (strike, lock), (g, lock + 0.06), (grow, lock + 2 * F)), 1.6)


# --- Old against new, for the user ------------------------------------------

REVIEW_GAP_SEC = 0.6


def review_pair(old: np.ndarray, new: np.ndarray) -> np.ndarray:
    old, new = norm(old), norm(new)
    return s.mix((old, 1.0, 0.0), (new, 1.0, len(old) / SAMPLE_RATE + REVIEW_GAP_SEC))


def review_shield(cast, form) -> np.ndarray:
    return review_pair(demo_shield(hum_cast_a, hum_form_a), demo_shield(cast, form))


def review_mend() -> np.ndarray:
    return review_pair(demo_mend(mend_rustle_tinkle, heal_gust_tinkle), demo_mend(mend_buried, heal_landing))


# --- Demos: the cues in the context they play in -----------------------------

def volley(block) -> np.ndarray:
    hit = norm(block())
    return s.mix(*[at(hit, i * VOLLEY_STAGGER_SEC) for i in range(VOLLEY_SHOTS)])


def crack_moments(seed: int = 1200) -> list[float]:
    """When the Stone Wall's cracks fire, from BarrierCrumbleController's
    schedule: evenly spread over 85% of the lead window, jittered, eased in."""
    rng = np.random.default_rng(seed)
    p = np.linspace(0.0, CRACK_STAGGER_SPAN, CRACK_COUNT) + rng.uniform(-CRACK_TIMING_JITTER, CRACK_TIMING_JITTER, CRACK_COUNT)
    p = np.sort(np.clip(p, 0.0, 0.95))
    t = CRACK_LEAD_SEC * p ** (1.0 / CRACK_PROGRESS_EXPONENT)
    # One sound per frame at most.
    out, last = [], -1.0
    for v in t:
        if v - last >= F:
            out.append(float(v))
            last = v
    return out


def crumble(crack) -> np.ndarray:
    rng = np.random.default_rng(1201)
    one = norm(crack())
    layers = []
    for t in crack_moments():
        speed = rng.uniform(*CRACK_DEMO_SPEED)
        n = int(len(one) / speed)
        varied = np.interp(np.arange(n) * speed, np.arange(len(one)), one)
        layers.append(at(varied, t))
    return s.mix(*layers)


def sequence(*parts) -> np.ndarray:
    """(builder, gain, start) triples, each part normalised first."""
    return s.mix(*[(norm(b()), g, t) for b, g, t in parts])


def demo_frost(freeze):
    return sequence((base.frost_blast, 1.0, 0.0), (freeze, 0.85, FROST_IMPACT_AFTER_CAST_SEC))


def demo_shield(cast, form):
    return sequence((cast, 1.0, 0.0), (form, 0.8, SHIELD_CONFIRM_SEC))


def demo_mend(cast, heal):
    return sequence((cast, 1.0, 0.0), (heal, 0.75, SHIELD_CONFIRM_SEC))


def demo_sanctuary(cast, heal, form):
    return sequence((cast, 1.0, 0.0), (heal, 0.6, SHIELD_CONFIRM_SEC), (form, 0.6, SHIELD_CONFIRM_SEC))


def demo_stone_wall(cast, rise, settle):
    rumble_at = WALL_RUMBLE_AFTER_CAST_SEC
    return sequence((cast, 0.8, 0.0), (rise, 0.65, rumble_at), (settle, 0.9, rumble_at + WALL_SETTLE_SEC))


SHIELD_LIFE_HOLD_SEC = 1.6    # how long the demo holds the shield up
SHIELD_LIFE_HITS = (1.9, 2.4)  # shots landing on it before the break


def demo_shield_life(cast, form, brk, held_loop):
    """A shield's whole life: cast, form, the loop held, two shots, the
    break on the second."""
    loop = norm(held_loop())
    start = SHIELD_CONFIRM_SEC + 0.6
    held = np.tile(loop, 2)[: s.n_samples(SHIELD_LIFE_HOLD_SEC + 0.6)]
    held[: s.n_samples(0.3)] *= np.linspace(0.0, 1.0, s.n_samples(0.3))
    end = s.n_samples(SHIELD_LIFE_HITS[1] - start)
    held = held[:end]
    held[-s.n_samples(0.05):] *= np.linspace(1.0, 0.0, s.n_samples(0.05))
    return s.mix((norm(cast()), 1.0, 0.0), (norm(form()), 0.8, SHIELD_CONFIRM_SEC), (held, 0.45, start),
                 (norm(block_a()), 0.8, SHIELD_LIFE_HITS[0]), (norm(brk()), 1.0, SHIELD_LIFE_HITS[1]))


# --- The sheet ---------------------------------------------------------------

def _cue(cid, label, group, band, note, **extra):
    return {"id": cid, "label": label, "group": group, "band": band, "note": note, **extra}


ICE = "Ice and wards (blue)"
LIFE = "Life (green)"
EARTH = "Earth: Stone Wall and breakable walls"
DEMO = "In context (demos, not uploaded)"

SHEET = [
    _cue("impact_freeze", "Freeze lands (Frost Nip, Stasis, Wizard bolt)", ICE, "gameplay",
         "Round 1: you picked B alone but A in the Frost Nip demo. A: the Frost Nip take A shatter. "
         "B: frost creeping (crackle thickening), locking with the strike. Which one?"),
    _cue("cast_blue_t2", "Shield cast (blue T2)", ICE, "gameplay",
         "Director's review: the cast is the event, the form a short accent. A (default): a frost crack, cold air pressed outward ('wooom'), the shell crackling into being, the hum faint underneath. B: the audible hum you asked for, shortened and quieter, on the same frost crack."),
    _cue("impact_shield", "Shield forms", ICE, "gameplay",
         "Director's review: a short accent now (0.22 s), the shell locking: the picked shield_block clank's recipe an octave down. Same for A and B."),
    _cue("shield_hum", "Shield held up (loop)", ICE, "loop",
         "Director's review. A (default): a faint shimmer of filtered noise and a low breath of air, the hum faint underneath. B: the round-2 hum loop. A 2 s loop; the game cannot play loops yet.",
         loop=True),
    _cue("shield_block", "A shot dies on a shield", ICE, "gameplay",
         "Picked in round 1: take A, the short high ice clank."),
    _cue("shield_break", "Shield breaks", ICE, "gameplay",
         "Director's review. A (default): the shell shattering, a low whumpf of air let out, shards, the hum dropping away faintly. B: round-2 A, the hum dropping an octave as it dies."),
    _cue("cast_blue_t3", "Stasis cast (blue T3)", ICE, "gameplay",
         "Director's review: Stasis is instant, so the lock lands at 0.05 s and the glacier groans and crystallises after it as the tail."),
    _cue("cast_green_t1", "Mend cast (green T1)", LIFE, "gameplay",
         "Director's review: the leaf rustle (round-1 B) with the tinkles buried under it as a faint glint."),
    _cue("impact_heal", "Heal lands", LIFE, "gameplay",
         "Director's review: lands at once (a short gust in, a soft thump at 0.06 s), warmth falling away after, tinkles buried in the tail."),
    _cue("cast_green_t3", "Sanctuary cast (green T3)", LIFE, "gameplay",
         "Round 2, take B's canopy gust layered with tinkles. A: sparse tinkles. B: a dense shimmer of tinkles. C: tinkles an octave lower, rounder and fewer."),
    _cue("cast_green_t2", "Stone Wall cast (green T2)", EARTH, "gameplay",
         "Picked in round 1: take B, a gritty scrape heaving upward."),
    _cue("wall_rise_rumble", "Stone Wall rising", EARTH, "gameplay",
         "Round 2, earth rumbling up, not fire (the pattering grit and hiss are gone). A: a deep rumble swelling and opening as it climbs, a few clods. "
         "B: the same rumble with four heavy shoves (the stepped rise you liked in the demo). C: the rumble with a low juddering scrape of rock on rock."),
    _cue("impact_wall", "Stone Wall settles", EARTH, "gameplay",
         "Round 2, take A made bassier. A: darker and heavier. B: the same, with a short low bloom of air and rumble after. C: two layers, the thud and a lower boom 30 ms behind it."),
    _cue("wall_crack", "Wall cracks (Stone Wall and breakable walls)", EARTH, "gameplay",
         "Round 1: you picked C alone but B in the crumbling demo. B: a brief grind of strain, then the snap. C: the snap and a little grit trickling. Which one?"),
    _cue("wall_break", "Wall breaks (breakable walls)", EARTH, "gameplay",
         "Picked in round 1: take B, crack, crumble, then four heavy chunks landing."),
    _cue("review_shield", "Director's review: shield cast + form, old then new", DEMO, "gameplay",
         "The round-2 pair (two long hums 0.08 s apart), a gap, then this take's revised pair.", demo=True),
    _cue("review_mend", "Director's review: Mend + heal, old then new", DEMO, "gameplay",
         "The round-2 pair (tinkles up front, heal peaking at 0.9 s), a gap, then the revised pair.", demo=True),
    _cue("demo_frost_nip", "Frost Nip: chosen cast, then the freeze landing", DEMO, "gameplay",
         "The chosen Frost Nip cast (blast) with freeze A or B 0.15 s later. In the game the fire lane's damage hit also lands then.",
         demo=True),
    _cue("demo_shield_life", "Shield: whole life (cast, form, held, a shot, break)", DEMO, "gameplay",
         "The take's cast and form, the hum loop held, a shot blocked (picked clank) and the take's break on the second shot.",
         demo=True),
    _cue("demo_shield", "Shield: cast, then the shell forming", DEMO, "gameplay",
         "The same take's cast, then impact_shield one round trip (0.08 s) later.", demo=True),
    _cue("demo_shield_hum", "Shield hum loop, three times", DEMO, "loop",
         "The loop played three times in a row, to hear the seam.", demo=True),
    _cue("demo_shield_block", "Shield under a volley (6 shots, 0.12 s apart)", DEMO, "gameplay",
         "The picked clank at the volley stagger.", demo=True),
    _cue("demo_mend", "Mend: cast, then the heal landing", DEMO, "gameplay",
         "The same take's cast, then impact_heal 0.08 s later.", demo=True),
    _cue("demo_sanctuary", "Sanctuary: cast, heal and shell together", DEMO, "gameplay",
         "The same take's Sanctuary cast, impact_heal and impact_shield (the game fires both 0.08 s in).", demo=True),
    _cue("demo_stone_wall", "Stone Wall: cast, rise, settle", DEMO, "gameplay",
         "The picked cast (B), then the take's rumble, and its settle at 0.73 s into the rise.", demo=True),
    _cue("demo_wall_crack", "Stone Wall crumbling (12 cracks in 2.1 s)", DEMO, "gameplay",
         "wall_crack B or C on the Stone Wall's crack schedule, each at a random speed 0.9-1.1.", demo=True),
]

# Round 1 takes that were picked keep their column; their code must not change.
_TAKE_BUILDERS = {
    "a": dict(impact_freeze=freeze_a, cast_blue_t2=ward_cast, impact_shield=ward_form, shield_hum=ward_held_loop,
              shield_block=block_a, shield_break=ward_break, cast_blue_t3=stasis_lock,
              cast_green_t1=mend_buried, impact_heal=heal_landing, cast_green_t3=sanctuary_light,
              wall_rise_rumble=rise_earth, impact_wall=settle_deep),
    "b": dict(impact_freeze=freeze_b, cast_blue_t2=hum_cast_event, impact_shield=ward_form, shield_hum=shield_hum_loop,
              shield_break=hum_break_a, cast_green_t3=sanctuary_dense, cast_green_t2=wall_cast_b,
              wall_rise_rumble=rise_lurch, impact_wall=settle_deep_bloom, wall_crack=crack_b, wall_break=break_b),
    "c": dict(cast_green_t3=sanctuary_low, wall_rise_rumble=rise_grind, impact_wall=settle_double, wall_crack=crack_c),
}


def _with_demos(b: dict) -> dict:
    cues = dict(b)
    has = lambda *ids: all(i in b for i in ids)  # noqa: E731
    if has("impact_freeze"):
        cues["demo_frost_nip"] = lambda: demo_frost(b["impact_freeze"])
    if has("cast_blue_t2", "impact_shield"):
        cues["review_shield"] = lambda: review_shield(b["cast_blue_t2"], b["impact_shield"])
        cues["demo_shield"] = lambda: demo_shield(b["cast_blue_t2"], b["impact_shield"])
    if has("cast_blue_t2", "impact_shield", "shield_break", "shield_hum"):
        cues["demo_shield_life"] = lambda: demo_shield_life(b["cast_blue_t2"], b["impact_shield"], b["shield_break"], b["shield_hum"])
        cues["demo_shield_hum"] = lambda: np.concatenate([norm(b["shield_hum"]())] * 3)
    if has("shield_block"):
        cues["demo_shield_block"] = lambda: volley(b["shield_block"])
    if has("cast_green_t1", "impact_heal"):
        cues["review_mend"] = review_mend
        cues["demo_mend"] = lambda: demo_mend(b["cast_green_t1"], b["impact_heal"])
    if has("cast_green_t3", "impact_shield") or has("cast_green_t3"):
        heal = b.get("impact_heal", heal_landing)
        form = b.get("impact_shield", ward_form)
        cues["demo_sanctuary"] = lambda: demo_sanctuary(b["cast_green_t3"], heal, form)
    if has("wall_rise_rumble", "impact_wall"):
        cues["demo_stone_wall"] = lambda: demo_stone_wall(wall_cast_b, b["wall_rise_rumble"], b["impact_wall"])
    if has("wall_crack"):
        cues["demo_wall_crack"] = lambda: crumble(b["wall_crack"])
    return cues


CUES: dict[str, dict] = {take["id"]: _with_demos(_TAKE_BUILDERS[take["id"]]) for take in TAKES}


# --- Decisions (user, 2026-11-28) -------------------------------------------
# Round 1 picks by ear: impact_freeze b, shield_block a, cast_green_t2 b,
# wall_crack c, wall_break b. impact_buff: "this doesnt need a sound i think,
# but we can keep the soundhook in" (deferred: no file, hook kept).
# Round 2: "make your best recommendation, i want to hear the sounds in game
# first", so the rest are the lane's recommendation, unheard by anyone, to be
# judged in the game.
# Director's review, same day: the seven lane picks were revised in place
# (same take ids): cast_blue_t2, impact_shield, shield_hum, shield_break,
# cast_blue_t3, cast_green_t1, impact_heal. Still unheard by the user. Take b
# of the shield family keeps the audible hum the user asked for, as a swap.
CHOSEN = {
    "impact_freeze": "b",
    "cast_blue_t2": "a",
    "impact_shield": "a",
    "shield_hum": "a",
    "shield_block": "a",
    "shield_break": "a",
    "cast_blue_t3": "a",
    "cast_green_t1": "a",
    "impact_heal": "a",
    "cast_green_t3": "a",
    "cast_green_t2": "b",
    "wall_rise_rumble": "b",
    "impact_wall": "a",
    "wall_crack": "c",
    "wall_break": "b",
}
DEFERRED = {"impact_buff": "no sound wanted for now; keep the hook (user, 2026-11-28)"}
