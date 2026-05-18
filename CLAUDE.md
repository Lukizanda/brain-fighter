# Roblox Game Development — Core Rules

## Project Wiki
- **Read `wiki/index.md` at the start of every non-trivial task** — it's 50 lines and tells you what systems exist, what's already built, and where to look. Prevents duplicating work and catching stale assumptions before they compound.
- **Read [`wiki/WIKI.md`](wiki/WIKI.md) when working on system architecture, game design, or anything cross-system.** It's the project's living shared brain — system pages, design notes, decisions, and status snapshots, all cross-linked. Update relevant pages after meaningful changes (an "ingest"); see WIKI.md for the operations contract.

## Project Stack
- **Rojo** for file sync (disk → Studio)
- **robloxstudio-mcp** for Studio interaction (inspect, playtest, create non-synced instances)
- **Luau** (.luau preferred, .lua accepted)
- **R15** character rigs

## Rojo Workflow (Critical)
- **ALWAYS write scripts and ModuleScripts to disk** so Rojo syncs them to Studio. Never use MCP `set_script_source` for scripts that should persist. This is the #1 cause of desync — if you edit in Studio, those changes only live in the `.rbxl` and won't make it into git.
- **Use MCP for non-synced instances**: Animation objects (with AnimationId), GUI template instances (ScreenGui, Sounds) parented to scripts with `ignoreUnknownInstances`, constraints, and anything not represented in the Rojo project file.
- **Use MCP for inspection and debugging**: `get_instance_children`, `get_playtest_output`, `start_playtest`, `capture_screenshot`, `search_assets`.
- After deleting/renaming files on disk, check Studio for stale duplicates — Rojo doesn't always clean up old instances.
- `.meta.json` files **only modify an instance Rojo is already creating** (from a sibling script/folder) — they do NOT create new instances on their own. To create a versioned non-script instance like a RemoteEvent, use a `.model.json` file with `{ "className": "...", "name": "..." }`.

## Pre-Sync Safety Checks
- **Before connecting Rojo**, review the sync panel for red (delete) items. These are Studio-only instances that Rojo will destroy because they don't exist on disk.
- **Before creating or modifying a script on disk**, check if the target instance in Studio has **child objects** (GUI templates, Sounds, Animations, RemoteEvents) using `get_instance_children`. If it does, ensure the parent's `.meta.json` has `"ignoreUnknownInstances": true` — otherwise Rojo will delete those children on sync.
- **When pulling from another machine**, always compare disk files vs Studio sources before syncing. Studio may have been edited directly and contain newer code than the repo.
- **Pre-commit hook validates `.meta.json` / `.model.json` files** for the silent-fail traps (children-array in meta, missing className in model, etc). Enable per clone via `git config core.hooksPath .githooks`. See `wiki/concepts/RojoJsonValidator.md`.
- **`init.model.json` inside a folder creates a CHILD named "init"** — it does NOT define the folder's class. To make a folder represent a non-script class (e.g. MeshPart, Tool), use `init.meta.json` with `"className"` set instead. Example: `Handle/init.meta.json` with `{ "className": "MeshPart", "ignoreUnknownInstances": true, "properties": { ... } }`.
- **Any folder-based instance with Studio-side children not tracked on disk** (mesh children, attachments, SurfaceAppearance, sounds) must have `"ignoreUnknownInstances": true` in its `init.meta.json` — otherwise Rojo will delete them on every sync.

## Character & Physics
- **Never set HumanoidRootPart.CFrame directly** to control orientation — the physics engine overrides it. Use `AlignOrientation` constraints with `RigidityEnabled = true` instead.
- **AutoRotate = false** is necessary but not sufficient for orientation control. You must pair it with a constraint.
- For TPS shooter characters: lock the whole body to camera yaw via AlignOrientation, use Motor6D manipulation (Waist/Neck/Shoulders) for upper body fine-tracking.
- **Don't hardcode Motor6D parent paths** — R15 rigs vary. Search by Motor6D name across `character:GetDescendants()`.

## Debugging Pattern
1. Use `Logger` module from `ReplicatedStorage.Shared.Core.Logger` — never raw `print`/`warn`.
   ```lua
   local Logger = require(ReplicatedStorage.Shared.Core.Logger)
   local log = Logger.new("SystemName")
   log:info("message")
   log:warn("message")
   log:infoThrottled("key", 60, "per-frame data")
   ```
2. Start playtest via MCP → wait → read output via MCP → iterate.
3. Log state transitions immediately, per-frame data throttled.

## Code Style
- **Type annotations**: add Luau type annotations to all function signatures (parameters + return types). Use `export type` for types shared across modules. Never use `--!nocheck` — fix the type issue instead.
- **Cleanup pattern**: every controller/system that allocates resources must have `:destroy()` and `:disable()`. `:disable()` is reversible (pause); `:destroy()` calls `:disable()` then clears all state (permanent teardown).

## Test Suite Hygiene
- After triggering `workspace:SetAttribute("RunTests", "<suite>")` and the suite reports `[AUTORUN DONE]`, **immediately clear it**: `workspace:SetAttribute("RunTests", nil)`. Do not ask — just do it.
- The attribute persists in the `.rbxl` and silently re-fires the autorunner on every subsequent playtest, contaminating non-test sessions with test fixtures.
- `TestResult_*` and `TestRunSummary` attributes are runtime-only on the playtest VM and clear on play-stop — only `RunTests` needs explicit nil.

