"""Production lane: fire, and the player's own movement and refusals.

Owned by the "Audio: fire lane" session (spawned 2026-11-28). It replaces the
stand-in sounds the game plays today. Rules: wiki/design/AudioDirection.md
(read it first); method: docs/agents/audio-sfx.md.

    python tools/sfx/render.py --lane fire
    python tools/sfx/lint.py --dir build/sfx/lanes/fire
    python tools/sfx/audition.py --dir build/sfx/lanes/fire --out build/sfx/lanes/fire/audition.html

Each cue id is the VfxConfig.EFFECTS id (or the game hook) it replaces.
Already chosen and frozen (do not change; listen to them for the family
sound): the Fireball explosion (pilot_md impact_damage_t2) and the Burning
loop (pilot_md burn_roar). Reuse helpers from pilot_md / collect_lab by
import; never edit those files.

The fire family, first pass (2026-11-28). The chosen explosion and burn are
noise-led: band-passed noise through the DAC, PSG noise, crackle pops, with
any tone only as weight underneath. Every fire cue here is built from those
same parts, so the family shares one grain:
  * air   - low-passed noise through the DAC that swells and falls (a "whoof")
  * roar  - pilot_md._fire_raw, the chosen burn's own recipe, enveloped
  * hiss  - PSG noise whose clock steps per frame (ignition, sizzle)
  * pops  - short band-passed noise clicks (crackle, debris)
Movement and the teleporter are air and ground only. The fizzle is the one
tonal cue (progress layer), in key.
"""

from __future__ import annotations

import numpy as np

import synth as s
import ym
from cues import pilot_md as base  # read-only: patches and helpers
from kit import BAND_GAIN_DB, PEAK_DBFS, SAMPLE_RATE, scale_hz, semitones
from ym import Op, Patch

LANE = {"id": "fire", "label": "Fire, movement and refusals"}

# At most three takes per cue, each different from the others.
TAKES = [
    {"id": "a", "label": "Take A"},
    {"id": "b", "label": "Take B"},
    {"id": "c", "label": "Take C"},
]


def _cue(cid, label, group, band, note, **extra):
    return {"id": cid, "label": label, "group": group, "band": band, "note": note, **extra}


FIRE = "Fire spells"
MOVE = "Player movement and refusals"
DEMO = "Demos: fast repeats and spell sequences (listen to these, not only the single takes)"

SHEET = [
    _cue("cast_red_t1", "Firebolt cast (red T1)", FIRE, "gameplay",
         "World layer. The tap-level red cast leaving the hands. Short; the family's smallest. Frequent, so judge a fast demo."),
    _cue("projectile_red_t1", "Firebolt in flight (launch layer)", FIRE, "gameplay",
         "Plays once at launch on the moving bolt (no loop path). A quiet whoosh-crackle that reads as the bolt travelling."),
    _cue("impact_damage", "Damage hit (Firebolt, boss volley, Wizard bolt)", FIRE, "gameplay",
         "World layer. The generic 'you were hit' sound, shared by several sources: physical, no element colour, a clear peak."),
    _cue("cast_red_t2", "Fireball cast (red T2)", FIRE, "gameplay",
         "Bigger than Firebolt: body added. Must lead naturally into the chosen Fireball explosion."),
    _cue("projectile_red_t2", "Fireball in flight (launch layer)", FIRE, "gameplay",
         "Heavier than the Firebolt flight: a rolling roar."),
    _cue("cast_red_t3", "Inferno cast (red T3)", FIRE, "gameplay",
         "Top tier: a 3 s charge ends here. Sub weight and a tail; the biggest player cast."),
    _cue("impact_damage_t3", "Inferno eruption", FIRE, "gameplay",
         "Fire bursting up from the ground under the target. Bigger than the Fireball explosion, but a different shape (an eruption, not a blast). Also stands in for the scramble seeker burst."),
    _cue("fizzle", "Refused (bad word, no mana, mind full, cancel)", MOVE, "ui",
         "PROGRESS layer: the one tonal cue in this lane. A soft deflated 'no', never a harsh buzzer. Heard very often by beginners."),
    _cue("dash", "Dash", MOVE, "gameplay",
         "World layer. A quick body whoosh. Today a place-file Sound (ReplicatedStorage.Shared.DashSounds.Dash)."),
    _cue("roll", "Roll", MOVE, "gameplay",
         "World layer. A tumble: a whoosh with a soft landing scuff."),
    _cue("arena_depart", "Arena teleporter: depart", MOVE, "gameplay",
         "World layer. Stepping on the ready-room pad. Today it borrows impact_shield; it will get its own effect entry."),
    _cue("arena_arrive", "Arena teleporter: arrive", MOVE, "gameplay",
         "World layer. Landing on the island; pairs with depart. Today it borrows impact_buff."),
    # Demo rows: not uploaded. Each plays the take in its column the way the
    # game would, at the game's current volume and pitch jitter.
    _cue("demo_cast_red_t1", "Demo: four Firebolt casts, 0.3 s apart", DEMO, "gameplay",
         "Fast casting. Each copy at a random pitch in the game's 0.95-1.10 range.", demo=True),
    _cue("demo_impact_damage", "Demo: four hits, 0.3 s apart", DEMO, "gameplay",
         "A volley or a fast exchange. Pitch jitter 0.92-1.08, as in the game.", demo=True),
    _cue("demo_fizzle", "Demo: four refusals, 0.3 s apart", DEMO, "ui",
         "A beginner mashing a bad word. Played at native pitch (see the lane report: the game plays the fizzle at 0.55 speed today).", demo=True),
    _cue("demo_dash_roll", "Demo: roll, roll, dash, roll at the game's cadence", DEMO, "gameplay",
         "Roll can repeat every 0.55 s; dash is once per jump.", demo=True),
    _cue("demo_firebolt", "Sequence: Firebolt cast + flight, hit 0.4 s later, twice", DEMO, "gameplay",
         "The three Firebolt sounds together at the game's volumes (cast 0.8, flight 0.35, hit 0.85).", demo=True),
    _cue("demo_fireball", "Sequence: Fireball cast + flight into the chosen explosion", DEMO, "gameplay",
         "Explosion (frozen, chosen) lands 0.55 s after the cast. Cast 1.0, flight 0.45, explosion 1.0.", demo=True),
    _cue("demo_inferno", "Sequence: Inferno cast and eruption together", DEMO, "gameplay",
         "Inferno is instant: the eruption lands about 50 ms after the cast.", demo=True),
    _cue("demo_teleport", "Pair: depart, then arrive 0.6 s later", DEMO, "gameplay",
         "In the game both fire on the same frame at the two pads; spaced here so each can be heard.", demo=True),
]

