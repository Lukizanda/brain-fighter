----------------------------------------------------------------------
-- GameConfig
----------------------------------------------------------------------
-- Game-wide configuration for default Roblox systems.
-- Change these values to toggle built-in Roblox UI and behaviors.
-- These are applied once at startup by CharacterSystemsLoader.
----------------------------------------------------------------------

local GameConfig = {
	----------------------------------------------------------------------
	-- Default Roblox UI Visibility
	----------------------------------------------------------------------
	-- Set to false to hide the corresponding built-in Roblox UI.
	-- Useful when replacing with custom UI (e.g., custom health bar,
	-- custom backpack, custom player list).
	----------------------------------------------------------------------
	SHOW_BACKPACK = false,         -- Default tool hotbar (bottom center)
	SHOW_HEALTH = false,           -- Default health bar (replaced by HealthGui)
	SHOW_PLAYER_LIST = false,      -- Leaderboard (top right) — replaced by custom ScoreboardGui; also frees the Tab key for WeaponRolodex cycling
	SHOW_CHAT = true,              -- Chat window
	SHOW_EMOTES = true,            -- Emote menu

	----------------------------------------------------------------------
	-- Combat feature gates
	----------------------------------------------------------------------
	-- Brain Fighter is being repurposed as an educational shooter; the
	-- inherited Archon team/PvP code is gated off rather than deleted so
	-- a single flag flip restores it for testing or a future PvP mode.
	-- Consumers across the damage, mode-registry, spawn, UI, and nametag
	-- layers read these directly via require(...).TEAMS_ENABLED /
	-- .PLAYER_VS_PLAYER_ENABLED.
	----------------------------------------------------------------------
	TEAMS_ENABLED = false,            -- Set true to restore Team Deathmatch mode + team UI + team-aware spawn/nametag/score logic.
	PLAYER_VS_PLAYER_ENABLED = false, -- Set true to restore PvP damage. When false, players cannot damage other players; NPCs remain valid targets.

	----------------------------------------------------------------------
	-- Dev-only helpers (leave off in shipped builds)
	----------------------------------------------------------------------
	DEV_AUTO_EQUIP_TOOL = "", -- name of a Tool in StarterPack to auto-equip on spawn; "" or nil to disable
	DEV_SMOKE_KILLFEED = false, -- when true, loop-fires 3 synthetic KillFeed events (normal kill / self-elim / env kill) so the UI can be verified without real combat
	DEV_BOT_COUNT = 0, -- number of stationary enemy-team bots to spawn for solo TDM tuning (0 disables); bots respawn via DeathHandler and credit kills via ScoreTracker.recordBotKill
	DEV_SIMULATE_LOADOUT_CYCLING = false, -- when true, server-side script spawns 2 tools in the player's Backpack, cycles them via humanoid:EquipTool, and writes the result to workspace.LoadoutCycleSimResult — used to repro / regression-test the LoadoutService re-entry guard without relying on real pedestal pickups (which can't be MCP-driven)

	----------------------------------------------------------------------
	-- Locomotion
	----------------------------------------------------------------------
	BACKWARD_SPEED_MULTIPLIER = 0.7,         -- 70% speed when walking backward
	FIRING_SPEED_MULTIPLIER = 0.8,           -- 80% speed when firing
	BACKWARD_FIRING_SPEED_MULTIPLIER = 0.5,  -- 50% speed when firing and walking backward
}

return GameConfig
