----------------------------------------------------------------------
-- LobbyService
----------------------------------------------------------------------
-- Owns the portals: who may use one, what happens when they do, and the
-- occupancy/queue numbers the signs read.
--
-- Phase 6 stage 4c — see `wiki/design/lobby.md` § Mode selection UX.
-- Stage 6 made the queue real — § Stage 6 detail.
--
-- **The client decides nothing.** The panel sends "this player pressed
-- Join on that portal" and this file re-derives everything else: that the
-- part really is a portal, that the player is standing at it, and that
-- their current state permits the move. A client-trusted portal would let
-- anyone teleport into a duel pad from the far side of the hub.
--
-- Two portal shapes exist and the difference is one attribute:
--   - `TargetArenaId` names one session   -> the boss arena.
--   - `TargetMode` names a mode key       -> every session running it:
--                                            the pool of duel pads.
-- Both go through the same queue. Pressing Join puts you in the portal's
-- queue and the queue is flushed at once and then once a second: a
-- session takes players when it has free seats (`RoundManager.freeSeats`)
-- and the queue can bring it up to its minimum. So the boss arena takes
-- anyone the moment it is not between rounds, and a duel pad takes two
-- at a time — one player waiting for a duel stays in the hub with the
-- practice blocks rather than standing alone on an empty pad.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local GameModes = require(ReplicatedStorage.Shared.GameMode.Modes)
local Lobby = require(ReplicatedStorage.Shared.Lobby)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("LobbyService")

local portalRequestRemote = ReplicatedStorage.Shared.Lobby.Remotes.PortalRequest :: RemoteEvent

-- The session tables. A module rather than the BindableFunctions this file
-- used to invoke (refactor chunk 8): typed calls, and no yield-forever trap
-- when a handler is unbound.
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

type Session = SessionRegistry.Session

local ATTR = Lobby.Attributes

----------------------------------------------------------------------
-- Queues
----------------------------------------------------------------------
-- Keyed by the portal part, not by an arena id: a pool portal has no
-- single arena to key on, and the boss portal's queue only exists while
-- its arena is between rounds.

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

local function isQueuedAnywhere(player: Player): boolean
	for _, queue in queues do
		if table.find(queue, player) then
			return true
		end
	end
	return false
end

-- The `Queued` half of PlayerState follows queue membership; the registry
-- cannot derive it from a roster, so this file tells it.
local function syncQueuedFlag(player: Player)
	if player.Parent then
		SessionRegistry.setQueued(player, isQueuedAnywhere(player))
	end
end

-- Drop players who left, or who are no longer in the lobby to wait in it.
local function pruneQueue(portal: BasePart)
	local queue = queueFor(portal)
	for i = #queue, 1, -1 do
		local player = queue[i]
		local home = SessionRegistry.forPlayer(player)
		local stillWaiting = player.Parent ~= nil
			and home ~= nil
			and not SessionRegistry.runsRounds(home:getMode())
		if not stillWaiting then
			table.remove(queue, i)
		end
	end
end

----------------------------------------------------------------------
-- Destinations
----------------------------------------------------------------------

local function stringAttribute(portal: BasePart, name: string): string
	local value = portal:GetAttribute(name)
	return if type(value) == "string" then value else ""
end

-- The sessions a portal can send you to. Sorted fullest-first so a pad
-- already holding one player (somebody left during its countdown) is
-- topped up before a fresh pad is opened, then by arena id so the order
-- is stable.
local function candidateSessions(portal: BasePart): { Session }
	local targetArenaId = stringAttribute(portal, ATTR.TargetArenaId)
	if targetArenaId ~= "" then
		local session = SessionRegistry.forArena(targetArenaId)
		return if session then { session } else {}
	end

	local mode = GameModes.find(stringAttribute(portal, ATTR.TargetMode))
	if not mode then
		return {}
	end

	local candidates: { Session } = {}
	for _, session in SessionRegistry.all() do
		if session:getMode() == mode then
			table.insert(candidates, session)
		end
	end
	table.sort(candidates, function(a: Session, b: Session): boolean
		local countA, countB = a:getPlayerCount(), b:getPlayerCount()
		if countA ~= countB then
			return countA > countB
		end
		return a:getArenaId() < b:getArenaId()
	end)
	return candidates
end

-- How many of `waiting` queued players a session takes this instant: its
-- free seats, but only when the queue can bring it up to its minimum.
-- Two seats and one player waiting is zero — the wait is better spent
-- in the hub than alone on the pad.
local function intake(session: Session, waiting: number): number
	local seats = session:freeSeats()
	if seats <= 0 or waiting <= 0 then
		return 0
	end
	local needed = math.max(0, session:minPlayers() - session:getPlayerCount())
	if waiting < needed then
		return 0
	end
	return math.min(seats, waiting)