SR = SAMPLE_RATE
FRAME = base.FRAME
TAKE_IDS = ("a", "b", "c")

# --- Lane primitives ----------------------------------------------------------
# 48 kHz shapes that end up on the chip: through the DAC (8-bit, held), or as
# PSG noise. Nothing reaches the output without going through ym.


def _norm(x: np.ndarray) -> np.ndarray:
    return x / max(1e-9, float(np.max(np.abs(x))))


def _ar(sec: float, attack: float, half_life: float, curve: float = 1.0) -> np.ndarray:
    """0..1 envelope at 48 kHz: rise over `attack` (curve > 1 swells in
    slowly), then an exponential fall with `half_life`."""
    t = s.times(sec)
    rise = np.clip(t / max(attack, 1e-4), 0.0, 1.0) ** curve
    return rise * 0.5 ** (np.maximum(t - attack, 0.0) / half_life)


def _chip_env(sec: float, attack: float, half_life: float, curve: float = 1.0) -> np.ndarray:
    """The same envelope on the chip-rate time axis."""
    t = np.arange(ym.chip_samples(sec)) / ym.CHIP_RATE
    rise = np.clip(t / max(attack, 1e-4), 0.0, 1.0) ** curve
    return rise * 0.5 ** (np.maximum(t - attack, 0.0) / half_life)


def _shaped(sec: float, seed: int, lo: float | None = None, hi: float | None = None) -> np.ndarray:
    x = s.noise(sec, seed)
    if lo and hi:
        x = s.bandpass(x, lo, hi)
    elif hi:
        x = s.lowpass(x, hi)
    elif lo:
        x = s.highpass(x, lo)
    return _norm(x)


def _dac(x: np.ndarray, rate: float) -> np.ndarray:
    return ym.dac_sample(_norm(x), SR, rate)


def air(sec: float, seed: int, env: np.ndarray, lo: float | None = None, hi: float | None = None,
        rate: float = 10000.0) -> np.ndarray:
    """Filtered noise under an envelope, through the DAC."""
    return _dac(_shaped(sec, seed, lo, hi) * env[: s.n_samples(sec)], rate)


def swept(sec: float, path_hz, seed: int, q: float = 1.5) -> np.ndarray:
    """Noise through a band-pass whose centre follows `path_hz` (a list of
    points spread evenly over the length), moved once per driver frame.
    A rising centre reads as something drawn up or approaching; falling as
    passing by or settling."""
    n = s.n_samples(sec)
    pts = np.asarray(path_hz, dtype=float)
    centre = np.exp(np.interp(np.linspace(0.0, 1.0, n), np.linspace(0.0, 1.0, len(pts)), np.log(pts)))
    blocks = max(2, int(round(sec * ym.FRAME_HZ)))
    return _norm(s.swept_bandpass(s.noise(sec, seed), centre, q=q, blocks=blocks))


def pops(sec: float, at_sec, seed: int, sizes=None, lo: float = 1500.0, hi: float = 5000.0,
         rate: float = 12000.0) -> np.ndarray:
    """Crackle pops at fixed times (unlike pilot_md.crackles, which places
    them at random): each a few ms of band-passed noise, through the DAC."""
    rng = np.random.default_rng(seed)
    x = np.zeros(s.n_samples(sec))
    sizes = sizes if sizes is not None else [1.0] * len(at_sec)
    for t, size in zip(at_sec, sizes):
        length = rng.uniform(0.004, 0.011)
        centre = rng.uniform(lo, hi)
        p = s.bandpass(s.noise(length, int(rng.integers(1 << 30))), centre * 0.5, min(centre * 1.6, 9000.0))
        p = _norm(p * s.decay(length, length * 0.2, attack=0.0002))
        at = s.n_samples(t) - 1
        end = min(len(x), at + len(p))
        x[at:end] += p[: end - at] * size
    return ym.dac_sample(x, SR, rate)


def hiss(vols, path_hz, seed: int) -> np.ndarray:
    """PSG white noise, one volume per frame (0 loudest, 15 off), its clock
    following `path_hz` per frame: the console's ignition / sizzle."""
    vols = [int(v) for v in np.clip(np.round(vols), 0, 15)]
    pts = np.asarray(path_hz, dtype=float)
    per = np.exp(np.interp(np.linspace(0, 1, len(vols)), np.linspace(0, 1, len(pts)), np.log(pts)))
    return base.noise_burst(vols, shift_hz=ym.frames(per), seed=seed)


def rumble(vols, seed: int) -> np.ndarray:
    """The PSG's slowest noise clock: low ground rumble."""
    vols = [int(v) for v in np.clip(np.round(vols), 0, 15)]
    return base.noise_burst(vols, divider=base.RUMBLE_DIVIDER, seed=seed)


