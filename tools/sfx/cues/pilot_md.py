"""Pilot family, kit D: 16-bit console RPG.

Written the way an early-90s console RPG's sound effects were: FM patches
in the chip's own register terms (tools/sfx/ym.py), a sound driver that
moves pitch and level once per 60 Hz frame, the PSG for noise and sparkle,
short 8-bit samples through the DAC for impacts, and echo made by replaying
a note quieter a few frames later on a spare channel.

The style follows the user's references (Phantasy Star IV, Shining Force
II): bright FM menu blips, arpeggiated item-get jingles, roaring feedback
patches for fire, metallic bells for ice. Every patch and cue is original.
"""

import numpy as np

import synth as s
import ym
from kit import SAMPLE_RATE, TRITONE_SEMITONES, scale_hz, semitones
from ym import Op, Patch

KIT = {"id": "md", "label": "16-bit RPG (chip model)", "trimDb": -5.5}

POP_OCTAVE = 1
SPELL_STEP_SEC = 0.26
FRAME = 1.0 / ym.FRAME_HZ
ECHO_FRAMES = 6          # driver echo: the repeat lands this many frames late
ECHO_DB = -9.0           # and this much quieter
TELEGRAPH_START_TL = 18  # the boss tell starts this many TL steps down (13.5 dB)

# --- Patches (register terms) -----------------------------------------------
# Each patch is a voice; cues pick a voice, they never invent a timbre.

# Menu blip: two 2-op pairs, a bright attack that settles to a pure tone.
BLIP = Patch(4, 5, [
    Op(mul=2, tl=30, ar=31, d1r=26, sl=8, d2r=16, rr=15),
    Op(mul=1, tl=0, ar=31, d1r=20, sl=6, d2r=14, rr=10),
    Op(mul=6, dt=2, tl=42, ar=31, d1r=28, sl=10, d2r=18, rr=15),
    Op(mul=2, dt=-1, tl=10, ar=31, d1r=21, sl=6, d2r=14, rr=10),
])

# Struck bar: marimba-like, modulator four times the carrier.
BAR = Patch(4, 3, [
    Op(mul=4, tl=28, ar=31, d1r=27, sl=12, d2r=18, rr=15),
    Op(mul=1, tl=0, ar=31, d1r=19, sl=7, d2r=13, rr=9),
    Op(mul=8, dt=1, tl=46, ar=31, d1r=29, sl=15, d2r=20, rr=15),
    Op(mul=2, tl=12, ar=31, d1r=20, sl=8, d2r=13, rr=9),
])

# Bell: inharmonic ratios, long ring, gentle vibrato.
BELL = Patch(5, 4, [
    Op(mul=7, dt=3, tl=34, ar=31, d1r=20, sl=6, d2r=12, rr=8),
    Op(mul=2, tl=4, ar=31, d1r=16, sl=4, d2r=11, rr=6),
    Op(mul=5, dt=-2, tl=10, ar=31, d1r=17, sl=5, d2r=11, rr=6, am=True),
    Op(mul=1, tl=6, ar=31, d1r=15, sl=4, d2r=10, rr=5),
], lfo_hz=ym.LFO_HZ[3], pms_cents=ym.PMS_CENTS[2], ams_db=ym.AMS_DB[1])

# Brass: the bright stab used for fanfares, modulator opens with the note.
BRASS = Patch(3, 6, [
    Op(mul=1, tl=26, ar=24, d1r=10, sl=4, d2r=4, rr=8),
    Op(mul=1, dt=1, tl=30, ar=26, d1r=8, sl=3, d2r=4, rr=8),
    Op(mul=2, tl=36, ar=28, d1r=12, sl=5, d2r=5, rr=8),
    Op(mul=1, tl=2, ar=26, d1r=6, sl=2, d2r=3, rr=8),
], lfo_hz=ym.LFO_HZ[4], pms_cents=ym.PMS_CENTS[3])

# Flame: maximum feedback breaks operator 1 into a roar.
FLAME = Patch(0, 7, [
    Op(mul=1, tl=8, ar=31, d1r=12, sl=4, d2r=8, rr=10),
    Op(mul=3, tl=22, ar=31, d1r=14, sl=6, d2r=8, rr=10),
    Op(mul=1, tl=18, ar=31, d1r=10, sl=4, d2r=6, rr=10),
    Op(mul=1, tl=0, ar=31, d1r=8, sl=3, d2r=6, rr=9),
])

# Crystal: very high, glassy ratios, fast tremolo shimmer.
CRYSTAL = Patch(4, 2, [
    Op(mul=13, dt=3, tl=40, ar=31, d1r=24, sl=8, d2r=16, rr=10),
    Op(mul=2, tl=6, ar=31, d1r=17, sl=5, d2r=12, rr=7, am=True),
    Op(mul=9, dt=-3, tl=38, ar=31, d1r=25, sl=9, d2r=16, rr=10),
    Op(mul=3, tl=10, ar=31, d1r=18, sl=6, d2r=12, rr=7, am=True),
], lfo_hz=ym.LFO_HZ[5], ams_db=ym.AMS_DB[2])

# Growl: a four-deep stack with heavy feedback, for the boss.
GROWL = Patch(0, 6, [
    Op(mul=0, tl=20, ar=20, d1r=4, sl=2, d2r=2, rr=10),
    Op(mul=1, dt=2, tl=26, ar=22, d1r=4, sl=2, d2r=2, rr=10),
    Op(mul=2, dt=-1, tl=30, ar=24, d1r=4, sl=3, d2r=2, rr=10, am=True),
    Op(mul=1, tl=0, ar=22, d1r=3, sl=2, d2r=1, rr=12),
], lfo_hz=ym.LFO_HZ[6], ams_db=ym.AMS_DB[1])

# Ice: hard and metallic, not musical. High, unrelated ratios, strong
# feedback, short decay, so it clanks instead of ringing.
ICE = Patch(2, 6, [
    Op(mul=11, dt=3, tl=22, ar=31, d1r=26, sl=10, d2r=18, rr=15),
    Op(mul=14, dt=-3, tl=30, ar=31, d1r=28, sl=12, d2r=20, rr=15),
    Op(mul=3, dt=2, tl=26, ar=31, d1r=26, sl=10, d2r=18, rr=15),
    Op(mul=1, tl=0, ar=31, d1r=22, sl=8, d2r=16, rr=13),
])

