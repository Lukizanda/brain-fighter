"""Screen many variants of a cue family and shortlist the few worth a listen.

    python tools/sfx/screen.py fireball [--count 160] [--keep 3]

This narrows the field; it does not replace listening. Before ranking, it
prints the same measurements for takes the user already judged by ear, so
it is visible whether the measurements agree with the user. Targets below
cite the judgement each one stands for.

Writes tools/sfx/cues/shortlist_<family>.json (committed, so a shortlist is
reproducible), which the kit turns into cues.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))

import metrics  # noqa: E402
import render  # noqa: E402
from cues import pilot_md  # noqa: E402

# Each target: metric -> (low, high, weight per unit outside, why).
FIREBALL_TARGETS = {
    "punch_db": (9.0, None, 1.0, "user: 'no distinct boom' measured 1.0-1.8 dB; the punch takes 9"),
    "pitch_clarity": (None, 0.45, 25.0, "user: 'sounds like a drum tom' on takes scoring 0.68-0.69; noise scores ~0.15. 0.45 is a judgement, not yet confirmed by ear"),
    "centroid_hz": (120.0, 380.0, 0.03, "user: 'more round and boomy' after the bright take at 449 Hz; kept well under it"),
    "above_4k": (None, 0.02, 100.0, "round: little hiss"),
    "phone_band": (0.20, None, 20.0, "phones play little below 150 Hz; the punch takes had only 0.09"),
    "ring_sec": (0.45, 1.1, 4.0, "an explosion lingers longer than a drum, not forever"),
}

# User, 2026-11-25, on fireball shortlist #1: "closer to what I want, but it
# doesn't sound as big", "tch-ba-boom".
FIREBALL_BIG_TARGETS = {
    "spark_hz": (2500.0, None, 0.002, "'tch': a bright spark first"),
    "two_events_db": (4.0, 10.0, 2.0, "'ba-boom': two events with a dip between, but joined like the spoken word (13-20 dB is near silence: two sounds)"),
    "boom_vs_hit_db": (-5.0, 3.0, 1.5, "the boom is at least nearly as big as the hit"),
    "late_level_db": (-15.0, None, 1.0, "'big': still going 0.3-0.8 s in (#1, 'not big', measures -30)"),
    "ring_sec": (0.9, 1.7, 4.0, "'big': rolls on for about a second or more"),
    "pitch_clarity": (None, 0.35, 25.0, "noise-led like #1 (0.29); 'drum tom' takes were 0.69"),
    "phone_band": (0.25, None, 20.0, "heard on phones"),
}

FAMILIES = {
    "fireball_big": {
        "space": pilot_md.BIG_SPACE,
        "build": pilot_md.big_explosion,
        "targets": FIREBALL_BIG_TARGETS,
        "band": "gameplay",
        "ids": ["impact_damage_t2", "md_boom_big2", "md_boom_big3"],
        # Ties go to the bigger boom: punch is measured where the boom now is,
        # so the default tie-break would pick the smallest booms.
        "tie": lambda d: d["pitch_clarity"] - (d["boom_vs_hit_db"] + d["late_level_db"]) / 40.0,
        "rated": [
            ("shortlist #1: user 'closer, not as big'", pilot_md.boom_pick1),
            ("punch A: user 'a little like a drum tom'", pilot_md.boom_punch),
            ("round take: user 'no boom, just tapers'", pilot_md.impact_damage_t2),
        ],
    },
    "fireball": {
        "space": pilot_md.FIREBALL_SPACE,
        "build": pilot_md.explosion,
        "targets": FIREBALL_TARGETS,
        "band": "gameplay",
        "ids": ["impact_damage_t2", "md_boom_pick2", "md_boom_pick3"],
        "rated": [
            ("bright boom: user 'not round'", pilot_md.boom_bright),
            ("round take: user 'no boom, just tapers'", pilot_md.impact_damage_t2),
            ("punch A: user 'a little like a drum tom'", pilot_md.boom_punch),
        ],
    },
}


def measure(x) -> dict:
    return {**metrics.describe(x), **metrics.structure(x)}


def score(measured: dict, targets: dict) -> float:
    penalty = 0.0
    for key, (low, high, weight, _) in targets.items():
        v = measured[key]
        if low is not None and v < low:
            penalty += (low - v) * weight
        if high is not None and v > high:
            penalty += (v - high) * weight
    return penalty


def sample(space: dict, rng) -> dict:
    return {k: float(rng.uniform(lo, hi)) for k, (lo, hi) in space.items()}


def distance(a: dict, b: dict, space: dict) -> float:
    return float(np.sqrt(sum(((a[k] - b[k]) / (hi - lo)) ** 2 for k, (lo, hi) in space.items())))


MIN_SPREAD = 0.6  # shortlisted variants must differ by at least this much
TIE_PUNCH_PER_CLARITY = 40.0  # 4 dB more punch is worth 0.1 less clarity


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("family", choices=sorted(FAMILIES))
    ap.add_argument("--count", type=int, default=800)
    ap.add_argument("--keep", type=int, default=3)
    ap.add_argument("--seed", type=int, default=2026)
    args = ap.parse_args()
    fam = FAMILIES[args.family]
    targets = fam["targets"]

    print("Do the measurements agree with the user's ear? Takes already judged:")
    cols = list(targets)
    print(f"  {'take':45s} " + " ".join(f"{c[:9]:>9s}" for c in cols) + "  penalty")
    for name, fn in fam["rated"]:
        d = measure(render.master(fn(), fam["band"], 0.0))
        print(f"  {name:45s} " + " ".join(f"{d[c]:9.2f}" for c in cols) + f"  {score(d, targets):7.1f}")

    rng = np.random.default_rng(args.seed)
    trials = []
    for i in range(args.count):
        p = sample(fam["space"], rng)
        d = measure(render.master(fam["build"](p), fam["band"], 0.0))
        trials.append((score(d, targets), p, d))
    # Ties (everything that meets the targets) go to the least tonal and the
    # punchiest: the tone limit is a judgement, so prefer clear margins.
    tie = fam.get("tie", lambda d: d["pitch_clarity"] - d["punch_db"] / TIE_PUNCH_PER_CLARITY)
    trials.sort(key=lambda t: (t[0], tie(t[2])))

    picks = []
    for pen, p, d in trials:
        if all(distance(p, q[1], fam["space"]) >= MIN_SPREAD for q in picks):
            picks.append((pen, p, d))
        if len(picks) == args.keep:
            break

    passed = sum(1 for t in trials if t[0] == 0.0)
    print(f"\n{args.count} variants; {passed} meet every target. Shortlist:")
    for i, (pen, p, d) in enumerate(picks):
        print(f"  #{i + 1} penalty {pen:.1f}: " + ", ".join(f"{c} {d[c]}" for c in cols))

    out = {
        "family": args.family,
        "count": args.count,
        "seed": args.seed,
        "targets": {k: {"low": v[0], "high": v[1], "why": v[3]} for k, v in targets.items()},
        "picks": [
            {"id": fam["ids"][i], "rank": i + 1, "penalty": round(pen, 2), "measured": d,
             "params": {k: round(v, 4) for k, v in p.items()}}
            for i, (pen, p, d) in enumerate(picks)
        ],
    }
    path = Path(__file__).parent / "cues" / f"shortlist_{args.family}.json"
    path.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
