----------------------------------------------------------------------
-- LobbyService
----------------------------------------------------------------------
-- Owns the portals: who may use one, what happens when they do, and the
-- occupancy/queue numbers the signs read.
--
-- Phase 6 stage 4c — see `wiki/design/lobby.md` § Mode selection UX.
--
-- **The client decides nothing.** The panel sends "this player pressed
-- Join on that portal" and this file re-derives everything else: that the
-- part really is a portal, that the player is standing at it, and that
-- their current state permits the move. A client-trusted portal would let
-- anyone teleport into a duel pad from the far side of the hub.
--
-- Two portal shapes exist and the difference is one attribute:
--   - `TargetArenaId` names a live session  -> transfer immediately.
--   - `TargetArenaId` is empty              -> hold in a queue.
-- The PvP portal is the second until stage 6 authors duel pads. It is a
-- real queue with a real answer, not a stub: the sign reads
-- `0/2 duelling - 1 waiting` because that is true.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local Lobby = require(ReplicatedStorage.Shared.Lobby)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("LobbyService")

local portalRequestRemote = ReplicatedStorage.Shared.Lobby.Remotes.PortalRequest :: RemoteEvent

-- The session tables. A module rather than the BindableFunctions this file
-- used to invoke (refactor chunk 8): typed calls, and no yield-forever trap
-- when a handler is unbound.
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local ATTR = Lobby.Attributes

----------------------------------------------------------------------
-- Queues
----------------------------------------------------------------------
-- Keyed by the portal part, not by an arena id: a queueing portal has no
-- arena to key on yet, which is the whole reason it queues.

local queues: { [BasePart]: { Player } } = {}
local lastRequestAt: { [Player]: number } = {}

local function queueFor(portal: BasePart): { Player }
	local queue = queues[portal]
	if not queue then
		queue = {}
		queues[portal] = queue
	end
	return queue
end

local function positionInQueue(portal: BasePart, player: Player): number?
	return table.find(queueFor(portal), player)
end

local function removeFromQueue(portal: BasePart, player: Player): boolean
	local queue = queueFor(portal)
	local index = table.find(queue, player)
	if not index then
		return false
	end
	table.remove(queue, index)
	return true
end

-- Drop players who left, or who are no longer in the lobby to wait in it.
local function pruneQueue(portal: BasePart)
	local queue = queueFor(portal)
	for i = #queue, 1, -1 do
		local player = queue[i]
		local stillWaiting = player.Parent ~= nil
			and player:GetAttribute(Arena.ID_ATTRIBUTE) == Arena.LOBBY_ID
		if not stillWaiting then
			table.remove(queue, i)
		end
	end
end

----------------------------------------------------------------------
-- Published counts
----------------------------------------------------------------------
-- Written as attributes on the portal part rather than pushed over a
-- remote: attributes replicate on their own, so the sign has no
-- subscription to manage and a late-joining client reads current numbers
-- the moment it asks.

local function occupancyOf(targetArenaId: string): number
	if targetArenaId == "" then
		return 0
	end
	local count = 0
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(Arena.ID_ATTRIBUTE) == targetArenaId then
			count += 1
		end
	end
	return count
end