# --- Driver helpers ----------------------------------------------------------

def out(x: np.ndarray) -> np.ndarray:
    """Chip-rate mix to a 48 kHz cue."""
    return ym.to_output(x)


def note(patch: Patch, hz, frames_on: int, ring_sec: float = 0.4, gain_db: float = 0.0, tl_offset=None):
    """Key on for `frames_on` driver frames, then let the release ring."""
    on = frames_on * FRAME
    return ym.fm_note(patch, hz, on + ring_sec, on, gain_db, tl_offset)


def with_echo(x: np.ndarray, repeats: int = 2) -> np.ndarray:
    """Driver echo: the same notes replayed on a spare channel, later and
    quieter. Not a reverb, which is part of the period sound."""
    delay = ECHO_FRAMES * FRAME
    layers = [(x, 0.0)] + [(x * 10.0 ** (ECHO_DB * k / 20.0), delay * k) for k in range(1, repeats + 1)]
    total = len(x) + ym.chip_samples(delay * repeats)
    return ym.place(total, *layers)


def arpeggio(patch: Patch, pitches, frames_each: int, ring_sec: float, gain_db: float = 0.0):
    """One note per pitch, retriggered every `frames_each` frames."""
    step = frames_each * FRAME
    parts = [(note(patch, hz, frames_each, ring_sec, gain_db), i * step) for i, hz in enumerate(pitches)]
    total = ym.chip_samples(step * len(pitches) + ring_sec)
    return ym.place(total, *parts)


def dac_knock(seconds: float = 0.05, play_rate: float = 8000.0, seed: int = 3) -> np.ndarray:
    """A short sampled knock played through the DAC: low rate, 8-bit,
    no smoothing. This is the crunch on the front of a hit."""
    body = s.sine(s.glide(900.0, 120.0, seconds, curve=2.0)) * s.decay(seconds, seconds * 0.25)
    snap = s.bandpass(s.noise(seconds, seed), 600.0, 4000.0) * s.decay(seconds, seconds * 0.12)
    return ym.dac_sample(s.mix(body, (snap, 0.7)), SAMPLE_RATE, play_rate)


def dac_boom(seconds: float = 0.22, play_rate: float = 10000.0, seed: int = 4) -> np.ndarray:
    body = s.sine(s.glide(160.0, 40.0, seconds, curve=1.5)) * s.decay(seconds, seconds * 0.3)
    grit = s.lowpass(s.noise(seconds, seed), 2500.0) * s.decay(seconds, seconds * 0.15)
    return ym.dac_sample(s.drive(s.mix(body, (grit, 0.6)), 2.0), SAMPLE_RATE, play_rate)


def noise_burst(volumes, divider: int = 512, periodic: bool = False, shift_hz=None, seed: int = 1):
    """PSG noise with a per-frame volume list (0 loudest, 15 off)."""
    sec = len(volumes) * FRAME
    return ym.psg_noise(ym.psg_volume(volumes), sec, divider, periodic, shift_hz, seed)


def dac_crackle(seconds: float, clicks_per_sec: float, seed: int, play_rate: float = 12000.0) -> np.ndarray:
    """Ice texture: a thinning scatter of tiny bright clicks, played through
    the DAC. Density falls away over the length."""
    rng = np.random.default_rng(seed)
    x = np.zeros(s.n_samples(seconds))
    t = 0.0
    while t < seconds:
        fade = 1.0 - t / seconds
        t += rng.exponential(1.0 / (clicks_per_sec * max(fade, 0.05)))
        if t >= seconds:
            break
        click = s.highpass(s.noise(0.003, int(rng.integers(1 << 30))), 3000.0) * s.decay(0.003, 0.0008, attack=0.0001)
        at = s.n_samples(t) - 1
        end = min(len(x), at + len(click))
        x[at:end] += click[: end - at] * fade * rng.uniform(0.4, 1.0)
    return ym.dac_sample(x, SAMPLE_RATE, play_rate)


def ice_hit(hz: float, gain_db: float = 0.0) -> np.ndarray:
    """The ice strike: two clashing notes a semitone apart, pitch dropping
    over four frames, crack noise on the front."""
    drop = [1.5, 1.2, 1.0, 0.92, 0.88]
    hit = note(ICE, ym.frames([hz * d for d in drop]), 4, ring_sec=0.18, gain_db=gain_db)
    clash = note(ICE, ym.frames([hz * semitones(1) * d for d in drop]), 3, ring_sec=0.14, gain_db=gain_db - 4.0)
    crack = noise_burst([0, 0, 2, 5, 9, 13, 15], shift_hz=ym.frames(np.geomspace(14000.0, 3000.0, 7)), seed=33) * 0.55
    return ym.place(max(len(hit), len(clash)), hit, clash, crack)


# Ice sits a semitone above the key's root: an attack should not land on
# a note the reward cues use.
ICE_HZ = scale_hz(0, POP_OCTAVE + 1) * semitones(1)
# The ice strike is very peaky; saturating the mix brings its body up to
# the level of the other spells, and adds bite.
ICE_DRIVE = 3.0
ICE_CRACKLE_GAIN = 3.0


def hot(x: np.ndarray, amount: float) -> np.ndarray:
    return s.drive(x / max(1e-9, np.max(np.abs(x))), amount)


# --- Letter -----------------------------------------------------------------

def block_pop(step: int = 0) -> np.ndarray:
    """Menu-blip pop: one frame an octave up, then the scale note, with a
    single frame of noise as the 'pop' and an 8-bit knock under it."""
    hz = scale_hz(step, POP_OCTAVE)
    pitch = ym.frames([hz * 2.0, hz])
    tone = note(BLIP, pitch, 3, ring_sec=0.18)
    click = noise_burst([2, 8, 15], divider=512, seed=11) * 0.35
    knock = dac_knock() * 0.5
    return out(ym.place(len(tone), tone, click, knock))


