# TPS Shooter Template

A Roblox third-person shooter template with camera, locomotion, weapon, and health systems.

## Starting a new project

1. Use this repo as a GitHub template (or clone + reset git)
2. Open `template.rbxl` in Roblox Studio
3. Install the Rojo plugin in Studio if not already installed
4. Run `rojo serve` from the project root
5. Connect Rojo from Studio (localhost:34872)
6. Run `/setup-project YourGameName` to create test objects (animations, target dummy, spawner)
7. Start building!

## What's included

### On disk (Rojo-synced)

| System | Location | Description |
|---|---|---|
| **Core** | `src/shared/Core/` | Logger, Cleanup mixin, InputCategorizer |
| **Camera** | `src/shared/Character/CameraController.luau` | TPS spring-arm camera with mode transitions |
| **Locomotion** | `src/shared/Character/LocomotionController.luau` | Directional movement states, upper body tracking, AlignOrientation |
| **Weapon Framework** | `src/shared/Weapon/` | WeaponController → FirearmController (single attribute-driven controller; `cameraModeFamily` Tool attribute selects Handgun vs Rifle) |
| **Health & Damage** | `src/shared/Health/` | Damage modifier pipeline, hit zones, constants |
| **Health Server** | `src/server/Health/` | HealthService, DeathHandler (clone-based respawn) |
| **Firearm Server** | `src/server/Firearm/` | Server-side shot validation, anti-cheat |
| **Client Managers** | `src/client/` | CameraManager, LocomotionManager, CharacterSystemsLoader |
| **Client UI** | `src/client/UI/` | HealthGui (health bar, damage flash, death screen) |
| **Networking** | `.meta.json` files | All RemoteEvents and BindableEvents |
| **Utilities** | `src/utility/` | disconnectAndClear, lerp, safePlayerAdded, bindToInstanceDestroyed |

### In template.rbxl (Studio-only)

| Instance | Location | Description |
|---|---|---|
| **Blaster Tool** | `Shared.Weapon.Templates.Blaster` | Complete weapon with Handle, Animations, Sounds, Haptics |
| **ViewModels** | `Shared.Weapon.ViewModels` | First-person weapon models with rigs |
| **VFX Objects** | `Shared.Weapon.Objects` | LaserBeam, CharacterImpact, EnvironmentImpact |
| **GUIs** | Under WeaponGuiController/WeaponTouchInputController | BlasterGui, ReticleGui, BlasterTouchGui, Hitmarker |
| **Spawner Meshes** | `Spawner.Meshes` | DefaultPedestal model |
| **R15 Rig** | `Workspace.Rig` | Reference character rig |
| **SpawnLocation** | `Workspace` | Player spawn point |

## What to customize

### Adding a new weapon
1. Create a new Tool in `Shared.Weapon.Templates/` (duplicate Blaster as a starting point)
2. Create a new controller in `src/shared/Weapon/Scripts/` extending `WeaponController`
3. Add server validation in `src/server/`
4. Add a spawner in Workspace with `WeaponName` attribute matching the template name

### Adding damage modifiers
Edit `src/shared/Health/DamageModifierRegistry.luau` — add new modifiers to the pipeline:
- `headshotModifier` — multiplies damage for headshots (2x)
- `armorModifier` — reduces damage by armor percentage (placeholder)
- `shieldModifier` — absorbs damage with shield HP (placeholder)

### Adding locomotion animations
Create Animation instances in `ReplicatedStorage.Shared.LocomotionAnimations`:
- Name must match MovementState: `Forward`, `Backward`, `StrafeLeft`, `StrafeRight`
- Set AnimationId to your animation asset
- The LocomotionController picks them up automatically

### Adding damageable objects
1. Add a `Humanoid` to any Model
2. Tag it with `Damageable` via CollectionService
3. Set attributes: `maxHealth` (number), `respawnTime` (number, 0 = no respawn)
4. The HealthService and DeathHandler manage it automatically

## Architecture rules

- **Rojo for scripts** — always write scripts to disk, never via MCP
- **MCP for Studio instances** — Animations, GUIs, complex models stay in Studio
- **Single ownership** — one system owns each Motor6D/property
- **AlignOrientation over CFrame** — use constraints for physics-safe rotation
- **Clone-based respawn** — destroy + clone from template, don't try to reset Humanoids
- **Logger for all output** — use `Logger.new("SystemName")`, never bare `print()`
- **disable() + destroy()** — every controller exposes both, destroy always calls disable first
- **.luau only** — no .lua files
