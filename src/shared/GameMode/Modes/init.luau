----------------------------------------------------------------------
-- GameMode registry
----------------------------------------------------------------------
-- Central lookup for every available game mode. To add a new mode:
--   1. Create a sibling ModuleScript next to NoOpMode.luau
--      implementing the GameModeDefinition interface.
--   2. Register it in the Modes table below with a short stable key.
--
-- GameModeService resolves the active mode by reading the workspace
-- attribute "ActiveGameMode" and looking it up here; falls back to
-- DEFAULT_MODE if unset or unknown.
----------------------------------------------------------------------

local Modes = {
	-- The shipped arena's mode: co-op boss fight with a clock, back to the
	-- hub when it ends (Phase 6 stage 5). Also the default, so a place file
	-- with no "ActiveGameMode" attribute boots into the fight.
	PvEBoss = require(script.PvEBoss),
	-- 1v1 on a duel pad: kill limit + clock, exactly two players, PvP on.
	-- Never the arena default — bound to the scene's `ArenaSlot` pads by
	-- their `Mode` attribute (Phase 6 stage 6).
	PvPDuel = require(script.PvPDuel),
	-- Idle arena: a round that never ends and nothing scores. Selectable
	-- through "ActiveGameMode" and used by the Multiplayer suite's
	-- throwaway sessions.
	NoOp = require(script.NoOpMode),
	-- The hub. Never resolved through the "ActiveGameMode" attribute —
	-- GameModeService requires it directly for the lobby session, because
	-- which mode the *arena* runs and the existence of a lobby are separate
	-- questions. Registered here anyway so the registry stays the one list
	-- of modes.
	Lobby = require(script.LobbyMode),
}

local DEFAULT_MODE = "PvEBoss"

local Registry = {}

Registry.DEFAULT_MODE = DEFAULT_MODE

function Registry.get(key: string?)
	if key and Modes[key] then
		return Modes[key], key
	end
	return Modes[DEFAULT_MODE], DEFAULT_MODE
end

-- Strict lookup: nil for an unknown key rather than the default. For the
-- scene's `ArenaSlot` `Mode` attributes, where silently running a duel pad
-- as the boss fight would be worse than not creating it.
function Registry.find(key: any): (any?, string?)
	if type(key) == "string" and Modes[key] then
		return Modes[key], key
	end
	return nil, nil
end

function Registry.list(): { string }
	local out = {}
	for k in Modes do
		table.insert(out, k)
	end
	return out
end

return Registry