def pop_bar(step: int = 0) -> np.ndarray:
    """Struck bar: a woody note, softer than the blip."""
    hz = scale_hz(step, POP_OCTAVE)
    tone = note(BAR, hz, 2, ring_sec=0.22)
    knock = dac_knock(play_rate=11000.0) * 0.4
    return out(ym.place(len(tone), tone, knock))


def pop_bubble(step: int = 0) -> np.ndarray:
    """Bubble: the pitch climbs over three frames into the note."""
    hz = scale_hz(step, POP_OCTAVE)
    pitch = ym.frames([hz * 0.5, hz * 0.75, hz * 1.5, hz])
    tone = note(BAR, pitch, 4, ring_sec=0.16)
    return out(tone)


def pop_coin(step: int = 0) -> np.ndarray:
    """Pickup: two quick notes a fourth apart, the item-get shorthand."""
    hz = scale_hz(step, POP_OCTAVE + 1)
    pitch = ym.frames([hz, hz, hz, hz * semitones(5)])
    tone = note(BLIP, pitch, 6, ring_sec=0.2, gain_db=-2.0)
    return out(tone)


def pop_crunch(step: int = 0) -> np.ndarray:
    """Crunchy: the knock is the sound, the note is a short tail."""
    hz = scale_hz(step, POP_OCTAVE)
    knock = dac_knock(0.07, play_rate=6000.0, seed=12)
    tone = note(BLIP, hz, 1, ring_sec=0.12, gain_db=-6.0)
    return out(ym.place(max(len(tone), len(knock)), knock, (tone, FRAME)))


def block_pop_wild() -> np.ndarray:
    hz = scale_hz(0, POP_OCTAVE)
    pop = block_pop(0)
    run = [hz * semitones(n) for n in (12, 16, 19, 24)]
    sparkle = with_echo(arpeggio(BELL, run, 3, ring_sec=0.3, gain_db=-4.0))
    sparkle = out(sparkle)
    return s.mix(pop, (sparkle, 0.8, 0.05))


def buffer_tile() -> np.ndarray:
    """Menu cursor: one short high blip."""
    hz = scale_hz(0, POP_OCTAVE + 1)
    return out(note(BLIP, hz, 1, ring_sec=0.1, gain_db=-3.0))


def memorize_success() -> np.ndarray:
    """Item-get jingle: a brass arpeggio that lands on a held, vibrato note,
    a bell doubling it an octave up, and the PSG adding a bass note."""
    steps = (0, 2, 3, 5)
    lead = arpeggio(BRASS, [scale_hz(st, POP_OCTAVE) for st in steps[:-1]], 4, ring_sec=0.1)
    hold = note(BRASS, scale_hz(steps[-1], POP_OCTAVE), 22, ring_sec=0.25)
    bell = arpeggio(BELL, [scale_hz(st, POP_OCTAVE + 1) for st in steps], 4, ring_sec=0.6, gain_db=-8.0)
    bass_sec = 0.6
    bass = ym.psg_square(scale_hz(0, POP_OCTAVE - 2), ym.psg_volume([4] * 12 + [6, 8, 10, 12, 15]), bass_sec) * 0.25
    arp_len = 3 * 4 * FRAME
    total = ym.chip_samples(arp_len + 22 * FRAME + 0.7)
    return out(with_echo(ym.place(total, lead, (hold, arp_len), bell, (bass, arp_len)), repeats=1))


def fizzle() -> np.ndarray:
    """Cancel: two falling notes on the brass, the second dulled by
    closing the modulator over a few frames."""
    hi, lo = scale_hz(3, POP_OCTAVE - 1), scale_hz(0, POP_OCTAVE - 1) * semitones(-1)
    pitch = ym.frames([hi] * 5 + [lo])
    dull = ym.frames([0] * 5 + [6, 12, 18, 24, 30])
    tone = note(BRASS, pitch, 12, ring_sec=0.12, gain_db=-2.0, tl_offset={2: dull})
    return out(tone)


# --- Spells -----------------------------------------------------------------

def cast_red_t1() -> np.ndarray:
    """Fire: a feedback roar swept down, PSG noise following the sweep, a
    DAC boom underneath."""
    frames_on = 14
    pitch = ym.frames(np.geomspace(700.0, 110.0, frames_on))
    roar = note(FLAME, pitch, frames_on, ring_sec=0.12)
    hiss = noise_burst([0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 15],
                       shift_hz=ym.frames(np.geomspace(12000.0, 1500.0, frames_on)), seed=21) * 0.45
    boom = dac_boom() * 0.7
    return out(ym.place(len(roar), roar, hiss, boom))


def cast_green_t1() -> np.ndarray:
    """Heal: a rising sparkle on the bell, echoed by the driver, over a
    soft brass swell."""
    run = [scale_hz(st, POP_OCTAVE) for st in range(6)]
    sparkle = with_echo(arpeggio(BELL, run, 2, ring_sec=0.45, gain_db=-2.0))
    pad = note(BRASS, scale_hz(0, POP_OCTAVE - 1), 18, ring_sec=0.2, gain_db=-12.0)
    return out(ym.place(len(sparkle), sparkle, pad))


def cast_blue_t1() -> np.ndarray:
    """Ice, take A (shatter): a hard clanking strike out of key, a noise
    crack, and ice crackling as it settles. No echo, no ring."""
    hit = ice_hit(ICE_HZ)
    shards = dac_crackle(0.30, 70.0, seed=34) * ICE_CRACKLE_GAIN
    return out(hot(ym.place(len(hit) + ym.chip_samples(0.1), hit, (shards, 2 * FRAME)), ICE_DRIVE))


def frost_blast() -> np.ndarray:
    """Ice, take B (blast): a cold rush of noise rising for six frames,
    then the strike and the crackle."""
    rush_frames = 6
    rush = noise_burst(list(np.linspace(13, 3, rush_frames).round().astype(int)),
                       shift_hz=ym.frames(np.geomspace(2000.0, 15000.0, rush_frames)), seed=35) * 0.5
    at = rush_frames * FRAME
    hit = ice_hit(ICE_HZ)
    shards = dac_crackle(0.28, 60.0, seed=36) * ICE_CRACKLE_GAIN
    total = ym.chip_samples(at) + len(hit) + ym.chip_samples(0.1)
    return out(hot(ym.place(total, rush, (hit, at), (shards, at + 2 * FRAME)), ICE_DRIVE))


