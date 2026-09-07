--!strict

----------------------------------------------------------------------
-- PortalGui
----------------------------------------------------------------------
-- The player-facing half of mode selection: a floating sign over every
-- portal, and a confirm panel when you walk onto one.
--
-- Phase 6 stage 4c — see `wiki/design/lobby.md` § Mode selection UX.
--
-- Reads the counts straight off the portal's attributes, which
-- LobbyService publishes. No remote in the read path, so a late-joining
-- client sees current numbers the moment it asks and there is no
-- subscription to leak.
--
-- The panel's policy is `Always`, not `LobbyOnly`. That looks wrong until
-- you remember the return pad: it is a portal standing in the arena, and
-- it needs the same panel. Proximity is what decides whether the panel is
-- on screen; the zone decides which portals exist near you.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local HudGate = require(ReplicatedStorage.Shared.Hud.HudGate)
local HudLayoutManager = require(ReplicatedStorage.Shared.Hud.HudLayoutManager)
local Lobby = require(ReplicatedStorage.Shared.Lobby)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local PortalPanelBuilder = require(ReplicatedStorage.Shared.Hud.PortalPanelBuilder)

local log = Logger.new("PortalGui")

local player = Players.LocalPlayer
local portalRequestRemote = ReplicatedStorage.Shared.Lobby.Remotes.PortalRequest :: RemoteEvent

local ATTR = Lobby.Attributes

-- Proximity is checked on a timer rather than every frame: the panel
-- appears when you walk onto a 18-stud pad, which no player crosses in
-- under a tenth of a second.
local PROXIMITY_POLL_SEC = 0.1

local panel = PortalPanelBuilder.build()
HudLayoutManager:register("Center", panel.gui, HudGate.Policy.Always)

----------------------------------------------------------------------
-- Signs
----------------------------------------------------------------------

type SignEntry = {
	sign: PortalPanelBuilder.PortalSign,
	connections: { RBXScriptConnection },
}

local signs: { [BasePart]: SignEntry } = {}

local function readNumber(portal: BasePart, name: string): number
	local value = portal:GetAttribute(name)
	return type(value) == "number" and value or 0
end

local function labelOf(portal: BasePart): string
	local label = portal:GetAttribute(ATTR.ModeLabel)
	return type(label) == "string" and label or portal.Name
end

-- "2/2 duelling - 1 waiting" for a capped portal, "3 inside" for an
-- uncapped one. A portal with no numbers on it reads as broken when
-- nobody else is on, which is why the zero case still prints.
local function countsTextFor(portal: BasePart): string
	local occupancy = readNumber(portal, ATTR.Occupancy)
	local capacity = readNumber(portal, ATTR.Capacity)
	local waiting = readNumber(portal, ATTR.Waiting)

	local head: string
	if capacity > 0 then
		head = string.format("%d/%d in", occupancy, capacity)
	else
		head = string.format("%d inside", occupancy)
	end

	if waiting > 0 then
		return string.format("%s - %d waiting", head, waiting)
	end
	return head
end

local function refreshSign(portal: BasePart)
	local entry = signs[portal]
	if not entry then
		return
	end
	entry.sign:setLabel(labelOf(portal))
	entry.sign:setCounts(countsTextFor(portal))
end

local function addSign(portal: BasePart)
	if signs[portal] then
		return
	end

	local sign = PortalPanelBuilder.buildSign(portal, Lobby.SIGN_HEIGHT_STUDS)
	sign.gui.Parent = portal

	local connections = {}
	for _, name in { ATTR.ModeLabel, ATTR.Occupancy, ATTR.Capacity, ATTR.Waiting } do
		table.insert(connections, portal:GetAttributeChangedSignal(name):Connect(function()
			refreshSign(portal)
		end))
	end

	signs[portal] = { sign = sign, connections = connections }
	refreshSign(portal)
end

local function removeSign(portal: BasePart)
	local entry = signs[portal]
	if not entry then
		return
	end
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	entry.sign:destroy()
	signs[portal] = nil
end

----------------------------------------------------------------------
-- Panel
----------------------------------------------------------------------

