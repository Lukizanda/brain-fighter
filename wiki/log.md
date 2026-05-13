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