def frost_icicle() -> np.ndarray:
    """Ice, take C (icicle): a thin metallic zap diving down over eight
    frames, dulling as it falls, then a short crackle."""
    frames_on = 8
    pitch = ym.frames(ICE_HZ * 2.0 * semitones(-np.linspace(0.0, 19.0, frames_on)))
    dull = ym.frames(np.linspace(0.0, 16.0, frames_on))
    zap = note(ICE, pitch, frames_on, ring_sec=0.08, tl_offset={0: dull, 1: dull})
    tick = noise_burst([1, 6, 12, 15], divider=512, seed=37) * 0.4
    shards = dac_crackle(0.18, 80.0, seed=38) * ICE_CRACKLE_GAIN
    at = frames_on * FRAME
    return out(hot(ym.place(len(zap) + ym.chip_samples(0.2), zap, tick, (shards, at)), ICE_DRIVE))


# --- Fire: explosion and burning -------------------------------------------
# Attack cues, so no in-key notes and no echo. The weight comes from the
# DAC sample and the PSG noise stepping down in pitch, which is the period's
# explosion; FM adds the low roar.

BOOM_DRIVE = 3.0
EXPLOSION_NOISE_START_HZ = 7000.0
EXPLOSION_NOISE_END_HZ = 700.0


def dac_explosion(seconds: float, play_rate: float, drive: float, seed: int) -> np.ndarray:
    """The sampled body of a blast: a sub drop and a gritty noise burst,
    driven hard, then played through the DAC at a low rate."""
    body = s.sine(s.glide(150.0, 28.0, seconds, curve=1.4)) * s.decay(seconds, seconds * 0.22)
    grit = s.lowpass(s.noise(seconds, seed), 3000.0) * s.decay(seconds, seconds * 0.14, attack=0.002)
    return ym.dac_sample(s.drive(s.mix(body, (grit, 0.9)), drive), SAMPLE_RATE, play_rate)


def falling_noise(frames_on: int, start_hz: float, end_hz: float, seed: int, wobble: float = 0.0):
    """PSG white noise whose clock steps down each frame while it fades:
    the classic console explosion. `wobble` makes the level roll."""
    k = np.arange(frames_on)
    level = np.linspace(0.0, 15.0, frames_on) ** 1.15 / 15.0 ** 0.15
    level = level + wobble * (k % 4 >= 2)
    vols = np.clip(np.round(level), 0, 15).astype(int)
    return noise_burst(list(vols), shift_hz=ym.frames(np.geomspace(start_hz, end_hz, frames_on)), seed=seed)


def boom_bright() -> np.ndarray:
    """The first explosion take (2026-11-25), kept to compare against: a
    driven DAC blast, bright falling noise, a low roar, debris."""
    roar = note(FLAME, ym.frames(np.geomspace(170.0, 40.0, 20)), 20, ring_sec=0.3, gain_db=-4.0)
    noise = falling_noise(40, EXPLOSION_NOISE_START_HZ, EXPLOSION_NOISE_END_HZ, seed=51) * 0.6
    blast = dac_explosion(0.7, 8000.0, 2.5, seed=52) * 0.9
    debris = dac_crackle(0.5, 35.0, seed=53, play_rate=8000.0) * 2.0
    total = ym.chip_samples(0.95)
    return out(hot(ym.place(total, blast, noise, roar, (debris, 8 * FRAME)), BOOM_DRIVE))


# Round boom: nearly pure low sines (gentle modulators, one an octave
# down), a slightly soft attack so it blooms instead of cracking, and very
# little drive.
ROUND = Patch(4, 1, [
    Op(mul=2, tl=34, ar=31, d1r=16, sl=6, d2r=10, rr=8),
    Op(mul=1, tl=0, ar=24, d1r=13, sl=3, d2r=8, rr=7),
    Op(mul=0, tl=44, ar=31, d1r=14, sl=6, d2r=10, rr=8),
    Op(mul=0, tl=4, ar=24, d1r=12, sl=3, d2r=7, rr=7),
])
# The same voice with a slower swell, for the deeper take.
ROUND_SOFT = Patch(4, 1, [
    Op(mul=2, tl=36, ar=31, d1r=14, sl=6, d2r=9, rr=7),
    Op(mul=1, tl=0, ar=19, d1r=11, sl=3, d2r=7, rr=6),
    Op(mul=0, tl=46, ar=31, d1r=12, sl=6, d2r=9, rr=7),
    Op(mul=0, tl=3, ar=19, d1r=10, sl=3, d2r=6, rr=6),
])
ROUND_DRIVE = 1.3
BLOOM_CUTOFF_HZ = 450.0
RUMBLE_DIVIDER = 2048    # the PSG's slowest noise clock: a low rumble
# The body falls between these. Phone and laptop speakers play little
# below about 150 Hz, so the boom starts high enough to be heard on them;
# headphones get the low end as well.
BOOM_START_HZ = 200.0
BOOM_END_HZ = 55.0


def air_bloom(seconds: float, attack: float, half_life: float, seed: int) -> np.ndarray:
    """The air pushed out by a blast: deep low-passed noise that swells in
    over `attack` and dies away, through the DAC."""
    x = s.lowpass(s.noise(seconds, seed), BLOOM_CUTOFF_HZ)
    x = x / np.max(np.abs(x)) * s.decay(seconds, half_life, attack=attack)
    return ym.dac_sample(x, SAMPLE_RATE, 8000.0)


def impact_damage_t2() -> np.ndarray:
    """Fireball explosion, round take A (whump): a deep falling sine body,
    a swell of low air, and a soft rumble underneath."""
    body = note(ROUND, ym.frames(np.geomspace(BOOM_START_HZ, BOOM_END_HZ, 22)), 22, ring_sec=0.5)
    bloom = air_bloom(0.7, 0.012, 0.12, seed=71) * 0.7
    vols = np.clip(np.round(np.linspace(3.0, 15.0, 36)), 0, 15).astype(int)
    rumble = noise_burst(list(vols), divider=RUMBLE_DIVIDER, seed=72) * 0.2
    total = ym.chip_samples(1.0)
    return out(hot(ym.place(total, body, bloom, rumble), ROUND_DRIVE))


