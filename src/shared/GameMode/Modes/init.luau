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
	NoOp = require(script.NoOpMode),
}

local DEFAULT_MODE = "NoOp"

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
