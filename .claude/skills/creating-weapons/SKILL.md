---
name: creating-weapons
description: Knowledge for creating new weapons (handgun, rifle, melee) in this TPS shooter — file layout, Studio-side setup, conventions, gotchas, and grip/mesh iteration workflows. Loads when adding weapons, copying templates, importing weapon meshes, or debugging weapon spawns.
---

# Creating Weapons

Reference for adding new weapons to this project. Three archetypes exist:

| Archetype | Reference template | Controller | `cameraModeFamily` | Hands |
|-----------|-------------------|------------|--------------------|-------|
| Handgun | `Blaster` | `FirearmController` | `"Handgun"` | one |
| Rifle (2-handed gun) | `AutoRifle` | `FirearmController` | `"Rifle"` | two |
| Melee | `Sword` | `MeleeSwingController` | n/a | one or two |

For a new weapon, copy the matching reference template's structure. After Phase B1's consolidation (2026-05-01) all firearms share one `FirearmController` and differ only by Tool attributes — `cameraModeFamily` selects the camera mode set, the rest (damage, RPM, magazine, etc.) is per-attribute. Don't create a `<Name>Controller` subclass; the previous Handgun/Rifle wrappers existed only to set 3 strings each and were retired.

## Split: what lives where

**Source (Rojo-synced, git-versioned):**
- `src/shared/Weapon/Templates/<Name>/init.meta.json` — Tool properties, `Grip`, gameplay attributes
- `src/shared/Weapon/Templates/<Name>/Scripts/<Name>.client.luau` — controller hookup
- `src/shared/Weapon/Templates/<Name>/Scripts/KeepAnchored.server.luau` — anchors Handle in Workspace (pedestal display); **without this the Tool falls through the floor after spawning**

**Studio-side (.rbxl, not versioned, protected by `ignoreUnknownInstances: true` on the Tool):**
- `Handle` — the MeshPart or Part the Tool uses as its physical handle
- `MuzzleAttachment` (Attachment) on the Handle — shot origin for firearms
- `Animations` folder — `Idle` / `Shoot` / `Reload` Animation instances with asset IDs
- `Sounds` folder — `AudioPlayer` instances (Shoot1/2/3 subfolder, Equip, MagIn, MagOut, Charger)
- `Haptics` folder — HapticEffect instances (ShootHaptic)
- `SwingAnimation` (melee only) — single Animation instance

Rifle-pose animations, shoot sounds, and haptics can be **cloned wholesale from AutoRifle via MCP** when creating a new rifle — the character only needs an `Idle` animation to strike the correct hold pose. Same for Blaster→handgun, or author new sets as needed.

## Firearm attributes (init.meta.json)

All firearms declare these. Tune per-weapon:

| Attribute | Type | Example | Notes |
|-----------|------|---------|-------|
| `_ammo` | Int32 | 30 | **MUST equal** `magazineSize` at spawn or equip will auto-reload before animations load and crash |
| `_reloading` | Bool | false | |
| `magazineSize` | Int32 | 30 | |
| `fireMode` | String | `"Auto"` or `"Semi"` | |
| `rateOfFire` | Float32 | 600 | Rounds per minute |
| `damage` | Float32 | 10 | |
| `range` | Float32 | 1000 | Max ray distance (studs) |
| `raysPerShot` | Int32 | 1 | `>1` → shotgun pattern |
| `rayRadius` | Float32 | 0.4 | Spherecast radius |
| `spread` | Float32 | 2.0 | Degrees |
| `reloadTime` | Float32 | 1.5 | Seconds |
| `recoilMin` / `recoilMax` | Vector2 | `[0,0]` | |
| `aimAssist*` | Float32 | varies | Range, FOV, friction, tracking, centering |
| `viewModel` | String | `"Blaster"` | First-person view model identifier |
| `unanchoredImpulseForce` | Float32 | 2 | Knockback on unanchored parts |
| `EnableFireRotation` | Bool | true | Pedestal weapon rotation |

## Melee attributes (init.meta.json)

Melee uses a different pipeline (`MeleeSwingController` + `MeleeSwingService`):

| Attribute | Type | Example | Notes |
|-----------|------|---------|-------|
| `meleeDamage` | Float32 | 25 | |
| `meleeReach` | Float32 | 6 | Studs in front of handle |
| `meleeHitboxWidth` | Float32 | 5 | |
| `meleeHitboxHeight` | Float32 | 5 | |
| `meleeWindupSeconds` | Float32 | 0.15 | Pre-active |
| `meleeActiveSeconds` | Float32 | 0.1 | Damage window |
| `meleeRecoverySeconds` | Float32 | 0.25 | Post-active |
| `meleeCooldownSeconds` | Float32 | 0.5 | Measured from Active entry |
| `meleeHitMode` | String | `"Single"` or `"Cleave"` | |

## Mesh import pipeline (Meshy)

Use `tools/prep-fbx.sh` to make the Meshy FBX Roblox-friendly, then import via Studio:

```bash
tools/prep-fbx.sh weapon.fbx              # default: rotate (0,0,90), scale 0.015
tools/prep-fbx.sh weapon.fbx 0 90 0       # custom Euler
tools/prep-fbx.sh weapon.fbx 0 0 0 --scale 1.0  # skip transforms
```

Output is `<input>_roblox.fbx` next to the input. Import that via Studio's `File → Import 3D…` dialog. Defaults are tuned for Meshy — axis-correct and roughly weapon-sized on first import. After import the mesh lands in `Workspace.<MeshyName>` (typically a Model containing one MeshPart).

## Mesh → Handle wiring (via MCP)

After import, the mesh is in `workspace.<name>` (typically a Model containing a MeshPart).

**Two Handle patterns:**