def hit(sec: float, cut_hz: float, half_life: float, drive: float, rate: float, seed: int,
        sub: float = 0.0, sub_hz: float = 120.0) -> np.ndarray:
    """A hit is a burst of muffled noise (not a tuned drum; the Fireball
    rounds showed a tuned note under a hit reads as a tom). `sub` adds a
    little falling sine weight under it."""
    burst = _shaped(sec, seed, hi=cut_hz) * s.decay(sec, half_life, attack=0.0008)
    if sub > 0:
        weight = s.sine(s.glide(sub_hz, 40.0, sec, curve=3.0)) * s.decay(sec, half_life * 1.4, attack=0.0008)
        burst = burst + sub * weight
    return _dac(s.drive(_norm(burst), drive), rate)


def roar(sec: float, seed: int, band, breath_hz: float, pops_per_sec: float, rumble_gain: float,
         env: np.ndarray) -> np.ndarray:
    """The chosen burn's own recipe (pilot_md._fire_raw: breathing band-passed
    roar, PSG bed, rumble, clustered crackles) under a one-shot envelope."""
    raw = base._fire_raw(sec, seed, band, breath_hz, 1.0, pops_per_sec, rumble_gain)
    n = min(len(raw), len(env))
    return raw[:n] * env[:n]


def mix(sec: float, *layers) -> np.ndarray:
    return ym.place(ym.chip_samples(sec), *layers)


def finish(chip: np.ndarray, drive: float = 1.0) -> np.ndarray:
    x = base.out(chip)
    return base.hot(x, drive) if drive > 1.0 else _norm(x)


# --- Firebolt cast (red T1) ------------------------------------------------------
# The smallest fire cue and the most frequent cast. Under 0.25 s, one idea each.

def bolt_cast_a() -> np.ndarray:
    """A, flick: a match-strike of hiss that falls in pitch, a small puff of
    air, three crackles."""
    flick = hiss([1, 0, 1, 3, 5, 7, 9, 12, 15], [11000.0, 2500.0], seed=201) * 0.5
    puff = air(0.16, 202, _ar(0.16, 0.006, 0.03), lo=300.0, hi=1600.0) * 0.7
    crackle = pops(0.16, [0.02, 0.05, 0.11], seed=203, sizes=[0.9, 0.6, 0.4]) * 0.6
    return finish(mix(0.22, flick, puff, crackle), 1.4)


def bolt_cast_b() -> np.ndarray:
    """B, whoof: gas catching. A low puff of air that swells for 15 ms and
    dies, with a tiny bright spark on its front."""
    spark = air(0.012, 211, _ar(0.012, 0.0005, 0.003), lo=3000.0, rate=16000.0) * 0.35
    puff = air(0.2, 212, _ar(0.2, 0.015, 0.045), hi=900.0, rate=8000.0)
    bed = base.noise_burst([4, 2, 3, 6, 10, 15], divider=1024, seed=213) * 0.2
    return finish(mix(0.24, spark, puff, bed), 1.3)


def bolt_cast_c() -> np.ndarray:
    """C, snap-crackle: the flame is the crackles: six pops in 0.14 s over a
    thin falling hiss."""
    crackle = pops(0.2, [0.0, 0.018, 0.045, 0.062, 0.1, 0.14], seed=221, sizes=[1.0, 0.6, 0.9, 0.5, 0.7, 0.4])
    thin = hiss([3, 2, 4, 6, 9, 12, 15], [9000.0, 4000.0], seed=222) * 0.3
    puff = air(0.12, 223, _ar(0.12, 0.004, 0.025), hi=600.0, rate=8000.0) * 0.4
    return finish(mix(0.22, crackle, thin, puff), 1.2)


# --- Firebolt flight (launch layer) ---------------------------------------------
# Rides on the moving bolt (CosmeticProjectile parents it to the projectile;
# it survives 1.6 s past impact). Layers under the cast at volume 0.35.

FLIGHT_T1_SEC = 0.8


def bolt_flight_a() -> np.ndarray:
    """A, whoosh: a band of air that sweeps down as it fades, with a few
    sparse crackles: something hot going past."""
    sec = FLIGHT_T1_SEC
    rush = _dac(swept(sec, [2600.0, 1400.0, 700.0], seed=231) * _ar(sec, 0.04, 0.15), 10000.0)
    crackle = pops(sec, [0.08, 0.21, 0.34, 0.52], seed=232, sizes=[0.5, 0.4, 0.3, 0.2]) * 0.4
    return finish(mix(sec, rush, crackle), 1.2)


def bolt_flight_b() -> np.ndarray:
    """B, sizzle: a thin PSG hiss that wavers unevenly and fades, with
    crackles thinning out behind it."""
    sec = FLIGHT_T1_SEC
    n = int(round(sec * ym.FRAME_HZ))
    waver = base.per_frame(base.breath(sec, 5.0, 241))[:n]
    fade = np.linspace(0.0, 1.0, n) ** 1.3
    vols = 2.0 + 3.0 * (1.0 - waver) + 10.0 * fade
    sizzle = hiss(vols, [9000.0, 6000.0], seed=242) * 0.4
    trail = base.crackles(sec, 22.0, seed=243) * _chip_env(sec, 0.01, 0.2) * 0.7
    return finish(mix(sec, sizzle, trail), 1.3)


def bolt_flight_c() -> np.ndarray:
    """C, flutter: a torch swung fast: mid air that flutters irregularly
    (no even pulse) and fades."""
    sec = FLIGHT_T1_SEC
    flutter = 0.3 + 0.7 * base.breath(sec, 22.0, 251)
    body = _shaped(sec, 252, lo=250.0, hi=1800.0) * flutter * _ar(sec, 0.03, 0.17)
    return finish(mix(sec, _dac(body, 10000.0)), 1.3)


