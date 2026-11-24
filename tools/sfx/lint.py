#!/usr/bin/env python3
"""Lint rendered SFX WAVs before upload to Roblox.

Usage: python tools/sfx/lint.py [--dir build/sfx]
Exit code 1 if any file FAILS. Library use: lint_file(path) -> [(level, code, message)].
"""
import argparse
import json
import math
import statistics
import sys
import wave
from pathlib import Path

import numpy as np

# ---- thresholds -----------------------------------------------------------
EXPECT_SAMPLE_RATE = 48000
EXPECT_CHANNELS = 1
EXPECT_SAMPLE_WIDTH_BYTES = 2
MIN_DURATION_S = 0.10
MAX_DURATION_S = 6.0
PEAK_FAIL_ABOVE_DBFS = -0.5
PEAK_WARN_BELOW_DBFS = -12.0
LOUD_WINDOW_S = 0.050
LOUD_WINDOW_FAIL_BELOW_DBFS = -30.0
DC_OFFSET_FAIL_ABOVE = 0.01
EDGE_SAMPLE_FAIL_ABOVE = 0.02
SILENCE_FLOOR_DBFS = -60.0
LEADING_SILENCE_WARN_ABOVE_S = 0.010
TRAILING_SILENCE_WARN_ABOVE_S = 0.150
# A loop wraps from its last sample to its first; a jump bigger than this clicks.
LOOP_SEAM_FAIL_ABOVE = 0.05
BAND_MEDIAN_WARN_DB = 6.0

FAIL, WARN = "FAIL", "WARN"
FULL_SCALE = 32768.0
EPS = 1e-12


def _db(x):
    return 20.0 * math.log10(max(float(x), EPS))


def _analyze(path, loop=False, demo=False):
    """Return (findings, stats). stats has 'rms_db' when audio was decoded."""
    out = []
    stats = {}
    try:
        with wave.open(str(path), "rb") as w:
            ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
            raw = w.readframes(n)
    except (OSError, EOFError, wave.Error) as e:
        out.append((FAIL, "unreadable", f"missing or unreadable (or not PCM): {e}"))
        return out, stats

    fmt_ok = True
    if ch != EXPECT_CHANNELS:
        out.append((FAIL, "not_mono", f"{ch} channels, expected {EXPECT_CHANNELS}"))
        fmt_ok = False
    if rate != EXPECT_SAMPLE_RATE:
        out.append((FAIL, "sample_rate", f"{rate} Hz, expected {EXPECT_SAMPLE_RATE}"))
    if width != EXPECT_SAMPLE_WIDTH_BYTES:
        out.append((FAIL, "bit_depth", f"{width * 8}-bit, expected {EXPECT_SAMPLE_WIDTH_BYTES * 8}-bit PCM"))
        fmt_ok = False
    if not fmt_ok or n == 0:
        if n == 0:
            out.append((FAIL, "empty", "no audio frames"))
        return out, stats

    x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / FULL_SCALE
    dur = n / float(rate)
    stats["duration"] = dur
    if dur < MIN_DURATION_S:
        out.append((FAIL, "too_short", f"duration {dur:.3f}s under {MIN_DURATION_S}s"))
    if dur > MAX_DURATION_S:
        # Demo rows are never uploaded, so the upload length cap does not apply.
        if not demo:
            out.append((FAIL, "too_long", f"duration {dur:.3f}s over {MAX_DURATION_S}s"))

    absx = np.abs(x)
    peak = float(absx.max())
    peak_db = _db(peak)
    stats["peak_db"] = peak_db
    if peak_db > PEAK_FAIL_ABOVE_DBFS:
        out.append((FAIL, "clipping", f"peak {peak_db:.1f} dBFS above {PEAK_FAIL_ABOVE_DBFS}"))
    elif peak_db < PEAK_WARN_BELOW_DBFS:
        out.append((WARN, "quiet_peak", f"peak {peak_db:.1f} dBFS below {PEAK_WARN_BELOW_DBFS}"))

    win = max(1, int(round(LOUD_WINDOW_S * rate)))
    if len(x) <= win:
        loud = math.sqrt(float(np.mean(x * x)))
    else:
        cs = np.concatenate(([0.0], np.cumsum(x * x)))
        loud = math.sqrt(float((cs[win:] - cs[:-win]).max()) / win)
    loud_db = _db(loud)
    if loud_db < LOUD_WINDOW_FAIL_BELOW_DBFS:
        out.append((FAIL, "too_quiet", f"loudest {int(LOUD_WINDOW_S * 1000)} ms RMS {loud_db:.1f} dBFS below {LOUD_WINDOW_FAIL_BELOW_DBFS}"))

    dc = float(np.mean(x))
    if abs(dc) > DC_OFFSET_FAIL_ABOVE:
        out.append((FAIL, "dc_offset", f"DC offset {dc:+.4f} exceeds {DC_OFFSET_FAIL_ABOVE}"))

    if loop:
        seam = abs(float(x[-1]) - float(x[0]))
        if seam > LOOP_SEAM_FAIL_ABOVE:
            out.append((FAIL, "loop_seam", f"wrap jumps {seam:.3f}, over {LOOP_SEAM_FAIL_ABOVE}"))
    else:
        if absx[0] > EDGE_SAMPLE_FAIL_ABOVE:
            out.append((FAIL, "start_click", f"first sample {x[0]:+.3f} exceeds {EDGE_SAMPLE_FAIL_ABOVE}"))
        if absx[-1] > EDGE_SAMPLE_FAIL_ABOVE:
            out.append((FAIL, "end_click", f"last sample {x[-1]:+.3f} exceeds {EDGE_SAMPLE_FAIL_ABOVE}"))

    floor = 10.0 ** (SILENCE_FLOOR_DBFS / 20.0)
    loud_idx = np.nonzero(absx >= floor)[0]
    if len(loud_idx) and not loop:
        lead = loud_idx[0] / float(rate)
        trail = (len(x) - 1 - loud_idx[-1]) / float(rate)
        if lead > LEADING_SILENCE_WARN_ABOVE_S:
            out.append((WARN, "leading_silence", f"leading silence {lead * 1000:.0f} ms over {LEADING_SILENCE_WARN_ABOVE_S * 1000:.0f} ms"))
        if trail > TRAILING_SILENCE_WARN_ABOVE_S:
            out.append((WARN, "trailing_silence", f"trailing silence {trail * 1000:.0f} ms over {TRAILING_SILENCE_WARN_ABOVE_S * 1000:.0f} ms"))

    stats["rms_db"] = _db(math.sqrt(float(np.mean(x * x))))
    return out, stats


