---
type: reference
description: Roblox Open Cloud as tested here — API keys stop working without notice (regenerate), and uploaded Decals only resolve through rbxthumb:// URLs
updated: 2026-10-15
---

# Roblox Open Cloud

**Verified against:** Open Cloud Assets API v1, 2026-04/05 (weapon-icon pipeline). **Official docs:** https://create.roblox.com/docs/cloud/open-cloud

## "Invalid API Key" with a key that used to work

Symptom: any `apis.roblox.com/...` call via `x-api-key` returns `HTTP 401 {"errors":[{"code":0,"message":"Invalid API Key"}]}`, even though the value in `.env` hasn't changed since the last successful call.

Workaround:
1. Go to https://create.roblox.com/dashboard/credentials → **API Keys**.
2. Click the existing key → **Regenerate** (or create a new one; the required scope is `asset:write`).
3. Paste the new value into `.env` as `ROBLOX_OPEN_CLOUD_API_KEY=<value>`, replacing the old line.
4. Re-run the failing call.

The underlying cause isn't worth chasing at this project's cadence: the value the dashboard hands back seems to have a short lifetime even when the key is set to never expire. Regenerate when it stops working. Never commit the key.

## Uploaded Decals need `rbxthumb://`

A PNG uploaded with `POST /assets/v1/assets` and `assetType="Decal"` returns an asset id that does **not** resolve as `ImageLabel.Image = "rbxassetid://<id>"`. `IsLoaded` stays false indefinitely, even after `ContentProvider:PreloadAsync` and minutes of waiting. The same id **does** resolve as:

```
rbxthumb://type=Asset&id=<id>&w=420&h=420
```

- `w`/`h` set the thumbnail resolution to fetch. 420 is a safe size for HUD icons.
- Likely cause: Open Cloud creates the Decal record (Approved, Active) almost at once, but the underlying Image asset that `rbxassetid://` needs takes much longer to become reachable, or never does. The thumbnail service reads the Decal directly.
- Images uploaded through Studio's Asset Manager use a different pipeline and work fine as `rbxassetid://`.
- The experience icon and thumbnails don't go through Open Cloud at all; they are uploaded in the Creator Dashboard ([[design/game-page]]).

## History

First hit by the weapon-icon pipeline (`tools/weapon_icon.py`, deleted 2026-10-15 with the rest of the weapon-era tooling; it's in git history if needed).
