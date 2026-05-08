# Roblox Game Development — Core Rules

## Project Wiki
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

## Character & Physics
- **Never set HumanoidRootPart.CFrame directly** to control orientation — the physics engine overrides it. Use `AlignOrientation` constraints with `RigidityEnabled = true` instead.
- **AutoRotate = false** is necessary but not sufficient for orientation control. You must pair it with a constraint.
- For TPS shooter characters: lock the whole body to camera yaw via AlignOrientation, use Motor6D manipulation (Waist/Neck/Shoulders) for upper body fine-tracking.
- **Don't hardcode Motor6D parent paths** — R15 rigs vary. Search by Motor6D name across `character:GetDescendants()`.

## Animation System
- Animation priority hierarchy: Core (lowest) < Idle < Movement < Action (highest).
- Locomotion animations go in `ReplicatedStorage.Shared.LocomotionAnimations` as Animation instances (not synced by Rojo — create via MCP).
- Name animations to match MovementState: `Forward`, `Backward`, `StrafeLeft`, `StrafeRight`.
- Set `track.Priority = Enum.AnimationPriority.Movement` and `track.Looped = true` for locomotion.

## Render Step Priorities
- `RenderPriority.Character.Value + 1` for locomotion (runs after Humanoid movement processing).
- `RenderPriority.Camera.Value + 1` for camera (runs after Roblox's default camera step).
- Higher priority number = runs later = gets the final say.

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

## No Magic Numbers
- Never use unexplained numeric or string literals in logic. Declare a named constant in the appropriate `*Constants.luau` file.
- Acceptable inline: `0`, `1`, `-1`, `true`, `false`, empty string `""`.

## Single Ownership Rule
- One system should own each Motor6D / property. If two scripts write to the same Motor6D.C0 or Humanoid.AutoRotate, they will fight. Merge them into one controller.
