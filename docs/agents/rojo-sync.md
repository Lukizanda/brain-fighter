# Rojo sync

The JSON hard rules are in the root [CLAUDE.md](../../CLAUDE.md). This page covers everything else about sync. Validator details: [`wiki/concepts/RojoJsonValidator.md`](../../wiki/concepts/RojoJsonValidator.md).

## What goes on disk and what goes through MCP
- **Disk (Rojo):** every Script, LocalScript and ModuleScript. If you edit one in Studio, the change only lives in the `.rbxl` and never reaches git. This is the #1 cause of desync.
- **MCP:** instances the project file doesn't represent: Animation objects (with `AnimationId`), GUI templates and Sounds parented to scripts with `ignoreUnknownInstances`, and constraints.
- To create a versioned non-script instance (for example a RemoteEvent), write a `<Name>.model.json` with `className`. A `.meta.json` won't create it.

## Folder-as-instance traps
- `init.model.json` inside a folder creates a **child named `init`**. It does not set the folder's class.
- To make a folder represent a MeshPart, Tool or similar, use `init.meta.json` with `"className"` set.
- Any folder-based instance that has Studio-side children not tracked on disk (meshes, attachments, SurfaceAppearance, sounds) **needs `"ignoreUnknownInstances": true`**. Otherwise Rojo deletes those children on every sync.

## Pre-sync safety
- **Before connecting Rojo**, check the sync panel for red (delete) items. They are Studio-only instances that Rojo is about to destroy. Read the indentation to find each item's direct parent: that parent needs `ignoreUnknownInstances`.
- **Before creating or modifying a script on disk**, inspect the target instance's children in Studio. If it has GUI templates, Sounds, Animations or RemoteEvents, make sure the parent's `.meta.json` sets `ignoreUnknownInstances: true`.
- **After deleting or renaming files**, check Studio for stale duplicates. Rojo doesn't always remove the old instances.
- **When pulling from another machine**, compare the disk files against the Studio sources before syncing, because Studio may hold newer code.
- Check `curl localhost:34872/api/rojo` before asking the user to reconnect Rojo.
