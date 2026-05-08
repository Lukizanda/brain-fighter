---
name: generate-weapon-icons
description: One-shot weapon HUD icon pipeline — `tools/weapon-icon.sh` renders a diagonal hero snapshot of the weapon's FBX via headless Blender, then publishes to Roblox via Open Cloud and binds the asset ID to the weapon's `init.meta.json`. Loads when the user asks to generate a weapon icon, render a hero icon, or publish a weapon icon.
---

# Generate Weapon Icons

Single-shot pipeline: take a diagonal snapshot of the weapon's actual mesh and use that as the HUD icon. No Gemini, no multi-angle reference renders, no manual upload step.

## End-to-end command

```bash
tools/weapon-icon.sh generate --weapon <Name> --preset <sword|gun> --fbx <path>
tools/weapon-icon.sh publish  --weapon <Name>
```

`generate` renders a 1024×1024 PNG to `C:/Google Drive/Work/AI/Generated Icons/<Name>_3d.png`. `publish` uploads that PNG as a Decal via Open Cloud, waits for moderation, and writes the `WeaponIcon` attribute into `src/shared/Weapon/Templates/<Name>/init.meta.json` using the `rbxthumb://type=Asset&id=<id>&w=420&h=420` URL form.

## Inputs

| Input | Notes |
|-------|-------|
| `--weapon` | PascalCase, must match the template folder under `src/shared/Weapon/Templates/`. |
| `--fbx` | Absolute path to the weapon's FBX. Use the prepped Roblox-friendly variant (the one passed through `tools/prep-fbx.sh`), not the raw Meshy export. |
| `--preset` | `sword` or `gun`. Sword = near top-down with -45° roll. Gun = 3/4 side profile with 150° roll. Pick whichever silhouette family matches your weapon. |

## Presets (camera + mesh transform tuned per silhouette)

Defined in `CAMERA_PRESETS` in `tools/render_weapon_hero_icon.py`:

- **`sword`** — near top-down view, -45° camera roll, padding 1.05. Pommel lands bottom-left, tip top-right.
- **`gun`** — 3/4 side profile, 150° roll, padding 1.05, `flip_long_axis: True` (rotates mesh 180° around its longest bbox axis so the grip hangs down). Stock lands bottom-left, muzzle top-right.

Knobs to reach for if a new weapon shape doesn't sit right under either preset:
- `direction` — camera position vector (normalized, subject at origin).
- `roll_deg` — camera roll around its own Z so the long axis runs bottom-left to top-right in frame. **Positive delta = CW rotation of the subject in frame.**
- `padding` — multiplier on bounding-box max dim for ortho_scale; smaller = tighter crop. 1.05 is a good default.
- `flip_long_axis` — set True if the grip/optic/handle points the wrong way after rolling.

## Gotchas

- **MUST use `rbxthumb://` URL form** for `WeaponIcon` — `rbxassetid://` doesn't resolve for Open Cloud-uploaded Decals. The `publish` step does this automatically.
- The current Open Cloud API key is scoped `asset:write` only — don't try to GET the uploaded asset, it returns `PERMISSION_DENIED`. Use `MarketplaceService:GetProductInfo` from Studio if you need asset metadata.
- Bash wrapper `render-hero-icon.sh` hardcodes the Blender 5.1 path: `/c/Program Files/Blender Foundation/Blender 5.1/blender.exe`. Update if the Blender version changes.
- Secrets are loaded from `.env` at repo root: `MESHY_API_KEY` (legacy, not used by the 3d path), `ROBLOX_OPEN_CLOUD_API_KEY`, `ROBLOX_USER_ID`.

## After publish

After `publish` writes the `WeaponIcon` attribute, Rojo syncs it and `WeaponSlotStrip` picks up the icon automatically on next character spawn. No code changes needed.

## When NOT to use this skill

- The user already has a finished icon PNG and just wants to upload it — call `tools/weapon-icon.sh publish --weapon <Name> --png <path>` directly.
- The user is asking about the in-game weapon panel UI itself — that's `WeaponSlotStrip` code, not this skill.
