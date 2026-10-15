---
type: reference
description: Rojo 7.7 as tested here — .model.json creates instances, .meta.json only modifies, and a lone .meta.json silently creates nothing
updated: 2026-10-15
---

# Rojo

**Verified against:** Rojo 7.7.0 (`rokit.toml`), 2026-09-23. **Official docs:** https://rojo.space/docs/v7/sync-details/

The rules agents must follow are in `CLAUDE.md` § Rojo JSON hard rules and [`docs/agents/rojo-sync.md`](../../docs/agents/rojo-sync.md). This page records how Rojo actually behaves and how we found out.

## `.model.json` vs `.meta.json`

| File | What it does |
|---|---|
| `<Name>.model.json` | **Creates** a new instance from JSON. The instance is named `<Name>` and has `className` from the file. |
| `<Name>.meta.json` | **Modifies** an instance Rojo is already creating from a sibling script or folder. Cannot create instances on its own. |

### When you need each

- Versioning a **RemoteEvent** / BindableEvent / ScreenGui / Folder in source control: use `.model.json`.
- Marking a folder as `ignoreUnknownInstances` so MCP-created children survive sync: use `.meta.json` next to the folder's `init.luau` or `init.meta.json`.
- Setting `Properties` on a script (RunContext, Disabled): use `.meta.json` next to the script.

### Examples in this repo

- `src/shared/Lobby/Remotes/PortalRequest.model.json` — `{ "className": "RemoteEvent" }` creates the RemoteEvent; the name comes from the file name.
- `src/server/GameMode/Events/RoundStarted.model.json` and `RoundEnded.model.json` — round-event BindableEvents, one file each. (The legacy `children`-array format inside an init meta silently failed Rojo sync; the per-file form fixed it.)
- Any folder in this repo with `ignoreUnknownInstances` is using `.meta.json`.

## Traps we have hit

**`children` inside `init.meta.json`.** Rojo accepts the file but silently creates none of the children. You find out only when the runtime's `WaitForChild` yields forever. Fix: split each child into its own `.model.json`.

**A lone `Name.meta.json`** (found 2026-09-23). A `.meta.json` with a `className` and no sibling script or folder: Rojo 7.7 creates **nothing** from it. `Shared/Health/Remotes/DamageConfirm.meta.json`, `DamageFeedback.meta.json` and `Server/Health/Events/PlayerDamaged.meta.json`, `PlayerEliminated.meta.json` had sat like that since the initial commit. The RemoteEvents and BindableEvents the damage path depends on existed only in the `.rbxl`, inside a second, Studio-only `Remotes` / `Events` folder that the parent's `ignoreUnknownInstances` kept alive. Rojo's own folder was empty, and the code only worked because `FindFirstChild` returned the Studio copy first. A fresh clone would have hung on `WaitForChild`. Fixed by renaming the four files to `.model.json` and collapsing the duplicate folders.

**How to check.** Rojo's `/api/read` tree (`curl localhost:34872/api/rojo` to find the session) shows what Rojo really creates. If it shows a folder as empty, the instances in it aren't versioned, whatever Studio shows.

**`init.model.json` inside a folder** creates a child named `init`; it doesn't set the folder's class. Use `init.meta.json` with `className`.

## See also

- [[concepts/RojoJsonValidator]] — the pre-commit hook that blocks these patterns.
- [[systems/Weapon]] — `Sword/Scripts/KeepAnchored.server.luau` had a `WaitForChild("Handle")` infinite-yield because the template didn't have a Handle Part. Different bug, same shape.