# --- Damage hit (generic) -----------------------------------------------------
# No element: a body being struck. A peak that stands clear, short.

def damage_a() -> np.ndarray:
    """A, thud: a muffled burst with a little low weight, a soft air tail
    14 dB under it."""
    thump = hit(0.3, 650.0, 0.028, 2.5, 9000.0, seed=261, sub=0.25)
    tail = air(0.25, 262, _ar(0.25, 0.02, 0.05), hi=400.0, rate=8000.0) * 0.2
    return finish(mix(0.34, thump, (tail, 0.03)), 1.05)


def damage_b() -> np.ndarray:
    """B, smack: brighter and shorter: a crack of hiss on the front, a
    sharper burst, a small low body after."""
    thump = hit(0.22, 2200.0, 0.016, 2.0, 12000.0, seed=271)
    crack = hiss([0, 5, 11, 15], [10000.0, 3500.0], seed=272) * 0.35
    body = air(0.18, 273, _ar(0.18, 0.004, 0.035), hi=350.0, rate=8000.0) * 0.3
    return finish(mix(0.26, thump, crack, (body, 0.015)), 1.05)


def damage_c() -> np.ndarray:
    """C, crunch: a gritty low-rate burst (the DAC at 5 kHz) with a spray of
    small debris pops."""
    thump = hit(0.28, 1300.0, 0.03, 3.5, 5000.0, seed=281, sub=0.15)
    debris = base.crackles(0.22, 40.0, seed=282) * _chip_env(0.22, 0.005, 0.06) * 0.6
    return finish(mix(0.32, thump, (debris, 0.02)), 1.05)


# --- Fireball cast (red T2) ---------------------------------------------------

CAST_T2_SEC = 0.6


def ball_cast_a() -> np.ndarray:
    """A, whoomph: a spark, a swell of low air, and a short burst of the
    burn's roar breathing under it."""
    sec = CAST_T2_SEC
    spark = hiss([0, 4, 10, 15], [12000.0, 5000.0], seed=291) * 0.3
    bloom = air(0.5, 292, _ar(0.5, 0.03, 0.09), hi=700.0, rate=8000.0)
    body = roar(sec, 29, (90.0, 1300.0), 6.0, 10.0, 0.2, _chip_env(sec, 0.02, 0.12)) * 0.6
    return finish(mix(sec, spark, bloom, body), 1.5)


def ball_cast_b() -> np.ndarray:
    """B, inhale then release: 0.12 s of air drawn in, cut off by the
    whoomph. The cast lands 0.12 s after the press."""
    sec = CAST_T2_SEC + 0.12
    inhale_sec = 0.12
    draw = air(inhale_sec, 301, np.linspace(0.0, 1.0, s.n_samples(inhale_sec)) ** 2.5, hi=800.0, rate=8000.0) * 0.35
    spark = hiss([0, 4, 10, 15], [12000.0, 5000.0], seed=302) * 0.3
    burst = hit(0.45, 1200.0, 0.07, 2.0, 8000.0, seed=303)
    body = roar(0.5, 30, (80.0, 1100.0), 5.0, 8.0, 0.2, _chip_env(0.5, 0.03, 0.1)) * 0.5
    at = inhale_sec
    return finish(mix(sec, draw, (spark, at), (burst, at), (body, at + 0.01)), 1.3)


def ball_cast_c() -> np.ndarray:
    """C, roar-out: the burn's roar thrown forward: fast in, deeper, busier
    with crackle, no separate puff."""
    sec = CAST_T2_SEC + 0.1
    body = roar(sec, 27, (70.0, 1200.0), 3.0, 14.0, 0.3, _chip_env(sec, 0.015, 0.14))
    spark = hiss([1, 3, 8, 15], [10000.0, 4000.0], seed=311) * 0.25
    return finish(mix(sec, body, spark), 1.6)


# --- Fireball flight (launch layer) ---------------------------------------------

FLIGHT_T2_SEC = 1.3


def ball_flight_a() -> np.ndarray:
    """A, rolling roar: the chosen burn's deep roar, swelling in over 60 ms
    and fading over a second."""
    sec = FLIGHT_T2_SEC
    return finish(roar(sec, 31, (60.0, 900.0), 2.0, 6.0, 0.3, _chip_env(sec, 0.06, 0.4)), 1.6)


def ball_flight_b() -> np.ndarray:
    """B, receding: a band of roar that sinks from 1.4 kHz to 300 Hz as it
    fades, over a low rumble: heavy, going away."""
    sec = FLIGHT_T2_SEC
    band = _dac(swept(sec, [1400.0, 700.0, 300.0], seed=321, q=1.2) * _ar(sec, 0.05, 0.35), 9000.0)
    n = int(round(sec * ym.FRAME_HZ))
    low = rumble(np.linspace(4.0, 15.0, n), seed=322) * 0.25
    trail = base.crackles(sec, 8.0, seed=323) * _chip_env(sec, 0.01, 0.4) * 0.5
    return finish(mix(sec, band, low, trail), 1.4)


def ball_flight_c() -> np.ndarray:
    """C, crackling trail: a brighter, faster-breathing roar with dense
    crackle: more burning than rolling."""
    sec = FLIGHT_T2_SEC
    return finish(roar(sec, 33, (120.0, 1600.0), 4.5, 16.0, 0.15, _chip_env(sec, 0.04, 0.35)), 1.6)


# --- Inferno cast (red T3) ----------------------------------------------------

CAST_T3_SEC = 1.3


def _sub(frames_on: int, start_hz: float, end_hz: float, ring: float) -> np.ndarray:
    """Low weight on the round boom voice (pilot_md.ROUND), normalised."""
    return _norm(base.note(base.ROUND, ym.frames(np.geomspace(start_hz, end_hz, frames_on)), frames_on, ring_sec=ring))


