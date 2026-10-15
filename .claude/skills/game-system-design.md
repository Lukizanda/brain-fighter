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

- **BlockShoot** owns block consumption: validating a pop and appending the letter to the buffer
- **Health** owns HP, damage processing (`applyDamage`), death, respawn
- **Economy** owns mana: `EnergyLedger` is the only writer
- **SpellCast** owns the cast relay and validation; **Skills** owns what a cast does
- **BlockSpawner** owns letter-block creation at marked locations

If a feature touches two domains, the systems communicate through **shared contracts** and never import each other's server/client scripts.

### 2. Three-Layer Separation

Every system follows this layout:

```
src/server/{System}/                -- Server-authoritative logic
  {System}Service.server.luau       -- Entry point: wires remotes/events, owns state
  {System}Constants.luau            -- Server-only tuning
  {System}Validation.luau           -- Guards for anything a client sends
  Events/                           -- BindableEvents (one .model.json each)

src/shared/{System}/                -- Contracts shared by client and server
  init.meta.json                    -- { "className": "Folder" }
  {System}Constants.luau            -- Tags, attribute names, numeric config
  {Domain}Types.luau                -- Type definitions and enums
  Remotes/                          -- RemoteEvents (one .model.json each)

src/shared/{Module}/                -- Pure-Luau gameplay module (no Instances, no services)
  init.luau
  __tests.luau

src/client/                         -- Client scripts (thin; delegate to shared modules)
  {Feature}.client.luau
```

Older systems (Health, GameMode, NPC, Boss) keep their server code in `Scripts/` subfolders. Match whichever layout the system you're editing already uses; don't migrate it as a side effect.

**Rules:**
- Shared constants, types, and remotes go in `src/shared/{System}/`.
- Client scripts in `src/client/` should be thin loaders that delegate to shared modules.
- Never put server logic in shared. Never put client-only UI code in shared (HUD builders in `shared/Hud/` are the exception: they are pure construction code).
- Spelling-chain logic (WordBuffer, Dictionary, SpellRegistry, CastAction, …) stays pure Luau so `__tests.luau` can run it without a playtest.

### 3. Communication Boundaries

Systems talk through these mechanisms only:

| Pattern | When to Use | Example |
|---------|-------------|---------|
| **RemoteEvent** | Client-server RPC | `SpellCastServer:FireServer(...)` |
| **BindableEvent** | Server-to-server cross-system | `PlayerEliminated:Fire(...)` |
| **Shared types/constants** | Data contracts | `DamageTypes.DamageRequest` |
| **CollectionService tags** | Dynamic instance discovery | `GetTagged("Damageable")` |
| **Attributes on instances** | Per-instance state the other VM reads | an NPC's `CurrentState` |

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

### 5. Extensibility via Registries and Data

Design systems so new variants are added by registration or data, not by modifying core code.

- **Registry pattern** for modifiers: `DamageModifierRegistry.modifiers`. Add a new modifier function to the array.
- **Data-driven specs** for spells: a new spell is a new entry in `SpellRegistry`'s `SPELLS` table, not a new code path.
- **Handler tables** for behaviour variants: `SkillDelivery.handlers[skill.delivery]` dispatches `instant` / `projectile` / `aoe` / `world_spawn`. A new delivery is a new handler, and the caller doesn't change.

### 6. Validation at System Boundaries

All data crossing trust boundaries (client to server) must be validated:

- Validate every remote argument with the guards in `src/server/Utility/TypeValidation/` (`validateNumber`, `validateInstance`, `validateVector3`), then with the system's own `{System}Validation.luau` (see `BlockShootValidation`, `SpellCastValidation`).
- Rate-limit spammable remotes with `src/server/Utility/RateLimiter.luau`.
- The server must re-derive anything the client claims: re-check reach, re-read the buffer, re-check the energy cost.
- Never trust client-provided instance references without verifying ownership and type.

### 7. Consistent Naming

| Item | Convention | Example |
|------|-----------|---------|
| System folders | PascalCase | `Health/`, `BlockShoot/` |
| Server entry points | `{System}Service.server.luau` | `BlockShootService.server.luau` |
| Constants files | `{System}Constants.luau` | `HealthConstants.luau` |
| Type definition files | `{Domain}Types.luau` | `DamageTypes.luau` |
| Registry files | `{Domain}Registry.luau` | `DamageModifierRegistry.luau` |
| Validation | `{System}Validation.luau`; generic guards `validate{Thing}.luau` | `SpellCastValidation.luau`, `validateNumber.luau` |
| Shared controllers | `{Name}Controller.luau` | `DashController.luau` |
| meta.json for folders | `init.meta.json` | `{ "className": "Folder" }` |

### 8. New System Checklist

When creating a new system, ensure:

- [ ] Server logic is in `src/server/{System}/`, with one `{System}Service.server.luau` entry point
- [ ] Shared types, constants and remotes are in `src/shared/{System}/`
- [ ] `init.meta.json` exists for each new folder that should be a Roblox Folder instance
- [ ] Each RemoteEvent / BindableEvent is its own `.model.json`, never a lone `.meta.json`
- [ ] Cross-system communication uses remotes, bindable events, or shared types, not direct requires
- [ ] All client-to-server data is validated and, if spammable, rate-limited
- [ ] An extensibility point exists (registry, data spec, or handler table)
- [ ] Logging uses `Logger.new("{System}")`, never raw `print`/`warn`
- [ ] Anything that allocates resources has `:disable()` and `:destroy()`, and tracks and disconnects its connections
- [ ] Player-facing VFX/SFX goes through `VfxBroadcast` / `SkillVisuals`, never server-side `spawnEffect`
- [ ] No system reaches into another system's internal modules
