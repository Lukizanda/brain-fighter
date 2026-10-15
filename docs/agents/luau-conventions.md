# Luau conventions

## Types
- Annotate every function signature (parameters and return type). Use `export type` for types shared across modules.
- Never use `--!nocheck`. Fix the type error instead.

## Lifecycle
- Every controller or system that allocates resources has both `:disable()` and `:destroy()`.
  - `:disable()` is reversible (a pause).
  - `:destroy()` calls `:disable()` and then clears all state (permanent teardown).

## Ownership
- Before adding code, name the system that owns the behavior and put the code there, not in whichever file is closest.
- Each Motor6D, `Humanoid.AutoRotate` or similar property has one writer. If two scripts write the same one, merge them into one controller.
- Find Motor6Ds by name across `character:GetDescendants()`. Don't hardcode their parent paths.

## Naming
- Classes, controllers and systems use PascalCase (`HealthService.luau`). Utilities and effects use camelCase (`lerp.luau`).
- Top-level distribution folders are lowercase (`client/`, `server/`, `shared/`). Domain folders are PascalCase (`Health/`, `Skills/`).
- Pure-Luau gameplay modules follow `<Name>/init.luau` plus `<Name>/__tests.luau`.
- Use `init.meta.json` for folder container properties, and `<Name>.meta.json` next to scripts that need child instances.

## Cross-VM timing
- `os.clock()` is per-VM. Any timestamp that crosses the wire uses `workspace:GetServerTimeNow()`.
