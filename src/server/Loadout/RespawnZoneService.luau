----------------------------------------------------------------------
-- RespawnZoneService
----------------------------------------------------------------------
-- Tracks which players are inside which `RespawnZone`-tagged volumes.
-- Phase 3B server-side counterpart that gates Phase 3C voluntary drops:
-- the LoadoutRequestDrop handler should only honour drop requests when
-- the player is standing in their team's respawn zone (which keeps the
-- map readable and prevents weapon-spam in the playable space).
--
-- Detection approach:
--   * `Touched` / `TouchEnded` per tagged BasePart, filtered to the
--     touching part being a HumanoidRootPart. HRP is the central body
--     part on every R6/R15 rig so "HRP inside zone" is a reliable
--     proxy for "player inside zone" without per-part counter
--     bookkeeping.
--   * Per-player presence map: presence[player] = { [zone] = true }.
--     A player is in a zone iff its entry exists in their map.
--
-- Team scoping:
--   * If a tagged BasePart sets a `Team` attribute (string, the team's
--     Name), it's considered a per-team zone — only counts for queries
--     that pass that team. Untagged zones are universal ("anyone's
--     respawn room").
--   * If the level later wants Red SpawnZone / Blue SpawnZone2 to be
--     team-scoped, set the Team attribute on each SpawnZoneBox in
--     Studio. The service picks it up at boot or on add.
--
-- API (require this module, then call):
--   RespawnZoneService.initialize() — wire all current + future zones
--   RespawnZoneService.isPlayerInZone(player, team?) -> boolean
--   RespawnZoneService.getPlayersInZone(team?) -> { Player }
--   RespawnZoneService.playerEnteredZone:Connect((player, zone) -> ())
--   RespawnZoneService.playerExitedZone:Connect((player, zone) -> ())
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("RespawnZoneService")

local ZONE_TAG = "RespawnZone"
local TEAM_ATTRIBUTE = "Team"
local HRP_NAME = "HumanoidRootPart"

local RespawnZoneService = {}

-- presence[player] = { [zone] = true }
local presence: { [Player]: { [BasePart]: true } } = {}

-- Bookkeeping so Disconnect is idempotent on zone removal / module re-init.
local zoneConnections: { [BasePart]: { RBXScriptConnection } } = {}

-- Public signals (BindableEvents because the consumers are server-side).
local enteredEvent = Instance.new("BindableEvent")
local exitedEvent = Instance.new("BindableEvent")
RespawnZoneService.playerEnteredZone = enteredEvent.Event
RespawnZoneService.playerExitedZone = exitedEvent.Event

local initialized = false

----------------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------------
local function zoneMatchesTeamFilter(zone: BasePart, team: Team?): boolean
	-- No filter: all zones count.
	if team == nil then
		return true
	end
	local zoneTeamName = zone:GetAttribute(TEAM_ATTRIBUTE)
	-- Untagged zones are universal — they count for any team query.
	if zoneTeamName == nil then
		return true
	end
	return zoneTeamName == team.Name
end

local function addPresence(player: Player, zone: BasePart)
	local set = presence[player]
	if not set then
		set = {}
		presence[player] = set
	end
	if set[zone] then
		return -- already tracked, suppress duplicate signal
	end
	set[zone] = true
	enteredEvent:Fire(player, zone)
end

local function removePresence(player: Player, zone: BasePart)
	local set = presence[player]
	if not set or not set[zone] then
		return
	end
	set[zone] = nil
	if next(set) == nil then
		presence[player] = nil
	end
	exitedEvent:Fire(player, zone)
end

local function onTouched(zone: BasePart, otherPart: BasePart)
	-- Filter to HRP only — every overlap fires Touched per limb otherwise.
	-- See module header for the rationale.
	if otherPart.Name ~= HRP_NAME then
		return
	end
	local character = otherPart.Parent
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	addPresence(player, zone)
end

local function onTouchEnded(zone: BasePart, otherPart: BasePart)
	if otherPart.Name ~= HRP_NAME then
		return
	end
	local character = otherPart.Parent
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	removePresence(player, zone)
end

local function attachZone(zone: BasePart)
	if zoneConnections[zone] then
		return -- already wired
	end
	local conns = {}
	table.insert(conns, zone.Touched:Connect(function(other)
		onTouched(zone, other)
	end))
	table.insert(conns, zone.TouchEnded:Connect(function(other)
		onTouchEnded(zone, other)
	end))
	zoneConnections[zone] = conns
end

local function detachZone(zone: BasePart)
	local conns = zoneConnections[zone]
	if not conns then
		return
	end
	for _, c in conns do
		c:Disconnect()
	end
	zoneConnections[zone] = nil

	-- Drop all presence entries for this zone so players who were "in"
	-- a deleted zone don't stay forever in the presence map.
	for _, set in presence do
		if set[zone] then
			set[zone] = nil
		end
	end
end

local function onPlayerRemoving(player: Player)
	presence[player] = nil
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function RespawnZoneService.initialize()
	if initialized then
		return
	end
	initialized = true

	for _, instance in CollectionService:GetTagged(ZONE_TAG) do
		if instance:IsA("BasePart") then
			attachZone(instance)
		end
	end

	CollectionService:GetInstanceAddedSignal(ZONE_TAG):Connect(function(instance)
		if instance:IsA("BasePart") then
			attachZone(instance)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(ZONE_TAG):Connect(function(instance)
		if instance:IsA("BasePart") then
			detachZone(instance)
		end
	end)

	Players.PlayerRemoving:Connect(onPlayerRemoving)

	local zoneCount = 0
	for _ in zoneConnections do
		zoneCount += 1
	end
	log:info(string.format("Initialized — wired %d RespawnZone-tagged parts", zoneCount))
end

function RespawnZoneService.isPlayerInZone(player: Player, team: Team?): boolean
	local set = presence[player]
	if not set then
		return false
	end
	for zone in set do
		if zoneMatchesTeamFilter(zone, team) then
			return true
		end
	end
	return false
end

function RespawnZoneService.getPlayersInZone(team: Team?): { Player }
	local result = {}
	for player, set in presence do
		for zone in set do
			if zoneMatchesTeamFilter(zone, team) then
				table.insert(result, player)
				break
			end
		end
	end
	return result
end

return RespawnZoneService