def lint_file(path, loop=False):
    """Return a list of (level, code, message) for one WAV file. A loop is
    checked at its wrap point instead of at its edges."""
    return _analyze(path, loop)[0]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="build/sfx")
    args = ap.parse_args(argv)
    root = Path(args.dir)
    try:
        index = json.loads((root / "index.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"FAIL cannot read {root / 'index.json'}: {e}")
        return 1

    cues = index.get("cues", [])
    band_of = {c["id"]: c.get("band", "?") for c in cues}
    loop_of = {c["id"]: c.get("loop", False) for c in cues}
    demo_of = {c["id"]: c.get("demo", False) for c in cues}
    files = index.get("files", {})
    kit_ids = [k["id"] for k in index.get("kits", [])] or list(files)

    results = []  # (kit, cue, relpath, findings, stats)
    for kit in kit_ids:
        for cue in cues:
            rel = files.get(kit, {}).get(cue["id"])
            if rel is None:
                continue
            findings, stats = _analyze(root / rel, loop_of.get(cue["id"], False), demo_of.get(cue["id"], False))
            results.append([kit, cue["id"], rel, findings, stats])

    # band loudness vs median within kit
    groups = {}
    for r in results:
        if "rms_db" in r[4]:
            groups.setdefault((r[0], band_of.get(r[1], "?")), []).append(r)
    band_report = []
    for (kit, band), rs in sorted(groups.items()):
        med = statistics.median(r[4]["rms_db"] for r in rs)
        band_report.append((kit, band, len(rs), med))
        for r in rs:
            d = r[4]["rms_db"] - med
            if abs(d) > BAND_MEDIAN_WARN_DB:
                r[3].append((WARN, "band_loudness", f"RMS {r[4]['rms_db']:.1f} dBFS is {d:+.1f} dB from {band} median {med:.1f}"))

    n_fail = n_warn = 0
    for kit, cue, rel, findings, stats in results:
        fails = [f for f in findings if f[0] == FAIL]
        warns = [f for f in findings if f[0] == WARN]
        n_fail += bool(fails)
        n_warn += bool(warns) and not fails
        status = "FAIL" if fails else ("WARN" if warns else "OK  ")
        rms = f"rms {stats['rms_db']:6.1f} dBFS" if "rms_db" in stats else "rms    n/a"
        print(f"{status} {kit}/{cue} [{band_of.get(cue, '?')}] {rms}")
        for lvl, code, msg in findings:
            print(f"       {lvl} {code}: {msg}")

    print("\nBand loudness (integrated RMS median per kit):")
    for kit, band, n, med in band_report:
        print(f"  {kit:12s} {band:9s} {n:3d} files  median {med:6.1f} dBFS")
    missing = sum(1 for k in kit_ids for c in cues if c["id"] not in files.get(k, {}))
    n_ok = len(results) - n_fail - n_warn
    print(f"\nSummary: {len(results)} files, {n_ok} ok, {n_warn} warn-only, {n_fail} FAIL"
          f" ({missing} cue/kit pairs have no file)")
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
