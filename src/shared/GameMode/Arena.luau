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

export type PlayerState = "InLobby" | "Queued" | "InArena"

local Arena = {}

-- Attribute carried by arena-bound scene parts — BlockSpawnVolume today,
-- spawn pads and zone triggers as later stages author them.
Arena.ID_ATTRIBUTE = "ArenaId"

-- The slot an unattributed part belongs to, and the arena the shipped
-- greybox runs in.
Arena.DEFAULT_ID = "Default"

-- The hub. A slot like any other — it has spawn pads, a block pool and a
-- session — but its mode never starts a round. See `wiki/design/lobby.md`
-- § Stage 4 detail, decision 1: making the lobby an arena rather than the
-- *absence* of one is what keeps a `nil` branch out of spawns, block pools
-- and broadcast audiences.
Arena.LOBBY_ID = "Lobby"

-- Where a player is in the lobby → arena cycle, written by GameModeService
-- as an attribute on the Player instance and read by the client HUD.
--
-- Attributes rather than a remote: they replicate on their own and are
-- readable the moment a client asks, so there is no join-order race between
-- a LocalScript starting and the server telling it where the player is.
Arena.PlayerState = {
	InLobby = "InLobby",
	Queued = "Queued",
	InArena = "InArena",
}

-- Attributes carried by the *Player* instance. `ID_ATTRIBUTE` is reused
-- deliberately: "which arena does this belong to" is the same question
-- whether it is asked of a spawn pad or of a person.
Arena.STATE_ATTRIBUTE = "PlayerState"

-- Authoring vocabulary for spawn pads. A mode definition names one of these
-- in its `spawnTag`, and `SpawnManager` resolves the pads carrying it that
-- also belong to the session's arena. Declared ahead of the geometry
-- (stage 4+) so scene authoring and mode config cannot pick different
-- spellings of the same idea.
Arena.SpawnTags = {
	-- The shipped Default arena's pad. The tag *name* predates this
	-- vocabulary — it is what the scene carries — so code refers to the key;
	-- retagging the pad would be a Studio change, not a code change.
	Default = "FFASpawn",
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