local nearestPortal: BasePart? = nil
-- A portal the player dismissed with "Not now". Cleared when they walk
-- out of range, so stepping back on offers it again. Without this the
-- proximity poll re-shows the panel a tenth of a second after dismissal
-- and the button reads as broken.
local dismissedPortal: BasePart? = nil

local function isQueuedHere(): boolean
	-- The client cannot see the queue table, only its own state. That is
	-- enough to label the button, and the server re-derives the truth.
	return HudGate.getState() == Arena.PlayerState.Queued
end

local function refreshPanel()
	local portal = nearestPortal
	if not portal then
		panel:setShown(false)
		return
	end

	local targetArenaId = portal:GetAttribute(ATTR.TargetArenaId)
	targetArenaId = type(targetArenaId) == "string" and targetArenaId or ""

	panel:setTitle(labelOf(portal))
	panel:setStatus(countsTextFor(portal))

	if targetArenaId == "" then
		panel:setPrimaryText(isQueuedHere() and "Leave queue" or "Join queue")
	elseif targetArenaId == Arena.LOBBY_ID then
		panel:setPrimaryText("Return to lobby")
	else
		panel:setPrimaryText("Enter")
	end

	panel:setAccent(portal.Color)
	panel:setShown(true)
end

local function livingRoot(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function updateProximity()
	local root = livingRoot()
	if not root then
		if nearestPortal then
			nearestPortal = nil
			refreshPanel()
		end
		return
	end

	local playerArenaId = player:GetAttribute(Arena.ID_ATTRIBUTE)
	local best: BasePart? = nil
	local bestDistance = Lobby.PANEL_RANGE_STUDS

	for portal in signs do
		-- Same arena check the server makes. Without it a player standing
		-- near the boundary could be offered a portal the server will
		-- refuse, which reads as a broken button.
		if Arena.idOf(portal) == playerArenaId then
			local distance = (root.Position - portal.Position).Magnitude
			if distance <= bestDistance then
				best = portal
				bestDistance = distance
			end
		end
	end

	if dismissedPortal and dismissedPortal ~= best then
		dismissedPortal = nil -- walked away; the offer is live again
	end
	if best == dismissedPortal then
		best = nil
	end

	if best ~= nearestPortal then
		nearestPortal = best
		refreshPanel()
	elseif best then
		-- Same portal, but its counts may have moved.
		panel:setStatus(countsTextFor(best))
	end
end

panel.confirmed:Connect(function()
	local portal = nearestPortal
	if not portal then
		return
	end
	local action = isQueuedHere() and "cancel" or "join"
	portalRequestRemote:FireServer(portal, action)
end)

panel.cancelled:Connect(function()
	-- Dismiss only. Queue membership is untouched — that is what the
	-- primary button is for when it reads "Leave queue".
	dismissedPortal = nearestPortal
	nearestPortal = nil
	panel:setShown(false)
end)

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

for _, portal in CollectionService:GetTagged(Lobby.PORTAL_TAG) do
	if portal:IsA("BasePart") and portal:IsDescendantOf(workspace) then
		addSign(portal)
	end
end

CollectionService:GetInstanceAddedSignal(Lobby.PORTAL_TAG):Connect(function(portal)
	if portal:IsA("BasePart") and portal:IsDescendantOf(workspace) then
		addSign(portal)
	end
end)

-- Re-scan after connecting. Tags replicate to the client asynchronously,
-- so a portal that arrives between the scan above and the Connect would
-- be caught by neither. `addSign` is idempotent, which is what makes the
-- belt-and-braces scan free.
for _, portal in CollectionService:GetTagged(Lobby.PORTAL_TAG) do
	if portal:IsA("BasePart") and portal:IsDescendantOf(workspace) then
		addSign(portal)
	end
end

CollectionService:GetInstanceRemovedSignal(Lobby.PORTAL_TAG):Connect(function(portal)
	if portal:IsA("BasePart") then
		removeSign(portal)
	end
end)

HudGate.stateChanged:Connect(refreshPanel)

task.spawn(function()
	while true do
		updateProximity()
		task.wait(PROXIMITY_POLL_SEC)
	end
end)

log:info(string.format("ready — %d portal(s) in range of this client", (function()
	local n = 0
	for _ in signs do n += 1 end
	return n
end)()))
