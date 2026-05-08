#!/usr/bin/env python3
"""
Rojo JSON schema validator.

Catches the silent-fail traps that bit us before — and *only* those.
Rojo's actual behavior is more lenient than CLAUDE.md implies; this
validator avoids style-policing and focuses on patterns that have
caused real production bugs.

Hard-blocked patterns (file fails CI):

* `.meta.json` with a `children` array — Rojo silently ignores it, so
  the children never appear in Studio. RoundStarted / RoundEnded paid
  for this. Use one `.model.json` per child instead.
* `.meta.json` with a `name` field — Rojo ignores it; the author
  almost certainly meant `.model.json`. Catches the conversion
  half-finished bug.
* `.model.json` missing `className` — Rojo refuses to create the
  instance and the consumer waits forever via WaitForChild.
* Either file type with invalid JSON — Rojo errors at sync time, but
  the error is easy to miss in the Rojo panel; better to block locally.

NOT enforced (convention-only, Rojo handles fine):

* Non-init `.meta.json` with `className` and no sibling .luau/folder —
  Rojo treats this as instance-creating in many cases. The convention
  prefers `.model.json`, but this isn't a correctness bug.
* `.model.json` without explicit `name` — Rojo derives the name from
  the filename stem.

Run modes:
  python tools/validate_rojo_json.py <files...>    # lint specific files
  python tools/validate_rojo_json.py --all         # walk src/ exhaustively
  python tools/validate_rojo_json.py --staged      # lint git-staged files only

Exit code 0 on pass, 1 on any error.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parent.parent
SRC_ROOT = REPO_ROOT / "src"

META_ALLOWED_TOP_LEVEL = {
    "className",
    "properties",
    "attributes",
    "ignoreUnknownInstances",
    "tags",
}

MODEL_REQUIRED_TOP_LEVEL = {"className"}
MODEL_ALLOWED_TOP_LEVEL = {
    "className",
    "name",
    "properties",
    "attributes",
    "tags",
    "children",
}


def _load_json(path: Path) -> tuple[dict | None, str | None]:
    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        return None, f"invalid JSON: {e}"
    except OSError as e:
        return None, f"cannot read: {e}"
    if not isinstance(data, dict):
        return None, "root must be a JSON object"
    return data, None


def _validate_meta(path: Path, data: dict) -> list[str]:
    errors: list[str] = []

    # The headline trap.
    if "children" in data:
        errors.append(
            "`.meta.json` cannot declare `children` — Rojo silently ignores "
            "it and the child instances never appear in Studio. Move each "
            "child into its own `.model.json` file in the same folder. "
            "(RoundStarted / RoundEnded silent-fail trap.)"
        )

    if "name" in data:
        errors.append(
            "`.meta.json` should not have `name` — Rojo ignores it (the "
            "instance name comes from the file/folder path). If you wanted "
            "to set a name, use `.model.json` instead."
        )

    # Don't double-report keys that already triggered a dedicated rule above.
    unknown = set(data.keys()) - META_ALLOWED_TOP_LEVEL - {"children", "name"}
    if unknown:
        errors.append(
            f"unknown top-level keys: {sorted(unknown)}. "
            f"Allowed: {sorted(META_ALLOWED_TOP_LEVEL)}"
        )

    return errors


def _validate_model(path: Path, data: dict) -> list[str]:
    errors: list[str] = []

    missing = MODEL_REQUIRED_TOP_LEVEL - data.keys()
    if missing:
        errors.append(
            f"missing required keys: {sorted(missing)}. "
            "`.model.json` must declare `className` (Rojo derives the "
            "instance name from the filename if `name` is omitted)."
        )

    for key in ("className", "name"):
        if key in data and not (isinstance(data[key], str) and data[key].strip()):
            errors.append(f"`{key}` must be a non-empty string")

    unknown = set(data.keys()) - MODEL_ALLOWED_TOP_LEVEL
    if unknown:
        errors.append(
            f"unknown top-level keys: {sorted(unknown)}. "
            f"Allowed: {sorted(MODEL_ALLOWED_TOP_LEVEL)}"
        )

    return errors


def validate_file(path: Path) -> list[str]:
    data, err = _load_json(path)
    if err:
        return [err]
    assert data is not None
    if path.name.endswith(".meta.json"):
        return _validate_meta(path, data)
    if path.name.endswith(".model.json"):
        return _validate_model(path, data)
    return []  # not a Rojo schema file we care about


def _iter_all_targets() -> Iterable[Path]:
    for pattern in ("**/*.meta.json", "**/*.model.json"):
        yield from SRC_ROOT.rglob(pattern)


def _iter_staged_targets() -> Iterable[Path]:
    try:
        out = subprocess.check_output(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
            cwd=REPO_ROOT,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"warning: could not list staged files ({e})", file=sys.stderr)
        return
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.endswith(".meta.json") or line.endswith(".model.json"):
            yield REPO_ROOT / line


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--all", action="store_true", help=f"walk {SRC_ROOT.relative_to(REPO_ROOT)} exhaustively")
    group.add_argument("--staged", action="store_true", help="lint git-staged files only")
    parser.add_argument("files", nargs="*", type=Path, help="explicit files to lint")
    args = parser.parse_args()

    if args.all:
        targets = list(_iter_all_targets())
    elif args.staged:
        targets = list(_iter_staged_targets())
    elif args.files:
        targets = [p.resolve() for p in args.files]
    else:
        parser.print_help(sys.stderr)
        return 2

    targets = [p for p in targets if p.exists() and (p.name.endswith(".meta.json") or p.name.endswith(".model.json"))]

    if not targets:
        return 0

    failures: list[tuple[Path, list[str]]] = []
    for path in targets:
        errors = validate_file(path)
        if errors:
            failures.append((path, errors))

    if failures:
        print("Rojo JSON schema validator: FAIL", file=sys.stderr)
        for path, errors in failures:
            try:
                rel = path.relative_to(REPO_ROOT)
            except ValueError:
                rel = path
            print(f"\n  {rel}", file=sys.stderr)
            for e in errors:
                print(f"    - {e}", file=sys.stderr)
        print(
            f"\n{len(failures)} file(s) failed validation. "
            "See https://rojo.space/docs/v7/sync-details/ for the full schema.",
            file=sys.stderr,
        )
        return 1

    print(f"Rojo JSON schema validator: OK ({len(targets)} file(s) checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
