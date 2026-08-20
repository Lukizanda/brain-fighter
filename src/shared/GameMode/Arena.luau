--!strict

----------------------------------------------------------------------
-- Arena
----------------------------------------------------------------------
-- Arena slot identity — the vocabulary every system that binds itself to
-- an arena has to agree on.
--
-- An arena slot is a physical, authored region of the place. `RoundManager`
-- sessions, `BlockSpawner` block pools and `SpawnManager` spawn sets are all
-- keyed by the same id, so adding an arena is a tag plus an attribute in
-- Studio rather than a code change. See `wiki/design/lobby.md` § Session
-- model.
--
-- This module exists so `"Default"` and `"ArenaId"` are declared once. They
-- are read by three scripts across two domains (GameMode and BlockSpawner);
-- as literals they would be three copies of a coupling with nothing holding
-- them in step.
----------------------------------------------------------------------

local Arena = {}

-- Attribute carried by arena-bound scene parts — BlockSpawnVolume today,
-- spawn pads and zone triggers as later stages author them.
Arena.ID_ATTRIBUTE = "ArenaId"

-- The slot an unattributed part belongs to, and the only slot the server
-- runs today.
Arena.DEFAULT_ID = "Default"

-- Authoring vocabulary for spawn pads. A mode definition names one of these
-- in its `spawnTag`, and `SpawnManager` resolves the pads carrying it that
-- also belong to the session's arena. Declared ahead of the geometry
-- (stage 4+) so scene authoring and mode config cannot pick different
-- spellings of the same idea.
Arena.SpawnTags = {
	Lobby = "LobbySpawn",
	PvEArena = "PvEArenaSpawn",
	PvPArena = "PvPArenaSpawn",
}

-- Which arena slot an authored part belongs to.
--
-- A missing attribute means DEFAULT_ID rather than "unassigned", and that
-- is the load-bearing decision in this module. The shipped arena's eight
-- BlockSpawnVolume parts are tagged but carry no ArenaId; treating absence
-- as an error — or as its own slot — would have stopped the shipped arena
-- spawning while every log stayed clean.
function Arena.idOf(instance: Instance): string
	local attribute = instance:GetAttribute(Arena.ID_ATTRIBUTE)
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end
	return Arena.DEFAULT_ID
end

return Arena
