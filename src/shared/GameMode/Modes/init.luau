----------------------------------------------------------------------
-- GameMode registry
----------------------------------------------------------------------
-- Central lookup for every available game mode. To add a new mode:
--   1. Create a sibling ModuleScript next to FFADeathmatch.luau
--      implementing the GameModeDefinition interface.
--   2. Register it in the Modes table below with a short stable key.
--
-- GameModeService resolves the active mode by reading the workspace
-- attribute "ActiveGameMode" and looking it up here; falls back to
-- DEFAULT_MODE if unset or unknown.
--
-- Brain Fighter combat gating (2026-05-13): the competitive modes are
-- conditionally registered based on GameConfig.TEAMS_ENABLED and
-- PLAYER_VS_PLAYER_ENABLED. When both are false the only mode
-- registered is NoOpMode (idle round, no scoring, no win condition),
-- so the educational-shooter build stays runnable without team/PvP
-- gameplay. Flip the flags in GameConfig to restore the originals.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)

local Modes = {
	NoOp = require(script.NoOpMode),
}

if GameConfig.PLAYER_VS_PLAYER_ENABLED then
	Modes.FFADeathmatch = require(script.FFADeathmatch)
end

if GameConfig.TEAMS_ENABLED then
	Modes.TeamDeathmatch = require(script.TeamDeathmatch)
end

-- DEFAULT_MODE picks the most "alive" available mode: TDM if teams are
-- on, FFA if PvP is on, otherwise the no-op stub. Workspace's
-- ActiveGameMode attribute still overrides this when set.
local DEFAULT_MODE
if GameConfig.TEAMS_ENABLED then
	DEFAULT_MODE = "TeamDeathmatch"
elseif GameConfig.PLAYER_VS_PLAYER_ENABLED then
	DEFAULT_MODE = "FFADeathmatch"
else
	DEFAULT_MODE = "NoOp"
end

local Registry = {}

Registry.DEFAULT_MODE = DEFAULT_MODE

function Registry.get(key: string?)
	if key and Modes[key] then
		return Modes[key], key
	end
	return Modes[DEFAULT_MODE], DEFAULT_MODE
end

function Registry.list(): { string }
	local out = {}
	for k in Modes do
		table.insert(out, k)
	end
	return out
end

return Registry
