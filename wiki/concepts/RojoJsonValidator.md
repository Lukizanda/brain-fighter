---
type: concept
description: Pre-commit validator for `.meta.json` / `.model.json` files; hard-blocks the silent-fail traps Rojo doesn't warn about
updated: 2026-05-22
---

# Rojo JSON Validator

**Files:** [`tools/validate_rojo_json.py`](../tools/validate_rojo_json.py) (the linter) + [`.githooks/pre-commit`](../.githooks/pre-commit) (the hook).

## Why

Rojo's JSON files are easy to break in ways that surface as silent runtime bugs, not Rojo errors. Two classes have already cost real debug time on this project:

1. **`.meta.json` with a `children` array** — looks like it should create child instances; Rojo silently ignores it. `RoundStarted` / `RoundEnded` were broken this way until the cause was found.
2. **`.model.json` missing `className`** — Rojo refuses to create the instance. The consumer's `WaitForChild` waits forever; nothing in the Rojo panel flags it.

These don't show up in `git diff` review unless you already know the trap. A pre-commit hook is the right place to catch them.

## What it blocks

| Pattern | Why it's a bug |
|---|---|
| `.meta.json` with `children` array | Silent fail; children never appear in Studio. Use one `.model.json` per child. |
| `.meta.json` with `name` field | Rojo ignores it. Author almost certainly wanted `.model.json`. Catches half-finished conversions. |
| `.model.json` missing `className` | No `className` → no instance → consumer hangs. |
| Invalid JSON in either file | Rojo errors at sync time but it's easy to miss in the panel; better to block locally. |
| Unknown top-level keys | Typos like `classsName` or `propertys`. |

## What it does NOT enforce

Originally the validator was stricter. After empirical MCP-probing of a running Studio session (see ingest log entry 2026-05-01) I dropped two rules that turned out to be over-corrected:

- **`.model.json` must have `name`** — Rojo derives the name from the filename stem when omitted. `Bind.model.json` with `{"className": "BindableEvent"}` produces a `Bind` BindableEvent.
- **Non-init `.meta.json` with `className` must have a sibling .luau/folder** — CLAUDE.md says non-init `.meta.json` files only *modify* an existing instance. Empirically Rojo creates instances from this pattern in many cases. The convention prefers `.model.json` (more explicit), but it's a style preference, not a correctness rule. The validator stays out of style debates.

The lesson: **validate against proven bugs, not aspirational conventions.** Style policing produces false positives that erode trust in the tool.

## Run modes

```sh
python tools/validate_rojo_json.py --all       # walk src/ exhaustively
python tools/validate_rojo_json.py --staged    # lint git-staged files only (what the hook uses)
python tools/validate_rojo_json.py path/to/file.meta.json  # explicit
```

Exit code 0 on pass, 1 on any error.

## Hook setup (one-time, per clone)

```sh
git config core.hooksPath .githooks
```

The hook script auto-skips if Python isn't on PATH (so contributors without Python don't get blocked, though they then carry the risk). Bypass for an emergency commit: `git commit --no-verify`.

## Upstream measurement: the generation eval

The validator is *defense*. By the time it fires, the LLM has already produced a bad file someone has to fix. [`evals/rojo_schema/`](../../evals/rojo_schema/) is the *prevention* counterpart — 50 generation prompts targeting the five trap categories above, graded by this validator, run through the actual Claude Code harness (CLAUDE.md + memory + skills). Headline at baseline: Sonnet 4.6 scored 42/50 (84%) against the BrainFighter harness on 2026-05-22.

The eval is what you run before/after changing `CLAUDE.md` to measure whether the change actually reduces the bug class at the source.

## Related

- [[concepts/ModelJsonInstances]] — when to use `.model.json` vs `.meta.json` (project convention).
- [`evals/rojo_schema/README.md`](../../evals/rojo_schema/README.md) — generation eval suite that uses this validator as its automated grader.
- `CLAUDE.md` — Pre-Sync Safety Checks section.
