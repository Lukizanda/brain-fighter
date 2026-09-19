--!strict

----------------------------------------------------------------------
-- scene_slots_have_sessions — the duel pads exist and are wired
----------------------------------------------------------------------
-- Structural, boot-time (shape 1 in MultiplayerTestPattern). Phase 6
-- stage 6 made arena slots scene-authored: an `ArenaSlot`-tagged instance
-- with `ArenaId` and `Mode` attributes gets a session at boot. That is
-- exactly the kind of wiring that drifts silently — a lost tag, a typo'd
-- mode key, a pad whose spawn parts forgot their ArenaId — with every
-- server log clean. So:
--
--   * at least one slot exists (stage 6 authored two duel pads);
--   * every slot has a session running the mode its attribute names;
--   * every PvP spawn pad's arena has a session and at least two pads;
--   * the duel portal names a mode the registry knows.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)
local GameModes = require(ReplicatedStorage.Shared.GameMode.Modes)
local Lobby = require(ReplicatedStorage.Shared.Lobby)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

return {
	name = "scene_slots_have_sessions",

	verify = function(_ctx): (boolean, string?)
		local failures: { string } = {}

		-- 1. Slots → sessions.
		local slotCount = 0
		for _, slot in CollectionService:GetTagged(Arena.SLOT_TAG) do
			if not slot:IsDescendantOf(workspace) then
				continue
			end
			slotCount += 1
			local arenaId = slot:GetAttribute(Arena.ID_ATTRIBUTE)
			local modeKey = slot:GetAttribute(Arena.MODE_ATTRIBUTE)
			if type(arenaId) ~= "string" or arenaId == "" then
				table.insert(failures, slot:GetFullName() .. " has no ArenaId")
				continue
			end
			local session = SessionRegistry.forArena(arenaId)
			if not session then
				table.insert(failures, string.format("slot %s (arena %s) has no session", slot:GetFullName(), arenaId))
				continue
			end
			local mode = GameModes.find(modeKey)
			if not mode then
				table.insert(failures, string.format("slot %s names unknown mode %s", slot:GetFullName(), tostring(modeKey)))
			elseif session:getMode() ~= mode then
				table.insert(failures, string.format("arena %s runs %s, its slot says %s",
					arenaId, tostring(session:getMode().name), tostring(modeKey)))
			end
		end
		if slotCount == 0 then
			table.insert(failures, string.format("no %s-tagged instance in the workspace — stage 6 authored two duel pads", Arena.SLOT_TAG))
		end

		-- 2. PvP spawn pads belong to arenas that have sessions, two per arena.
		local padsPerArena: { [string]: number } = {}
		for _, pad in CollectionService:GetTagged(Arena.SpawnTags.PvPArena) do
			if pad:IsA("BasePart") and pad:IsDescendantOf(workspace) then
				local arenaId = Arena.idOf(pad)
				padsPerArena[arenaId] = (padsPerArena[arenaId] or 0) + 1
			end
		end
		for arenaId, count in padsPerArena do
			if not SessionRegistry.forArena(arenaId) then
				table.insert(failures, string.format("%s pads resolve to arena %s, which has no session (missing ArenaId on the pad?)",
					Arena.SpawnTags.PvPArena, arenaId))
			end
			if count < GameModeConstants.DUEL_PLAYERS then
				table.insert(failures, string.format("arena %s has %d %s pad(s), a duel needs %d",
					arenaId, count, Arena.SpawnTags.PvPArena, GameModeConstants.DUEL_PLAYERS))
			end
		end

		-- 3. Every pool portal names a mode the registry knows.
		for _, portal in CollectionService:GetTagged(Lobby.PORTAL_TAG) do
			if not (portal:IsA("BasePart") and portal:IsDescendantOf(workspace)) then
				continue
			end
			local targetArenaId = portal:GetAttribute(Lobby.Attributes.TargetArenaId)
			if type(targetArenaId) == "string" and targetArenaId ~= "" then
				continue
			end
			local targetMode = portal:GetAttribute(Lobby.Attributes.TargetMode)
			if not GameModes.find(targetMode) then
				table.insert(failures, string.format("portal %s has no TargetArenaId and its TargetMode %s is unknown",
					portal:GetFullName(), tostring(targetMode)))
			end
		end

		if #failures > 0 then
			return false, table.concat(failures, "; ")
		end
		return true, string.format("%d scene slot(s) wired", slotCount)
	end,
}
