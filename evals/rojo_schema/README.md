# Rojo Schema Eval

An automated quiz for the AI agent that authors most of this repo's `.meta.json` and `.model.json` files. 50 generation prompts → call the agent → grade with the existing validator → produce a pass-rate that can be tracked across model versions, prompt changes, and time.

## What this measures

This repo has a [validator](../../tools/validate_rojo_json.py) that hard-blocks five silent-fail patterns in Rojo project sync files. The validator is **defense** — it catches the bug at commit time, after the LLM has already produced bad output that someone has to fix.

This eval is **prevention**. It measures whether the actual day-to-day generation pipeline (Claude Code in this repo, with this `CLAUDE.md`, this auto-memory, whatever skills load on the prompt) avoids producing those patterns in the first place. The headline is a single number: "X out of 50 generations would have passed the validator on the first try."

A non-100% baseline is the *interesting* result. The whole point of the eval is to surface where the harness leaks, so you can patch it and watch the number move.

## Why this matters

The five hard-blocked patterns aren't theoretical — `RoundStarted` and `RoundEnded` were both broken on this project by the `.meta.json`-with-`children` trap until the cause was found. The validator now catches that at commit time. This eval closes the loop upstream: if the agent stops producing the trap, we never hit the validator at all. See [`wiki/concepts/RojoJsonValidator.md`](../../wiki/concepts/RojoJsonValidator.md).

## How to run

### Default (system eval — uses your Claude Code subscription)

```bash
uv run evals/rojo_schema/run.py                       # writes runs/harness-<utc>/
uv run evals/rojo_schema/grade.py                     # writes report.md + report.csv
```

No API key needed. The runner shells out to `claude -p` 50 times against your normal Claude Code harness — same CLAUDE.md, same memory, same model setting. Wall time ≈ 15-25 minutes at the default concurrency of 2. Subscription quota: 50 short calls.

### Raw-model mode (component eval — needs API key)

```bash
export ANTHROPIC_API_KEY=sk-ant-...
uv run evals/rojo_schema/run.py --raw-model --model claude-sonnet-4-6
uv run evals/rojo_schema/grade.py
```

Uses `claude -p --bare`, which skips CLAUDE.md auto-discovery, auto-memory, hooks. Isolates the model from the harness. Cost: ~$0.40 on Sonnet, ~$0.04 on Haiku. Use this only when diagnosing the system eval — i.e. when the harness score drops, you want to know whether the model regressed or your CLAUDE.md did.

### Smoke test

```bash
uv run evals/rojo_schema/run.py --limit 3 --run-name smoke
uv run evals/rojo_schema/grade.py --run smoke
```

## Case design

50 cases in [`cases.jsonl`](cases.jsonl), one JSON object per line:

```json
{"id": "T1a-children-roundstarted", "style": "filename-fixed", "expected_kind": ".meta.json",
 "trap": "meta-with-children", "prompt": "Write the contents of ...", "notes": "Bait: ..."}
```

### Trap cases (25)

Each prompt is **designed to tempt** the agent into a validator-rejected pattern. The correct response *resists the bait*. Phrasings are realistic things a developer might actually ask for.

| Trap | ID prefix | Count | What the prompts bait |
|---|---|---|---|
| `meta-with-children` | `T1` | 5 | Phrasings like "include the child Sound inline", "declare them as children". Rojo silently ignores `children` in `.meta.json` — RoundStarted/RoundEnded incident. |
| `meta-with-name` | `T2` | 5 | Prompts that ask for an instance name distinct from the filename stem. Rojo ignores `name` in `.meta.json`. |
| `model-missing-classname` | `T3` | 5 | Prompts that describe behavior ("a signal for when…", "the channel that…") without naming a Roblox class. `.model.json` without `className` produces no instance. |
| `invalid-json` | `T4` | 5 | Requests for inline comments, trailing commas, markdown headers, single quotes — non-JSON conventions a developer might absentmindedly ask for. |
| `unknown-keys` | `T5` | 5 | Metadata-style fields (`description`, `version`, `author`, `label`) and the `classname` (lowercase) typo. |

### Positive cases (25)

Clean prompts that a competent agent should pass easily. They establish the baseline and surface failures that *aren't* trap-driven (formatting, refusal, etc).