def inferno_cast_a() -> np.ndarray:
    """A, great whoomph: a spark, a big slow swell of deep air, the burn's
    roar over a second, rumble and a little falling sub under it."""
    sec = CAST_T3_SEC
    spark = hiss([0, 2, 6, 11, 15], [12000.0, 4000.0], seed=331) * 0.3
    bloom = air(1.0, 332, _ar(1.0, 0.04, 0.22), hi=500.0, rate=8000.0)
    body = roar(sec, 41, (60.0, 1000.0), 1.5, 8.0, 0.4, _chip_env(sec, 0.03, 0.35)) * 0.7
    weight = _sub(30, 110.0, 45.0, 0.4) * 0.22
    return finish(mix(sec, spark, bloom, body, weight), 1.4)


def inferno_cast_b() -> np.ndarray:
    """B, release: a 0.1 s rush rising as the charge lets go, then a hard
    burst and the roar rolling on."""
    sec = CAST_T3_SEC + 0.1
    rise_sec = 0.1
    rush = _dac(swept(rise_sec, [400.0, 2000.0], seed=341) * np.linspace(0.0, 1.0, s.n_samples(rise_sec)) ** 2, 10000.0) * 0.45
    burst = hit(0.6, 900.0, 0.06, 2.5, 8000.0, seed=342, sub=0.25, sub_hz=100.0)
    bloom = air(0.9, 343, _ar(0.9, 0.03, 0.2), hi=450.0, rate=8000.0) * 0.6
    body = roar(1.1, 42, (60.0, 900.0), 1.2, 6.0, 0.45, _chip_env(1.1, 0.06, 0.35)) * 0.6
    at = rise_sec
    return finish(mix(sec, rush, (burst, at), (bloom, at + 0.01), (body, at + 0.02)), 1.3)


def inferno_cast_c() -> np.ndarray:
    """C, period blast: the console's classic falling PSG noise, with the
    roar and crackle under it: brighter, more 16-bit."""
    sec = CAST_T3_SEC
    fall = base.falling_noise(45, 6000.0, 500.0, seed=351, wobble=1.0) * 0.55
    bloom = air(0.9, 352, _ar(0.9, 0.02, 0.18), hi=600.0, rate=8000.0) * 0.8
    body = roar(sec, 43, (70.0, 1100.0), 2.0, 12.0, 0.35, _chip_env(sec, 0.02, 0.3)) * 0.5
    weight = _sub(24, 120.0, 50.0, 0.3) * 0.18
    return finish(mix(sec, fall, bloom, body, weight), 1.4)


# --- Inferno eruption ------------------------------------------------------------
# The Fireball explosion is spark, hit, then a boom that swells and rolls
# away. The eruption is a ground hit followed by a column of fire going up and
# burning: a sustained, rising roar rather than a second boom. Visual: flames
# thrown upward for ~1 s, smoke to 2.4 s.

ERUPT_SEC = 2.3
# The column / roar after the hit comes up close to the hit's level, as the
# chosen explosion's boom does (boom_vs_hit -0.7 dB): that is what makes it big.
ERUPT_COLUMN_GAIN = 2.2
ERUPT_BED_GAIN = 2.0
ERUPT_ROAR_GAIN = 2.6


def erupt_a() -> np.ndarray:
    """A, geyser: a deep ground thump, then a roaring column whose band rises
    as it swells over 0.3 s and burns on, crackling, for two seconds."""
    sec = ERUPT_SEC
    thump = hit(0.5, 350.0, 0.045, 2.2, 8000.0, seed=361, sub=0.3, sub_hz=100.0)
    col_sec = 2.1
    column = swept(col_sec, [250.0, 900.0, 1400.0, 1100.0, 700.0], seed=362, q=0.9)
    column = column * (0.55 + 0.45 * base.breath(col_sec, 3.0, 363)) * _ar(col_sec, 0.22, 0.5, curve=1.6)
    column = _dac(column, 10000.0) * ERUPT_COLUMN_GAIN
    crackle = base.crackles(col_sec, 20.0, seed=364, big_every=1.0) * _chip_env(col_sec, 0.15, 0.6) * 0.7
    n = int(round(sec * ym.FRAME_HZ))
    low = rumble(np.linspace(2.0, 15.0, n), seed=365) * 0.3
    return finish(mix(sec, thump, (column, 0.04), (crackle, 0.06), low), 1.15)


def erupt_b() -> np.ndarray:
    """B, burst-up: a hard crack and burst, a rush of hiss climbing in pitch
    (going up), then debris pattering down over a low roar."""
    sec = ERUPT_SEC
    burst = hit(0.4, 1500.0, 0.03, 2.8, 10000.0, seed=371, sub=0.2)
    crack = hiss([0, 3, 8, 15], [13000.0, 6000.0], seed=372) * 0.35
    k = np.linspace(0.0, 1.0, 24)
    up = hiss(8.0 - 6.0 * np.sin(np.pi * k) + 7.0 * k ** 3, [1200.0, 13000.0], seed=373) * 0.5
    bed = roar(2.0, 52, (60.0, 900.0), 1.2, 3.0, 0.35, _chip_env(2.0, 0.2, 0.6, curve=2.0)) * ERUPT_BED_GAIN
    rng = np.random.default_rng(374)
    times = np.sort(0.35 + 1.6 * rng.random(16) ** 1.6)
    debris = pops(sec, list(times), seed=375, sizes=list(np.linspace(0.9, 0.25, 16)), lo=800.0, hi=3500.0) * 0.55
    return finish(mix(sec, burst, crack, (up, 0.03), (bed, 0.05), debris), 1.15)


