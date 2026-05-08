---
description: Scaffold a new weapon (handgun, rifle, or melee) via the weapon-builder subagent
argument-hint: <type: handgun|rifle|melee> <Name>
---

Delegate to the `weapon-builder` subagent (Task tool, `subagent_type: "weapon-builder"`) to create a new weapon.

Arguments: `$ARGUMENTS`

Parse as `<type> <Name>`:
- `type` must be one of `handgun`, `rifle`, or `melee` — maps to reference template `Pistol`, `Rifle`, or `Sword` respectively
- `Name` must be PascalCase and not already taken under `src/shared/Weapon/Templates/`

If either argument is missing or invalid, ask the user before dispatching.

When launching the subagent, pass:
- The resolved type and reference template name
- The target `Name`
- Any mesh hints the user mentioned in the prompt (e.g. "I imported it as workspace.Foo")
- Confirmation that the `creating-weapons` skill will auto-load for it

The subagent handles scaffolding, Studio-side wiring, grip iteration, playtest verification, and the commit. Hand control back to the user when it finishes or needs input.
