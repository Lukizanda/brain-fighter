---
description: Generate a Meshy prompt for a new asset (weapon or environment) using the project's family vocabulary, then append the accepted result to memory so the library grows
argument-hint: <category> <Name> [optional one-line brief]
---

The user wants a Meshy prompt for a new asset that respects the project's existing visual vocabulary. Memory holds two libraries — `reference_meshy_weapon_prompts.md` for weapons and `reference_meshy_environment_prompts.md` for environment assets — each with rules + actually-used prompts. This command generates a new prompt informed by those, then **appends the accepted result back to the library** so the next invocation has more context.

Arguments: `$ARGUMENTS` — parse as `<category> <Name> [optional one-line brief]`.

## Categories

| Category | Memory file | Notes |
|----------|-------------|-------|
| `weapon-rifle` | `reference_meshy_weapon_prompts.md` | Two-handed firearm, rifle scale |
| `weapon-handgun` | `reference_meshy_weapon_prompts.md` | One-handed firearm, pistol scale |
| `weapon-melee` | `reference_meshy_weapon_prompts.md` | Sword / bat / hammer / etc. |
| `env-tile` | `reference_meshy_environment_prompts.md` | Tileable architectural (wall, floor, roof, ceiling) |
| `env-window` | `reference_meshy_environment_prompts.md` | Window or aperture |
| `env-vegetation` | `reference_meshy_environment_prompts.md` | Trees, plants, mushrooms, foliage |
| `env-prop` | `reference_meshy_environment_prompts.md` | Cover crates, barrels, level-dressing props |
| `env-fixture` | `reference_meshy_environment_prompts.md` | Lights, signs, doors, non-tileable architectural |

If the category doesn't match the table, ask the user. Don't guess.

## Procedure

1. **Read the relevant memory file** based on category. Both files live under `~/.claude/projects/c--OneDrive-Documents-RobloxProjects-Sandbox/memory/`.

2. **Identify the closest sibling.** For weapons that's a same-archetype entry in the same family (e.g. BlasterMk2 → BlasterPistol). For env assets it's a same-category entry that matches whatever family the project's level has settled on. If no sibling exists yet, seed from the category's rules section directly.

3. **Generate the prompt** following the rules:
   - Lead with the asset's role + scale ("Lowpoly sci-fi rifle" / "Lowpoly stylized pine tree").
   - Describe 3-5 structural features (shapes Meshy can build, not adjectives).
   - Reuse vocabulary verbatim from the closest sibling for at least 3 details so the family resemblance survives remesh.
   - Add explicit negations only when changing form factor (pistol "no stock", tile "edges flush").
   - End with "single isolated object on plain background."
   - Drop "no character, no hands" framing unless terse prompts misfire — see the weapon-prompts rules for the rationale.

4. **Show the prompt to the user.** Ask for one of:
   - `looks good` / `ship it` / `accept` → proceed to step 5
   - `tweak: <change>` → revise and re-show
   - `start over with <new direction>` → re-generate from scratch

5. **Append to memory.** Once accepted, edit the relevant memory file's Library section (locate the `## Library — used prompts` heading or `## Prompt library` heading depending on file) and add a new entry following the existing shape:

   ```md
   ### <Name> — <one-line description> (YYYY-MM-DD)

   > <the accepted prompt verbatim>

   Why it works: <1-2 sentence rationale — what structural details anchor it to the family, what scale/silhouette overrides this asset needed>
   ```

   For weapons the rationale should reference the sibling whose vocabulary was reused. For env assets the rationale should reference the family anchor (wall ribs, wood slats, etc.) and the category's tileability/scale notes.

   Use the `Edit` tool to splice the entry into the correct section — don't `Write` the whole file (preserves untouched content).

6. **Don't auto-commit.** This is memory, not the repo. Memory writes are immediate and don't go through git.

## Pitfalls to avoid

- **Don't append the prompt before user accepts.** The library should reflect prompts the user actually shipped, not Claude's first draft.
- **Don't lose the user's tweaks.** If the user says `tweak: <change>`, the saved prompt is the post-tweak version, not the original.
- **Don't duplicate categories in env file.** Sub-sections within the env library are organised by category — appending to the wrong sub-section pollutes the future-sibling-lookup.
- **Don't write `originSessionId` on appended entries.** That field is for the memory file's frontmatter, not per-entry.
- **Don't drop the closest-sibling rationale** when generating — it's the entire reason the library exists. If no sibling exists, say so explicitly: "No prior <category> in the library; seeding from the rules section."

## Why this command and not Fabric

The project's visual consistency depends on cross-prompt continuity (sibling vocabulary, family anchors, scale words). Stateless CLI tools like Fabric can't carry that context across invocations without you re-feeding examples each time. The slash command instead leans on auto-memory — Claude already loaded both prompt libraries on session start, so the closest-sibling lookup is free.

Future option: if the user later wants the standalone-CLI workflow (e.g. for batch generation), Fabric can be layered on with its pattern reading from these same memory files. The two paths aren't exclusive.