def erupt_c() -> np.ndarray:
    """C, rumble-erupt: 70 ms of the ground giving way, the blast, then the
    burn's roar long and loud with big crackles."""
    sec = ERUPT_SEC
    lead = 0.07
    give = air(lead, 381, np.linspace(0.0, 1.0, s.n_samples(lead)) ** 1.5, hi=160.0, rate=6000.0) * 0.5
    give_psg = rumble([8, 5, 3, 2], seed=382) * 0.3
    blast = hit(0.6, 500.0, 0.05, 2.5, 8000.0, seed=383, sub=0.1, sub_hz=90.0)
    body = roar(2.1, 53, (60.0, 1100.0), 1.0, 10.0, 0.4, _chip_env(2.1, 0.2, 0.6, curve=2.0)) * ERUPT_ROAR_GAIN
    return finish(mix(sec, give, give_psg, (blast, lead), (body, lead + 0.03)), 1.15)


# --- Fizzle (progress layer) ------------------------------------------------------
# The one tonal cue in the lane. In key (kit.scale_hz), soft, short, no ring,
# no echo. A muted, round voice: two 2-op pairs with gentle modulators.

MUTE = Patch(4, 0, [
    Op(mul=1, tl=38, ar=31, d1r=18, sl=8, d2r=10, rr=12),
    Op(mul=1, tl=0, ar=26, d1r=12, sl=4, d2r=8, rr=11),
    Op(mul=2, dt=1, tl=48, ar=31, d1r=20, sl=10, d2r=12, rr=12),
    Op(mul=1, dt=-1, tl=8, ar=26, d1r=12, sl=4, d2r=8, rr=11),
])
FIZZLE_OCTAVE = -1          # A3 / F#3: low and soft


def fizzle_a() -> np.ndarray:
    """A, uh-oh: two soft notes falling a minor third (A3 to F#3, both in
    key), the second dulled as it ends."""
    hi, lo = scale_hz(3, FIZZLE_OCTAVE), scale_hz(2, FIZZLE_OCTAVE)
    first = base.note(MUTE, hi, 4, ring_sec=0.03)
    dull = ym.frames([0, 4, 10, 16, 22, 28])
    second = base.note(MUTE, lo, 6, ring_sec=0.06, gain_db=-2.0, tl_offset={0: dull, 2: dull})
    return finish(mix(0.25, first, (second, 5 * FRAME)))


def fizzle_b() -> np.ndarray:
    """B, deflate: one note (A3) that sags down four semitones and goes dull
    and quiet as it sags, like air let out."""
    frames_on = 11
    k = np.linspace(0.0, 1.0, frames_on)
    pitch = ym.frames(scale_hz(3, FIZZLE_OCTAVE) * semitones(-4.0 * k ** 1.6))
    dull = ym.frames(26.0 * k)
    quieter = ym.frames(14.0 * k ** 2)
    tone = base.note(MUTE, pitch, frames_on, ring_sec=0.06, tl_offset={0: dull, 2: dull, 1: quieter, 3: quieter})
    return finish(tone)


def fizzle_c() -> np.ndarray:
    """C, bonk: one short dull note (D4, the key's root) with a soft puff of
    air on it. The most minimal."""
    tone = base.note(MUTE, scale_hz(0, FIZZLE_OCTAVE + 1), 2, ring_sec=0.12, tl_offset={0: 8, 2: 8})
    puff = air(0.08, 391, _ar(0.08, 0.003, 0.02), hi=500.0, rate=8000.0) * 0.25
    return finish(mix(0.2, tone, puff))


# --- Dash and roll ------------------------------------------------------------------
# Dash: 0.2 s airborne burst, once per jump. Roll: 0.35 s grounded, every
# 0.55 s at most (GameConfig DASH / ROLL).

def dash_a() -> np.ndarray:
    """A, whoosh: a band of air that rises then falls as the body passes
    through it, 0.24 s."""
    sec = 0.24
    return finish(mix(sec, _dac(swept(sec, [500.0, 2200.0, 800.0], seed=401, q=1.4) * _ar(sec, 0.05, 0.05, curve=2.0), 12000.0)), 1.2)


def dash_b() -> np.ndarray:
    """B, swish: brighter and quicker, sweeping up, with a small low push
    of air under the start."""
    sec = 0.16
    swish = _dac(swept(sec, [1500.0, 5000.0], seed=411, q=2.0) * _ar(sec, 0.03, 0.03, curve=2.0), 16000.0)
    push = air(0.1, 412, _ar(0.1, 0.003, 0.02), hi=300.0, rate=8000.0) * 0.3
    return finish(mix(0.2, swish, push), 1.2)


def dash_c() -> np.ndarray:
    """C, fwip: chip noise, its clock swept up then down over ten frames:
    the most 16-bit of the three."""
    vols = [12, 8, 4, 2, 5, 9, 13, 15]
    return finish(hiss(vols, [4000.0, 9000.0, 13000.0, 8000.0, 2500.0], seed=421) * 0.6, 1.1)


def _scuff(sec: float, seed: int) -> np.ndarray:
    """Feet or body scraping the ground: gritty mid noise with a rough,
    fast-wavering level, through the DAC at a low rate."""
    rough = 0.4 + 0.6 * base.breath(sec, 60.0, seed)
    return _dac(_shaped(sec, seed + 1, lo=800.0, hi=4000.0) * rough * _ar(sec, 0.005, sec * 0.3), 6000.0)


def _thump(seed: int) -> np.ndarray:
    return _dac(s.drive(_shaped(0.08, seed, hi=220.0) * _ar(0.08, 0.002, 0.018), 1.8), 8000.0)


