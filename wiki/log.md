---
type: log
description: Append-only chronological record of wiki ingests and lints. Newest entries at the bottom.
---

# Wiki Log

Format: `## [YYYY-MM-DD] <ingest|lint|init> | <one-line topic>` followed by a 2–4 line summary.

## [2026-05-08] init | wiki reset for Brain Fighter

Forked from a prior TPS template. Game-specific design + status content stripped; concepts and systems pages retained as engineering reference. Brain Fighter's own design pages will be authored as the project takes shape.

## [2026-05-13] ingest | Team/PvP combat gated off

Two new GameConfig flags added: TEAMS_ENABLED (default false) and PLAYER_VS_PLAYER_ENABLED (default false). All team-aware and PvP-damaging code paths now check these flags. Files preserved on disk; reversal is a config flip. See systems/GameMode, systems/Health, systems/Loadout, systems/HUD for per-system notes.

## [2026-05-13] ingest | SpawnLocation set Neutral for team-off build

Follow-up to the Team/PvP gate. `Workspace.Arena.SpawnZone.SpawnLocation` was `Neutral = false` with `TeamColor = Bright red`; with no Team instances created (TeamService gated off), the engine rejected the pad for every player and spawned them at the world fallback → sky → fall death. Flipped to `Neutral = true` via MCP+ChangeHistoryService and verified with a playtest (HumanoidStateType.Running on the pad, Health = 100, XZ offset = 0.004 from pad centre). Studio in-memory change; user saves the .rbxl to persist. See systems/GameMode "SpawnLocation must be Neutral while teams are off".

## [2026-05-13] ingest | Canonical gameplay-loop design doc

New `wiki/design/gameplay-loop.md` written as the authoritative source for Brain Fighter's core loop — captures the 10-step loop, all 12 resolved decisions with rationale (grouped by buffer/input, spell typing, economy, targeting, spawner, dictionary, win condition), letter/length/tier tuning tables, the nine-spell prototype roster, ten worked formula examples (CAT through CHARACTERIZE), and the three open questions (tier-cast UX, spawn density, color distribution). Cross-links to the sibling `gameplay-loop.excalidraw` diagram and the in-progress `hud.mockup.html`. Added to `index.md` under Design.

## [2026-05-13] ingest | Resolved spawner + cast-menu open questions

Three previously-open design questions resolved and folded into the canonical doc. **Spawn density**: ~24 blocks at any time in a moderate arena (~8 per color), framed as density-per-area in code so it scales with level size; letter selection within a color is Scrabble-frequency-weighted. **Color distribution**: equal-weight (33/33/33) default with per-level `colorWeights` override; no adaptive spawning. **Placement-spell marker**: crosshair glyph (⌖) at the right edge of the menu entry + dashed outline around the entry (auto-target entries use solid outline); first-time use triggers a one-shot tutorial flash. The doc's Open Questions section has been replaced with a Playtest Verification list — all major decisions are now resolved; what remains is tuning. Mockup updated to use ⌖ + dashed border on the Stone Wall entry.

## [2026-05-13] ingest | TPS character stack gated behind GameConfig flag

Brain Fighter switches from TPS camera-locked body orientation to default Roblox platformer-style controls (free-look camera, `Humanoid.AutoRotate = true`, default R15 animations). New `GameConfig.TPS_CHARACTER_ENABLED` flag (default `false`) gates `CameraManager` + `LocomotionManager` initialization in `CharacterSystemsLoader`; when off, both controllers are skipped and the default Roblox PlayerModule handles camera and locomotion. Verified via MCP playtest: `AutoRotate=true`, no `AlignOrientation` on HumanoidRootPart, `CameraType=Custom` with the player Humanoid as subject. Files preserved; flip the flag to restore the TPS feel. See systems/Character "TPS character stack is gated off by default."