| Category | ID prefix | Count | Coverage |
|---|---|---|---|
| `init-meta-folder` | `P1` | 5 | `init.meta.json` declaring a Folder with `ignoreUnknownInstances`. Pattern: [`src/shared/Core/init.meta.json`](../../src/shared/Core/init.meta.json). |
| `standalone-meta` | `P2` | 5 | Standalone `.meta.json` creating non-folder instances (BindableEvent, RemoteEvent, Configuration). Pattern: [`src/server/Health/Events/PlayerDamaged.meta.json`](../../src/server/Health/Events/PlayerDamaged.meta.json). |
| `simple-model` | `P3` | 5 | `.model.json` for versioned instances (RemoteEvent, Sound, Animation). Pattern: [`src/shared/GameMode/Remotes/GameStateChanged.model.json`](../../src/shared/GameMode/Remotes/GameStateChanged.model.json). |
| `model-with-properties` | `P4` | 5 | `.model.json` with a `properties` block — Color3, multi-property Sound, StringValue, IntValue. |
| `model-derived-name` | `P5` | 5 | `.model.json` that omits `name`, letting Rojo derive it from the filename stem. Pattern: [`src/utility/bindToInstanceDestroyed/DestructionHandler/Bind.model.json`](../../src/utility/bindToInstanceDestroyed/DestructionHandler/Bind.model.json). |

### Style: `filename-fixed` vs `open`

- **`filename-fixed`** (27 cases): the prompt names the file path, so the agent has no choice about `.meta.json` vs `.model.json`. Grading is validator-only.
- **`open`** (23 cases): the prompt describes intent, the agent picks the extension. Grading has two axes:
  1. **kind_correct** — did the agent pick the expected extension?
  2. **validator_passed** — does the file pass the validator?

A case passes only if both axes pass. The split lets the report distinguish "the agent generates valid content but picks the wrong filetype" from "the agent picks the right filetype but generates invalid content."

## Output layout

```
runs/<run-name>/
├── manifest.json                 # backend, started/completed, tokens, harness_fingerprint
├── report.csv                    # one row per attempted case (committed)
├── report.md                     # summary + failure dump (committed)
├── outputs/                      # generated files (committed)
│   ├── T1a-children-roundstarted__RoundStarted.meta.json
│   ├── P3a-model-shoot__Shoot.model.json
│   └── ...
└── responses/                    # raw API blobs (gitignored)
    └── <id>.response.json
```

The `manifest.json` for system-eval runs records a **harness fingerprint** — SHA256 of `CLAUDE.md`, the user's global `CLAUDE.md`, every auto-memory file, the git commit, and the `claude` CLI version. This locks down which version of the harness produced the number. A re-run six months from now isn't comparable unless the fingerprint matches.

## Baseline result

| run | score | what changed |
|---|---|---|
| [`baseline-harness-2026-05-22`](runs/baseline-harness-2026-05-22/report.md) | **42/50 (84%)** | Initial baseline. Sonnet 4.6 against the harness as it existed at git `592736c`. |
| [`harness-after-rules-2026-05-22`](runs/harness-after-rules-2026-05-22/report.md) | **47/50 (94%)** | Added a "Rojo JSON Hard Rules" block to `CLAUDE.md` (explicit DO-NOT rules + exhaustive allowed-keys lists). +10 points; remaining failures are all open-ended kind-selection cases. |

The 10-point jump is the iteration loop the eval was built for: **measure → patch CLAUDE.md → re-measure**. Filename-fixed cases went 27/27 (100%) after the rules — every trap with an unambiguous user intent is now resisted. The remaining gap is open-ended cases where the model can legally choose `.meta.json` vs `.model.json`; the codebase itself uses both conventions, so this is house-style ambiguity, not a single rule away from being fixed.

### Current baseline detail — `harness-after-rules-2026-05-22`

| metric | value |
|---|---|
| model | `claude-sonnet-4-6` (Claude Code default via `~/.claude/settings.json`) |
| backend | `harness` (full repo CLAUDE.md + auto-memory loaded) |
| wall time | ~6 min (concurrency 2) |

**Pass rate by trap (post-rules):**

| trap | pass | total |
|---|---|---|
| `meta-with-children` | 3 | 5 |
| `meta-with-name` | 5 | 5 |
| `model-missing-classname` | 5 | 5 |
| `invalid-json` | 5 | 5 |
| `unknown-keys` | 5 | 5 |
| _positive cases_ | 24 | 25 |