def roll_a() -> np.ndarray:
    """A, whoosh and scuff: a soft whoosh over the roll, a short scrape as
    it ends."""
    sec = 0.42
    whoosh = _dac(swept(0.32, [400.0, 1500.0, 600.0], seed=431, q=1.4) * _ar(0.32, 0.07, 0.07, curve=2.0), 12000.0) * 0.8
    return finish(mix(sec, whoosh, (_scuff(0.1, 432) * 0.6, 0.28)), 1.2)


def roll_b() -> np.ndarray:
    """B, tumble: a low whoosh with two soft body thumps (shoulder, then
    feet) and a light scrape."""
    sec = 0.42
    whoosh = _dac(swept(0.32, [300.0, 1100.0, 500.0], seed=441, q=1.2) * _ar(0.32, 0.06, 0.08, curve=2.0), 10000.0) * 0.6
    return finish(mix(sec, whoosh, (_thump(442) * 0.7, 0.06), (_thump(443) * 0.55, 0.25),
                      (_scuff(0.08, 444) * 0.3, 0.3)), 1.2)


def roll_c() -> np.ndarray:
    """C, slide: friction along the ground: rough noise whose band sinks as
    the roll slows to a stop."""
    sec = 0.4
    rough = 0.5 + 0.5 * base.breath(sec, 45.0, 451)
    slide = swept(sec, [2000.0, 1200.0, 600.0], seed=452, q=1.0) * rough * _ar(sec, 0.02, 0.12)
    return finish(mix(sec, _dac(slide, 8000.0)), 1.2)


# --- Arena teleporter --------------------------------------------------------------
# One use per 2 s per player (ArenaEntryConstants.COOLDOWN_SEC). World layer:
# air moving, no tone. Depart and arrive are mirror images, take for take.

def _whirl(sec: float, rate_from: float, rate_to: float, path_hz, seed: int) -> np.ndarray:
    """Air turning: a band of noise whose level circles at a rate that
    changes (faster for leaving, slower for arriving), like the collect
    sound's spin-in."""
    rate = s.glide(rate_from, rate_to, sec)
    turn = 0.35 + 0.65 * (0.5 + 0.5 * np.sin(2.0 * np.pi * np.cumsum(rate) / SR))
    return swept(sec, path_hz, seed, q=1.3) * turn


def depart_a() -> np.ndarray:
    """A, drawn up: a rush of air rising from 300 Hz to 4.5 kHz, swelling,
    cut off by a soft low implosion."""
    rise = 0.45
    rush = swept(rise, [300.0, 1200.0, 4500.0], seed=461) * np.linspace(0.0, 1.0, s.n_samples(rise)) ** 2
    implode = air(0.14, 462, _ar(0.14, 0.004, 0.03), hi=400.0, rate=8000.0) * 0.6
    return finish(mix(0.62, _dac(rush, 12000.0), (implode, rise)), 1.2)


def arrive_a() -> np.ndarray:
    """A, set down: the rush falling back from 4.5 kHz, a soft landing
    thump, a little dust."""
    fall = 0.32
    rush = swept(fall, [4500.0, 1200.0, 350.0], seed=471) * _ar(fall, 0.02, 0.09)
    land = hit(0.2, 260.0, 0.03, 1.8, 8000.0, seed=472)
    dust = air(0.2, 473, _ar(0.2, 0.01, 0.05), lo=2000.0, rate=12000.0) * 0.15
    return finish(mix(0.55, _dac(rush, 12000.0), (land * 0.8, 0.26), (dust, 0.28)), 1.2)


def depart_b() -> np.ndarray:
    """B, whirl out: air spinning faster and rising, gone with a puff."""
    sec = 0.5
    spin = _whirl(sec, 5.0, 24.0, [500.0, 2500.0], seed=481) * np.linspace(0.2, 1.0, s.n_samples(sec)) ** 1.5
    puff = air(0.1, 482, _ar(0.1, 0.003, 0.02), hi=900.0, rate=8000.0) * 0.5
    return finish(mix(0.62, _dac(spin, 12000.0), (puff, sec)), 1.2)


def arrive_b() -> np.ndarray:
    """B, whirl in: air spinning down and slowing, settling with a soft
    thump."""
    sec = 0.45
    spin = _whirl(sec, 24.0, 5.0, [2500.0, 500.0], seed=491) * _ar(sec, 0.02, 0.18)
    land = hit(0.2, 260.0, 0.03, 1.8, 8000.0, seed=492)
    return finish(mix(0.62, _dac(spin, 12000.0), (land * 0.7, 0.4)), 1.2)


def depart_c() -> np.ndarray:
    """C, flash out: a bright crack and a burst of air blown outward,
    falling away."""
    crack = hiss([0, 3, 8, 15], [13000.0, 7000.0], seed=501) * 0.4
    blow = _dac(swept(0.4, [3000.0, 600.0], seed=502, q=1.0) * _ar(0.4, 0.003, 0.07), 12000.0)
    return finish(mix(0.45, crack, blow), 1.2)


def arrive_c() -> np.ndarray:
    """C, flash in: the same crack, a thump of landing, dust settling."""
    crack = hiss([0, 3, 8, 15], [13000.0, 7000.0], seed=511) * 0.4
    land = hit(0.25, 300.0, 0.035, 2.0, 8000.0, seed=512)
    dust = air(0.3, 513, _ar(0.3, 0.02, 0.07), lo=1500.0, hi=6000.0, rate=12000.0) * 0.25
    return finish(mix(0.45, crack, (land, 0.01), (dust, 0.03)), 1.2)


# --- Demos ------------------------------------------------------------------------
# Played the way the game plays them: each file mastered to its band, scaled
# by its VfxConfig volume, at a random PlaybackSpeed in its pitchRange.

