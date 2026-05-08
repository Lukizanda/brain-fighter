---
type: concept
description: Roblox Open Cloud sometimes returns "Invalid API Key" days after the key was last verified working. Workaround for this project — regenerate the key in the dashboard and paste the new value into `.env`.
updated: 2026-05-02
---

# Roblox Open Cloud Auth — "Invalid API Key" workaround

Symptom: `tools/weapon_icon.py publish` (or any `apis.roblox.com/...` call via `x-api-key`) returns `HTTP 401 {"errors":[{"code":0,"message":"Invalid API Key"}]}`, even though the value in `.env` is unchanged from when publish last succeeded.

## Workaround

1. Go to https://create.roblox.com/dashboard/credentials → **API Keys**
2. Click the existing key → **Regenerate** (or create a new one if needed; required scope is `asset:write`)
3. Paste the new value into `.env` as `ROBLOX_OPEN_CLOUD_API_KEY=<value>` (replacing the old line)
4. Re-run `tools/weapon-icon.sh publish --weapon <Name>`

That's it — the underlying root cause (the value the dashboard hands back appears to have a short TTL even when "no expiration" is set on the key) isn't worth chasing for this project's cadence. Regenerate when it stops working.

## Cross-references

- Auto-memory: `feedback_roblox_open_cloud_api_key.md`
- Token-vs-resolution gotcha for uploaded Decals: use `rbxthumb://...` for Open Cloud-uploaded Decals — `rbxassetid://` doesn't resolve. See `feedback_roblox_open_cloud_icon.md`.
- Pipeline that hits this: [[systems/Weapon]]'s icon section, `tools/weapon_icon.py`
