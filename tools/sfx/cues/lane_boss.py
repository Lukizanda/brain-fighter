"""Production lane: the boss (the Brain) and its scramble puzzle.

Owned by the "Audio: boss lane" session (spawned 2026-11-28). It replaces
the stand-in sounds the game plays today. Rules: wiki/design/AudioDirection.md
(read it first); method: docs/agents/audio-sfx.md.

    python tools/sfx/render.py --lane boss
    python tools/sfx/lint.py --dir build/sfx/lanes/boss
    python tools/sfx/audition.py --dir build/sfx/lanes/boss --out build/sfx/lanes/boss/audition.html

Cue ids are the VfxConfig.EFFECTS id, or the BossConstants / BombConstants
constant, they replace. Several boss events borrow other effects today
(ward_up uses wall_rise_rumble, and so on); they get their own effect entries
when wired, so design each for its own event. Reuse helpers from pilot_md
by import; never edit it. pilot_md.boss_telegraph is an unjudged first try.

Round 1 (2026-11-28). The boss's voice is still a proposal (AudioDirection
rule 3: low, detuned, tritone). So across the boss cues one take carries
that voice under the physical sound and the others do not, and the user's
pick rules on it. World cues are noise-led; only scramble_tap and the
lead-in of scramble_defuse are in key.
"""

from __future__ import annotations

import numpy as np
from scipy import signal

import synth as s
import ym
from cues import pilot_md as base  # read-only: patches and helpers
from kit import ROOT_HZ, SAMPLE_RATE, TRITONE_SEMITONES, scale_hz, semitones

LANE = {"id": "boss", "label": "The Brain and its scramble puzzle"}

TAKES = [
    {"id": "a", "label": "Take A"},
    {"id": "b", "label": "Take B"},
    {"id": "c", "label": "Take C"},
]

FRAME = base.FRAME

# --- Game timings these cues are built against (read 2026-11-28) -----------
VOLLEY_SHOTS = 20             # BossConfig Brain FireballVolley count
VOLLEY_STAGGER_SEC = 0.15     # ... staggerSec
SHOT_FLIGHT_SEC = 0.6         # demo only: a shot dying ~55 studs out at speed 90
HATCH_STAGGER_SEC = 0.3       # BossConfig bombHatchStaggerSec
PUZZLE_LETTERS = 4            # bombLettersByPhase, phase 2
FAST_TAP_SEC = 0.3            # demo: a fast solver, the collect demo's spacing
# Roblox plays one file per cue; the demos vary it only the way a
# pitchRange would. The ranges today were set for the stand-in assets.
DEMO_SPEED_JITTER = 0.04

# --- The boss voice (proposal, AudioDirection rule 3) ----------------------
# A tritone below the key's root, two octaves down: G#2 against D. The voice
# is a pair of growls a tritone apart, the upper one detuned so it beats.
BOSS_HZ = ROOT_HZ * semitones(TRITONE_SEMITONES - 24)
BOSS_DETUNE_CENTS = 18.0


def _norm(x: np.ndarray) -> np.ndarray:
    return x / max(1e-9, float(np.max(np.abs(x))))


def _db(gain_db: float) -> float:
    return 10.0 ** (gain_db / 20.0)


def dac(x: np.ndarray, rate: float) -> np.ndarray:
    """A 48 kHz sample, normalised, played through the 8-bit DAC."""
    return ym.dac_sample(_norm(x), SAMPLE_RATE, rate)


# --- Physical primitives (chip-rate out) -------------------------------------

def thud(sec: float, cut_hz: float, half_life: float, seed: int, rate: float = 8000.0,
         sub_hz: float = 0.0, sub_level: float = 0.0, drive: float = 2.0) -> np.ndarray:
    """A body hit: a burst of muffled noise, an optional short sub drop under
    it, saturated, through the DAC. Noise-led, so it does not ring as a drum."""
    burst = _norm(s.lowpass(s.noise(sec, seed), cut_hz)) * s.decay(sec, half_life, attack=0.001)
    if sub_level > 0:
        sub = s.sine(s.glide(sub_hz, sub_hz * 0.45, sec, curve=1.5)) * s.decay(sec, half_life * 1.4, attack=0.001)
        burst = burst + sub * sub_level
    return dac(s.drive(_norm(burst), drive), rate)


def crack(sec: float, low_hz: float, high_hz: float, seed: int, rate: float = 16000.0) -> np.ndarray:
    """A bright snap: band-passed noise, very short."""
    x = s.bandpass(s.noise(sec, seed), low_hz, high_hz) * s.decay(sec, sec * 0.25, attack=0.0003)
    return dac(x, rate)


def rumble(sec: float, cut_hz: float, attack: float, half_life: float, seed: int,
           wobble_hz: float = 3.0, wobble: float = 0.5, rate: float = 6000.0) -> np.ndarray:
    """Low air and ground: low-passed noise that swells in, rolls unevenly
    (a slow random swell, never a steady pulse) and dies away."""
    x = _norm(s.lowpass(s.noise(sec, seed), cut_hz, order=2))
    roll = 1.0 - wobble + wobble * base.breath(sec, wobble_hz, seed + 7)
    return dac(x * roll * s.decay(sec, half_life, attack=attack), rate)


def swell_in(sec: float, cut_hz: float, seed: int, power: float = 2.0, rate: float = 8000.0) -> np.ndarray:
    """Noise rising to a cut-off (an in-rush), for gathering and windups."""
    x = _norm(s.lowpass(s.noise(sec, seed), cut_hz)) * s.swell(sec, power)
    return dac(x, rate)


def sweep(sec: float, start_hz: float, end_hz: float, seed: int, q: float = 2.0,
          attack: float = 0.01, half_life: float = 1.0, rate: float = 12000.0) -> np.ndarray:
    """Noise through a resonant band whose centre glides: a squelch going
    down, a rush going up."""
    centre = s.glide(start_hz, end_hz, sec)
    x = s.swept_bandpass(s.noise(sec, seed), centre, q=q, blocks=max(8, int(sec * 120)))
    return dac(_norm(x) * s.decay(sec, half_life, attack=attack), rate)


def psg_rise(frames_on: int, start_hz: float, end_hz: float, seed: int, peak_at: float = 0.6) -> np.ndarray:
    """PSG noise whose clock climbs every frame, swelling then fading: the
    console's 'whoosh up'."""
    k = np.linspace(0.0, 1.0, frames_on)
    shape = np.where(k < peak_at, k / peak_at, (1.0 - k) / (1.0 - peak_at))
    vols = np.clip(np.round(15.0 - 15.0 * shape), 0, 15).astype(int)
    return base.noise_burst(list(vols), shift_hz=ym.frames(np.geomspace(start_hz, end_hz, frames_on)), seed=seed)


def ground_bed(frames_on: int, start_vol: float, seed: int, roll: float = 1.5) -> np.ndarray:
    """The PSG's slowest noise clock, fading with an uneven roll."""
    k = np.arange(frames_on)
    vols = np.linspace(start_vol, 15.0, frames_on) + roll * np.sin(k / 3.7) * np.sin(k / 9.1)
    vols = np.clip(np.round(vols), 0, 15).astype(int)
    return base.noise_burst(list(vols), divider=base.RUMBLE_DIVIDER, seed=seed)


def clacks(times, seed: int, low_hz: float = 900.0, high_hz: float = 4500.0,
           body_cut: float = 1500.0, levels=None) -> np.ndarray:
    """Hard little objects knocking: each a snap with a short woody body."""
    parts = []
    rng = np.random.default_rng(seed)
    for i, t in enumerate(times):
        sec = 0.05
        snap = s.bandpass(s.noise(sec, seed + 10 * i), low_hz, high_hz) * s.decay(sec, 0.004, attack=0.0002)
        body = _norm(s.lowpass(s.noise(sec, seed + 10 * i + 1), body_cut)) * s.decay(sec, 0.012, attack=0.0005)
        level = 1.0 if levels is None else levels[i]
        x = dac(snap + body * rng.uniform(0.5, 0.9), 14000.0) * level
        parts.append((x, t))
    total = ym.chip_samples(max(times) + 0.08)
    return ym.place(total, *parts)


# --- The boss voice (tonal; sits under the physical layers) -------------------

def boss_voice(frames_on: int, semis_from: float, semis_to: float, gain_db: float = 0.0,
               open_from: float = 12.0, open_to: float = 0.0, ring_sec: float = 0.15,
               octave: int = -1) -> np.ndarray:
    """The proposed boss voice: a feedback growl on G# a tritone off the key,
    with a detuned partner a tritone above it so the pair beats and clashes.
    `semis_*` bends the pitch across the note (a rise is a tell, a fall a
    groan); `open_*` opens or closes the growl's modulators, in TL steps."""
    root = BOSS_HZ * 2.0 ** octave
    bend = semitones(np.linspace(semis_from, semis_to, frames_on))
    opening = ym.frames(np.linspace(open_from, open_to, frames_on))
    low = base.note(base.GROWL, ym.frames(root * bend), frames_on, ring_sec=ring_sec,
                    tl_offset={0: opening, 1: opening})
    partner = root * semitones(TRITONE_SEMITONES) * 2.0 ** (BOSS_DETUNE_CENTS / 1200.0)
    high = base.note(base.GROWL, ym.frames(partner * bend), frames_on, ring_sec=ring_sec,
                     gain_db=-6.0, tl_offset={0: opening, 1: opening})
    n = max(len(low), len(high))
    return _norm(ym.place(n, low, high)) * _db(gain_db)