def _as_game(x: np.ndarray, band: str, volume: float = 1.0) -> np.ndarray:
    return _norm(x) * 10.0 ** ((PEAK_DBFS + BAND_GAIN_DB[band]) / 20.0) * volume


def _speed(x: np.ndarray, rate: float) -> np.ndarray:
    """PlaybackSpeed: pitch and length change together."""
    idx = np.arange(0.0, len(x) - 1, rate)
    return np.interp(idx, np.arange(len(x)), x)


def _series(x: np.ndarray, starts, band: str, volume: float, pitch=(1.0, 1.0), seed: int = 1):
    rng = np.random.default_rng(seed)
    return [(_speed(_as_game(x, band, volume), rng.uniform(*pitch)), 1.0, t) for t in starts]


FAST_STEPS = [0.0, 0.3, 0.6, 0.9]


def _demo_fast(build, band: str, volume: float, pitch, seed: int):
    return lambda: s.mix(*_series(build(), FAST_STEPS, band, volume, pitch, seed))


def _demo_dash_roll(dash, roll):
    def build():
        d, r = dash(), roll()
        layers = _series(r, [0.0, 0.55], "gameplay", 1.0)
        layers += _series(d, [1.2], "gameplay", 1.0)
        layers += _series(r, [1.9], "gameplay", 1.0)
        return s.mix(*layers)
    return build


def _demo_firebolt(cast, flight, dmg):
    def build():
        c, f, h = cast(), flight(), dmg()
        layers = []
        for i, t in enumerate([0.0, 0.9]):
            layers += _series(c, [t], "gameplay", 0.8, (0.95, 1.10), seed=10 + i)
            layers += _series(f, [t], "gameplay", 0.35, seed=20 + i)
            layers += _series(h, [t + 0.4], "gameplay", 0.85, (0.92, 1.08), seed=30 + i)
        return s.mix(*layers)
    return build


def _demo_fireball(cast, flight):
    def build():
        layers = _series(cast(), [0.0], "gameplay", 1.0, (0.90, 1.05), seed=41)
        layers += _series(flight(), [0.0], "gameplay", 0.45, (0.95, 1.05), seed=42)
        layers += _series(base.CUES["impact_damage_t2"](), [0.55], "gameplay", 1.0)
        return s.mix(*layers)
    return build


def _demo_inferno(cast, erupt):
    def build():
        layers = _series(cast(), [0.0], "gameplay", 1.0, (0.85, 1.0), seed=51)
        layers += _series(erupt(), [0.05], "gameplay", 1.0, (0.88, 1.0), seed=52)
        return s.mix(*layers)
    return build


def _demo_teleport(depart, arrive):
    def build():
        return s.mix(*(_series(depart(), [0.0], "gameplay", 1.0) + _series(arrive(), [0.6], "gameplay", 1.0)))
    return build


# CUES[take_id][cue_id] = a function returning a float array at 48 kHz.
BUILDERS = {
    "cast_red_t1": (bolt_cast_a, bolt_cast_b, bolt_cast_c),
    "projectile_red_t1": (bolt_flight_a, bolt_flight_b, bolt_flight_c),
    "impact_damage": (damage_a, damage_b, damage_c),
    "cast_red_t2": (ball_cast_a, ball_cast_b, ball_cast_c),
    "projectile_red_t2": (ball_flight_a, ball_flight_b, ball_flight_c),
    "cast_red_t3": (inferno_cast_a, inferno_cast_b, inferno_cast_c),
    "impact_damage_t3": (erupt_a, erupt_b, erupt_c),
    "fizzle": (fizzle_a, fizzle_b, fizzle_c),
    "dash": (dash_a, dash_b, dash_c),
    "roll": (roll_a, roll_b, roll_c),
    "arena_depart": (depart_a, depart_b, depart_c),
    "arena_arrive": (arrive_a, arrive_b, arrive_c),
}

CUES: dict[str, dict] = {take["id"]: {} for take in TAKES}
for _i, _take in enumerate(TAKE_IDS):
    _c = CUES[_take]
    for _cid, _fns in BUILDERS.items():
        _c[_cid] = _fns[_i]
    _c["demo_cast_red_t1"] = _demo_fast(_c["cast_red_t1"], "gameplay", 0.8, (0.95, 1.10), seed=61)
    _c["demo_impact_damage"] = _demo_fast(_c["impact_damage"], "gameplay", 0.85, (0.92, 1.08), seed=62)
    _c["demo_fizzle"] = _demo_fast(_c["fizzle"], "ui", 1.0, (1.0, 1.0), seed=63)
    _c["demo_dash_roll"] = _demo_dash_roll(_c["dash"], _c["roll"])
    _c["demo_firebolt"] = _demo_firebolt(_c["cast_red_t1"], _c["projectile_red_t1"], _c["impact_damage"])
    _c["demo_fireball"] = _demo_fireball(_c["cast_red_t2"], _c["projectile_red_t2"])
    _c["demo_inferno"] = _demo_inferno(_c["cast_red_t3"], _c["impact_damage_t3"])
    _c["demo_teleport"] = _demo_teleport(_c["arena_depart"], _c["arena_arrive"])

# Chosen by the user, 2026-11-28 (round 1, "for now ... i want to play them in
# game first"). Don't change these takes' code: the packager fingerprints them.
# Note: impact_damage alone was B, but the four-hits demo was ticked A.
CHOSEN = {
    "cast_red_t1": "b",
    "projectile_red_t1": "a",
    "impact_damage": "b",
    "cast_red_t2": "c",
    "projectile_red_t2": "b",
    "cast_red_t3": "b",
    "impact_damage_t3": "b",
    "fizzle": "a",
    "dash": "a",
    "roll": "b",
    "arena_depart": "a",
    "arena_arrive": "a",
}
