#!/usr/bin/env python3
"""
Grades a run produced by run.py.

For each case in cases.jsonl with a matching output file, runs
`tools/validate_rojo_json.py` and records pass/fail. Writes report.csv
(machine-readable) and report.md (human-readable) into the run directory.

Two pass axes:

* `kind_correct` — for `style=="open"` cases, did the agent pick the
  expected `.meta.json` / `.model.json` extension? For `filename-fixed`
  cases the kind was dictated, so this is trivially true.
* `validator_passed` — does `tools/validate_rojo_json.py <file>` exit 0?

A case passes only if both axes pass.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
from pathlib import Path

# Pull the parser from run.py so re-parse logic stays in one place.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from run import parse_response  # noqa: E402

EVAL_DIR = Path(__file__).resolve().parent
REPO_ROOT = EVAL_DIR.parent.parent
VALIDATOR = REPO_ROOT / "tools" / "validate_rojo_json.py"


def reparse_responses(run_dir: Path) -> dict:
    """Re-apply the current parser to saved responses, overwriting outputs/.

    Use after improving the parser to recover model responses that were
    correct-but-mangled-by-old-parser, without re-running the model.
    Returns a summary dict.
    """
    responses_dir = run_dir / "responses"
    outputs_dir = run_dir / "outputs"
    if not responses_dir.is_dir():
        raise SystemExit(f"No responses/ in {run_dir} — can't re-parse without saved raw responses.")
    outputs_dir.mkdir(exist_ok=True)

    # Clear stale outputs first so a case whose filename changes (e.g., the agent re-picked
    # .meta.json vs .model.json) doesn't leave a stale file behind under the old name.
    for p in outputs_dir.iterdir():
        if p.is_file() and "__" in p.name:
            p.unlink()

    changed = []
    unchanged = []
    parse_errors = []
    for resp_path in sorted(responses_dir.glob("*.response.json")):
        data = json.loads(resp_path.read_text(encoding="utf-8"))
        case_id = data["case_id"]
        last_attempt = data["attempts"][-1] if data.get("attempts") else None
        if not last_attempt:
            parse_errors.append(case_id)
            continue
        text = last_attempt.get("text", "")
        filename, body, err = parse_response(text)
        if filename is None:
            parse_errors.append(case_id)
            continue
        out_path = outputs_dir / f"{case_id}__{filename}"
        out_path.write_text(body, encoding="utf-8")
        # Compare against what was originally saved as the filename — if a case's filename
        # changed because the parser is more lenient now, flag it.
        if data.get("filename") and data["filename"] != filename:
            changed.append((case_id, data["filename"], filename))
        else:
            unchanged.append(case_id)

    return {
        "changed": changed,
        "unchanged_count": len(unchanged),
        "parse_errors": parse_errors,
    }
CASES_PATH = EVAL_DIR / "cases.jsonl"


def load_cases() -> dict[str, dict]:
    cases = {}
    for line in CASES_PATH.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        c = json.loads(line)
        cases[c["id"]] = c
    return cases


def find_latest_run() -> Path:
    runs = sorted((EVAL_DIR / "runs").glob("*/"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not runs:
        raise SystemExit("No runs found under evals/rojo_schema/runs/. Run run.py first.")
    return runs[0]


def kind_from_filename(filename: str) -> str | None:
    if filename.endswith(".meta.json"):
        return ".meta.json"
    if filename.endswith(".model.json"):
        return ".model.json"
    return None


def validate(path: Path) -> tuple[bool, str]:
    """Returns (passed, first_line_of_stderr)."""
    proc = subprocess.run(
        [sys.executable, str(VALIDATOR), str(path)],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )
    passed = proc.returncode == 0
    stderr = (proc.stderr or "").strip()
    # The validator prints a summary header, then per-file details. Pull the first specific error line.
    first_err = ""
    for line in stderr.splitlines():
        line = line.strip()
        if line.startswith("- "):
            first_err = line[2:].strip()
            break
    if not first_err:
        first_err = stderr.splitlines()[0] if stderr.splitlines() else ""
    return passed, first_err


def grade_run(run_dir: Path) -> list[dict]:
    cases = load_cases()
    outputs_dir = run_dir / "outputs"
    responses_dir = run_dir / "responses"
    if not outputs_dir.is_dir():
        raise SystemExit(f"No outputs/ in {run_dir}. Did run.py succeed?")

    # Determine which case IDs were actually attempted in this run. `responses/` is the
    # authoritative source — every case attempt (success or parse error) writes a response,
    # while `outputs/` only has files for cases that parsed successfully. Falling back
    # to outputs/ keeps grading working if responses/ is missing (e.g. cleaned by .gitignore).
    attempted_ids: set[str] = set()
    if responses_dir.is_dir():
        for p in responses_dir.iterdir():
            if p.name.endswith(".response.json"):
                attempted_ids.add(p.name[:-len(".response.json")])
    if not attempted_ids:
        for p in outputs_dir.iterdir():
            if "__" in p.name:
                attempted_ids.add(p.name.split("__", 1)[0])

    # Build map: case_id -> output path
    output_by_id: dict[str, Path] = {}
    for p in outputs_dir.iterdir():
        if not p.is_file():
            continue
        if "__" in p.name:
            output_by_id[p.name.split("__", 1)[0]] = p

    rows: list[dict] = []
    for case_id, case in cases.items():
        if case_id not in attempted_ids:
            continue
        out_path = output_by_id.get(case_id)
        if out_path is None:
            rows.append({
                "id": case_id,
                "style": case["style"],
                "trap": case["trap"],
                "expected_kind": case["expected_kind"],
                "actual_kind": "",
                "kind_correct": False,
                "validator_passed": False,
                "case_passed": False,
                "validator_error": "no output file produced (parse_error during run)",
            })
            continue

        actual_kind = kind_from_filename(out_path.name) or ""
        if case["style"] == "filename-fixed":
            kind_correct = True
        else:
            kind_correct = actual_kind == case["expected_kind"]

        validator_passed, err = validate(out_path)
        case_passed = kind_correct and validator_passed

        rows.append({
            "id": case_id,
            "style": case["style"],
            "trap": case["trap"],
            "expected_kind": case["expected_kind"],
            "actual_kind": actual_kind,
            "kind_correct": kind_correct,
            "validator_passed": validator_passed,
            "case_passed": case_passed,
            "validator_error": err,
        })
    return rows


def write_csv(rows: list[dict], path: Path) -> None:
    fields = ["id", "style", "trap", "expected_kind", "actual_kind",
              "kind_correct", "validator_passed", "case_passed", "validator_error"]
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def breakdown(rows: list[dict], key: str) -> list[tuple[str, int, int]]:
    by: dict[str, list[dict]] = {}
    for r in rows:
        by.setdefault(r[key], []).append(r)
    out = []
    for k, group in sorted(by.items()):
        passed = sum(1 for r in group if r["case_passed"])
        out.append((k, passed, len(group)))
    return out


def write_md(rows: list[dict], path: Path, run_dir: Path, cases: dict[str, dict]) -> None:
    manifest_path = run_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}

    passed = sum(1 for r in rows if r["case_passed"])
    total = len(rows)
    pct = (passed / total * 100) if total else 0

    lines = []
    lines.append(f"# {manifest.get('backend', 'unknown')} run — {manifest.get('run_name', run_dir.name)}")
    lines.append("")
    lines.append(f"**{passed} / {total} passed ({pct:.0f}%)**")
    lines.append("")
    if manifest:
        lines.append(f"- backend: `{manifest.get('backend')}`")
        lines.append(f"- model: `{manifest.get('model')}`")
        lines.append(f"- started: {manifest.get('started_at')}")
        lines.append(f"- wall: {manifest.get('wall_seconds', 0):.1f}s")
        if "estimated_cost_usd" in manifest:
            lines.append(f"- estimated cost: ${manifest['estimated_cost_usd']:.4f}")
        if manifest.get("parse_errors"):
            lines.append(f"- parse errors: {len(manifest['parse_errors'])}")
        if "harness_fingerprint" in manifest:
            fp = manifest["harness_fingerprint"]
            lines.append(f"- git commit: `{fp.get('git_commit', '?')[:12]}`")
            lines.append(f"- CLAUDE.md sha256: `{fp.get('claude_md_sha256', '?')[:12]}`")
    lines.append("")

    lines.append("## By trap category")
    lines.append("")
    lines.append("| trap | pass | total |")
    lines.append("|---|---|---|")
    for k, p, t in breakdown(rows, "trap"):
        lines.append(f"| `{k}` | {p} | {t} |")
    lines.append("")

    lines.append("## By style")
    lines.append("")
    lines.append("| style | pass | total |")
    lines.append("|---|---|---|")
    for k, p, t in breakdown(rows, "style"):
        lines.append(f"| `{k}` | {p} | {t} |")
    lines.append("")

    lines.append("## By expected kind")
    lines.append("")
    lines.append("| kind | pass | total |")
    lines.append("|---|---|---|")
    for k, p, t in breakdown(rows, "expected_kind"):
        lines.append(f"| `{k}` | {p} | {t} |")
    lines.append("")

    failures = [r for r in rows if not r["case_passed"]]
    if failures:
        lines.append(f"## Failures ({len(failures)})")
        lines.append("")
        for r in failures:
            case = cases.get(r["id"], {})
            lines.append(f"### `{r['id']}`")
            lines.append("")
            prompt = case.get("prompt", "?")
            short_prompt = prompt if len(prompt) < 220 else prompt[:200] + "..."
            lines.append(f"- **trap:** `{r['trap']}` · **style:** `{r['style']}` · **expected:** `{r['expected_kind']}` · **actual:** `{r['actual_kind']}`")
            lines.append(f"- **kind_correct:** {r['kind_correct']} · **validator_passed:** {r['validator_passed']}")
            lines.append(f"- **prompt:** {short_prompt}")
            if r["validator_error"]:
                lines.append(f"- **validator error:** {r['validator_error']}")
            out_name = next(
                (p.name for p in (run_dir / "outputs").iterdir() if p.name.startswith(r["id"] + "__")),
                None,
            )
            if out_name:
                body = (run_dir / "outputs" / out_name).read_text(encoding="utf-8")
                lines.append("")
                lines.append("<details><summary>generated</summary>")
                lines.append("")
                lines.append("```json")
                lines.append(body.rstrip())
                lines.append("```")
                lines.append("</details>")
            lines.append("")
    else:
        lines.append("## Failures")
        lines.append("")
        lines.append("_None._")
        lines.append("")

    lines.append("---")
    lines.append("Re-run: `uv run evals/rojo_schema/run.py && uv run evals/rojo_schema/grade.py`")
    lines.append("")

    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", help="run name under runs/; defaults to most recent")
    parser.add_argument(
        "--reparse",
        action="store_true",
        help="re-apply the current parser to saved raw responses before grading. "
             "Use after improving run.py's parser to recover from saved data without re-running.",
    )
    args = parser.parse_args()

    if args.run:
        run_dir = EVAL_DIR / "runs" / args.run
        if not run_dir.is_dir():
            print(f"ERROR: no such run: {run_dir}", file=sys.stderr)
            return 2
    else:
        run_dir = find_latest_run()

    if args.reparse:
        print(f"Re-parsing saved responses in {run_dir}")
        summary = reparse_responses(run_dir)
        if summary["changed"]:
            print(f"  filename changed: {len(summary['changed'])} case(s)")
            for case_id, old, new in summary["changed"]:
                print(f"    {case_id}: {old} -> {new}")
        print(f"  unchanged: {summary['unchanged_count']}")
        if summary["parse_errors"]:
            print(f"  parse errors: {summary['parse_errors']}")
        print()

    print(f"Grading {run_dir}")
    rows = grade_run(run_dir)
    cases = load_cases()

    csv_path = run_dir / "report.csv"
    md_path = run_dir / "report.md"
    write_csv(rows, csv_path)
    write_md(rows, md_path, run_dir, cases)

    passed = sum(1 for r in rows if r["case_passed"])
    total = len(rows)
    pct = (passed / total * 100) if total else 0
    print()
    print(f"Result: {passed}/{total} passed ({pct:.0f}%)")
    print(f"  {csv_path}")
    print(f"  {md_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