## Studio DataModel Mutations
- Any `execute_luau` call that creates, destroys, reparents, or renames Studio instances must be wrapped in a `ChangeHistoryService` waypoint so the user can Ctrl+Z the whole operation atomically.
  ```lua
  local ok, recording = pcall(function() return ChangeHistoryService:TryBeginRecording("label") end)
  -- do the work
  if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
  ```
- Read-only inspections (GetChildren, properties) don't need waypoints.
- When replacing a Part that has WeldConstraints pointing to it, **explicitly re-wire `Part0`/`Part1` to the replacement** before destroying the old Part — the WeldConstraint reference doesn't move with a reparent and will go nil on destroy, silently breaking the weld.

## Project Structure
```
src/
  client/          — LocalScripts (CharacterSystemsLoader, CameraManager, LocomotionManager)
    UI/            — UI LocalScripts (HealthGui)
  server/          — Server Scripts (weapon spawner, shot validation, health service)
  shared/
    Core/          — Shared utilities (Logger, Cleanup, InputCategorizer, GameConfig)
    Character/     — Character systems (CameraController, LocomotionController)
    Health/        — Health/damage types, constants, modifiers
    Hud/           — Code-driven HUD system (HudLayoutManager, builders, configs)
    Weapon/        — Weapon systems (controllers, effects, state machines)
      Scripts/     — Weapon-specific modules
      Templates/   — Weapon tool templates (Blaster, etc.)
    LocomotionAnimations/  — Folder for locomotion Animation instances
  utility/         — Generic utilities (disconnectAndClear, lerp, etc.)
```

## Naming Conventions
- Weapon-specific scripts get `Weapon` prefix if their name is otherwise generic (e.g., `WeaponGuiController`, `WeaponAnimationController`, `WeaponTouchInputController`).
- Character-level systems live in `shared/Character/` without prefix.
- Generic utilities (like `InputCategorizer`) should not be under Weapon/.
- **Script type suffixes**: `.client.luau` = LocalScript, `.server.luau` = Script, no suffix = ModuleScript.
- **Casing by role**: PascalCase for classes/controllers/systems (`WeaponStateMachine.luau`); camelCase for utilities and effects (`castRays.luau`, `impactEffect.luau`).
- **Folders**: lowercase for top-level distribution (`client/`, `server/`, `shared/`); PascalCase for domain folders (`Character/`, `Weapon/`).
- **Meta files**: `init.meta.json` for folder container properties; `<Name>.meta.json` alongside scripts that need child instances.

## No Magic Numbers
- Never use unexplained numeric or string literals in logic. Declare a named constant in the appropriate `*Constants.luau` file.
- Acceptable inline: `0`, `1`, `-1`, `true`, `false`, empty string `""`.

## Single Ownership Rule
- One system should own each Motor6D / property. If two scripts write to the same Motor6D.C0 or Humanoid.AutoRotate, they will fight. Merge them into one controller.

## Token Budget & Session Discipline

### Parallel Session Cap
- **Never spawn more than 3 concurrent subagent/Nimbalyst sessions at once.** More than 3 parallel sessions multiplies token cost without proportional throughput gain.
- **Prefer sequential over parallel for small module builds** (<150 lines each). Serial is cheaper; parallel is only worth it when modules are large and truly independent.
- **No redundant planning/context-only sessions.** Context-gathering belongs in the parent planner — never spin up a dedicated session just to read files and relay a summary.

### Ollama Pre-flight
- **Before any session that will read 3+ files or any file >200 lines**, verify Ollama is reachable: run `ollama list`. If unreachable, the global Ollama recovery flow applies.
- **In spawned subagent sessions**, use `ask_ollama.py` for all file Q&A and wiki reads. Fresh subagent contexts have no cache, so direct reads are always full price.

### Wiki Reads in Subagents
- Delegate `wiki/index.md` and `wiki/WIKI.md` reads to `ask_ollama.py` in any spawned session — never use direct Read for these in a fresh context.
- Example: `uv run C:/Users/admin/.claude/tools/ask_ollama.py --file wiki/index.md "What systems are in Phase 3?"`

### Session Lifecycle
- **Mark sessions `complete` and close them** as soon as the deliverable is done. Do not leave sessions in `validating` while iterating.
- **Cap playtest iterations at 2 per session** before escalating to the user with a diagnosis. Repeated playtest loops in a single session are a major token drain.
- **No wiki updates inside parallel build sessions.** Defer all `wiki/log.md` and system-page updates to a single follow-up session, or bundle them into the commit session.

### Scope Discipline for Spawned Sessions
- Every spawned session must have an explicit scope: which file(s) it owns, what it must not touch, and a clear done condition.
- If a spawned session discovers work outside its declared scope, it must stop and report — never expand scope autonomously.

## Wiki Maintenance
- After every commit **and** after any significant in-chat architectural decision, proactively audit `wiki/` for stale references before declaring done. Don't wait for the user to ask.
- Steps: grep `wiki/` for renamed symbols/retired concepts → update affected system/concept/design pages → append an ingest entry to `wiki/log.md` → bump `updated:` frontmatter on changed pages.
- Don't rewrite history — old `log.md` entries and decision rationales referencing now-retired terms stay as-is.
- Bundle wiki updates into the same commit where possible; separate follow-up commit if the original was already pushed.
