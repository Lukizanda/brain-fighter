---
type: schema
description: Conventions and operations for the Brain Fighter project wiki — read this first before reading or writing any other wiki page.
---

# Brain Fighter Wiki — Schema

Inspired by Karpathy's [LLM Wiki gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f). Three layers, in priority order from authoritative to derived:

1. **Raw sources** (authoritative) — `src/` source tree, `CLAUDE.md`, the auto-memory at `~/.claude/projects/.../memory/`, `.rbxlx` Studio state, git history.
2. **The wiki** (this folder) — markdown summaries, system pages, design notes, decisions, status snapshots. Owned by the LLM. Cross-references everywhere.
3. **The schema** (this file) — conventions for layer 2.

**The wiki never replaces the source tree.** When the wiki and the code disagree, the code wins and the wiki is wrong.

## Folder layout

```
wiki/
  WIKI.md              — this file (schema + operations)
  index.md             — categorized catalog of every wiki page
  log.md               — append-only chronological record of ingests / lints
  systems/             — one page per gameplay/engine system (Weapon, Health, NPC, Locomotion, HUD, Loadout, GameMode, Tests)
  design/              — game-design pages (vision, art direction, weapon family vocabulary, level intent)
  decisions/           — mini-ADRs: non-obvious choices with rationale
  concepts/            — recurring patterns / shared idioms (Single Ownership, Builder+Config+LayoutManager, .model.json)
  status/              — living progress snapshots per workstream (TDM, Loadout, Greybox, Melee, etc.)
```

## Page conventions

Every page begins with frontmatter:

```yaml
---
type: system | design | decision | concept | status
description: one-line hook — used in index.md and search
updated: YYYY-MM-DD
---
```

- **Wikilinks**: `[[Page Name]]` (Obsidian style). Use `[[Page Name|alt text]]` when the alt text is more readable.
- **Code references**: `src/path/to/file.luau:line` so the user can click through.
- **Dates**: absolute (`2026-04-30`), never relative ("yesterday", "last week").
- **No magic claims**: if a page says "X works this way", the reader should be able to verify it from the named files. Don't paraphrase code that's about to drift.

## Page types

| Type | Purpose | Lifetime |
|---|---|---|
| `system` | What a code system does, key files, dependencies, contracts. Reflects current `src/`. | Long-lived; updated when the system changes. |
| `design` | Game-design intent (vision, pillars, art direction, vocabulary). | Long-lived; updated when intent shifts. |
| `decision` | Why we made a non-obvious choice. Rationale + alternatives considered. | Append-only — old decisions stay even when superseded; add a "Superseded by" link. |
| `concept` | A pattern or idiom that recurs across systems. | Long-lived. |
| `status` | Living progress snapshot for a workstream. | High churn — updated whenever progress is made. May be archived when the workstream ships. |

## Operations

### Ingest

Triggered when the user says "log this", finishes a meaningful change, or after a design conversation. The LLM:

1. Identifies which existing pages need to be updated (often 3–10).
2. Updates them in place — keeps frontmatter `updated` current.
3. Creates new pages where a concept/system/decision doesn't yet have a home.
4. Updates `index.md` with any new pages.
5. Appends one entry to `log.md`: `## [YYYY-MM-DD] ingest | <one-line topic>` followed by a 2–4 line summary of what changed and which pages were touched.

A single ingest can touch 10–15 pages — that's the bookkeeping the wiki exists to absorb.

### Query

When the user asks a design or architecture question:

1. Read the relevant wiki pages first, then verify against `src/` if the answer hinges on current behaviour.
2. Answer with citations: `[[System Page]]` and `src/path:line`.
3. If the answer is non-trivial and reusable, offer to file it back as a new page (often a `decision/` or `concept/` entry).

### Lint

On demand (`/wiki-lint` or "lint the wiki"):

1. Find broken wikilinks (target page doesn't exist).
2. Find pages older than 30 days whose `updated` date is suspect — verify against `git log` of referenced files.
3. Find contradictions between pages (rare, but the index makes them findable).
4. Find orphans — pages no link points to. Either link them in or delete.
5. Report findings; the user decides what to act on.

## What does NOT belong in the wiki

- Anything reproducible from `git log` / `git blame`.
- File-by-file API documentation that mirrors the code (the code is the doc).
- Ephemeral session state — that goes in plans, tasks, or memory.
- Secrets, tokens, asset upload credentials.
- Rules already in `CLAUDE.md` — link to them, don't duplicate.

## Relationship to other systems

- **`CLAUDE.md`** — engineering rules (Rojo workflow, naming, single ownership). The wiki cites these but doesn't restate them.
- **Auto-memory** (`~/.claude/projects/.../memory/`) — cross-conversation reminders for the LLM (user preferences, feedback, reference pointers). Project-specific facts that recur and are stable should migrate here. Memory remains the LLM's working memory; the wiki is the project's shared brain.
- **`docs/`** in the repo — long-form snapshots (e.g. `docs/npc-mvp-status.md`). The wiki summarizes and links; it doesn't replace.
