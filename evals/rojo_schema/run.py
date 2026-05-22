#!/usr/bin/env python3
"""
Rojo-schema eval runner.

For each case in cases.jsonl, calls Claude to generate a `.meta.json` or
`.model.json` file, then writes the parsed output to `runs/<name>/outputs/`.
Grading is a separate step — see grade.py.

Two backends:

* Default (system eval): shells out to `claude -p` with all tools disabled.
  This loads the full repo harness — CLAUDE.md, auto-memory, project
  context — so the score reflects what the actual day-to-day agent
  would produce in this repo. No API key required; uses your Claude
  Code subscription.

* `--raw-model`: shells out to `claude -p --bare`. This skips CLAUDE.md
  auto-discovery, auto-memory, hooks — isolates the model from the
  harness. Requires ANTHROPIC_API_KEY because --bare bypasses keychain
  auth. Use this for diagnostics ("did the model regress, or did my
  CLAUDE.md regress?").

Usage:
    uv run evals/rojo_schema/run.py                       # system eval
    uv run evals/rojo_schema/run.py --limit 3             # smoke test
    uv run evals/rojo_schema/run.py --raw-model --model claude-sonnet-4-6
"""
from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parent
REPO_ROOT = EVAL_DIR.parent.parent
CASES_PATH = EVAL_DIR / "cases.jsonl"

OUTPUT_CONTRACT = """\
You are generating one Rojo project sync file. Respond with exactly two parts and nothing else:

  Line 1: a JSON object {"filename": "<NAME.meta.json or NAME.model.json>"}
  Line 2: a single blank line
  Lines 3+: the raw JSON content of that file

Hard rules:
- No markdown fences. No prose. No commentary before or after.
- Do not use any tools. Do not read any files. Output only.
- The Line-3+ JSON must be valid JSON (double quotes, no trailing commas, no comments).
- Pick filename based on the user's request: `.meta.json` modifies an instance Rojo already creates (sibling script/folder); `.model.json` versions a standalone non-script instance.
"""

# Per-Mtok pricing for the cost estimate in --raw-model mode. Approximate.
PRICE_TABLE = {
    "claude-sonnet-4-6": (3.00, 15.00),
    "claude-haiku-4-5": (0.80, 4.00),
    "claude-opus-4-7": (15.00, 75.00),
}

FILENAME_LINE_RE = re.compile(r'^\s*\{\s*"filename"\s*:\s*"([^"]+\.(?:meta|model)\.json)"\s*\}\s*$')


def load_cases(path: Path, limit: int | None) -> list[dict]:
    cases = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        cases.append(json.loads(line))
    if limit is not None:
        cases = cases[:limit]
    return cases


def _clean_json_body(body: str) -> str:
    """Strip markdown fences and trailing prose from a body that should contain JSON.

    Handles three observed model failure modes that aren't model bugs per se,
    just output-contract violations:
      1. ```json {...} ```           — fenced code block
      2. {...}\n\nProse explanation. — trailing commentary after valid JSON
      3. ```json {...} ``` Prose.    — both
    """
    s = body.strip()

    # Case 1+3: leading ```...``` fence. Skip the opening fence line and stop at the closing fence.
    if s.startswith("```"):
        first_nl = s.find("\n")
        if first_nl != -1:
            s = s[first_nl + 1:]
            close_idx = s.find("```")
            if close_idx != -1:
                s = s[:close_idx]
        s = s.strip()

    # Case 2: try to parse the first JSON value; ignore any trailing text. raw_decode returns
    # (obj, end_index) so we can slice to just the syntactically-valid prefix.
    try:
        _obj, end = json.JSONDecoder().raw_decode(s)
        s = s[:end]
    except json.JSONDecodeError:
        # Couldn't extract — leave as-is so the validator surfaces the actual error.
        pass

    return s.rstrip() + "\n"


def parse_response(text: str) -> tuple[str | None, str | None, str | None]:
    """Returns (filename, file_body, error). On parse failure, filename and body are None."""
    lines = text.splitlines()
    # Tolerate a leading explanation paragraph; scan for the first line matching the contract.
    filename = None
    fname_idx = -1
    for i, line in enumerate(lines):
        m = FILENAME_LINE_RE.match(line)
        if m:
            filename = m.group(1)
            fname_idx = i
            break
    if filename is None:
        return None, None, "no {\"filename\": \"...\"} line found in response"
    # File body is everything after the filename line, skipping blank separator lines.
    body_lines = lines[fname_idx + 1:]
    while body_lines and not body_lines[0].strip():
        body_lines.pop(0)
    body = "\n".join(body_lines)
    if not body.strip():
        return None, None, "filename line present but no file body followed"
    body = _clean_json_body(body)
    return filename, body, None