**Pass rate by style:** filename-fixed **27/27 (100%)** · open-ended 20/23 (87%).
**Pass rate by expected kind:** `.meta.json` 17/20 (85%) · `.model.json` 30/30 (100%).

### What still fails

All 3 remaining failures are **open-ended kind-selection** cases — the prompt describes intent without naming a filename, the model picks `.model.json` over the conventional `.meta.json`, and the file passes the validator but loses on `kind_correct`:

- `T1b-children-soundpack`, `T1d-children-particle-fx` — folder-with-children prompts. Model emits `<Folder>.model.json` with children inline (legal Rojo) instead of the conventional `init.meta.json` + sibling-`.model.json`-per-child pattern. The CLAUDE.md rule names this convention but doesn't override the model's strong prior toward consolidation.
- `P2d-meta-tags` — RemoteEvent + a tag. Model picks `.model.json`; the repo itself has BOTH `.meta.json` and `.model.json` patterns for tagged remotes, so this is house-style ambiguity in the codebase, not a single CLAUDE.md rule away from being fixed.

### A note on the parser fix

The very first ungraded run scored 38/50 (76%). Three of those "failures" were the model giving *correct* answers wrapped in markdown ```` ```json ```` fences (which the parser kept verbatim, breaking the validator on the leading ` ``` ` line). After patching the parser to strip fences and extract the first valid JSON value, those three converted to passes — the model didn't change, only my extraction did. So the genuine baseline against the original harness was 84%, and the post-rules run is 94%.

### A note on noise

A smoke test of the same three `T1` cases run earlier the same day produced *different* outputs than the full baseline run (e.g. T1a-roundstarted came back as `.model.json` in the baseline, but `.meta.json` with a `children` array in the smoke test). System eval is intrinsically noisy — Claude Code's session-level memory load, skill triggers, and context warming all vary between runs. Treat single-run deltas of less than ~5 points as inside the noise floor; run twice to estimate.

### To reproduce or re-baseline

```bash
uv run evals/rojo_schema/run.py --run-name baseline-harness-<DATE>
uv run evals/rojo_schema/grade.py --run baseline-harness-<DATE>
```

## Regressions caught

- **2026-05-22** — baseline established at 42/50 (84%) against `claude-sonnet-4-6` + the BrainFighter harness at git `592736c`.
- **2026-05-22** — added a "Rojo JSON Hard Rules" block to `CLAUDE.md` (explicit DO-NOT rules for the four hard-blockable patterns + exhaustive allowed-keys lists for both file types). Re-run: **47/50 (94%), +10 points.** All filename-fixed cases now pass (27/27); every trap category except `meta-with-children` is now 5/5. Remaining failures are open-ended kind-selection cases where house style in the codebase itself is ambiguous.

## Adding a case

1. Append a JSONL line to `cases.jsonl`:
   ```json
   {"id": "T1f-children-attachments", "style": "open", "expected_kind": ".meta.json", "trap": "meta-with-children", "prompt": "...", "notes": "Bait: ..."}
   ```
2. Re-run + re-grade.
3. Commit the new case + the updated report.

The `notes` field exists so the case can be defended six months later when no one remembers why the prompt is worded the way it is.

## Limitations

- **Schema, not intent.** The validator only catches the five hardcoded silent-fail patterns. A case where the agent picks `BindableEvent` when the user meant `RemoteEvent` will pass the validator — the file is schema-valid, just semantically wrong. The eval measures schema validity, not intent fidelity.
- **System-eval noise floor.** Memory triggers and skill triggers vary run-to-run; the same backend can swing ~5 points between runs. Run twice to estimate variance before reading too much into a small delta.
- **Harness fingerprint locks a moment.** If `CLAUDE.md` drifts, comparing a new run to an old number requires matching fingerprints or accepting that the comparison is loose.
- **Single-shot generation only.** The eval doesn't test multi-turn refinement ("here's my draft, please fix the children array"). That's a v2 design.

## File index

- [`cases.jsonl`](cases.jsonl) — the 50 generation prompts
- [`run.py`](run.py) — calls Claude, writes outputs
- [`grade.py`](grade.py) — runs the validator, writes the report
- [`runs/`](runs/) — per-run artifacts (one subdir per `--run-name`)
- [`../../tools/validate_rojo_json.py`](../../tools/validate_rojo_json.py) — the validator (existed before this eval)
- [`../../wiki/concepts/RojoJsonValidator.md`](../../wiki/concepts/RojoJsonValidator.md) — wiki page for the validator
