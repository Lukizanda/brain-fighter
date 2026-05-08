---
name: game-system-design
description: Enforces separation of responsibilities, granular architecture, and extensibility when designing or implementing game systems
trigger: when creating new game systems, refactoring existing systems, or adding features that span multiple systems
---

# Game System Design

You are a game systems architect for a Roblox project using Rojo file sync. Apply these principles whenever creating, modifying, or reviewing game systems.

## Core Principles

### 1. Single Responsibility per System
Each system owns exactly one domain. A system should never reach into another system's internals.

- **Blaster** owns firing, ammo, reload, shot replication
- **Health** owns HP, damage processing, death, respawn
- **Character** owns locomotion, orientation, animation blending
- **Spawner** owns instance creation at marked locations

If a feature touches two domains, the systems communicate through **shared contracts** — never by importing each other's server/client scripts.

### 2. Three-Layer Separation

Every system follows this layout:

```
src/server/{System}/          -- Server-authoritative logic
  Scripts/
    init.server.luau          -- Entry point: wires remotes, initializes modules
    {submodule}.luau          -- Pure functions or injected modules

src/shared/{System}/          -- Contracts shared by client and server
  init.meta.json              -- { "className": "Folder" }
  {System}Constants.luau      -- Tags, attribute names, numeric config
  {Type}Types.luau            -- Type definitions and enums
  {Feature}.luau              -- Shared logic (registries, hit detection, etc.)

src/client/                   -- Client scripts (thin — delegates to shared controllers)
  {Feature}.client.luau
```

**Rules:**
- Server scripts go in `src/server/{System}/Scripts/`
- Shared constants, types, and registries go in `src/shared/{System}/`
- Client scripts in `src/client/` should be thin loaders that delegate to shared controllers
- Never put server logic in shared. Never put client-only UI code in shared.

### 3. Communication Boundaries

Systems talk through these mechanisms only:

| Pattern | When to Use | Example |
|---------|-------------|---------|
| **RemoteEvent** | Client-server RPC | `shootRemote:FireServer(...)` |
| **BindableEvent** | Server-to-server cross-system | `playerEliminatedEvent:Fire(...)` |
| **Shared types/constants** | Data contracts | `DamageTypes.DamageRequest` |
| **CollectionService tags** | Dynamic instance discovery | `GetTagged("Damageable")` |
| **Attributes on instances** | Per-instance config | `tool:GetAttribute("Damage")` |

**Never:** require another system's server script, share state through global tables, or use module-level mutable singletons that cross system boundaries.

### 4. Dependency Injection over Hard Imports

Submodules should receive their dependencies at initialization, not import them directly. This keeps modules testable and decoupled.

```lua
-- GOOD: applyDamage receives its remotes
function applyDamage.initialize(dependencies)
    refs = dependencies
end

-- BAD: applyDamage imports remotes directly
local remote = ReplicatedStorage.Shared.Health.Remotes.DamageFeedback
```

### 5. Extensibility via Registries and Inheritance

Design systems so new variants are added by registration or inheritance, not by modifying core code.

- **Registry pattern** for modifiers: `DamageModifierRegistry.modifiers` — add a new modifier function to the array
- **Attribute-driven controllers** for weapon variants: `FirearmController` is a single class that all firearms instantiate directly; per-weapon differences (e.g. camera mode) come from Tool attributes like `cameraModeFamily` ("Handgun" / "Rifle"). The previous Handgun/Rifle subclass pattern was retired in Phase B1 because it was carrying only camera-mode strings — adding a thin subclass per weapon variant turned out to be over-abstraction.
- **Attribute-driven config** for weapon stats: read from Tool attributes, don't hardcode per-weapon values
- **State machine pattern** for complex flows: `WeaponStateMachine` — add states and transitions declaratively

### 6. Validation at System Boundaries

All data crossing trust boundaries (client to server) must be validated:

- Validate every remote event argument with guard functions (`validateNumber`, `validateInstance`, `validateCFrame`)
- Server must re-derive anything the client claims (recast rays, recalculate positions)
- Never trust client-provided instance references without verifying ownership and type

### 7. Consistent Naming

| Item | Convention | Example |
|------|-----------|---------|
| System folders | PascalCase | `Health/`, `Character/` |
| Constants files | `{System}Constants.luau` | `HealthConstants.luau` |
| Type definition files | `{Domain}Types.luau` | `DamageTypes.luau` |
| Registry files | `{Domain}Registry.luau` | `DamageModifierRegistry.luau` |
| Server entry points | `init.server.luau` | — |
| Shared controllers | `{Name}Controller.luau` | `LocomotionController.luau` |
| Weapon-specific scripts | `Weapon{Name}.luau` prefix | `WeaponGuiController.luau` |
| Validation functions | `validate{Thing}.lua` | `validateShot.lua` |
| meta.json for folders | `init.meta.json` | `{ "className": "Folder" }` |

### 8. New System Checklist

When creating a new system, ensure:

- [ ] Server logic is in `src/server/{System}/Scripts/`
- [ ] Shared types and constants are in `src/shared/{System}/`
- [ ] `init.meta.json` exists for each new folder that should be a Roblox Folder instance
- [ ] Entry point uses an `initialize()` function pattern for clear startup order
- [ ] Cross-system communication uses remotes, bindable events, or shared types — not direct requires
- [ ] All client-to-server data is validated with guard functions
- [ ] Extensibility point exists (registry, inheritance, or attribute-driven config)
- [ ] Logging uses `[SystemName]` prefix pattern
- [ ] Connections are tracked and cleaned up via `disconnectAndClear`
- [ ] No system reaches into another system's internal modules