def boom_bloom() -> np.ndarray:
    """Round take B (deep bloom): slower to swell, deeper and longer, the
    rumble rolling as it fades."""
    frames_on = 40
    body = note(ROUND_SOFT, ym.frames(np.geomspace(BOOM_START_HZ * 0.8, BOOM_END_HZ * 0.8, frames_on)), frames_on, ring_sec=0.7)
    bloom = air_bloom(1.2, 0.04, 0.25, seed=73) * 0.8
    k = np.arange(60)
    vols = np.clip(np.round(np.linspace(4.0, 15.0, 60) + 1.5 * np.sin(k / 3.0)), 0, 15).astype(int)
    rumble = noise_burst(list(vols), divider=RUMBLE_DIVIDER, seed=74) * 0.2
    total = ym.chip_samples(1.5)
    return out(hot(ym.place(total, body, bloom, rumble), ROUND_DRIVE - 0.1))


# --- The boom's punch --------------------------------------------------------
# The round takes had no moment of impact: a soft attack and a slow glide made
# one smooth slope, and the drive lifted the tail toward the peak (measured:
# flat within 2 dB for 250 ms). A boom needs a hit that stands about 10 dB
# above what follows. The hit is a kick drum: a sampled thump whose pitch
# dives in ~50 ms, played through the DAC like the period's drum samples. The
# round body and air come in under it, lower, and the drive is nearly off.

KICK_START_HZ = 260.0
KICK_END_HZ = 60.0
KICK_DIVE_SEC = 0.05
KICK_PLAY_RATE = 11000.0
PUNCH_DRIVE = 1.1
BODY_UNDER_PUNCH_DB = -10.0  # the round body sits this far under the hit
TAIL_DELAY_SEC = 0.035      # and swells in just after it, so the hit stands alone
# Saturating the kick (only the kick) adds harmonics a phone speaker can
# play, so the hit is heard even where its fundamental is not.
KICK_DRIVE = 2.5
KICK_DECAY_FRACTION = 0.12  # half-life as a share of the kick's length


def dac_kick(seconds: float = 0.35, click: float = 0.35, seed: int = 81) -> np.ndarray:
    """A kick-drum thump: instant attack, pitch diving KICK_START_HZ to
    KICK_END_HZ in KICK_DIVE_SEC, a short click on the front."""
    dive = s.glide(KICK_START_HZ, KICK_END_HZ, KICK_DIVE_SEC, curve=2.0)
    pitch = np.concatenate([dive, np.full(s.n_samples(seconds) - len(dive), KICK_END_HZ)])
    body = s.sine(pitch) * s.decay(seconds, seconds * KICK_DECAY_FRACTION, attack=0.0005)
    snap = s.lowpass(s.noise(0.008, seed), 2500.0) * s.decay(0.008, 0.0015, attack=0.0002)
    kick = s.mix(body, (snap, click))
    kick = s.drive(kick / np.max(np.abs(kick)), KICK_DRIVE)
    return ym.dac_sample(kick, SAMPLE_RATE, KICK_PLAY_RATE)


def round_tail(seconds: float, seed: int) -> np.ndarray:
    """What follows the hit: the round falling body, the air bloom and a
    soft rumble, all below the punch."""
    body = note(ROUND, ym.frames(np.geomspace(150.0, 50.0, 18)), 18, ring_sec=0.45)
    bloom = air_bloom(0.6, 0.02, 0.12, seed=seed) * 0.6
    vols = np.clip(np.round(np.linspace(5.0, 15.0, 30)), 0, 15).astype(int)
    rumble = noise_burst(list(vols), divider=RUMBLE_DIVIDER, seed=seed + 1) * 0.15
    tail = ym.place(ym.chip_samples(seconds), body, bloom, rumble)
    return tail / np.max(np.abs(tail)) * 10.0 ** (BODY_UNDER_PUNCH_DB / 20.0)


def boom_punch() -> np.ndarray:
    """Punch take A: the kick lands, the round body blooms under it."""
    kick = dac_kick()
    tail = round_tail(0.9, seed=82)
    return out(hot(ym.place(ym.chip_samples(0.9), kick, (tail, TAIL_DELAY_SEC)), PUNCH_DRIVE))


def boom_inhale() -> np.ndarray:
    """Punch take B: a short in-breath of rising air, cut off by the hit,
    so the boom arrives as an event."""
    inhale_sec = 0.14
    swell = s.lowpass(s.noise(inhale_sec, 83), 900.0)
    swell = swell / np.max(np.abs(swell)) * np.linspace(0.0, 1.0, s.n_samples(inhale_sec)) ** 2.5
    inhale = ym.dac_sample(swell, SAMPLE_RATE, 8000.0) * 0.35
    at = inhale_sec
    kick = dac_kick(seed=84)
    tail = round_tail(0.9, seed=85)
    total = ym.chip_samples(at + 0.9)
    return out(hot(ym.place(total, inhale, (kick, at), (tail, at + TAIL_DELAY_SEC)), PUNCH_DRIVE))


def boom_crack() -> np.ndarray:
    """Punch take C: the kick plus a bright, very short crack of fire on
    the front, more explosion than drum; the tail stays round."""
    kick = dac_kick(click=0.6, seed=86)
    crack = noise_burst([0, 3, 8, 15], shift_hz=ym.frames([12000.0, 8000.0, 5000.0, 3000.0]), seed=87) * 0.35
    tail = round_tail(0.9, seed=88)
    return out(hot(ym.place(ym.chip_samples(0.9), kick, crack, (tail, TAIL_DELAY_SEC)), PUNCH_DRIVE))


# --- Explosion family (screened) ---------------------------------------------
# A noise-led explosion with every choice as a parameter, so screen.py can
# try many variants and shortlist the few worth a listen. The earlier takes
# all rested on a tuned note (pitch clarity 0.64-0.79); with a hit on top that
# reads as a drum tom. Here the hit is a burst of muffled noise and any tone
# is only weight underneath.

