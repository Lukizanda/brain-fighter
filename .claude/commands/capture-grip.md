---
description: Capture a Tool's current Grip CFrame from live Studio into its init.meta.json (so Rojo's next sync persists the tweak instead of overwriting it)
argument-hint: <WeaponName>
---

> **STATUS: UNTESTED.** This command was authored but not run end-to-end. The MCP query and the JSON shape are based on inspection of `init.meta.json` and Rojo's documented CFrame format, not on a verified round-trip. The first invocation should be done with the user watching — verify the captured CFrame survives a Rojo sync and the weapon's grip looks right in-hand before trusting it.

The user has tweaked a weapon Tool's `Grip` in Studio and wants the value persisted to disk. Without this, the next Rojo sync overwrites the in-Studio tweak with whatever's in `init.meta.json`.

Arguments: `$ARGUMENTS` (single weapon name; PascalCase; must match a folder under `src/shared/Weapon/Templates/`)

If the argument is missing, ask which weapon. Don't guess.

## Procedure

1. **Read the live Grip via MCP `execute_luau`.** The Tool template lives at `ReplicatedStorage.Shared.Weapon.Templates.<WeaponName>`:

   ```lua
   local tool = game.ReplicatedStorage.Shared.Weapon.Templates:FindFirstChild("<WeaponName>")
   if not tool or not tool:IsA("Tool") then return "missing or wrong class" end
   local g = tool.Grip
   return string.format("%.6f|%.6f|%.6f|%.6f|%.6f|%.6f|%.6f|%.6f|%.6f|%.6f|%.6f|%.6f",
       g.Position.X, g.Position.Y, g.Position.Z,
       g.RightVector.X, g.RightVector.Y, g.RightVector.Z,
       g.UpVector.X, g.UpVector.Y, g.UpVector.Z,
       (-g.LookVector).X, (-g.LookVector).Y, (-g.LookVector).Z)
   ```

   The 12 components are returned in `init.meta.json`'s order: position(x,y,z) + orientation rows[1..3] (right, up, -look). Don't reorder — Roblox `CFrame.RightVector` / `.UpVector` / `-.LookVector` correspond to the matrix rows that Rojo reads back.

2. **Update `src/shared/Weapon/Templates/<WeaponName>/init.meta.json`.** Replace the `properties.Grip.CFrame` block with the captured values, preserving the 6-decimal precision and the `[[r11,r12,r13],[r21,r22,r23],[r31,r32,r33]]` nested-array shape Rojo expects. Use `Edit` not `Write` to keep the surrounding JSON untouched.

3. **Validate.** Run `python tools/validate_rojo_json.py <path>` on the modified file. It should pass — the schema doesn't change, only values do.

4. **Show the user the diff.** Call `git diff src/shared/Weapon/Templates/<WeaponName>/init.meta.json` so they can sanity-check before committing.

5. **Don't auto-commit.** Let the user verify the grip looks right in-game first (since the whole point is iterating). They commit when satisfied with `git add ... && git commit -m "tune(<weaponname>): capture grip from studio"`.

## Common pitfalls

- **`GripPos` conflict trap.** Roblox `Tool` has two linked properties: `Grip` (CFrame) and `GripPos` (Vector3). `GripPos` overrides the position component of `Grip` — when both are set in `init.meta.json`, Rojo applies both on every sync and whichever lands last wins. If `GripPos: [0, 0, 0]` is in the file, your tweaked grip position keeps getting zeroed on every sync. **Before / during a capture, check the file for a `GripPos` block — if present, delete it.** `Grip.CFrame` is the single source of truth; `Tool.GripPos` derives from it automatically. (Bit the LaserBlaster grip iteration loop on 2026-05-02; cleaned up across LaserBlaster + AutoRifle + Blaster in the same commit.)
- **Rojo overwrites your tweak before you run this.** If you tweak in Studio and Rojo is connected with auto-sync on, the next sync round-trip drops your edit. Pause Rojo (or disconnect, run capture, reconnect) if you find your value resetting.
- **Don't capture from playtest.** Playtest creates a clone of the Tool inside the player's character; that clone's grip changes don't propagate to the Templates folder. Edit the template Tool directly in edit-mode `ReplicatedStorage.Shared.Weapon.Templates`.
- **Verify Studio is connected before capturing.** Use `mcp__Roblox_Studio__list_roblox_studios` first if there's any doubt about which session you're driving.

## Why no Python tool

The project syncs one-way (disk → Studio) via Rojo serve, and there's no `BrainFighter.rbxlx` on disk to parse — the live workspace state only exists in the running Studio process. Reading it requires MCP (Claude or a Studio plugin); a stand-alone CLI tool can't reach it.
