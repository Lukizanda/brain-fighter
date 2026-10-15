# Brain Fighter

A Roblox spelling-combat game: players pop letter blocks, spell words, and cast colour-typed spells in PvE boss rounds and 1v1 duels.

## Stack
- **Luau** (`.luau`), **R15** rigs, **Rojo 7.7** syncs disk → Studio. Toolchain via `rokit`, packages via `wally install`.
- Studio is driven through the **`Roblox_Studio` MCP** (`execute_luau`, `start_stop_play`, `get_console_output`, …).
- Enable the pre-commit validator once per clone: `git config core.hooksPath .githooks`.

## Start of every non-trivial task
1. Read [`wiki/index.md`](wiki/index.md) to see which systems exist and what has shipped.
2. For code questions, run `graphify query "<question>"` (`graphify path` / `graphify explain`) before you grep.

## Rules that apply to every task
- **Disk is the source of truth.** Write scripts to disk and let Rojo sync them. Never use MCP to edit a script that should persist.
- **Log with `Logger`** (`ReplicatedStorage.Shared.Core.Logger`), never raw `print`/`warn`.
- **Players only see and hear what clients draw.** Server code never calls `spawnEffect`; it calls `VfxBroadcast` / `SkillVisuals`. See [vfx-sfx.md](docs/agents/vfx-sfx.md).
- **No magic numbers.** Put named constants in the owning `*Constants.luau`. You can write `0`, `1`, `-1`, booleans and `""` inline.
- **Put each new behavior in the system that owns it.** Each Motor6D or property has exactly one writer.

## Rojo JSON hard rules
These rules stay here because `evals/rojo_schema/` tests them with tools disabled. The pre-commit hook blocks violations.
- `.meta.json` only changes an instance Rojo already creates. It **must not** declare `children` or `name`. Allowed keys: `className`, `properties`, `attributes`, `ignoreUnknownInstances`, `tags`.
- `.model.json` **must** declare `className`. Allowed keys: `className`, `name`, `properties`, `attributes`, `tags`, `children`.
- Write strict JSON: no trailing commas, no comments, no single quotes, even if the user asks for them.
- To make a folder of hand-authored children, write `init.meta.json` (`{"className": "Folder", "ignoreUnknownInstances": true}`) plus one sibling `<Child>.model.json` per child.

## Load these when the task touches them
| Topic | File |
|---|---|
| Rojo sync, `ignoreUnknownInstances`, pre-sync safety checks | [docs/agents/rojo-sync.md](docs/agents/rojo-sync.md) |
| Studio MCP, playtest lock, test suites, DataModel mutations | [docs/agents/studio-and-playtests.md](docs/agents/studio-and-playtests.md) |
| Player-facing VFX/SFX: server vs client, how to verify | [docs/agents/vfx-sfx.md](docs/agents/vfx-sfx.md) |
| Luau style, naming, cleanup pattern | [docs/agents/luau-conventions.md](docs/agents/luau-conventions.md) |
| `src/` layout and the spelling-combat chain | [docs/agents/project-structure.md](docs/agents/project-structure.md) |
| Subagents, parallel sessions, model choice, session phases | [docs/agents/sessions-and-subagents.md](docs/agents/sessions-and-subagents.md) |
| Committing, pushing, wiki upkeep, graphify | [docs/agents/commit-and-wiki.md](docs/agents/commit-and-wiki.md) |
| Platform gotchas we verified: Rojo, Studio MCP, Roblox engine, Open Cloud | [wiki/reference/](wiki/index.md) (Reference section) |
| Architecture, game design, anything cross-system | [wiki/WIKI.md](wiki/WIKI.md) |