**A. Mesh-as-Handle (what BlasterMk2 uses):** clone the MeshPart directly as the Tool's `Handle`. Simple; works for meshes that are a single MeshPart. Set `Anchored=false`, `CanCollide=false`, `Massless=true`.

**B. Invisible Handle + welded mesh (what AutoRifle uses):** keep a 0.5³ transparent Part named `Handle`; put the visible mesh(es) in a child `Model:<Name>` with WeldConstraints back to the Handle. Needed when the visible weapon is a multi-part Model.

For rifles/handguns in this project, **pattern B is cleaner** because the Tool's pivot stays at a known invisible point while the visual can be offset/replaced without re-tuning Grip.

## Grip iteration workflow

Grip CFrame is tool-relative — affects how the Handle attaches to the hand when equipped.

1. In Studio, equip the Tool on a dummy character OR parent the Tool to the **template** at `ReplicatedStorage.Shared.Weapon.Templates.<Name>` and use Studio's **right-click → Edit Grip** tool. (Editing the template is the only path that survives Rojo sync — playtest clones don't propagate.)
2. Tweak until it looks right in hand.
3. Run `/capture-grip <Name>` — the slash command reads the live `Grip` CFrame via MCP, writes the 12-component matrix back to `init.meta.json`, runs the Rojo JSON validator, and shows you the diff. **Doesn't auto-commit** — eyeball the diff, equip the weapon to verify it feels right, then commit.
4. If Rojo's auto-sync keeps overwriting your tweak before you can capture, disconnect the Studio Rojo plugin first, tweak + capture, then reconnect.

## Spawn marker setup

Weapons appear in-world via `RespawnPedestalManager` (the legacy `WeaponSpawnerManager` was retired in Phase B2 on 2026-05-01):

- Place a `Part` named `RespawnPedestal` anywhere in `workspace` (typically under a `SpawnZone.RespawnPedestals` folder, see `Workspace.Arena.SpawnZone` for the live layout)
- Set attributes on the part:
  - `WeaponName` (String) — must match the template's folder name in `Templates/`
  - `SpawnerMesh` (String, optional) — a pedestal mesh from `Spawner/Meshes`
  - `RespawnAfterClaim` (Bool, optional) — default true; set false for one-shot spawns
  - `Stub` (Bool, optional) — true if the target weapon is intentionally retired and the pedestal is left as a level-intent marker (e.g. `ShieldPrototype` post-C3); the manager skips silently instead of warning about the missing template
- At round-start the manager scans tagged parts, clones each weapon onto the pedestal, and per-pedestal regenerates after a player picks the weapon up

## MuzzleAttachment

Firearms require an `Attachment` named `MuzzleAttachment` on the `Handle` (or on the Body MeshPart for pattern B). Without it, shot origins fall back to the camera, which looks visibly wrong.

- Place at the **barrel tip** in the Handle's local frame
- The forward direction should align with the barrel (typically `+Z` or `-Z` depending on mesh orientation)
- Add a `ParticleEmitter` named `FlashEmitter` as a child for muzzle flash (clone from `AutoRifle.AutoRifle.Body.MuzzleAttachment.FlashEmitter`)
- Set `Attachment.Visible = true` during placement so you can drag it in the viewport; untoggle for ship

## Rojo gotchas

- `.meta.json` **does not create instances** — it only modifies properties of instances Rojo is already creating. To version a non-script instance (like a `RemoteEvent`), use a `.model.json` with `{ "className": "RemoteEvent", "name": "..." }`
- Int32 attributes (like `_ammo`, `magazineSize`, `raysPerShot`) sometimes fail to sync on fresh template creation. If the weapon crashes on equip with a nil error, re-set them via MCP
- If multiple stale `rojo.exe` processes exist, Studio may be talking to the wrong one. Kill all and restart the serve
- After deleting/renaming files on disk, Studio may keep stale duplicates — check `get_instance_children` after the sync

## ToolNoneAnim + default hotbar

- Roblox auto-plays `ToolNoneAnim` on tool equip. For **melee**, `MeleeSwingController` stops it in `_suppressDefaultToolAnim` so character keeps walk/idle animations between swings. Firearms don't need this because `WeaponAnimationController` loads a Weapon-provided `Idle` at Action priority
- The project hides the default Backpack hotbar (`GameConfig.SHOW_BACKPACK = false`). Press number keys `1`/`2`/... to equip, or use `DEV_AUTO_EQUIP_TOOL = "<Name>"` in `GameConfig` to auto-equip a specific tool on spawn for testing

## Melee extras

Melee weapons don't use Animations/Sounds/Haptics folders. Instead:
- A single `Animation` instance named `SwingAnimation` child of the Tool, with an uploaded KeyframeSequence asset ID
- **Hierarchical Pose tree** in the KeyframeSequence (HRP → LowerTorso → UpperTorso → branches). Flat poses load without error but silently don't animate joints
- `MeleeSwingController` plays it on `Windup` state entry; server `MeleeSwingService` validates the swing, runs `MeleeHitDetector.sweep`, applies damage through `HealthService.applyDamage`

## Test verification checklist

After creating a weapon, playtest and confirm:
- No errors on equip
- Pose/hold looks right
- Shoot / swing triggers (click) with animation + sound + haptic
- Muzzle origin visible at barrel, not camera (firearms)
- Reload works (R key) for firearms
- Reticle / HUD updates
- Grip tuned cleanly in hand

## Reference templates (for copy-paste starting points)

- `src/shared/Weapon/Templates/Blaster/` — handgun reference
- `src/shared/Weapon/Templates/AutoRifle/` — rifle reference
- `src/shared/Weapon/Templates/Sword/` — melee reference
- `src/shared/Weapon/Templates/BlasterMk2/` — most recent rifle, matches current workflow