async def call_claude(prompt: str, *, raw_model: bool, model: str | None, semaphore: asyncio.Semaphore) -> dict:
    """Returns {"stdout": ..., "stderr": ..., "exit_code": ..., "elapsed_s": ..., "parsed_json": ...|None}."""
    args = [
        "claude", "-p",
        "--output-format", "json",
        "--tools", "",
        "--append-system-prompt", OUTPUT_CONTRACT,
        "--no-session-persistence",
    ]
    if raw_model:
        args.append("--bare")
    if model:
        args.extend(["--model", model])
    args.append(prompt)

    async with semaphore:
        t0 = dt.datetime.now(dt.timezone.utc)
        proc = await asyncio.create_subprocess_exec(
            *args,
            cwd=str(REPO_ROOT),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout_b, stderr_b = await proc.communicate()
        elapsed = (dt.datetime.now(dt.timezone.utc) - t0).total_seconds()

    stdout = stdout_b.decode("utf-8", errors="replace")
    stderr = stderr_b.decode("utf-8", errors="replace")
    parsed = None
    try:
        parsed = json.loads(stdout)
    except json.JSONDecodeError:
        pass
    return {
        "stdout": stdout,
        "stderr": stderr,
        "exit_code": proc.returncode,
        "elapsed_s": elapsed,
        "parsed_json": parsed,
    }


def extract_text_and_usage(claude_result: dict) -> tuple[str, dict, str | None, float]:
    """Pull the response text, token usage, resolved model name, and cost out of `claude -p --output-format json`.

    `modelUsage` is a dict keyed by model id; the "primary" model for the call is the one
    that produced the most output tokens (Claude Code may invoke a lightweight model for
    intent classification before invoking the main model for the response).
    """
    parsed = claude_result["parsed_json"]
    if parsed is None:
        return claude_result["stdout"], {}, None, 0.0
    text = parsed.get("result") or parsed.get("text") or claude_result["stdout"]
    usage = parsed.get("usage") or {}
    cost = float(parsed.get("total_cost_usd") or 0.0)

    primary_model: str | None = None
    model_usage = parsed.get("modelUsage") or {}
    if model_usage:
        primary_model = max(model_usage.items(), key=lambda kv: kv[1].get("outputTokens", 0))[0]

    return text, usage, primary_model, cost


async def run_case(case: dict, *, raw_model: bool, model: str | None, semaphore: asyncio.Semaphore) -> dict:
    """Call the model once with optional one retry on parse failure."""
    attempts = []
    for attempt in range(2):
        prompt = case["prompt"]
        if attempt == 1:
            prompt = (
                "Your previous response did not follow the required format. "
                "Re-emit in the exact format described in the system prompt: "
                "first line `{\"filename\": \"...\"}`, blank line, then the raw JSON content. "
                "No commentary, no fences.\n\n"
                + case["prompt"]
            )
        result = await call_claude(prompt, raw_model=raw_model, model=model, semaphore=semaphore)
        text, usage, primary_model, cost = extract_text_and_usage(result)
        filename, body, err = parse_response(text)
        attempts.append({
            "exit_code": result["exit_code"],
            "elapsed_s": result["elapsed_s"],
            "text": text,
            "usage": usage,
            "primary_model": primary_model,
            "cost_usd": cost,
            "stderr": result["stderr"],
            "parse_error": err,
        })
        if err is None:
            break
    return {
        "case_id": case["id"],
        "filename": filename,
        "body": body,
        "attempts": attempts,
    }


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def harness_fingerprint() -> dict:
    """Capture enough of the repo + global config that a future run can be compared to this one."""
    fingerprint = {}

    project_claude_md = REPO_ROOT / "CLAUDE.md"
    if project_claude_md.exists():
        fingerprint["claude_md_sha256"] = sha256_file(project_claude_md)

    user_claude_md = Path.home() / ".claude" / "CLAUDE.md"
    if user_claude_md.exists():
        fingerprint["user_claude_md_sha256"] = sha256_file(user_claude_md)

    memory_dir = Path.home() / ".claude" / "projects" / "C--OneDrive-Documents-RobloxProjects-BrainFighter" / "memory"
    if memory_dir.exists():
        files = []
        for p in sorted(memory_dir.glob("*.md")):
            files.append({"name": p.name, "sha256": sha256_file(p)})
        fingerprint["memory_files"] = files

    try:
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO_ROOT, text=True).strip()
        fingerprint["git_commit"] = commit
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    try:
        ver = subprocess.check_output(["claude", "--version"], text=True).strip()
        fingerprint["claude_cli_version"] = ver
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    return fingerprint


def estimate_cost(model: str, usage_in: int, usage_out: int) -> float:
    if model not in PRICE_TABLE:
        return 0.0
    inp, outp = PRICE_TABLE[model]
    return (usage_in / 1_000_000) * inp + (usage_out / 1_000_000) * outp


