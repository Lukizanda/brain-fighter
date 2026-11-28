"""Render every cue of every kit to build/sfx/<kit>/<cue>.wav and write
build/sfx/index.json for audition.py and lint.py.

    python tools/sfx/render.py [--out build/sfx]
    python tools/sfx/render.py --lane fire     (one production lane only)

A lane is a module tools/sfx/cues/lane_<name>.py with LANE, TAKES, SHEET and
CUES = {take_id: {cue_id: builder}}. It renders to build/sfx/lanes/<name>/,
one column per take, so parallel sessions never write the same files.

Renders are reproducible: every noise source takes a fixed seed.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, str(Path(__file__).parent))

import kit  # noqa: E402
from cues import pilot_chip, pilot_genesis, pilot_mallet, pilot_md, sheet  # noqa: F401  # noqa: E402

# The page shows the two 16-bit kits; the first two kits (mallet, chip)
# were judged on 2026-11-23 and are kept for reference only.
KITS = [pilot_md, pilot_genesis]
from cues import letter_lab  # noqa: E402  (registers the lab's cues into the kit)
from cues import collect_lab  # noqa: E402  (registers the collect cues into the kit)

CUE_SHEET = sheet.PILOT + [
    {"id": cid, "label": label, "group": group, "band": "gameplay", "note": note, **({"demo": True} if demo else {})}
    for cid, label, group, demo, note in letter_lab.SHEET + collect_lab.SHEET
]
INT16_MAX = 32767
DC_BLOCK_HZ = 20.0
# A tail is cut once it has fallen this far below the peak, keeping a short
# pad so the cut itself is inaudible.
TAIL_FLOOR_DB = -60.0
TAIL_PAD_SEC = 0.03


def master(x: np.ndarray, band: str, trim_db: float, loop: bool = False) -> np.ndarray:
    """Remove DC, trim the dead tail, fade the edges, normalise to the
    band's peak level plus the kit's loudness trim. A loop keeps its exact
    length and edges: its seam was built by the cue, and a fade or filter
    transient here would click every time it wraps."""
    import synth

    if loop:
        x = np.asarray(x, dtype=np.float64)
        x = x - np.mean(x)
        target_db = kit.PEAK_DBFS + kit.BAND_GAIN_DB[band] + trim_db
        return x / np.max(np.abs(x)) * 10.0 ** (target_db / 20.0)

    x = synth.highpass(np.asarray(x, dtype=np.float64), DC_BLOCK_HZ, order=1)
    floor = np.max(np.abs(x)) * 10.0 ** (TAIL_FLOOR_DB / 20.0)
    audible = np.nonzero(np.abs(x) > floor)[0]
    if len(audible):
        x = x[: audible[-1] + synth.n_samples(TAIL_PAD_SEC)]
    short = synth.n_samples(kit.MIN_DURATION_SEC) - len(x)
    if short > 0:
        x = np.concatenate([x, np.zeros(short)])
    fade_in = synth.n_samples(kit.FADE_IN_SEC)
    fade_out = synth.n_samples(kit.FADE_OUT_SEC)
    x[:fade_in] *= np.linspace(0.0, 1.0, fade_in)
    x[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)
    peak = np.max(np.abs(x))
    if peak <= 0:
        raise ValueError("cue rendered silence")
    target_db = kit.PEAK_DBFS + kit.BAND_GAIN_DB[band] + trim_db
    return x / peak * 10.0 ** (target_db / 20.0)


def render_lane(name: str, out: Path) -> int:
    import importlib

    lane = importlib.import_module(f"cues.lane_{name}")
    index = {
        "sampleRate": kit.SAMPLE_RATE,
        "lane": name,
        "kits": [{"id": take["id"], "label": take["label"]} for take in lane.TAKES],
        "cues": lane.SHEET,
        "files": {},
    }
    for take in lane.TAKES:
        (out / take["id"]).mkdir(parents=True, exist_ok=True)
        index["files"][take["id"]] = {}
        for cue in lane.SHEET:
            build = lane.CUES.get(take["id"], {}).get(cue["id"])
            if build is None:
                continue
            samples = master(build(), cue["band"], take.get("trimDb", 0.0), cue.get("loop", False))
            rel = f"{take['id']}/{cue['id']}.wav"
            wavfile.write(out / rel, kit.SAMPLE_RATE, np.round(samples * INT16_MAX).astype(np.int16))
            index["files"][take["id"]][cue["id"]] = rel
            print(f"  ok {rel}  {len(samples) / kit.SAMPLE_RATE * 1000:.0f} ms")
    (out / "index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")
    print(f"wrote {out / 'index.json'}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=None)
    parser.add_argument("--lane", default=None, help="render one production lane (cues/lane_<name>.py)")
    args = parser.parse_args()
    if args.lane:
        return render_lane(args.lane, Path(args.out or f"build/sfx/lanes/{args.lane}"))
    out = Path(args.out or "build/sfx")

    index = {
        "sampleRate": kit.SAMPLE_RATE,
        "kits": [{"id": m.KIT["id"], "label": m.KIT["label"]} for m in KITS],
        "cues": CUE_SHEET,
        "files": {},
    }
    for module in KITS:
        kit_id = module.KIT["id"]
        (out / kit_id).mkdir(parents=True, exist_ok=True)
        index["files"][kit_id] = {}
        for cue in CUE_SHEET:
            build = module.CUES.get(cue["id"])
            if build is None:
                continue
            samples = master(build(), cue["band"], module.KIT["trimDb"], cue.get("loop", False))
            rel = f"{kit_id}/{cue['id']}.wav"
            wavfile.write(out / rel, kit.SAMPLE_RATE, np.round(samples * INT16_MAX).astype(np.int16))
            index["files"][kit_id][cue["id"]] = rel
            print(f"  ok {rel}  {len(samples) / kit.SAMPLE_RATE * 1000:.0f} ms")

    (out / "index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")
    print(f"wrote {out / 'index.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