# --- Mixing --------------------------------------------------------------------

def mix_chip(seconds: float, *layers) -> np.ndarray:
    """Chip-rate layers -> one 48 kHz cue through the console output."""
    return base.out(ym.place(ym.chip_samples(seconds), *layers))


def finish(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
    """Final gentle saturation. Impacts stay near 1.0 so the hit keeps its
    peak above the tail (saturation flattens punch)."""
    return base.hot(x, drive) if drive > 1.0 else _norm(x)


def jittered(x: np.ndarray, speed: float) -> np.ndarray:
    """The file as Roblox plays it at PlaybackSpeed `speed`."""
    return signal.resample(x, max(1, int(round(len(x) / speed))))


def repeat_demo(build, times, seed: int, gains=None) -> np.ndarray:
    """One file played at `times`, each at a jittered speed: how a repeated
    cue is heard in the game."""
    one = build()
    rng = np.random.default_rng(seed)
    layers = []
    for i, t in enumerate(times):
        g = 1.0 if gains is None else gains[i]
        layers.append((jittered(one, 1.0 + rng.uniform(-DEMO_SPEED_JITTER, DEMO_SPEED_JITTER)), g, t))
    return s.mix(*layers)


# =============================================================================
# Boss attacks
# =============================================================================

# --- Volley: one shot launched (x20, 0.15 s apart) ---------------------------

def shot_spit() -> np.ndarray:
    """A: a muffled spit of air and a short falling hiss. No pitch."""
    puff = thud(0.14, 1100.0, 0.022, seed=501, rate=9000.0, drive=2.2)
    hiss = base.falling_noise(6, 6000.0, 1500.0, seed=502) * 0.35
    return finish(mix_chip(0.22, puff, (hiss, 0.01)))


def shot_pshew() -> np.ndarray:
    """B: the console 'pshew': bright noise stepping down for ten frames,
    a small soft puff under it."""
    pshew = base.falling_noise(10, 9000.0, 900.0, seed=511) * 0.8
    puff = thud(0.1, 700.0, 0.02, seed=512, rate=8000.0) * 0.4
    return finish(mix_chip(0.24, pshew, puff))


def shot_spit_voice() -> np.ndarray:
    """C: take A's spit, with a four-frame grunt of the boss voice under it."""
    puff = thud(0.14, 1100.0, 0.022, seed=501, rate=9000.0, drive=2.2)
    hiss = base.falling_noise(6, 6000.0, 1500.0, seed=502) * 0.35
    grunt = boss_voice(4, 2.0, 0.0, gain_db=-8.0, open_from=4.0, open_to=10.0, ring_sec=0.06, octave=0)
    return finish(mix_chip(0.24, puff, (hiss, 0.01), grunt))


def _volley_times():
    return [i * VOLLEY_STAGGER_SEC for i in range(VOLLEY_SHOTS)]


# --- A projectile dies (x20 a volley; quiet and short) --------------------------

def death_thud() -> np.ndarray:
    """A: a dull, short thud against cover."""
    return finish(mix_chip(0.13, thud(0.12, 650.0, 0.016, seed=521, rate=7000.0, drive=1.8)))


def death_fizz() -> np.ndarray:
    """B: a small pop and the fire hissing out."""
    pop = thud(0.04, 1600.0, 0.006, seed=531, rate=10000.0) * 0.8
    hiss = base.noise_burst([3, 4, 6, 8, 10, 12, 14, 15], divider=512, seed=532) * 0.4
    return finish(mix_chip(0.16, pop, (hiss, 0.005)))


def death_crumble() -> np.ndarray:
    """C: take A's thud with a few grains of grit falling off the wall."""
    knock = thud(0.12, 650.0, 0.016, seed=521, rate=7000.0, drive=1.8)
    grit = clacks([0.025, 0.05, 0.085], seed=541, low_hz=1800.0, high_hz=6000.0, body_cut=900.0,
                  levels=[0.35, 0.25, 0.15])
    return finish(mix_chip(0.17, knock, grit))


def _death_times(seed: int = 550):
    """Deaths trail the launches by the flight, spread a little by range."""
    rng = np.random.default_rng(seed)
    return sorted(t + SHOT_FLIGHT_SEC + rng.uniform(-0.12, 0.25) for t in _volley_times())


# --- Ground Slam ------------------------------------------------------------------
# The biggest hit. The Fireball explosion lessons apply: a moment of impact
# that stands ~10 dB over 100-200 ms later, no tuned note under it, a second
# wave that rolls on, and energy a phone can play.

SLAM_SEC = 2.0


def _slam_hit(seed: int) -> np.ndarray:
    """The ground taking the blow: deep muffled noise with a little sub."""
    return thud(0.5, 380.0, 0.045, seed=seed, rate=9000.0, sub_hz=90.0, sub_level=0.25, drive=2.6)


def _duck(x: np.ndarray, at: float, length: float, depth: float) -> np.ndarray:
    """A dip just after the hit, so the hit stands alone (chip-rate)."""
    a, n = ym.chip_samples(at), ym.chip_samples(length)
    third = n // 3
    curve = np.ones(len(x))
    shape = np.concatenate([np.linspace(1.0, depth, third), np.full(third, depth),
                            np.linspace(depth, 1.0, n - 2 * third)])
    curve[a:a + len(shape)] = shape
    return x * curve


def slam_crack_boom() -> np.ndarray:
    """A: stone cracks, the ground takes the hit, then a second, deeper wave
    of rumble swells in and rolls on, with debris pattering down."""
    snap = crack(0.03, 900.0, 5000.0, seed=601) * 0.7
    hit = _slam_hit(602)
    boom = rumble(1.6, 320.0, 0.07, 0.5, seed=603, wobble_hz=4.0, wobble=0.35) * 1.15
    bed = ground_bed(100, 3.0, seed=604) * 0.35
    debris = base.crackles(0.9, 14.0, seed=605) * 0.5
    mix = ym.place(ym.chip_samples(SLAM_SEC), snap, (hit, 0.012), (boom, 0.13), (bed, 0.05), (debris, 0.2))
    return finish(base.out(_duck(mix, 0.05, 0.07, 0.62)), 1.2)


def slam_wave() -> np.ndarray:
    """B: a heavy thud, then the shockwave passing: a rush of noise whose
    band falls from bright to deep as it rolls out across the floor."""
    hit = _slam_hit(612)
    wave = sweep(1.3, 2200.0, 160.0, seed=613, q=1.2, attack=0.05, half_life=0.5, rate=10000.0) * 1.0
    boom = rumble(1.6, 260.0, 0.1, 0.5, seed=614, wobble=0.4) * 0.8
    bed = ground_bed(100, 4.0, seed=615) * 0.3
    mix = ym.place(ym.chip_samples(SLAM_SEC), hit, (wave, 0.1), (boom, 0.14), (bed, 0.05))
    return finish(base.out(_duck(mix, 0.04, 0.07, 0.45)), 1.15)


def slam_roar() -> np.ndarray:
    """C: take A's slam with the boss voice roaring under the second wave,
    falling as it fades."""
    snap = crack(0.03, 900.0, 5000.0, seed=601) * 0.7
    hit = _slam_hit(602)
    boom = rumble(1.6, 320.0, 0.07, 0.5, seed=603, wobble_hz=4.0, wobble=0.35) * 1.0
    bed = ground_bed(100, 3.0, seed=604) * 0.3
    debris = base.crackles(0.9, 14.0, seed=605) * 0.45
    roar = boss_voice(48, 0.0, -4.0, gain_db=-10.0, open_from=2.0, open_to=14.0, ring_sec=0.35, octave=0)
    mix = ym.place(ym.chip_samples(SLAM_SEC), snap, (hit, 0.012), (boom, 0.13), (bed, 0.05),
                   (debris, 0.2), (roar, 0.12))
    return finish(base.out(_duck(mix, 0.05, 0.07, 0.62)), 1.2)


# --- Knockup: a player thrown skyward ------------------------------------------

def knock_thump_whoosh() -> np.ndarray:
    """A: a body thump, then a whoosh of noise climbing as you rise."""
    hit = thud(0.1, 900.0, 0.02, seed=621, rate=9000.0, sub_hz=120.0, sub_level=0.3)
    rise = psg_rise(22, 700.0, 9000.0, seed=622, peak_at=0.45) * 0.55
    return finish(mix_chip(0.5, hit, (rise, 0.03)))


def knock_swoop() -> np.ndarray:
    """B: the thump, then air rushing past: a band of noise sweeping up and
    fading as you hang at the top."""
    hit = thud(0.1, 900.0, 0.02, seed=621, rate=9000.0, sub_hz=120.0, sub_level=0.3)
    air = sweep(0.6, 300.0, 3200.0, seed=632, q=1.6, attack=0.12, half_life=0.18) * 0.4
    return finish(mix_chip(0.72, hit, (air, 0.06)))


def knock_punch_zip() -> np.ndarray:
    """C: terse: a sharper hit with a crack on it, and a five-frame zip up."""
    snap = crack(0.015, 1500.0, 6000.0, seed=641) * 0.5
    hit = thud(0.08, 1400.0, 0.014, seed=642, rate=10000.0, sub_hz=140.0, sub_level=0.25)
    zip_ = psg_rise(6, 2000.0, 12000.0, seed=643, peak_at=0.3) * 0.45
    return finish(mix_chip(0.22, snap, hit, (zip_, 0.03)))


# =============================================================================
# Boss presence and ward
# =============================================================================

# --- Entrance: the countdown starts (something huge stirring) -----------------
ENTRANCE_START_SEC = 3.2


def stir_rumble() -> np.ndarray:
    """A: deep ground rumble swelling in and rolling, with two distant thuds
    of something moving. No pitch."""
    sec = ENTRANCE_START_SEC
    body = _norm(s.bandpass(s.noise(sec, 701), 60.0, 420.0, order=2))
    env = s.swell(sec, 1.6) * np.concatenate([np.ones(s.n_samples(sec - 0.7)), np.linspace(1, 0, s.n_samples(0.7))])
    roll = 0.55 + 0.45 * base.breath(sec, 2.5, 702)
    ground = dac(body * env[:len(body)] * roll, 6000.0)
    bed = base.noise_burst([int(v) for v in np.clip(np.round(14 - 7 * np.sin(np.linspace(0, np.pi, 190))), 0, 15)],
                           divider=base.RUMBLE_DIVIDER, seed=703) * 0.3
    far1 = thud(0.4, 300.0, 0.06, seed=704, rate=7000.0, sub_hz=70.0, sub_level=0.3) * 0.35
    far2 = thud(0.4, 300.0, 0.06, seed=705, rate=7000.0, sub_hz=70.0, sub_level=0.3) * 0.5
    return finish(mix_chip(sec, ground, bed, (far1, 1.1), (far2, 2.0)), 1.3)


def stir_growl() -> np.ndarray:
    """B: the boss voice waking: a low tritone growl opening slowly and
    rising over a rumble, a long version of the proposed tell."""
    sec = ENTRANCE_START_SEC
    frames_on = int((sec - 0.5) * ym.FRAME_HZ)
    growl = boss_voice(frames_on, 0.0, 4.0, gain_db=-7.0, open_from=20.0, open_to=2.0, ring_sec=0.4, octave=0)
    swell = ym.frames(np.linspace(1.0, 0.0, frames_on) ** 1.5)
    growl = growl * np.concatenate([1.0 - 0.85 * swell, np.ones(max(0, len(growl) - len(swell)))])[:len(growl)]
    ground = rumble(sec, 380.0, 1.2, 1.4, seed=711, wobble=0.4) * 1.0
    return finish(mix_chip(sec, ground, (growl, 0.1)), 1.2)


def stir_heartbeat() -> np.ndarray:
    """C: a giant slow heartbeat, lub-dub, quickening and growing closer,
    over a low rumble. Noise thuds, no pitch."""
    sec = ENTRANCE_START_SEC
    beats = [0.15, 1.05, 1.8, 2.4]
    layers = []
    for i, t in enumerate(beats):
        level = 0.4 + 0.2 * i
        lub = thud(0.35, 450.0, 0.05, seed=720 + 2 * i, rate=7000.0, sub_hz=90.0, sub_level=0.1) * level
        dub = thud(0.3, 400.0, 0.04, seed=721 + 2 * i, rate=7000.0, sub_hz=80.0, sub_level=0.1) * level * 0.7
        layers += [(lub, t), (dub, t + 0.2)]
    ground = rumble(sec, 250.0, 1.5, 1.2, seed=729, wobble=0.3) * 0.35
    return finish(mix_chip(sec, ground, *layers), 1.2)


# --- Entrance: the Brain lands (must not read as the Ground Slam) ------------
# The slam is stone cracking and a wave; the landing is a soft, heavy body:
# a wet thud and a squelch, no crack and a shorter tail.

def land_wet() -> np.ndarray:
    """A: a heavy soft body landing: a deep thud and a wet squelch dropping."""
    hit = thud(0.45, 420.0, 0.05, seed=741, rate=8000.0, sub_hz=85.0, sub_level=0.3, drive=2.4)
    squelch = sweep(0.4, 1400.0, 220.0, seed=742, q=3.0, attack=0.01, half_life=0.1) * 0.55
    bed = ground_bed(40, 5.0, seed=743) * 0.25
    return finish(mix_chip(1.0, hit, (squelch, 0.02), (bed, 0.03)), 1.15)


def land_roar() -> np.ndarray:
    """B: the thud, then the boss voice: a short roar announcing itself."""
    hit = thud(0.45, 420.0, 0.05, seed=741, rate=8000.0, sub_hz=85.0, sub_level=0.3, drive=2.4)
    roar = boss_voice(40, 1.0, -2.0, gain_db=-9.0, open_from=10.0, open_to=2.0, ring_sec=0.3, octave=0)
    bed = ground_bed(40, 5.0, seed=743) * 0.25
    return finish(mix_chip(1.5, hit, (roar, 0.22), (bed, 0.03)), 1.15)


def land_flare() -> np.ndarray:
    """C: the thud and squelch, then the core flaring: a rush of noise rising
    and settling as the eyes snap open."""
    hit = thud(0.45, 420.0, 0.05, seed=741, rate=8000.0, sub_hz=85.0, sub_level=0.3, drive=2.4)
    squelch = sweep(0.3, 1200.0, 260.0, seed=752, q=3.0, attack=0.01, half_life=0.08) * 0.4
    flare = sweep(0.6, 500.0, 4500.0, seed=753, q=1.5, attack=0.2, half_life=0.15) * 0.45
    return finish(mix_chip(1.1, hit, (squelch, 0.02), (flare, 0.25)), 1.15)


# --- Word ward goes up -------------------------------------------------------

def ward_plates() -> np.ndarray:
    """A: air gathering in, then four shell plates clacking shut, one after
    another, heavier each time."""
    gather = swell_in(0.4, 1800.0, seed=761, power=2.5) * 0.4
    plates = clacks([0.4, 0.52, 0.62, 0.7], seed=762, low_hz=600.0, high_hz=3500.0, body_cut=900.0,
                    levels=[0.55, 0.65, 0.8, 1.0])
    seal = thud(0.25, 500.0, 0.035, seed=763, rate=8000.0, sub_hz=90.0, sub_level=0.2) * 0.6
    return finish(mix_chip(1.1, gather, plates, (seal, 0.7)), 1.1)


def ward_swirl_hum() -> np.ndarray:
    """B: a swirl of air winding faster round the boss, locking with a deep
    clunk, and the boss voice humming low behind the shell."""
    sec = 0.8
    swirl_rate = np.cumsum(s.glide(3.0, 14.0, sec)) / SAMPLE_RATE
    swirl = 0.45 + 0.55 * np.abs(np.sin(np.pi * swirl_rate))
    air = s.swept_bandpass(s.noise(sec, 771), s.glide(500.0, 2600.0, sec), q=2.0, blocks=96)
    air = dac(_norm(air) * swirl * s.swell(sec, 1.5), 10000.0) * 0.55
    clunk = thud(0.3, 600.0, 0.03, seed=772, rate=8000.0, sub_hz=100.0, sub_level=0.3) * 0.9
    hum = boss_voice(40, 0.0, 0.0, gain_db=-12.0, open_from=18.0, open_to=24.0, ring_sec=0.25, octave=0)
    return finish(mix_chip(1.7, air, (clunk, sec), (hum, sec)), 1.1)


def ward_seal() -> np.ndarray:
    """C: one move: an in-rush of air opening up, cut off by a single heavy
    clank of the shell slamming shut (metal, out of key, no ring)."""
    rush = sweep(0.55, 300.0, 3000.0, seed=781, q=1.0, attack=0.5, half_life=1.0) * 0.5
    clank = base.ice_hit(BOSS_HZ * 4.0, gain_db=-9.0)
    body = thud(0.3, 700.0, 0.03, seed=782, rate=9000.0, sub_hz=110.0, sub_level=0.25) * 0.9
    bed = ground_bed(24, 7.0, seed=783) * 0.2
    return finish(mix_chip(1.0, rush, (clank, 0.55), (body, 0.55), (bed, 0.56)), 1.1)


# --- Word ward breaks (the players' win, still a world sound) --------------

def ward_shatter() -> np.ndarray:
    """A: a crack and a burst, then shell fragments scattering and pattering
    down."""
    snap = crack(0.03, 1200.0, 7000.0, seed=801) * 0.6
    burst = thud(0.3, 1800.0, 0.03, seed=802, rate=11000.0, drive=2.4) * 0.9
    shards = base.crackles(1.0, 30.0, seed=803, big_every=0.4) * 0.8
    fall = base.falling_noise(30, 7000.0, 900.0, seed=804) * 0.35
    return finish(mix_chip(1.3, snap, (burst, 0.008), (fall, 0.01), (shards, 0.04)), 1.15)


def ward_burst_stagger() -> np.ndarray:
    """B: a bright pop with the console's falling-noise burst, a few big
    fragments, and the boss's body thudding back as it staggers open."""
    pop = crack(0.02, 2000.0, 8000.0, seed=811) * 0.9
    burst = thud(0.2, 2000.0, 0.02, seed=815, rate=11000.0, drive=2.4) * 0.9
    fall = base.falling_noise(36, 9000.0, 600.0, seed=812) * 0.45
    shards = clacks([0.1, 0.19, 0.33, 0.5], seed=813, low_hz=800.0, high_hz=5000.0, body_cut=1200.0,
                    levels=[0.5, 0.4, 0.3, 0.2])
    stagger = thud(0.35, 400.0, 0.05, seed=814, rate=8000.0, sub_hz=80.0, sub_level=0.3) * 0.7
    return finish(mix_chip(1.2, pop, (burst, 0.005), (fall, 0.01), shards, (stagger, 0.24)), 1.1)


def ward_shatter_groan() -> np.ndarray:
    """C: take A's shatter, with the boss voice groaning down under it."""
    snap = crack(0.03, 1200.0, 7000.0, seed=801) * 0.6
    burst = thud(0.3, 1800.0, 0.03, seed=802, rate=11000.0, drive=2.4) * 0.9
    shards = base.crackles(1.0, 30.0, seed=803, big_every=0.4) * 0.7
    groan = boss_voice(50, 0.0, -7.0, gain_db=-12.0, open_from=0.0, open_to=16.0, ring_sec=0.3, octave=0)
    return finish(mix_chip(1.5, snap, (burst, 0.008), (shards, 0.04), (groan, 0.12)), 1.15)


# --- The Brain eats a letter (a loss for the players) -----------------------
# The body tell gulps over EAT_GULP_SEC (0.3 s).

def eat_gulp() -> np.ndarray:
    """A: a wet squelch sliding down into a soft swallow thump."""
    squelch = sweep(0.28, 1300.0, 240.0, seed=831, q=1.6, attack=0.015, half_life=0.12) * 0.8
    swallow = thud(0.25, 450.0, 0.04, seed=832, rate=7000.0, sub_hz=110.0, sub_level=0.1) * 0.7
    return finish(mix_chip(0.6, squelch, (swallow, 0.2)), 1.2)


def eat_chomp() -> np.ndarray:
    """B: a crunch as the block is bitten, then the gulp."""
    bite = clacks([0.0, 0.03], seed=841, low_hz=700.0, high_hz=3200.0, body_cut=1100.0, levels=[1.0, 0.6])
    squelch = sweep(0.24, 1100.0, 260.0, seed=842, q=1.6, attack=0.01, half_life=0.1) * 0.6
    swallow = thud(0.25, 450.0, 0.04, seed=843, rate=7000.0, sub_hz=110.0, sub_level=0.1) * 0.6
    return finish(mix_chip(0.65, bite, (squelch, 0.09), (swallow, 0.26)), 1.2)


def eat_slurp_growl() -> np.ndarray:
    """C: a slurp drawing in, the gulp, and a short satisfied growl of the
    boss voice."""
    slurp = sweep(0.2, 350.0, 1600.0, seed=851, q=3.0, attack=0.12, half_life=0.2) * 0.5
    squelch = sweep(0.24, 1200.0, 240.0, seed=852, q=1.6, attack=0.01, half_life=0.1) * 0.7
    swallow = thud(0.25, 450.0, 0.04, seed=853, rate=7000.0, sub_hz=110.0, sub_level=0.1) * 0.6
    growl = boss_voice(18, 0.0, -1.0, gain_db=-10.0, open_from=6.0, open_to=14.0, ring_sec=0.15, octave=0)
    return finish(mix_chip(0.95, slurp, (squelch, 0.18), (swallow, 0.36), (growl, 0.42)), 1.2)


# =============================================================================
# Scramble puzzle
# =============================================================================

# --- Puzzle lands --------------------------------------------------------------

def puzzle_thunk() -> np.ndarray:
    """A: one solid thunk on the floor and a short rattle of the tiles."""
    hit = thud(0.25, 1000.0, 0.03, seed=901, rate=9000.0, sub_hz=130.0, sub_level=0.25)
    rattle = clacks([0.05, 0.08, 0.12], seed=902, levels=[0.4, 0.3, 0.2])
    return finish(mix_chip(0.4, hit, rattle), 1.1)


def puzzle_clatter() -> np.ndarray:
    """B: the letters dropping one by one, like dice: a soft thump and four
    tile clacks spilling out."""
    hit = thud(0.15, 600.0, 0.02, seed=911, rate=8000.0) * 0.5
    tiles = clacks([0.02, 0.07, 0.13, 0.2], seed=912, low_hz=1100.0, high_hz=5500.0, body_cut=1800.0,
                   levels=[1.0, 0.8, 0.85, 0.6])
    return finish(mix_chip(0.35, hit, tiles), 1.1)


def puzzle_armed() -> np.ndarray:
    """C: the thunk, then a short sizzle of a fuse catching: it is armed."""
    hit = thud(0.25, 1000.0, 0.03, seed=901, rate=9000.0, sub_hz=130.0, sub_level=0.25)
    fuse_sec = 0.6
    hiss = _norm(s.highpass(s.noise(fuse_sec, 921), 3000.0)) * s.decay(fuse_sec, 0.18, attack=0.05)
    hiss = dac(hiss, 14000.0) * 0.3
    sparks = base.crackles(fuse_sec, 25.0, seed=922) * 0.5
    return finish(mix_chip(0.8, hit, (hiss, 0.06), (sparks, 0.06)), 1.1)


# --- A letter hatches into a seeker (3-4 in a row, 0.3 s apart) -------------

def hatch_crack_whoof() -> np.ndarray:
    """A: a shell cracking and fire catching with a whoof."""
    snap = crack(0.02, 1500.0, 7000.0, seed=931) * 0.7
    whoof = base.air_bloom(0.25, 0.012, 0.05, seed=932) * 0.9
    sparks = base.crackles(0.15, 30.0, seed=933) * 0.4
    return finish(mix_chip(0.3, snap, (whoof, 0.01), (sparks, 0.02)), 1.3)


def hatch_pop_hiss() -> np.ndarray:
    """B: a small pop and a hiss climbing fast, cut off as it launches."""
    pop = thud(0.05, 1600.0, 0.008, seed=941, rate=10000.0) * 0.8
    hiss = psg_rise(9, 1800.0, 9000.0, seed=942, peak_at=0.85) * 0.5
    return finish(mix_chip(0.22, pop, (hiss, 0.02)), 1.2)


def hatch_crack_chirp() -> np.ndarray:
    """C: take A's crack and whoof, with a short rising chirp of the boss
    voice an octave up: the boss's creature waking."""
    snap = crack(0.02, 1500.0, 7000.0, seed=931) * 0.7
    whoof = base.air_bloom(0.25, 0.012, 0.05, seed=932) * 0.8
    chirp = boss_voice(6, 0.0, 4.0, gain_db=-8.0, open_from=4.0, open_to=0.0, ring_sec=0.06, octave=1)
    return finish(mix_chip(0.3, snap, (whoof, 0.01), (chirp, 0.02)), 1.3)


def _hatch_times():
    return [i * HATCH_STAGGER_SEC for i in range(PUZZLE_LETTERS)]


# --- Correct tap (PROGRESS layer: may be tonal, sparse) ---------------------
# Shared with popping a chasing seeker (POP_VFX). In key: kit.scale_hz.

def _tile_click(seed: int, level: float = 1.0) -> np.ndarray:
    return clacks([0.0], seed=seed, low_hz=1800.0, high_hz=6500.0, body_cut=2500.0, levels=[level])


def tap_click_note(step: int = 0) -> np.ndarray:
    """A: a tile click with a short, quiet menu-blip note on the key."""
    click = _tile_click(951, 0.5)
    hz = scale_hz(step, 1)
    tone = base.note(base.BLIP, hz, 2, ring_sec=0.1)
    return finish(mix_chip(0.2, click, tone))


def tap_bar(step: int = 0) -> np.ndarray:
    """B: a woody struck-bar note on the key, no click: the most musical."""
    tone = base.note(base.BAR, scale_hz(step, 1), 2, ring_sec=0.14)
    return finish(mix_chip(0.2, tone))


def tap_lock_only(step: int = 0) -> np.ndarray:
    """C: no note at all: a solid lock clack, for comparison."""
    click = _tile_click(961)
    lock = thud(0.06, 1500.0, 0.01, seed=962, rate=10000.0) * 0.5
    return finish(mix_chip(0.14, click, (lock, 0.012)))


def _tap_demo(build) -> np.ndarray:
    """A fast solver: four accepted taps FAST_TAP_SEC apart. The tonal takes
    climb the scale per letter (that needs PlaybackSpeed per tap index in
    the game); the click-only take repeats one file."""
    layers = [(build(step), 1.0, i * FAST_TAP_SEC) for i, step in enumerate((0, 1, 2, 4))]
    return s.mix(*layers)


# --- Word sent back at the boss (progress leads, a world impact follows) -----
# Plays once at the puzzle's centre (DEFUSE_VFX; the boss-damage switch is off).

def defuse_rise_hit() -> np.ndarray:
    """A: a quick three-note rise on the key, then a whoosh away and a
    muffled hit."""
    rise = base.arpeggio(base.BLIP, [scale_hz(k, 1) for k in (0, 2, 4)], 2, ring_sec=0.12, gain_db=-3.0)
    whoosh = psg_rise(14, 900.0, 7000.0, seed=971, peak_at=0.7) * 0.4
    hit = thud(0.35, 700.0, 0.04, seed=972, rate=9000.0, sub_hz=100.0, sub_level=0.25) * 0.9
    return finish(mix_chip(0.75, rise, (whoosh, 0.1), (hit, 0.32)), 1.1)


def defuse_stab_boom() -> np.ndarray:
    """B: one bright brass stab on the key's root and fifth, with a blast of
    air and a thud under it at once."""
    root = base.note(base.BRASS, scale_hz(0, 1), 5, ring_sec=0.2)
    fifth = base.note(base.BRASS, scale_hz(3, 1), 5, ring_sec=0.2, gain_db=-3.0)
    air = base.air_bloom(0.4, 0.01, 0.08, seed=981) * 0.6
    hit = thud(0.35, 700.0, 0.04, seed=982, rate=9000.0, sub_hz=100.0, sub_level=0.25) * 0.6
    return finish(mix_chip(0.7, root, fifth, (air, 0.02), (hit, 0.02)), 1.1)


def defuse_physical() -> np.ndarray:
    """C: no note: a rush away, a hard hit, and the boss voice grunting in
    pain, for comparison."""
    whoosh = psg_rise(14, 900.0, 7000.0, seed=991, peak_at=0.7) * 0.5
    lead = thud(0.04, 1500.0, 0.006, seed=994, rate=10000.0) * 0.3
    snap = crack(0.025, 1200.0, 6000.0, seed=992) * 0.4
    hit = thud(0.35, 700.0, 0.04, seed=993, rate=9000.0, sub_hz=100.0, sub_level=0.25)
    grunt = boss_voice(12, 0.0, -5.0, gain_db=-10.0, open_from=0.0, open_to=10.0, ring_sec=0.15, octave=0)
    return finish(mix_chip(0.85, lead, whoosh, (snap, 0.22), (hit, 0.23), (grunt, 0.3)), 1.1)


# =============================================================================
# Round 2 (2026-11-28), from the user's notes on round 1
# =============================================================================
# The takes the user picked in round 1 are built from the helpers above, so
# those helpers are frozen: round 2 adds new ones and never edits the old.
# Chosen: ward_swirl_hum, ward_shatter_groan, puzzle_armed, hatch_crack_whoof,
# tap_bar, defuse_rise_hit.


def swept_lowpass(x: np.ndarray, cutoff_hz: np.ndarray, blocks: int = 64) -> np.ndarray:
    """A low-pass whose cut-off follows a curve, in short blocks, each block
    re-filtered from one block earlier so the filter has settled."""
    out = np.zeros(len(x))
    edges = np.linspace(0, len(x), blocks + 1).astype(int)
    for a, b in zip(edges[:-1], edges[1:]):
        cut = float(np.clip(np.mean(cutoff_hz[a:b]), 30.0, SAMPLE_RATE * 0.45))
        sos = signal.butter(2, cut, "lowpass", fs=SAMPLE_RATE, output="sos")
        lo = max(0, a - (b - a))
        out[a:b] = signal.sosfilt(sos, x[lo:b])[a - lo:]
    return out


def shaped_noise(sec: float, low_hz: float, high_hz: float, seed: int, attack: float,
                 half_life: float, rate: float = 10000.0) -> np.ndarray:
    """Band-passed noise with a soft attack: a breath of air or flame, not a
    knock (round 1's launch was a 1 ms attack and read as 'hammering a nail')."""
    x = _norm(s.bandpass(s.noise(sec, seed), low_hz, high_hz))
    return dac(x * s.decay(sec, half_life, attack=attack), rate)


def tremor(sec: float, rate_hz: float, depth: float, seed: int) -> np.ndarray:
    """An uneven shake: a 0..1 random swell faster than a breath, as gain."""
    return 1.0 - depth + depth * base.breath(sec, rate_hz, seed)


def gravel(sec: float, per_sec, seed: int, low_hz: float = 220.0, high_hz: float = 1400.0) -> np.ndarray:
    """Rock and debris rattling: dull grains, low and mid, never the bright
    pops of fire. `per_sec` may be a function of time (0..1) for a build."""
    rng = np.random.default_rng(seed)
    x = np.zeros(s.n_samples(sec))
    t = 0.0
    while True:
        rate = per_sec(t / sec) if callable(per_sec) else per_sec
        t += rng.exponential(1.0 / max(rate, 0.5))
        if t >= sec - 0.03:
            break
        length = rng.uniform(0.006, 0.02)
        grain = s.bandpass(s.noise(length, int(rng.integers(1 << 30))), low_hz, high_hz)
        grain = _norm(grain) * s.decay(length, length * 0.3, attack=0.0005)
        at = s.n_samples(t) - 1
        x[at:at + len(grain)] += grain[: len(x) - at] * rng.lognormal(-0.7, 0.5)
    return ym.dac_sample(x, SAMPLE_RATE, 9000.0)


def deep_roar(sec: float, seed: int, cut_hz: float = 120.0) -> np.ndarray:
    """The sub of an earthquake: very low noise, through a slow DAC."""
    return dac(s.lowpass(s.noise(sec, seed), cut_hz, order=4), 4000.0)


# --- Volley launch, round 2: fire shot out --------------------------------------
# User: "sounds too much like hammering a nail, doesn't sound like a fire
# being shot out". Measured on round 1: a 1 ms attack, 34-42 dB of punch and
# under 0.25 s. So: a softer attack (peak 20 ms or more in), a breathy flame
# body, and a tail that carries the shot away.

def shot_fwoosh() -> np.ndarray:
    """A: a fwoosh of flame: breathy noise swelling in fast and trailing off,
    with a puff of air behind it and a few crackles."""
    flame = shaped_noise(0.4, 300.0, 2600.0, seed=1001, attack=0.03, half_life=0.07)
    puff = base.air_bloom(0.3, 0.02, 0.05, seed=1002) * 0.5
    pops = base.crackles(0.25, 22.0, seed=1003) * 0.3
    return finish(mix_chip(0.42, flame, puff, (pops, 0.04)), 1.3)


def shot_jet() -> np.ndarray:
    """B: a flame jet: a burst of noise whose brightness opens and closes,
    like a short blast from a flamethrower."""
    sec = 0.42
    cut = np.interp(np.arange(s.n_samples(sec)), [0, s.n_samples(0.06), s.n_samples(sec)], [600.0, 3500.0, 700.0])
    x = swept_lowpass(s.noise(sec, 1011), cut, blocks=48)
    x = _norm(s.highpass(x, 180.0)) * s.decay(sec, 0.09, attack=0.025)
    jet = dac(x, 11000.0)
    pops = base.crackles(0.3, 18.0, seed=1012) * 0.3
    return finish(mix_chip(0.44, jet, (pops, 0.05)), 1.4)


def shot_whoomp_away() -> np.ndarray:
    """C: a soft low whoomp as the fireball leaves, and its roar falling
    away from you."""
    whoomp = base.air_bloom(0.3, 0.018, 0.05, seed=1021) * 0.8
    away = sweep(0.45, 1800.0, 500.0, seed=1022, q=1.0, attack=0.03, half_life=0.09, rate=10000.0) * 0.8
    return finish(mix_chip(0.47, whoomp, (away, 0.01)), 1.3)


# --- Projectile death, round 2: fire fizzling out ------------------------------
# User: "none of these sounds like fire fizzling out. it sounds like something
# splatting". Round 1 led with a low thud (centroid 550 Hz). A fizzle is high
# hiss with almost no low end: centroid well over 2 kHz.

def death_hiss() -> np.ndarray:
    """A: the flame snuffed: a quick high hiss dying away, a few last
    crackles."""
    hiss = dac(_norm(s.highpass(s.noise(0.32, 1031), 2500.0)) * s.decay(0.32, 0.06, attack=0.004), 16000.0)
    pops = base.crackles(0.2, 30.0, seed=1032) * 0.35
    return finish(mix_chip(0.33, hiss, (pops, 0.01)))


def death_sizzle() -> np.ndarray:
    """B: a sputtering sizzle, like water on embers: high noise that cuts in
    and out at random as it dies."""
    sec = 0.36
    x = _norm(s.bandpass(s.noise(sec, 1041), 3000.0, 9000.0))
    gate = (s.held_noise(45.0, sec, 1042) > -0.2).astype(float)
    gate = s.lowpass(gate, 300.0)
    x = x * gate * s.decay(sec, 0.09, attack=0.003)
    return finish(mix_chip(0.37, dac(x, 18000.0)), 1.6)


def death_fizz_down() -> np.ndarray:
    """C: a soft puff of flame and the console's fizz stepping slowly down."""
    puff = shaped_noise(0.12, 600.0, 3000.0, seed=1051, attack=0.004, half_life=0.02) * 0.4
    vols = [3, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    fizz = base.noise_burst(vols, shift_hz=ym.frames(np.geomspace(14000.0, 4000.0, len(vols))), seed=1052) * 0.6
    return finish(mix_chip(0.27, puff, (fizz, 0.01)))


# --- Ground Slam, round 2: an impact, then a shockwave -------------------------
# User: "sounds like an inferno rather than a ground slam. There is no distinct
# impact, and shockwave sound. just a high to low consistent sound." Measured
# on round 1: punch 4-6 dB (the second wave filled the 100-200 ms window) and
# fire-like crackles on the tail. So: a hit that stands 9 dB or more over
# 100-200 ms later, a separate shockwave starting ~0.22 s in that does not
# fall from high to low, a bass rumble, and no crackles. Both events sit
# inside the first 0.5 s, in case the game cuts the sound there.

SLAM2_SEC = 1.9
SHOCK_AT_SEC = 0.22


def slam_impact(seed: int) -> np.ndarray:
    """The ground taking the blow: heavy low noise, a sub drop and a crunch of
    rock, saturated so a phone hears it."""
    sec = 0.35
    body = _norm(s.lowpass(s.noise(sec, seed), 550.0)) * s.decay(sec, 0.04, attack=0.001)
    crunch = _norm(s.bandpass(s.noise(sec, seed + 1), 180.0, 1400.0)) * s.decay(sec, 0.018, attack=0.0005)
    sub = s.sine(s.glide(110.0, 42.0, sec, curve=1.6)) * s.decay(sec, 0.045, attack=0.001)
    return dac(s.drive(_norm(body + crunch * 0.6 + sub * 0.12), 2.6), 9000.0)


def shock_whump(seed: int) -> np.ndarray:
    """The pressure wave as a deep whump: low air swelling in and out, with a
    little mid rush on it. Its band holds still; it does not sweep down."""
    sec = 1.2
    low = _norm(s.lowpass(s.noise(sec, seed), 240.0, order=3))
    mid = _norm(s.bandpass(s.noise(sec, seed + 1), 300.0, 1500.0)) * 0.35
    env = s.decay(sec, 0.22, attack=0.07)
    return dac((low + mid) * env, 7000.0)


def shock_rush(seed: int) -> np.ndarray:
    """The pressure wave as air rushing past: a steady band of noise that
    swells up and passes, rising and falling in level only."""
    sec = 0.8
    x = _norm(s.bandpass(s.noise(sec, seed), 250.0, 1800.0))
    t = np.linspace(0.0, 1.0, len(x))
    passing = np.sin(np.pi * t ** 0.6) ** 2
    return dac(x * passing, 10000.0)


def quake_tail(sec: float, seed: int, level: float) -> np.ndarray:
    """What is left: a low rolling rumble that shakes as it fades."""
    roar = deep_roar(sec, seed, 140.0)
    body = dac(_norm(s.bandpass(s.noise(sec, seed + 1), 60.0, 350.0)) * tremor(sec, 7.0, 0.5, seed + 2)
               * s.decay(sec, 0.35, attack=0.05), 6000.0)
    roar = roar * ym.dac_sample(s.decay(sec, 0.4, attack=0.05), SAMPLE_RATE, 4000.0)
    return (roar * 0.6 + body) * level


def slam_hit_whump() -> np.ndarray:
    """A: a heavy hit, a breath of quiet, then the shockwave as a deep whump
    and a shaking rumble rolling out."""
    hit = slam_impact(1101)
    wave = shock_whump(1102) * 1.1
    tail = quake_tail(1.75, 1103, 0.7)
    return finish(mix_chip(SLAM2_SEC, hit, (wave, SHOCK_AT_SEC), (tail, 0.03)), 1.1)


def slam_hit_rush() -> np.ndarray:
    """B: the heavy hit, then the shockwave as a rush of air sweeping past
    you, over a low rumble."""
    hit = slam_impact(1111)
    wave = shock_rush(1112) * 1.0
    tail = quake_tail(1.75, 1113, 0.45)
    return finish(mix_chip(SLAM2_SEC, hit, (wave, SHOCK_AT_SEC - 0.04), (tail, 0.03)), 1.1)


def slam_hit_whump_roar() -> np.ndarray:
    """C: take A with the boss voice roaring under the shockwave, held level
    (not falling)."""
    hit = slam_impact(1101)
    wave = shock_whump(1102) * 1.0
    tail = quake_tail(1.75, 1103, 0.65)
    roar = boss_voice(50, 0.0, -1.0, gain_db=-11.0, open_from=4.0, open_to=12.0, ring_sec=0.35, octave=0)
    return finish(mix_chip(SLAM2_SEC, hit, (wave, SHOCK_AT_SEC), (tail, 0.03),
                           (roar, SHOCK_AT_SEC)), 1.1)


# --- New cue: the boss rises before the slam ------------------------------------
# User: "a 'big' boss taking off in a whoosh". The body tell (TelegraphConstants):
# rises over SLAM_RISE_SEC, hangs trembling, drops in the last SLAM_DROP_SEC to
# land on WindupEndsAt; the whole warning is 1.8 s. The cue plays from the
# windup start and stops at the landing, where the slam cue takes over.
SLAM_RISE_SEC = 0.65
SLAM_DROP_SEC = 0.18
SLAM_WARNING_SEC = 1.8


def _lift_whoosh(seed: int, sec: float = SLAM_RISE_SEC + 0.25) -> np.ndarray:
    """A heavy body pushing air down as it lifts: low noise whose band opens
    upward while it swells, then closes as it slows at the top."""
    n = s.n_samples(sec)
    peak = s.n_samples(SLAM_RISE_SEC * 0.75)
    cut = np.interp(np.arange(n), [0, peak, n], [250.0, 1800.0, 400.0])
    x = _norm(swept_lowpass(s.noise(sec, seed), cut, blocks=64))
    env = np.interp(np.arange(n), [0, peak, n], [0.15, 1.0, 0.0]) ** 1.3
    low = _norm(s.lowpass(s.noise(sec, seed + 1), 160.0, order=3)) * env
    return dac(x * env + low * 0.7, 9000.0)


def _hang(seed: int, sec: float) -> np.ndarray:
    """Hanging in the air, trembling: a low unsteady rumble."""
    x = _norm(s.bandpass(s.noise(sec, seed), 50.0, 400.0)) * tremor(sec, 9.0, 0.6, seed + 1)
    fade = np.interp(np.arange(s.n_samples(sec)), [0, s.n_samples(0.15), s.n_samples(sec)], [0.0, 1.0, 0.8])
    return dac(x * fade, 6000.0)


def _drop_whoosh(seed: int) -> np.ndarray:
    """The fall: a short rush of air, rising in level into the landing."""
    sec = SLAM_DROP_SEC + 0.02
    x = _norm(s.bandpass(s.noise(sec, seed), 200.0, 2500.0)) * s.swell(sec, 2.0)
    return dac(x, 10000.0)


def rise_full() -> np.ndarray:
    """A: the whole move: a big whoosh up, a trembling hang, and a short rush
    down that stops where the slam lands."""
    hang_at = SLAM_RISE_SEC
    hang_sec = SLAM_WARNING_SEC - SLAM_DROP_SEC - hang_at
    drop_at = SLAM_WARNING_SEC - SLAM_DROP_SEC
    lift = _lift_whoosh(1201)
    hang = _hang(1202, hang_sec + 0.05) * 0.35
    drop = _drop_whoosh(1203) * 0.8
    return finish(mix_chip(SLAM_WARNING_SEC, lift, (hang, hang_at), (drop, drop_at)), 1.2)


def rise_liftoff() -> np.ndarray:
    """B: only the take-off: one big whoosh up that fades as it reaches the
    top, leaving the slam cue to carry the landing."""
    return finish(mix_chip(1.0, _lift_whoosh(1211, 1.0)), 1.2)


def rise_full_tell() -> np.ndarray:
    """C: take A with the boss voice rising through the hang: the proposed
    rising tell, as long as the windup."""
    hang_at = SLAM_RISE_SEC
    hang_sec = SLAM_WARNING_SEC - SLAM_DROP_SEC - hang_at
    drop_at = SLAM_WARNING_SEC - SLAM_DROP_SEC
    lift = _lift_whoosh(1201)
    hang = _hang(1202, hang_sec + 0.05) * 0.3
    drop = _drop_whoosh(1203) * 0.8
    frames_on = int((SLAM_WARNING_SEC - 0.3) * ym.FRAME_HZ)
    tell = boss_voice(frames_on, 0.0, 5.0, gain_db=-10.0, open_from=18.0, open_to=0.0, ring_sec=0.05, octave=0)
    return finish(mix_chip(SLAM_WARNING_SEC, lift, (hang, hang_at), (drop, drop_at), (tell, 0.2)), 1.2)


# --- Entrance start, round 2: an earthquake approaching -------------------------
# User: "none of they sound rumble-ly or bass-y, let's try something more like
# an approaching earth quake?" Round 1's rumble had its centroid at 326 Hz and
# under 20% of its energy below 150 Hz. Now most of it sits below 150 Hz
# (headphones), with a shaking body and rattling gravel in 150 Hz-1.4 kHz so a
# phone still hears it, and it grows the whole time.
QUAKE_SEC = 4.0


def _quake(seed: int, sec: float, envelope: np.ndarray) -> np.ndarray:
    roar = deep_roar(sec, seed, 110.0)
    body = dac(_norm(s.bandpass(s.noise(sec, seed + 1), 45.0, 300.0)) * tremor(sec, 8.0, 0.55, seed + 2), 5000.0)
    grind = dac(_norm(s.bandpass(s.noise(sec, seed + 3), 150.0, 700.0)) * tremor(sec, 5.0, 0.7, seed + 4), 7000.0)
    gain = ym.dac_sample(envelope, SAMPLE_RATE, 4000.0)
    n = min(len(roar), len(body), len(grind), len(gain))
    stones = gravel(sec, lambda u: 2.0 + 40.0 * u ** 2, seed + 5)[:n]
    bed = ym.psg_noise(1.0, sec, divider=base.RUMBLE_DIVIDER, seed=seed + 6)[:n] * 0.15
    return (roar[:n] * 1.0 + body[:n] * 0.6 + grind[:n] * 0.2 + bed) * gain[:n] + stones * 0.5 * gain[:n]


def _crescendo(sec: float, peak_at: float, power: float = 2.2) -> np.ndarray:
    n = s.n_samples(sec)
    t = np.arange(n) / SAMPLE_RATE
    up = np.clip(t / peak_at, 0.0, 1.0) ** power
    down = np.clip(1.0 - (t - peak_at) / (sec - peak_at), 0.0, 1.0)
    return np.where(t < peak_at, 0.12 + 0.88 * up, down)


def quake_approach() -> np.ndarray:
    """A: an earthquake coming closer: a deep roar and a shaking rumble
    growing for 3.4 s, gravel rattling harder, then settling."""
    return finish(base.out(_quake(1301, QUAKE_SEC, _crescendo(QUAKE_SEC, 3.4))), 1.3)


def quake_surges() -> np.ndarray:
    """B: the quake in three surges, each nearer and bigger than the last."""
    n = s.n_samples(QUAKE_SEC)
    t = np.arange(n) / SAMPLE_RATE
    env = np.zeros(n)
    for at, level in ((0.0, 0.35), (1.3, 0.65), (2.5, 1.0)):
        u = np.clip((t - at) / 1.3, 0.0, 1.0)
        env = np.maximum(env, np.maximum(0.15 * level, level * np.sin(np.pi * u ** 0.7)) * (t >= at))
    return finish(base.out(_quake(1311, QUAKE_SEC, env)), 1.3)


def quake_approach_growl() -> np.ndarray:
    """C: take A with the boss voice growling up from inside the quake."""
    quake = _quake(1301, QUAKE_SEC, _crescendo(QUAKE_SEC, 3.4))
    frames_on = int(3.2 * ym.FRAME_HZ)
    growl = boss_voice(frames_on, 0.0, 3.0, gain_db=-12.0, open_from=22.0, open_to=4.0, ring_sec=0.4, octave=0)
    swell = ym.frames(np.linspace(0.0, 1.0, frames_on) ** 2)
    growl = growl * np.concatenate([swell, np.ones(max(0, len(growl) - len(swell)))])[:len(growl)]
    return finish(base.out(ym.place(len(quake), quake, (growl, 0.6))), 1.3)


# --- Entrance landing, round 2: take C, bass-ier --------------------------------
# User: take C (thud + roar) is closer, but "needs to sound bass-y". Round 1's
# C had its hit at 420 Hz cut-off. Now the hit is a deep slam of low noise
# and sub with a long low bloom; the roar is round 1's, or an octave lower.

def bass_landing(seed: int) -> np.ndarray:
    sec = 0.7
    body = _norm(s.lowpass(s.noise(sec, seed), 320.0, order=3)) * s.decay(sec, 0.07, attack=0.002)
    sub = s.sine(s.glide(90.0, 38.0, sec, curve=1.4)) * s.decay(sec, 0.06, attack=0.002)
    smack = _norm(s.bandpass(s.noise(sec, seed + 1), 200.0, 1200.0)) * s.decay(sec, 0.015, attack=0.0005)
    hit = dac(s.drive(_norm(body + sub * 0.18 + smack * 0.4), 2.4), 7000.0)
    bloom = dac(_norm(s.lowpass(s.noise(1.0, seed + 2), 150.0, order=3)) * s.decay(1.0, 0.18, attack=0.03), 4000.0)
    return ym.place(max(len(hit), len(bloom)), hit, (bloom * 0.6, 0.02))


def land_bass_roar() -> np.ndarray:
    """A: a deep, heavy landing with a low bloom, then round 1's roar."""
    roar = boss_voice(40, 1.0, -2.0, gain_db=-9.0, open_from=10.0, open_to=2.0, ring_sec=0.3, octave=0)
    return finish(mix_chip(1.5, bass_landing(1401), (roar, 0.22)), 1.15)


def land_bass_deep_roar() -> np.ndarray:
    """B: the same deep landing, with the roar doubled an octave down."""
    roar = boss_voice(40, 1.0, -2.0, gain_db=-9.0, open_from=10.0, open_to=2.0, ring_sec=0.3, octave=0)
    under = boss_voice(40, 1.0, -2.0, gain_db=-9.0, open_from=8.0, open_to=0.0, ring_sec=0.3, octave=-1)
    return finish(mix_chip(1.5, bass_landing(1401), (roar, 0.22), (under, 0.22)), 1.15)


# --- The Brain eats a letter, round 2: crunch and gulp --------------------------
# User: "can i get a gulp an crunch sound?" A crunch is many dull-bright
# grains over a tenth of a second (a block bitten); a gulp is a short throat
# 'glk', a resonance falling fast with a little release after it.

def crunch(sec: float, seed: int, grains: int = 14) -> np.ndarray:
    rng = np.random.default_rng(seed)
    x = np.zeros(s.n_samples(sec))
    for i in range(grains):
        t = sec * (i / grains) ** 1.3 * 0.9
        length = rng.uniform(0.004, 0.012)
        g = s.bandpass(s.noise(length, int(rng.integers(1 << 30))), rng.uniform(500.0, 1200.0), rng.uniform(2500.0, 5000.0))
        g = _norm(g) * s.decay(length, length * 0.3, attack=0.0003) * (1.0 - 0.5 * i / grains) * rng.uniform(0.6, 1.0)
        at = s.n_samples(t) - 1
        x[at:at + len(g)] += g[: len(x) - at]
    body = _norm(s.lowpass(s.noise(sec, seed + 1), 900.0)) * s.decay(sec, 0.02, attack=0.001) * 0.6
    return dac(x + body, 12000.0)


def glk(seed: int, depth: float = 1.0) -> np.ndarray:
    """A gulp: a throat resonance dropping fast, then a small release."""
    sec = 0.09
    down = s.swept_bandpass(s.noise(sec, seed), s.glide(700.0 * depth, 230.0 * depth, sec, curve=1.5), q=5.0, blocks=12)
    down = _norm(down) * s.decay(sec, 0.025, attack=0.004)
    rel_sec = 0.05
    up = s.swept_bandpass(s.noise(rel_sec, seed + 1), s.glide(300.0 * depth, 650.0 * depth, rel_sec), q=4.0, blocks=8)
    up = _norm(up) * s.decay(rel_sec, 0.012, attack=0.003) * 0.45
    thump = s.sine(s.glide(150.0 * depth, 70.0 * depth, 0.12)) * s.decay(0.12, 0.025, attack=0.002) * 0.3
    return dac(s.mix(down, (up, 1.0, 0.085), thump), 9000.0)


def eat_crunch_gulp() -> np.ndarray:
    """A: one crunching bite, then a gulp."""
    return finish(mix_chip(0.5, crunch(0.13, 1501), (glk(1502), 0.2)), 1.2)


def eat_chomp_gulp() -> np.ndarray:
    """B: two big crunching bites, then a deeper gulp."""
    return finish(mix_chip(0.65, crunch(0.12, 1511), (crunch(0.1, 1512, 10) * 0.75, 0.15),
                           (glk(1513, 0.75), 0.36)), 1.2)


def eat_crunch_gulp_growl() -> np.ndarray:
    """C: take A, with a short satisfied growl of the boss voice after."""
    growl = boss_voice(18, 0.0, -1.0, gain_db=-10.0, open_from=6.0, open_to=14.0, ring_sec=0.15, octave=0)
    return finish(mix_chip(0.8, crunch(0.13, 1501), (glk(1502), 0.2), (growl, 0.32)), 1.2)


# =============================================================================
# Sheet
# =============================================================================

def _cue(cid, label, group, band, note, **extra):
    return {"id": cid, "label": label, "group": group, "band": band, "note": note, **extra}


ATTACK = "Boss attacks"
BOSS = "Boss presence and ward"
PUZZLE = "Scramble puzzle"
# Column C carries the proposed boss voice (a low tritone growl, detuned) on
# every boss cue; A and B are physical only.

SHEET = [
    _cue("projectile_boss_fireball", "Boss volley: one shot launched", ATTACK, "boss",
         "Round 2, fire shot out (softer attack, flame body). A: fwoosh of flame + puff + crackles. "
         "B: flame-jet burst opening and closing. C: soft low whoomp + roar falling away (no voice)."),
    _cue("demo_volley", "Demo: a 20-shot volley (launches)", ATTACK, "boss",
         "One file, 20 plays 0.15 s apart at +-4% speed. At this length the shots overlap into a stream.", demo=True),
    _cue("projectile_destroy", "A projectile dies on a wall or in the air", ATTACK, "gameplay",
         "Round 2, fizzling out, no low thud. A: high hiss snuffed + last crackles. B: sputtering sizzle. "
         "C: small flame puff + the console's fizz stepping down."),
    _cue("demo_volley_landing", "Demo: the volley launching and landing", ATTACK, "boss",
         "Launches with this column's death take ~0.6 s behind, 6 dB down, as heard from cover.", demo=True),
    _cue("boss_slam_rise", "NEW: the boss rises before the Ground Slam", ATTACK, "boss",
         "1.8 s, the windup: rise 0.65 s, hang trembling, drop 0.18 s into the slam. A: big whoosh up, "
         "trembling hang, rush down. B: just the big take-off whoosh. C: A + the boss voice rising (the tell)."),
    _cue("aoe_boss_groundslam", "Ground Slam lands", ATTACK, "boss",
         "Round 2: a hit, a beat, then the shockwave; no crackles, nothing falling high to low. A: hit, deep "
         "whump, shaking rumble. B: hit, a rush of air sweeping past, rumble. C: A + the boss roar held level."),
    _cue("impact_knockup", "Launched skyward: a PLAYER thrown up by the slam", ATTACK, "gameplay",
         "Unchanged from round 1: please judge as the player's launch (the boss rising is the new cue above). "
         "A: thump + climbing whoosh. B: thump + air swept up. C: cracked hit + short zip."),
    _cue("boss_entrance_start", "Boss entrance: countdown starts", BOSS, "boss",
         "Round 2, an earthquake approaching, 4 s, bass-heavy. A: one long build, gravel rattling harder. "
         "B: three surges, each nearer. C: A + the boss voice growling up from inside it."),
    _cue("boss_entrance_appear", "Boss entrance: the Brain lands", BOSS, "boss",
         "Round 2, your take C made bass-ier. A: deep heavy landing + low bloom + the same roar. "
         "B: the same with the roar doubled an octave down. C: round 1's take C, to compare."),
    _cue("boss_ward_up", "Word ward goes up", BOSS, "boss", "CHOSEN: take C (round 1). Unchanged."),
    _cue("boss_ward_down", "Word ward breaks", BOSS, "boss", "CHOSEN: take C (round 1). Unchanged."),
    _cue("boss_hunger_eat", "The Brain eats a letter", BOSS, "boss",
         "Round 2, crunch + gulp. A: one crunching bite, a throat gulp. B: two bites, a deeper gulp. "
         "C: A + a short satisfied boss growl."),
    _cue("scramble_land", "Scramble puzzle lands", PUZZLE, "boss", "CHOSEN: take C (round 1). Unchanged."),
    _cue("scramble_hatch", "A letter hatches into a seeker", PUZZLE, "boss", "CHOSEN: take A (round 1). Unchanged."),
    _cue("demo_scramble_hatch", "Demo: four letters hatching", PUZZLE, "boss",
         "One file, four plays 0.3 s apart.", demo=True),
    _cue("scramble_tap", "Scramble: correct tap", PUZZLE, "gameplay", "CHOSEN: take B (round 1). Unchanged."),
    _cue("demo_scramble_tap", "Demo: a fast solve, four taps", PUZZLE, "gameplay",
         "Four taps 0.3 s apart, climbing the scale per letter (needs PlaybackSpeed per tap in game).", demo=True),
    _cue("scramble_defuse", "Scramble: word sent back at the boss", PUZZLE, "gameplay",
         "CHOSEN: take A (round 1). Unchanged."),
]

_LAUNCH = {"a": shot_fwoosh, "b": shot_jet, "c": shot_whoomp_away}
_DEATH = {"a": death_hiss, "b": death_sizzle, "c": death_fizz_down}
_HATCH = {"a": hatch_crack_whoof, "b": hatch_pop_hiss, "c": hatch_crack_chirp}
_TAP = {"a": tap_click_note, "b": tap_bar, "c": tap_lock_only}


def _volley_landing(take: str) -> np.ndarray:
    launches = repeat_demo(_LAUNCH[take], _volley_times(), seed=561)
    deaths = repeat_demo(_DEATH[take], _death_times(), seed=562)
    return s.mix((launches, 1.0, 0.0), (deaths, _db(-6.0), 0.0))


def _column(take: str, **cues) -> dict:
    col = {
        "projectile_boss_fireball": _LAUNCH[take],
        "demo_volley": lambda: repeat_demo(_LAUNCH[take], _volley_times(), seed=561),
        "projectile_destroy": _DEATH[take],
        "demo_volley_landing": lambda: _volley_landing(take),
        "scramble_hatch": _HATCH[take],
        "demo_scramble_hatch": lambda: repeat_demo(_HATCH[take], _hatch_times(), seed=563),
        "scramble_tap": _TAP[take],
        "demo_scramble_tap": lambda: _tap_demo(_TAP[take]),
    }
    col.update(cues)
    return col


CUES: dict[str, dict] = {
    "a": _column("a", boss_slam_rise=rise_full, aoe_boss_groundslam=slam_hit_whump,
                 impact_knockup=knock_thump_whoosh, boss_entrance_start=quake_approach,
                 boss_entrance_appear=land_bass_roar, boss_ward_up=ward_plates, boss_ward_down=ward_shatter,
                 boss_hunger_eat=eat_crunch_gulp, scramble_land=puzzle_thunk, scramble_defuse=defuse_rise_hit),
    "b": _column("b", boss_slam_rise=rise_liftoff, aoe_boss_groundslam=slam_hit_rush,
                 impact_knockup=knock_swoop, boss_entrance_start=quake_surges,
                 boss_entrance_appear=land_bass_deep_roar, boss_ward_up=ward_seal,
                 boss_ward_down=ward_burst_stagger, boss_hunger_eat=eat_chomp_gulp,
                 scramble_land=puzzle_clatter, scramble_defuse=defuse_stab_boom),
    "c": _column("c", boss_slam_rise=rise_full_tell, aoe_boss_groundslam=slam_hit_whump_roar,
                 impact_knockup=knock_punch_zip, boss_entrance_start=quake_approach_growl,
                 boss_entrance_appear=land_roar, boss_ward_up=ward_swirl_hum,
                 boss_ward_down=ward_shatter_groan, boss_hunger_eat=eat_crunch_gulp_growl,
                 scramble_land=puzzle_armed, scramble_defuse=defuse_physical),
}


# =============================================================================
# Chosen (2026-11-28). Do not change these takes' code: package.py
# fingerprints the renders.
# =============================================================================
CHOSEN = {
    # Picked by the user, by ear, in round 1.
    "boss_ward_up": "c",              # ward_swirl_hum
    "boss_ward_down": "c",            # ward_shatter_groan
    "scramble_land": "c",             # puzzle_armed
    "scramble_hatch": "a",            # hatch_crack_whoof
    "scramble_tap": "b",              # tap_bar (rising per letter in the demo)
    "scramble_defuse": "a",           # defuse_rise_hit
    # Director's pick, unheard by anyone (the user handed the rest of the lane
    # to the director, 2026-11-28).
    "projectile_boss_fireball": "a",  # shot_fwoosh
    "projectile_destroy": "c",        # death_fizz_down
    "boss_slam_rise": "c",            # rise_full_tell
    "aoe_boss_groundslam": "a",       # slam_hit_whump
    "impact_knockup": "a",            # knock_thump_whoosh
    "boss_entrance_start": "a",       # quake_approach
    "boss_entrance_appear": "a",      # land_bass_roar
    "boss_hunger_eat": "a",           # eat_crunch_gulp
}
USER_PICKED = ("boss_ward_up", "boss_ward_down", "scramble_land", "scramble_hatch", "scramble_tap", "scramble_defuse")