end

-- Move everyone the portal's sessions will take right now, in queue
-- order. Returns how many moved.
local function flushPortal(portal: BasePart): number
	pruneQueue(portal)
	local queue = queueFor(portal)
	local moved = 0

	for _, session in candidateSessions(portal) do
		local take = intake(session, #queue)
		for _ = 1, take do
			local player = table.remove(queue, 1)
			if not player then
				break
			end
			if SessionRegistry.transferPlayer(player, session:getArenaId()) then
				moved += 1
				log:info(string.format("%s took %s -> %s", player.Name,
					stringAttribute(portal, ATTR.ModeLabel), session:getArenaId()))
			else
				-- transferPlayer already said why. They are out of the
				-- queue; make PlayerState agree.
				syncQueuedFlag(player)
			end
		end
		if #queue == 0 then
			break
		end
	end

	return moved
end

----------------------------------------------------------------------
-- Published counts
----------------------------------------------------------------------
-- Written as attributes on the portal part rather than pushed over a
-- remote: attributes replicate on their own, so the sign has no
-- subscription to manage and a late-joining client reads current numbers
-- the moment it asks.
--
-- Occupancy is the roster count across the portal's sessions; Capacity
-- is their combined `maxPlayers` when every one of them is capped (two
-- duel pads read `0/4 in`) and 0 — uncapped — otherwise.

local function publishCounts(portal: BasePart)
	pruneQueue(portal)

	local candidates = candidateSessions(portal)
	local occupancy = 0
	local capacity = 0
	local allCapped = #candidates > 0
	for _, session in candidates do
		occupancy += session:getPlayerCount()
		local maxPlayers: number? = session:getMode().getConfig().maxPlayers
		if maxPlayers then
			capacity += maxPlayers
		else
			allCapped = false
		end
	end

	portal:SetAttribute(ATTR.Occupancy, occupancy)
	portal:SetAttribute(ATTR.Capacity, if allCapped then capacity else 0)
	portal:SetAttribute(ATTR.Waiting, #queueFor(portal))
end

local function livePortals(): { BasePart }
	local portals: { BasePart } = {}
	for _, portal in CollectionService:GetTagged(Lobby.PORTAL_TAG) do
		if portal:IsA("BasePart") and portal:IsDescendantOf(workspace) then
			table.insert(portals, portal)
		end
	end
	return portals
end

local function publishAll()
	for _, portal in livePortals() do
		publishCounts(portal)
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
	-- what stops a lobby player reaching an arena's return pad and a
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
	if positionInQueue(portal, player) then
		return -- already waiting; pressing Join again is not a second place
	end
	if #candidateSessions(portal) == 0 then
		refuse(player, portal, string.format("no session for TargetArenaId=%q / TargetMode=%q",
			stringAttribute(portal, ATTR.TargetArenaId), stringAttribute(portal, ATTR.TargetMode)))
		return
	end

	table.insert(queueFor(portal), player)
	SessionRegistry.setQueued(player, true)

	-- Usually this is the whole story: the boss arena takes you now, or a
	-- second duellist completes a pad. Otherwise the heartbeat keeps trying.
	flushPortal(portal)

	local position = positionInQueue(portal, player)
	if position then
		log:info(string.format("%s queued for %s (position %d)", player.Name,
			stringAttribute(portal, ATTR.ModeLabel), position))
	end
end

local function onCancel(player: Player, portal: BasePart)
	if not removeFromQueue(portal, player) then
		return
	end
	syncQueuedFlag(player)
	log:info(string.format("%s left the queue for %s", player.Name,
		stringAttribute(portal, ATTR.ModeLabel)))
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
-- Heartbeat
----------------------------------------------------------------------
-- Sessions open up on their own clock — a duel pad's intermission ends,
-- the boss arena leaves PostRound — and nothing in RoundManager announces
-- it server-side. Retrying the queues once a second is the honest answer
-- for a queue a few players long, and it keeps the signs' occupancy
-- current as rounds send people home.

task.spawn(function()
	while true do
		task.wait(Lobby.QUEUE_FLUSH_SEC)
		for portal in queues do
			if portal:IsDescendantOf(workspace) then
				flushPortal(portal)
			end
		end
		publishAll()
	end
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

publishAll()

log:info(string.format("ready — %d portal(s), range %d studs, queue flush every %ds",
	#livePortals(), Lobby.SERVER_RANGE_STUDS, Lobby.QUEUE_FLUSH_SEC))
