---
type: concept
description: Roblox Open Cloud sometimes returns "Invalid API Key" days after the key was last verified working. Workaround for this project — regenerate the key in the dashboard and paste the new value into `.env`.
updated: 2026-10-15
---

# Roblox Open Cloud Auth — "Invalid API Key" workaround

Symptom: any `apis.roblox.com/...` call via `x-api-key`) returns `HTTP 401 {"errors":[{"code":0,"message":"Invalid API Key"}]}`, even though the value in `.env` is unchanged from when publish last succeeded.

## Workaround

1. Go to https://create.roblox.com/dashboard/credentials → **API Keys**
2. Click the existing key → **Regenerate** (or create a new one if needed; required scope is `asset:write`)
3. Paste the new value into `.env` as `ROBLOX_OPEN_CLOUD_API_KEY=<value>` (replacing the old line)
4. Re-run the failing call

That's it — the underlying root cause (the value the dashboard hands back appears to have a short TTL even when "no expiration" is set on the key) isn't worth chasing for this project's cadence. Regenerate when it stops working.

## Cross-references

- Auto-memory: `feedback_roblox_open_cloud_api_key.md`
- Token-vs-resolution gotcha for uploaded Decals: use `rbxthumb://...` for Open Cloud-uploaded Decals — `rbxassetid://` doesn't resolve. See `feedback_roblox_open_cloud_icon.md`.
- First hit by the weapon-icon pipeline (`tools/weapon_icon.py`, deleted 2026-10-15 with the rest of the weapon-era tooling; recover from git history if needed)
