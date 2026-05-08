---
type: design
description: Visual direction — chunky lowpoly sci-fi proportions, greybox-first levels, no surface decoration on weapons
updated: 2026-04-30
---

# Art Direction

## Weapons

- **Lowpoly / chunky / oversized proportions** — reads best at TPS distance.
- **Target ~1000 tris on remesh** for held weapons.
- Detail comes from **structural shapes** (bolts, panels, tubing, housings), not surface decoration. Fine detail dies at 1000 tris.
- Family identity preserved via shared structural vocabulary across siblings (silhouette + housing + accent shapes), not surface decoration.

## Levels

- **Greybox-first**. Geometry, sightlines, and cover layouts must work in monochrome before any prop / texture / lighting pass.
- **Validate sightlines with raycasts**, not eyeballed screenshots — top-down views deceive about wedge orientations and chest-height occlusion.
- Greybox parts share `Workspace.Arena.LevelGreybox` and use a naming prefix system (`Cover_`, `Catwalk_`, `Tower_`, `Bridge_`) so they can be batch-cleared by prefix without nuking the whole folder.

## Characters

R15 rigs only. No bespoke skeleton work. Animation priorities go Core < Idle < Movement < Action — see `CLAUDE.md`.

## UI

- **Code-driven**. Every HUD element is a Builder + Config + LayoutManager triple — see [[concepts/BuilderConfigLayout]]. No `.rbxmx` GUI templates checked into the repo.
- Visual direction iterating; current pass favors gradient backdrops, corner-anchored pills, dark-on-bright contrast for readability.
