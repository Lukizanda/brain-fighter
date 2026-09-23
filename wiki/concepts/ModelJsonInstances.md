---
type: concept
description: .model.json creates versioned non-script instances; .meta.json only modifies. Critical Rojo gotcha.
updated: 2026-09-23
---

# `.model.json` vs `.meta.json`

A persistent source of confusion in this project. Get it wrong and Rojo silently fails to create the instance.

## The rule

| File | What it does |
|---|---|
| `<Name>.model.json` | **Creates** a new instance from JSON. The instance is named `<Name>` and has `className` from the file. |
| `<Name>.meta.json` | **Modifies** an instance Rojo is already creating from a sibling script or folder. Cannot create instances on its own. |

## When you need each

- Versioning a **RemoteEvent** / BindableEvent / ScreenGui / Folder in source control: use `.model.json`.
- Marking a folder as `ignoreUnknownInstances` so MCP-created children survive sync: use `.meta.json` next to the folder's `init.luau` or `init.meta.json`.
- Setting `Properties` on a script (RunContext, Disabled): use `.meta.json` next to the script.

## Examples in this repo

- `src/shared/Lobby/Remotes/PortalRequest.model.json` — `{ "className": "RemoteEvent" }` creates the RemoteEvent; the name comes from the file name. (Was the melee `MeleeSwingRequest` example until the weapon stack was removed.)
- `src/server/GameMode/Events/RoundStarted.model.json` and `RoundEnded.model.json` — versioning round-event BindableEvents per file. (The legacy `children`-array format inside an init meta silently failed Rojo sync; the per-file form fixed it.)
- Any folder in this repo with `ignoreUnknownInstances` is using `.meta.json`.

## The trap

A common mistake: putting a `children` array inside an `init.meta.json` to "create" sibling RemoteEvents. Rojo accepts the file but silently does not create the children. You discover this only when the runtime fires `WaitForChild` and infinite-yields. The fix is always: split each child into its own `.model.json` file.

**The quieter variant (found 2026-09-23):** a *lone* `Name.meta.json` with a `className` and no sibling script or folder. Rojo 7.7 creates **nothing** from it — `Shared/Health/Remotes/DamageConfirm.meta.json`, `DamageFeedback.meta.json` and `Server/Health/Events/PlayerDamaged.meta.json`, `PlayerEliminated.meta.json` had sat like that since the initial commit, and the RemoteEvents/BindableEvents the damage path depends on existed only in the `.rbxl`, inside a second, Studio-only `Remotes` / `Events` folder that the parent's `ignoreUnknownInstances` kept alive. Rojo's own folder was empty; the code only worked because `FindFirstChild` returned the Studio copy first. A fresh clone would have hung on `WaitForChild`. Rojo's `/api/read` tree is the tell — if it shows the folder empty, the instances are not versioned. Fixed by renaming the four files to `.model.json` and collapsing the duplicate folders.

## See also

- `CLAUDE.md` § Rojo Workflow — the canonical statement of the rule.
- [[systems/Weapon]] — `Sword/Scripts/KeepAnchored.server.luau` had a `WaitForChild("Handle")` infinite-yield because the template didn't have a Handle Part. Different bug, same shape.