local function publishCounts(portal: BasePart)
	pruneQueue(portal)
	local targetArenaId = portal:GetAttribute(ATTR.TargetArenaId)
	portal:SetAttribute(ATTR.Occupancy, occupancyOf(type(targetArenaId) == "string" and targetArenaId or ""))
	portal:SetAttribute(ATTR.Waiting, #queueFor(portal))
end

local function publishAll()
	for _, portal in CollectionService:GetTagged(Lobby.PORTAL_TAG) do
		if portal:IsA("BasePart") and portal:IsDescendantOf(workspace) then
			publishCounts(portal)
		end
	end
end

----------------------------------------------------------------------
-- Validation
----------------------------------------------------------------------

local function refuse(player: Player, portal: Instance?, reason: string)
	log:info(string.format("Portal refused for %s (%s): %s",
		player.Name, portal and portal.Name or "<nil>", reason))
end

-- Returns the portal part if this player may act on it right now.
local function validate(player: Player, portal: any): BasePart?
	if typeof(portal) ~= "Instance" or not portal:IsA("BasePart") then
		refuse(player, nil, "not a BasePart")
		return nil
	end
	if not CollectionService:HasTag(portal, Lobby.PORTAL_TAG) then
		refuse(player, portal, "not tagged " .. Lobby.PORTAL_TAG)
		return nil
	end
	if not portal:IsDescendantOf(workspace) then
		refuse(player, portal, "not in workspace")
		return nil
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		refuse(player, portal, "no character")
		return nil
	end

	local distance = (root.Position - portal.Position).Magnitude
	if distance > Lobby.SERVER_RANGE_STUDS then
		refuse(player, portal, string.format("out of range (%.0f studs)", distance))
		return nil
	end

	-- The portal has to be in the arena the player is standing in. This is
	-- what stops a lobby player reaching the arena's return pad and a
	-- player in an arena reaching the hub's portals.
	if Arena.idOf(portal) ~= player:GetAttribute(Arena.ID_ATTRIBUTE) then
		refuse(player, portal, "portal belongs to another arena")
		return nil
	end

	return portal
end

----------------------------------------------------------------------
-- Requests
----------------------------------------------------------------------

local function onJoin(player: Player, portal: BasePart)
	local targetArenaId = portal:GetAttribute(ATTR.TargetArenaId)
	targetArenaId = type(targetArenaId) == "string" and targetArenaId or ""

	if targetArenaId ~= "" then
		-- A slot exists. Transfer, and let SessionRegistry clear the queue
		-- flag as part of the move.
		local ok = SessionRegistry.transferPlayer(player, targetArenaId)
		if not ok then
			refuse(player, portal, "transfer to " .. targetArenaId .. " refused")
			return
		end
		removeFromQueue(portal, player)
		log:info(string.format("%s took %s -> %s", player.Name,
			tostring(portal:GetAttribute(ATTR.ModeLabel)), targetArenaId))
		return
	end

	-- No slot yet. Hold them, and say so.
	if positionInQueue(portal, player) then
		return -- already waiting; pressing Join again is not a second place
	end
	table.insert(queueFor(portal), player)
	SessionRegistry.setQueued(player, true)
	log:info(string.format("%s queued for %s (position %d)", player.Name,
		tostring(portal:GetAttribute(ATTR.ModeLabel)), #queueFor(portal)))
end

local function onCancel(player: Player, portal: BasePart)
	if not removeFromQueue(portal, player) then
		return
	end
	-- Only clear the flag if they are not waiting on some other portal.
	local stillQueued = false
	for other, queue in queues do
		if other ~= portal and table.find(queue, player) then
			stillQueued = true
			break
		end
	end
	if not stillQueued then
		SessionRegistry.setQueued(player, false)
	end
	log:info(string.format("%s left the queue for %s", player.Name,
		tostring(portal:GetAttribute(ATTR.ModeLabel))))
end

portalRequestRemote.OnServerEvent:Connect(function(player: Player, portal: any, action: any)
	local now = os.clock()
	local last = lastRequestAt[player]
	if last and now - last < Lobby.REQUEST_COOLDOWN_SEC then
		return
	end

	local validated = validate(player, portal)
	if not validated then
		return
	end
	lastRequestAt[player] = now

	if action == "join" then
		onJoin(player, validated)
	elseif action == "cancel" then
		onCancel(player, validated)
	else
		refuse(player, validated, "unknown action " .. tostring(action))
		return
	end

	publishAll()
end)

----------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAt[player] = nil
	for portal in queues do
		removeFromQueue(portal, player)
	end
	publishAll()
end)

-- Occupancy changes whenever anybody's arena changes, which is exactly
-- when SessionRegistry republishes their attributes.
Players.PlayerAdded:Connect(function(player: Player)
	player:GetAttributeChangedSignal(Arena.ID_ATTRIBUTE):Connect(publishAll)
end)
for _, player in Players:GetPlayers() do
	player:GetAttributeChangedSignal(Arena.ID_ATTRIBUTE):Connect(publishAll)
end

publishAll()

local portalCount = 0
for _, portal in CollectionService:GetTagged(Lobby.PORTAL_TAG) do
	if portal:IsA("BasePart") and portal:IsDescendantOf(workspace) then
		portalCount += 1
	end
end
log:info(string.format("ready — %d portal(s), range %d studs", portalCount, Lobby.SERVER_RANGE_STUDS))