FIREBALL_SPACE = {
    "blast_cut_hz": (350.0, 2200.0),   # how muffled the noise burst is
    "blast_half_life": (0.02, 0.10),   # how fast the burst dies
    "blast_rate": (6000.0, 11000.0),   # DAC playback rate: lower is crunchier
    "blast_drive": (1.0, 3.0),
    "sub_level": (0.0, 0.6),           # tuned weight under the burst
    "sub_start_hz": (80.0, 180.0),
    "body_db": (-22.0, -8.0),          # the round FM tail, under the hit
    "bloom_level": (0.0, 1.0),         # the swell of low air
    "rumble_gain": (0.0, 0.3),
    "crack_gain": (0.0, 0.4),
    "duck": (0.3, 1.0),                # dip just after the hit: lower pops more
    "drive": (1.0, 2.0),
}
EXPLOSION_SEC = 1.1
DUCK_START_SEC = 0.03
DUCK_LEN_SEC = 0.06
_explosion_cache = {}


def _explosion_parts():
    """The parts that don't depend on the parameters, rendered once."""
    if not _explosion_cache:
        body = note(ROUND, ym.frames(np.geomspace(150.0, 50.0, 18)), 18, ring_sec=0.5)
        _explosion_cache["body"] = body / np.max(np.abs(body))
        vols = np.clip(np.round(np.linspace(5.0, 15.0, 36)), 0, 15).astype(int)
        _explosion_cache["rumble"] = noise_burst(list(vols), divider=RUMBLE_DIVIDER, seed=91)
        _explosion_cache["bloom"] = air_bloom(0.7, 0.02, 0.14, seed=92)
        _explosion_cache["crack"] = noise_burst([0, 3, 8, 15], shift_hz=ym.frames([12000.0, 8000.0, 5000.0, 3000.0]), seed=93)
    return _explosion_cache