async def main_async() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-model", action="store_true", help="bypass repo harness (CLAUDE.md, memory) via `claude -p --bare`. Requires ANTHROPIC_API_KEY.")
    parser.add_argument("--model", default=None, help="model id (raw-model mode only; default uses Claude Code's configured model)")
    parser.add_argument("--limit", type=int, default=None, help="run only first N cases (smoke test)")
    parser.add_argument("--concurrency", type=int, default=None, help="parallel calls; default 2 (harness) / 8 (raw-model)")
    parser.add_argument("--run-name", default=None, help="name for runs/<name>/ output dir")
    parser.add_argument("--cases", type=Path, default=CASES_PATH, help="path to cases.jsonl")
    args = parser.parse_args()

    if args.raw_model and not os.environ.get("ANTHROPIC_API_KEY"):
        print("ERROR: --raw-model requires ANTHROPIC_API_KEY", file=sys.stderr)
        return 2

    backend = "raw-model" if args.raw_model else "harness"
    concurrency = args.concurrency or (8 if args.raw_model else 2)
    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H-%M-%S")
    run_name = args.run_name or f"{backend}-{timestamp}"
    run_dir = EVAL_DIR / "runs" / run_name
    outputs_dir = run_dir / "outputs"
    responses_dir = run_dir / "responses"
    outputs_dir.mkdir(parents=True, exist_ok=True)
    responses_dir.mkdir(parents=True, exist_ok=True)

    cases = load_cases(args.cases, args.limit)
    print(f"Loaded {len(cases)} cases. Backend={backend}, concurrency={concurrency}.")
    print(f"Output dir: {run_dir}")

    semaphore = asyncio.Semaphore(concurrency)
    started_at = dt.datetime.now(dt.timezone.utc)
    tasks = [run_case(c, raw_model=args.raw_model, model=args.model, semaphore=semaphore) for c in cases]

    parse_errors: list[str] = []
    total_in_tokens = 0
    total_out_tokens = 0
    total_cost_usd = 0.0
    models_seen: dict[str, int] = {}

    for i, fut in enumerate(asyncio.as_completed(tasks), 1):
        result = await fut
        case_id = result["case_id"]
        attempt = result["attempts"][-1] if result["attempts"] else None
        if attempt:
            primary = attempt.get("primary_model")
            if primary:
                models_seen[primary] = models_seen.get(primary, 0) + 1
            total_cost_usd += attempt.get("cost_usd", 0.0)
        if result["filename"] is None:
            parse_errors.append(case_id)
            last_err = attempt["parse_error"] if attempt else "no attempts"
            print(f"[{i}/{len(cases)}] {case_id:35s} PARSE-ERR  {last_err}")
        else:
            out_path = outputs_dir / f"{case_id}__{result['filename']}"
            out_path.write_text(result["body"], encoding="utf-8")
            in_tok = attempt["usage"].get("input_tokens", 0) or attempt["usage"].get("cache_read_input_tokens", 0) or 0
            out_tok = attempt["usage"].get("output_tokens", 0) or 0
            total_in_tokens += in_tok
            total_out_tokens += out_tok
            print(f"[{i}/{len(cases)}] {case_id:35s} OK         {result['filename']:40s} ({attempt['elapsed_s']:.1f}s)")

        response_path = responses_dir / f"{case_id}.response.json"
        response_path.write_text(json.dumps({
            "case_id": case_id,
            "attempts": result["attempts"],
            "filename": result["filename"],
        }, indent=2), encoding="utf-8")

    completed_at = dt.datetime.now(dt.timezone.utc)

    # If `models_seen` recorded the resolved model, prefer that over the user-supplied alias.
    resolved_model = max(models_seen, key=models_seen.get) if models_seen else None
    primary_model_label = resolved_model or args.model or "(unknown)"

    manifest = {
        "run_name": run_name,
        "backend": backend,
        "model": primary_model_label,
        "model_alias_requested": args.model if args.raw_model else "(Claude Code configured default)",
        "models_seen": models_seen,
        "started_at": started_at.isoformat(),
        "completed_at": completed_at.isoformat(),
        "wall_seconds": (completed_at - started_at).total_seconds(),
        "case_count": len(cases),
        "concurrency": concurrency,
        "parse_errors": parse_errors,
        "tokens": {"input": total_in_tokens, "output": total_out_tokens},
        # `total_cost_usd` reflects what the equivalent API call would have cost.
        # In harness mode (subscription) this is informational only — no actual charge.
        "reported_cost_usd": round(total_cost_usd, 4),
    }
    if args.raw_model and args.model:
        manifest["estimated_cost_usd"] = round(estimate_cost(args.model, total_in_tokens, total_out_tokens), 4)
    if not args.raw_model:
        manifest["harness_fingerprint"] = harness_fingerprint()

    (run_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print()
    print(f"Run complete: {run_dir}")
    print(f"  Model: {primary_model_label}")
    print(f"  {len(cases) - len(parse_errors)}/{len(cases)} parsed cleanly, {len(parse_errors)} parse errors")
    print(f"  Tokens: {total_in_tokens} in / {total_out_tokens} out")
    print(f"  Reported cost: ${total_cost_usd:.4f}" + ("  (informational — subscription)" if not args.raw_model else ""))
    if args.raw_model and args.model:
        print(f"  Estimated cost (price-table): ${manifest.get('estimated_cost_usd', 0):.4f}")
    print(f"  Next: uv run evals/rojo_schema/grade.py --run {run_name}")
    return 0


def main() -> int:
    return asyncio.run(main_async())


if __name__ == "__main__":
    sys.exit(main())
