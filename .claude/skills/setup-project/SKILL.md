---
name: setup-project
description: Set up Studio instances for a new project using the TPS shooter template — creates test targets, locomotion animations, weapon spawners, and damageable templates
allowed-tools: mcp__robloxstudio-mcp__create_object, mcp__robloxstudio-mcp__set_property, mcp__robloxstudio-mcp__set_attribute, mcp__robloxstudio-mcp__add_tag, mcp__robloxstudio-mcp__execute_luau, mcp__robloxstudio-mcp__get_instance_children
argument-hint: [project name]
---

# Setup Project

Set up Studio-only instances for a new project based on the TPS shooter template.
Project name: $ARGUMENTS

## Prerequisites

Before running this skill:
1. Open `BrainFighter.rbxl` in Roblox Studio
2. Connect Rojo (`rojo serve`) and sync

## Steps

### Step 1: Verify template is loaded

Check that the BrainFighter.rbxl base instances exist:
- `game.ReplicatedStorage.Shared.Weapon.Templates.Blaster` (Tool)
- `game.ReplicatedStorage.Shared.Weapon.Objects` (VFX folder)
- `game.ReplicatedStorage.Shared.Weapon.ViewModels` (weapon models)

If missing, warn the user to open BrainFighter.rbxl first.

### Step 2: Create LocomotionAnimations

Create Animation instances in `game.ReplicatedStorage.Shared.LocomotionAnimations`:

| Name | AnimationId | Notes |
|---|---|---|
| Forward | (leave empty) | User adds their own |
| Backward | rbxassetid://180426354 | Placeholder walk animation |
| StrafeLeft | (leave empty) | User adds their own |
| StrafeRight | (leave empty) | User adds their own |

Only create animations that don't already exist. Set Priority to Movement and Looped to true where possible via attributes.

### Step 3: Create TargetDummy

Create a simple damageable target in Workspace for testing:

1. Create a Model named "TargetDummy" at position (0, 5, -15)
2. Add parts:
   - HumanoidRootPart (2x2x1, Transparency=1, Anchored=true, CanCollide=false) at (0, 5, -15)
   - Head (Ball shape, 1.2 size, BrickColor="Bright yellow", Anchored=true) at (0, 7.4, -15)
   - UpperTorso (2x1.6x1, BrickColor="Bright blue", Anchored=true) at (0, 6, -15)
   - LowerTorso (2x0.4x1, BrickColor="Bright blue", Anchored=true) at (0, 4.5, -15)
3. Add Humanoid with Health=100, MaxHealth=100
4. Set PrimaryPart to HumanoidRootPart
5. Create RootJoint Motor6D via execute_luau (Part0=HumanoidRootPart, Part1=LowerTorso)
6. Set Humanoid.BreakJointsOnDeath = false
7. Add CollectionService tag "Damageable"
8. Set attributes: maxHealth=100, respawnTime=5

### Step 4: Create WeaponSpawner

Create a spawner Part in Workspace:

1. Create Part named "WeaponSpawner" at position (0, 3.5, -5)
2. Set Size to (4, 1, 4), Anchored=true, BrickColor="Medium stone grey"
3. Set attributes: WeaponName="Blaster", SpawnerMesh="DefaultPedestal"

### Step 5: Verify setup

Use get_instance_children to confirm:
- LocomotionAnimations has the animation instances
- TargetDummy exists with Humanoid, tag, and attributes
- WeaponSpawner exists with correct attributes

Report what was created and what the user needs to configure next:
- Add animation IDs to Forward/StrafeLeft/StrafeRight
- Customize weapon spawner positions
- Add more damageable targets as needed