def explosion(p: dict, seed: int = 94) -> np.ndarray:
    parts = _explosion_parts()
    sec = 0.6
    burst = s.lowpass(s.noise(sec, seed), p["blast_cut_hz"])
    burst = burst / np.max(np.abs(burst)) * s.decay(sec, p["blast_half_life"], attack=0.001)
    sub = s.sine(s.glide(p["sub_start_hz"], 40.0, 0.12, curve=1.5))
    sub = np.concatenate([sub, np.zeros(s.n_samples(sec) - len(sub))]) * s.decay(sec, 0.06, attack=0.001)
    hit = s.drive(burst + sub * p["sub_level"], p["blast_drive"])
    hit = ym.dac_sample(hit / np.max(np.abs(hit)), SAMPLE_RATE, p["blast_rate"])
    tail_gain = 10.0 ** (p["body_db"] / 20.0)
    mix = ym.place(
        ym.chip_samples(EXPLOSION_SEC),
        hit,
        (parts["body"] * tail_gain, 0.035),
        (parts["bloom"] * p["bloom_level"] * tail_gain * 2.0, 0.02),
        parts["rumble"] * p["rumble_gain"],
        parts["crack"] * p["crack_gain"],
    )
    duck_at = ym.chip_samples(DUCK_START_SEC)
    duck_len = ym.chip_samples(DUCK_LEN_SEC)
    curve = np.ones(len(mix))
    shape = np.concatenate([np.linspace(1.0, p["duck"], duck_len // 3), np.full(duck_len // 3, p["duck"]),
                            np.linspace(p["duck"], 1.0, duck_len - 2 * (duck_len // 3))])
    curve[duck_at:duck_at + len(shape)] = shape
    return out(hot(mix * curve, p["drive"]))


def _shortlisted(name: str):
    """Cue functions for a shortlist written by screen.py, if one exists."""
    import json
    from pathlib import Path
    path = Path(__file__).with_name(f"shortlist_{name}.json")
    if not path.exists():
        return {}
    picks = json.loads(path.read_text(encoding="utf-8"))["picks"]
    return {pick["id"]: (lambda params=pick["params"]: explosion(params)) for pick in picks}


def _shortlisted_with(name: str, build):
    """Like _shortlisted, for a family with its own builder."""
    import json
    from pathlib import Path
    path = Path(__file__).with_name(f"shortlist_{name}.json")
    if not path.exists():
        return {}
    picks = json.loads(path.read_text(encoding="utf-8"))["picks"]
    return {pick["id"]: (lambda params=pick["params"]: build(params)) for pick in picks}


# --- Big explosion: "tch-ba-boom" -------------------------------------------
# User, 2026-11-25: shortlist #1 is "closer" but not big enough, and should
# sound like "tch-ba-boom". Three events: a bright spark of ignition, the
# hit, then a second, bigger boom that swells in and rolls on. The hit is
# shortlist #1 exactly, since that is the part the user liked.

BA_PARAMS = {
    "blast_cut_hz": 419.9645, "blast_half_life": 0.0332, "blast_rate": 10298.6159,
    "blast_drive": 2.8614, "sub_level": 0.169, "sub_start_hz": 80.9344,
    "body_db": -21.7215, "bloom_level": 0.7315, "rumble_gain": 0.1172,
    "crack_gain": 0.0402, "duck": 0.4743, "drive": 1.2943,
}

BIG_SPACE = {
    "tch_gain": (0.15, 0.7),
    "tch_sec": (0.012, 0.045),         # length of the spark
    "tch_highpass_hz": (1500.0, 5000.0),
    "tch_lead": (0.025, 0.07),         # spark comes this long before the hit
    "boom_delay": (0.07, 0.2),         # boom swells this long after the hit
    "boom_db": (-6.0, 2.0),            # boom peak relative to the hit
    "boom_attack": (0.02, 0.08),       # how slowly the boom swells
    "boom_half_life": (0.15, 0.45),    # how long it rolls
    "boom_cut_hz": (180.0, 600.0),     # how deep the boom's air is
    "body_level": (0.0, 0.8),          # tuned weight in the boom
    "rumble_gain": (0.0, 0.5),
    "drive": (1.0, 1.8),
}
BIG_SEC = 1.9
BOOM_PLAY_RATE = 8000.0


def tch(p: dict, seed: int = 101) -> np.ndarray:
    """The spark: a very short burst of bright noise, through the DAC."""
    sec = p["tch_sec"]
    x = s.highpass(s.noise(sec, seed), p["tch_highpass_hz"]) * s.decay(sec, sec * 0.3, attack=0.0005)
    return out(ym.dac_sample(x / np.max(np.abs(x)), SAMPLE_RATE, 16000.0))


def boom_layer(p: dict, seed: int = 102) -> np.ndarray:
    """The big second event: deep air swelling in and rolling on, a falling
    round body for weight, and a long low rumble."""
    sec = 1.5
    air = s.lowpass(s.noise(sec, seed), p["boom_cut_hz"], order=2)
    air = air / np.max(np.abs(air)) * s.decay(sec, p["boom_half_life"], attack=p["boom_attack"])
    air = ym.dac_sample(air, SAMPLE_RATE, BOOM_PLAY_RATE)
    frames_on = 40
    body = note(ROUND_SOFT, ym.frames(np.geomspace(120.0, 40.0, frames_on)), frames_on, ring_sec=0.8)
    body = body / np.max(np.abs(body))
    vols = np.clip(np.round(np.linspace(3.0, 15.0, 80)), 0, 15).astype(int)
    rumble = noise_burst(list(vols), divider=RUMBLE_DIVIDER, seed=seed + 1)
    mix = ym.place(ym.chip_samples(sec), air, (body * p["body_level"], 0.01), rumble * p["rumble_gain"])
    mix = out(mix)
    return mix / np.max(np.abs(mix))


def big_explosion(p: dict) -> np.ndarray:
    ba = explosion(BA_PARAMS)
    ba = ba / np.max(np.abs(ba))
    at_ba = p["tch_lead"]
    at_boom = at_ba + p["boom_delay"]
    boom = boom_layer(p) * 10.0 ** (p["boom_db"] / 20.0)
    mix = s.mix((tch(p) * p["tch_gain"], 1.0, 0.0), (ba, 1.0, at_ba), (boom, 1.0, at_boom))
    mix = mix[: s.n_samples(BIG_SEC)]
    return s.drive(mix / np.max(np.abs(mix)), p["drive"])


def boom_pick1() -> np.ndarray:
    """Last round's shortlist #1, the user's closest, kept to compare."""
    return explosion(BA_PARAMS)


# --- Burning ---------------------------------------------------------------
# A loop, since the status lasts. Fire has no pitch: it is noise that
# breathes slowly and unevenly, and crackles at random. (The first take used
# a pitched FM roar and flickered every frame, and sounded like a lawn
# mower: a steady pitch plus an even pulse reads as an engine.)

BURN_LOOP_SEC = 3.0
BURN_SEAM_SEC = 0.4
BURN_PREROLL_SEC = 0.1   # dropped, so the output filter has settled
BURN_DRIVE = 1.8


def breath(seconds: float, rate_hz: float, seed: int) -> np.ndarray:
    """A slow, uneven 0..1 swell: noise smoothed below `rate_hz`."""
    x = s.lowpass(s.noise(seconds + 1.0, seed), rate_hz)[s.n_samples(1.0):]
    return (x - x.min()) / max(1e-9, x.max() - x.min())


def per_frame(curve: np.ndarray) -> np.ndarray:
    """Sample a 48 kHz curve once per driver frame."""
    step = SAMPLE_RATE / ym.FRAME_HZ
    return curve[(np.arange(int(len(curve) / step)) * step).astype(int)]


def crackles(seconds: float, per_sec: float, seed: int, big_every: float = 0.0) -> np.ndarray:
    """Random pops of random size and brightness; an occasional bigger snap
    if `big_every` is set. Through the DAC."""
    rng = np.random.default_rng(seed)
    x = np.zeros(s.n_samples(seconds))
    t = rng.exponential(1.0 / per_sec)
    while t < seconds - 0.02:
        big = big_every > 0 and rng.random() < 1.0 / (big_every * per_sec)
        length = rng.uniform(0.004, 0.012) * (2.5 if big else 1.0)
        centre = rng.uniform(1500.0, 5000.0)
        pop = s.bandpass(s.noise(length, int(rng.integers(1 << 30))), centre * 0.5, min(centre * 1.6, 9000.0))
        pop = pop * s.decay(length, length * 0.2, attack=0.0002)
        pop = pop / max(1e-9, np.max(np.abs(pop)))
        at = s.n_samples(t) - 1
        end = min(len(x), at + len(pop))
        x[at:end] += pop[: end - at] * (1.0 if big else rng.lognormal(-1.0, 0.5))
        # Pops come in small clusters, like wood splitting.
        t += rng.exponential(1.0 / per_sec) * (0.25 if rng.random() < 0.3 else 1.0)
    return ym.dac_sample(x, SAMPLE_RATE, 12000.0)


def _fire_raw(seconds: float, seed: int, roar_band: tuple, breath_hz: float,
              roar_gain: float, pops_per_sec: float, rumble_gain: float) -> np.ndarray:
    rng_seed = seed * 10
    swell = breath(seconds, breath_hz, rng_seed)
    roar = s.bandpass(s.noise(seconds, rng_seed + 1), *roar_band)
    roar = roar / np.max(np.abs(roar)) * (0.35 + 0.65 * swell)
    roar = ym.dac_sample(roar, SAMPLE_RATE, 10000.0) * roar_gain
    # PSG noise bed following the same breath, never on a fixed pulse.
    bed_vol = np.clip(np.round(11.0 - 4.0 * per_frame(swell)), 0, 15).astype(int)
    bed = noise_burst(list(bed_vol), divider=1024, seed=rng_seed + 2) * 0.18
    rumble_vol = np.clip(np.round(10.0 - 4.0 * per_frame(breath(seconds, breath_hz * 0.5, rng_seed + 3))), 0, 15).astype(int)
    rumble = noise_burst(list(rumble_vol), divider=RUMBLE_DIVIDER, seed=rng_seed + 4) * rumble_gain
    pops = crackles(seconds, pops_per_sec, rng_seed + 5, big_every=1.2) * 0.9
    n = min(len(roar), len(bed), len(rumble), len(pops))
    return roar[:n] + bed[:n] + rumble[:n] + pops[:n]


def _seamless(raw_chip: np.ndarray) -> np.ndarray:
    """Chip-rate render -> 48 kHz loop whose end is cross-faded into its
    start (equal power)."""
    raw = out(raw_chip)[s.n_samples(BURN_PREROLL_SEC):]
    raw = hot(raw, BURN_DRIVE)
    body = s.n_samples(BURN_LOOP_SEC)
    seam = s.n_samples(BURN_SEAM_SEC)
    loop = raw[:body].copy()
    fade = np.linspace(0.0, np.pi / 2.0, seam)
    loop[:seam] = raw[:seam] * np.sin(fade) + raw[body:body + seam] * np.cos(fade)
    return loop


RAW_SEC = BURN_PREROLL_SEC + BURN_LOOP_SEC + BURN_SEAM_SEC


def burn_loop() -> np.ndarray:
    """Burning, take A (crackling): a breathing bed of soft noise under lots
    of irregular crackles."""
    return _seamless(_fire_raw(RAW_SEC, 8, (120.0, 1800.0), 1.6, 0.6, 14.0, 0.12))


def burn_roar() -> np.ndarray:
    """Burning, take B (roaring): a bigger, deeper whoosh that swells and
    falls, fewer crackles."""
    return _seamless(_fire_raw(RAW_SEC, 9, (60.0, 900.0), 0.8, 1.0, 5.0, 0.25))


def _demo(loop: np.ndarray) -> np.ndarray:
    tiled = np.tile(loop, 3)
    fade = s.n_samples(0.4)
    tiled[-fade:] *= np.linspace(1.0, 0.0, fade)
    return tiled


def demo_burn() -> np.ndarray:
    """Demo only: take A three times over, so the seam can be heard."""
    return _demo(burn_loop())


def demo_burn_roar() -> np.ndarray:
    """Demo only: take B three times over."""
    return _demo(burn_roar())


def burn_tick() -> np.ndarray:
    """A burn damage tick over the loop: a flare of hiss, a soft whoof of
    air and a couple of pops. No pitched tone."""
    flare = noise_burst([3, 0, 1, 3, 6, 9, 12, 15], shift_hz=ym.frames(np.geomspace(9000.0, 2500.0, 8)), seed=62) * 0.5
    whoof = air_bloom(0.2, 0.01, 0.05, seed=64) * 0.8
    pops = crackles(0.15, 30.0, seed=63) * 0.8
    total = ym.chip_samples(0.25)
    return out(hot(ym.place(total, flare, whoof, (pops, FRAME)), 1.8))


# --- Brain ------------------------------------------------------------------

def boss_telegraph() -> np.ndarray:
    """A growl that opens frame by frame, a tritone buzz above it, and low
    periodic noise throbbing underneath."""
    frames_on = 72
    root = 55.0
    pitch = ym.frames(root * semitones(np.linspace(0.0, 5.0, frames_on)))
    opening = ym.frames(np.linspace(18.0, 0.0, frames_on))
    # The carrier climbs too, so the tell grows louder as well as nastier.
    swell = ym.frames(np.linspace(TELEGRAPH_START_TL, 0.0, frames_on) ** 1.0)
    growl = note(GROWL, pitch, frames_on, ring_sec=0.05, tl_offset={0: opening, 1: opening, 3: swell})
    buzz_pitch = ym.frames(root * 2.0 * semitones(TRITONE_SEMITONES + np.linspace(0.0, 5.0, frames_on)))
    buzz = note(GROWL, buzz_pitch, frames_on, ring_sec=0.05, gain_db=-9.0)
    throb = noise_burst([int(v) for v in np.clip(np.round(10 - 6 * np.linspace(0, 1, frames_on)
                                                         + 3 * (np.arange(frames_on) % 6 < 3)), 0, 15)],
                        periodic=True, shift_hz=ym.frames(np.geomspace(400.0, 900.0, frames_on)), seed=41) * 0.3
    return out(ym.place(len(growl), growl, buzz, throb))


def demo_spell_word() -> np.ndarray:
    letters = [block_pop(step) for step in range(5)]
    layers = [(x, 1.0, i * SPELL_STEP_SEC) for i, x in enumerate(letters)]
    layers.append((memorize_success(), 1.0, len(letters) * SPELL_STEP_SEC + 0.25))
    return s.mix(*layers)


CUES = {
    "block_pop": block_pop,
    "md_pop_bar": pop_bar,
    "md_pop_bubble": pop_bubble,
    "md_pop_coin": pop_coin,
    "md_pop_crunch": pop_crunch,
    "block_pop_wild": block_pop_wild,
    "buffer_tile": buffer_tile,
    "demo_spell_word": demo_spell_word,
    "memorize_success": memorize_success,
    "fizzle": fizzle,
    "cast_red_t1": cast_red_t1,
    "cast_green_t1": cast_green_t1,
    "cast_blue_t1": cast_blue_t1,
    "md_frost_blast": frost_blast,
    "md_frost_icicle": frost_icicle,
    "burn_loop": burn_loop,
    "demo_burn": demo_burn,
    "md_burn_roar": burn_roar,
    "md_demo_burn_roar": demo_burn_roar,
    "md_burn_tick": burn_tick,
    "boss_telegraph": boss_telegraph,
}

# Screened explosions (tools/sfx/screen.py), shortlisted for the user.
# The big "tch-ba-boom" shortlist replaces the first one on the page; the
# first one's #1 stays as a comparison row.
CUES.update(_shortlisted_with("fireball_big", big_explosion))
CUES["md_boom_pick1"] = boom_pick1

# Chosen by the user, 2026-11-25: big fireball #3 ("soft spark, swelling
# boom"). Its settings are copied here, not read from the shortlist file,
# so re-running the screen cannot change the chosen sound.
FIREBALL_EXPLOSION_PARAMS = {
    "tch_gain": 0.2484, "tch_sec": 0.0331, "tch_highpass_hz": 3135.4394, "tch_lead": 0.0417,
    "boom_delay": 0.1161, "boom_db": 0.3241, "boom_attack": 0.0743, "boom_half_life": 0.2032,
    "boom_cut_hz": 454.1696, "body_level": 0.2386, "rumble_gain": 0.4835, "drive": 1.7359,
}
CUES["impact_damage_t2"] = lambda: big_explosion(FIREBALL_EXPLOSION_PARAMS)
