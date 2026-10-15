"""Agent knowledge-lookup benchmark.

Asks the real Claude Code harness (CLAUDE.md, auto-memory, skills) a fixed set
of project questions whose answers live in the repo's docs, wiki or memory, and
records what each answer cost: tokens, USD, wall time, agent turns, and whether
the answer contained the key fact.

Use it for A/B comparisons of the instruction/doc layout: run once per arm with
a different --label, changing only the docs between runs, then compare with
--summarize.

    uv run evals/agent_bench/run.py --label before --reps 3
    uv run evals/agent_bench/run.py --label after --reps 3
    uv run evals/agent_bench/run.py --summarize before after

Runs are read-only: edit tools and MCP servers are disabled. Memory is keyed by
the checkout path, so run every arm from the main checkout (not a worktree).
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import re
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
RUNS_DIR = HERE / "runs"
DISALLOWED = "Edit,Write,NotebookEdit,Agent,WebFetch,WebSearch"


def resolve_claude_bin() -> str:
    # Same shim workaround as evals/rojo_schema/run.py.
    found = shutil.which("claude")
    if found and found.lower().endswith((".cmd", ".bat")):
        bundled = Path(found).parent / "node_modules" / "@anthropic-ai" / "claude-code" / "bin" / "claude.exe"
        if bundled.exists():
            return str(bundled)
    return found or "claude"


CLAUDE_BIN = resolve_claude_bin()


def run_one(case: dict, rep: int) -> dict:
    args = [
        CLAUDE_BIN, "-p",
        "--output-format", "json",
        "--disallowedTools", DISALLOWED,
        "--strict-mcp-config",
        "--no-session-persistence",
        case["prompt"],
    ]
    t0 = time.monotonic()
    proc = subprocess.run(args, cwd=REPO_ROOT, capture_output=True, text=True, encoding="utf-8")
    wall = time.monotonic() - t0
    row = {"case": case["id"], "rep": rep, "wall_s": round(wall, 2), "exit": proc.returncode}
    try:
        out = json.loads(proc.stdout)
    except json.JSONDecodeError:
        row.update(error="unparseable stdout", stderr=proc.stderr[-500:])
        return row
    usage = out.get("usage", {})
    text = out.get("result", "") or ""
    row.update(
        turns=out.get("num_turns"),
        cost_usd=out.get("total_cost_usd"),
        api_s=round((out.get("duration_api_ms") or 0) / 1000, 2),
        input_tokens=usage.get("input_tokens", 0),
        cache_write=usage.get("cache_creation_input_tokens", 0),
        cache_read=usage.get("cache_read_input_tokens", 0),
        output_tokens=usage.get("output_tokens", 0),
        passed=all(re.search(p, text, re.IGNORECASE) for p in case["expect"]),
        answer=text,
    )
    row["context_tokens"] = row["input_tokens"] + row["cache_write"] + row["cache_read"]
    return row


def run(label: str, reps: int, concurrency: int) -> None:
    cases = [json.loads(l) for l in (HERE / "cases.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    jobs = [(c, r) for r in range(reps) for c in cases]
    out_path = RUNS_DIR / f"{label}.jsonl"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"{label}: {len(jobs)} runs, concurrency {concurrency}")
    with cf.ThreadPoolExecutor(concurrency) as pool, out_path.open("w", encoding="utf-8") as f:
        for row in pool.map(lambda j: run_one(*j), jobs):
            f.write(json.dumps(row) + "\n")
            f.flush()
            print(f"  {row['case']:<22} rep{row['rep']}  {'PASS' if row.get('passed') else 'FAIL'}"
                  f"  {row.get('context_tokens', '?'):>7} ctx  {row.get('turns', '?'):>2} turns  {row['wall_s']:>6}s")
    summarize([label])


def summarize(labels: list[str]) -> None:
    """One row per arm.

    base_prompt  context of the cheapest single-turn run: the fixed cost every
                 turn pays (system prompt + CLAUDE.md + memory index + tools)
    mean_ctx     mean context tokens per question, summed over its turns
    """
    cols = ["passed", "base_prompt", "mean_ctx", "mean_out", "mean_turns", "mean_wall_s", "total_usd"]
    print(f"{'arm':<20}" + "".join(f"{c:>13}" for c in cols))
    for label in labels:
        rows = [json.loads(l) for l in (RUNS_DIR / f"{label}.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
        ok = [r for r in rows if "error" not in r]
        single = [r["context_tokens"] for r in ok if r.get("turns") == 1]
        cells = [
            f"{sum(r['passed'] for r in ok)}/{len(rows)}",
            f"{min(single)}" if single else "-",
            f"{statistics.mean(r['context_tokens'] for r in ok):.0f}",
            f"{statistics.mean(r['output_tokens'] for r in ok):.0f}",
            f"{statistics.mean(r['turns'] for r in ok):.2f}",
            f"{statistics.mean(r['wall_s'] for r in ok):.1f}",
            f"{sum(r['cost_usd'] or 0 for r in ok):.2f}",
        ]
        print(f"{label:<20}" + "".join(f"{c:>13}" for c in cells))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--label")
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--concurrency", type=int, default=3)
    ap.add_argument("--summarize", nargs="+", metavar="LABEL")
    a = ap.parse_args()
    if a.summarize:
        summarize(a.summarize)
    elif a.label:
        run(a.label, a.reps, a.concurrency)
    else:
        ap.error("pass --label or --summarize")


if __name__ == "__main__":
    sys.exit(main())
