--[[
	NPCService
	----------
	Top-level NPC orchestrator. Spawns NPCs from tagged spawn points,
	creates an NPCController per NPC, ticks them on Heartbeat.

	One NPC set per arena session (refactor chunk 9). NPCs used to be
	spawned once at boot from every NPCSpawn marker in the place and
	lived for the server's lifetime, hunting whoever was closest. They now
	belong to the arena whose round is running: a set is created when that
	arena's `RoundStarted` fires — or, at boot, for any session already
	Active, because the Default round starts during GameModeService's boot
	and the WorldDataManager wait below can outlast it — and torn down on
	its `RoundEnded`. Every spawned Model carries `ArenaId`, which is what
	Perception reads to scope its target scan to that arena's roster, so a
	hub player is never an NPC target: nothing hostile carries `Lobby`.

	A marker's arena is its own `ArenaId` attribute, snapshotted with the
	marker by WorldDataManager. An unattributed marker is the Default
	arena's, the same reading `Arena.idOf` gives every other authored part.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local NPCConstants = require(ReplicatedStorage.Shared.NPC.NPCConstants)
local NPCTypes = require(ReplicatedStorage.Shared.NPC.NPCTypes)
local Patroller = require(ReplicatedStorage.Shared.NPC.Archetypes.Patroller)

local scriptsFolder = script.Parent.Scripts
local NPCController = require(scriptsFolder.NPCController)

-- AIWorldData — authoritative source for spawn/patrol positions
local WorldDataManager = require(ServerScriptService.Server.AI.Scripts.WorldDataManager)
-- Which sessions exist and whether their round is running, for the boot
-- reconcile. Called, never written to.
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local gameModeEvents = ServerScriptService.Server.GameMode.Events
local roundStartedEvent = gameModeEvents.RoundStarted :: BindableEvent
local roundEndedEvent = gameModeEvents.RoundEnded :: BindableEvent

local log = Logger.new("NPCService")

-- Seconds a freshly spawned set stands before its controllers are ticked,
-- so the rigs settle on the floor before being commanded.
local SPAWN_SETTLE_SEC = 2

-- ============================================================
-- State
-- ============================================================
type Archetype = NPCTypes.Archetype
type MarkerSnapshot = WorldDataManager.MarkerSnapshot
type NPCControllerInstance = NPCController.NPCControllerInstance

-- The NPCs that fight for one arena's round.
type ArenaSet = {
	arenaId: string,
	controllers: { NPCControllerInstance },
	tickFrom: number, -- os.clock() after which the set is ticked
}

local sets: { [string]: ArenaSet } = {}
local spawnCounter = 0
local heartbeatConn: RBXScriptConnection? = nil
local eventConns: { RBXScriptConnection } = {}

-- ============================================================
-- Spawn helpers
-- ============================================================
local function getTemplate(templateName: string): Model?
	local aiWorldData = ServerStorage:FindFirstChild("AIWorldData")
	if not aiWorldData then
		log:warn("ServerStorage.AIWorldData folder not found")
		return nil
	end
	local rigs = aiWorldData:FindFirstChild("Rigs")
	if not rigs then
		log:warn("ServerStorage.AIWorldData.Rigs folder not found")
		return nil
	end
	local template = rigs:FindFirstChild(templateName)
	if not template or not template:IsA("Model") then
		log:warn("Rig template not found:", templateName)
		return nil
	end
	return template
end

-- Equip a weapon visually on the NPC's right hand. Uses Humanoid:EquipTool()
-- so Roblox handles the RightGrip weld correctly. Strips scripts from the
-- cloned tool since NPC shooting is driven by NPC code, not the weapon's
-- client/server scripts.
local function equipWeapon(npc: Model, weaponTemplateName: string?): Tool?
	if not weaponTemplateName then
		return nil
	end

	local templates = ReplicatedStorage.Shared.Weapon.Templates
	local template = templates:FindFirstChild(weaponTemplateName)
	if not template or not template:IsA("Tool") then
		log:warn("Weapon template not found:", weaponTemplateName)
		return nil
	end

	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		log:warn("NPC has no Humanoid:", npc.Name)
		return nil
	end

	local weapon = template:Clone() :: Tool
	local handle = weapon:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		log:warn("Weapon template has no Handle:", weaponTemplateName)
		weapon:Destroy()
		return nil
	end

	-- Strip scripts from the cloned tool — the NPC shoots via NPC logic,
	-- not the weapon's own Scripts folder (which targets players).
	local weaponScripts = weapon:FindFirstChild("Scripts")
	if weaponScripts then
		weaponScripts:Destroy()
	end
	for _, child in weapon:GetChildren() do
		if child:IsA("LocalScript") or child:IsA("Script") then
			child:Destroy()
		end
	end

	-- Ensure handle is ready to be equipped
	handle.Anchored = false
	handle.CanCollide = false
	handle.Massless = true

	-- Humanoid:EquipTool handles the RightGrip weld using Tool.Grip automatically.
	-- Tool must first be parented to a place the humanoid can reach.
	weapon.Parent = npc
	humanoid:EquipTool(weapon)

	log:info(string.format("Equipped %s on %s", weapon.Name, npc.Name))

	return weapon
end

-- The arena a spawn marker belongs to. Mirrors `Arena.idOf` over the
-- snapshot's attribute table, since the marker Part itself is destroyed
-- after WorldDataManager snapshots it.
local function markerArenaId(snapshot: MarkerSnapshot): string
	local attribute = snapshot.attributes[Arena.ID_ATTRIBUTE]
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end
	return Arena.DEFAULT_ID
end

local function spawnNPCAtPosition(
	set: ArenaSet,
	spawnName: string,
	spawnPosition: Vector3,
	archetype: Archetype
): Model?
	local template = getTemplate(archetype.templateName)
	if not template then
		return nil
	end

	local npc = template:Clone()
	spawnCounter += 1
	npc.Name = archetype.name .. "_" .. spawnCounter

	-- Position slightly above the spawn point to avoid clipping into the floor
	local npcSpawnPosition = spawnPosition + Vector3.new(0, 3, 0)
	npc:PivotTo(CFrame.new(npcSpawnPosition))

	-- Configure humanoid
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = archetype.walkSpeed
	else
		log:warn("Template has no Humanoid:", archetype.templateName)
	end

	-- Which arena this NPC fights for (Perception's target scope, and the
	-- Hittables filter every skill reads), and what the kill feed calls it.
	npc:SetAttribute(Arena.ID_ATTRIBUTE, set.arenaId)
	npc:SetAttribute(NPCConstants.ARCHETYPE_ATTRIBUTE, archetype.name)

	-- Tag for queries / cleanup
	CollectionService:AddTag(npc, NPCConstants.TAG_NPC)

	npc.Parent = Workspace

	-- Equip visual weapon (if specified by archetype)
	local weapon = equipWeapon(npc, archetype.weaponTemplateName)

	-- Create the controller for this NPC
	local controller = NPCController.new(npc, archetype, weapon)
	if controller then
		table.insert(set.controllers, controller)
	else
		log:warn("Failed to create controller for", npc.Name)
	end

	log:info(string.format("[%s] Spawned %s at %s", set.arenaId, npc.Name, spawnName))
	return npc
end

-- ============================================================
-- Per-arena sets
-- ============================================================
local function spawnArena(arenaId: string)
	if sets[arenaId] then
		log:info(string.format("[%s] NPC set already exists — leaving it", arenaId))
		return
	end

	local set: ArenaSet = {
		arenaId = arenaId,
		controllers = {},
		tickFrom = os.clock() + SPAWN_SETTLE_SEC,
	}
	sets[arenaId] = set

	local considered = 0
	for _, snapshot in WorldDataManager.getSpawns() do
		if markerArenaId(snapshot) ~= arenaId then
			continue
		end
		considered += 1
		spawnNPCAtPosition(set, snapshot.name, snapshot.position, Patroller)
	end

	log:info(string.format("[%s] NPC set created — %d spawn point(s), %d controller(s)",
		arenaId, considered, #set.controllers))
end

local function teardownArena(arenaId: string)
	local set = sets[arenaId]
	if not set then
		return
	end
	sets[arenaId] = nil

	local count = #set.controllers
	for _, controller in set.controllers do
		local npc = controller:getBlackboard().npc
		controller:destroy()
		if npc and npc.Parent then
			npc:Destroy()
		end
	end
	table.clear(set.controllers)

	log:info(string.format("[%s] NPC set torn down — %d controller(s)", arenaId, count))
end

-- ============================================================
-- Tick loop
-- ============================================================
local function tickAllControllers(dt: number)
	local now = os.clock()
	for _, set in sets do
		if now < set.tickFrom then
			continue
		end
		local controllers = set.controllers
		-- Iterate in reverse so we can remove dead controllers safely
		for i = #controllers, 1, -1 do
			local controller = controllers[i]
			controller:tick(dt)

			-- If the controller's NPC died, the controller will have flipped to
			-- not-alive on its next tick. Cull it from the list.
			local bb = controller:getBlackboard()
			if not bb.npc or not bb.npc.Parent then
				controller:destroy()
				table.remove(controllers, i)
			end
		end
	end
end

-- ============================================================
-- Round events
-- ============================================================
local function onRoundStarted(_roster: { Player }, arenaId: any)
	if type(arenaId) ~= "string" then
		log:warn("RoundStarted fired without an arena id — no NPC set created")
		return
	end
	spawnArena(arenaId)
end

local function onRoundEnded(_winnerId: any, _winnerName: any, arenaId: any)
	if type(arenaId) ~= "string" then
		return
	end
	teardownArena(arenaId)
end

-- Sessions whose round was already running before this Script connected.
local function reconcile()
	for arenaId, session in SessionRegistry.all() do
		if session:isActive() and not sets[arenaId] then
			spawnArena(arenaId)
		end
	end
end

-- ============================================================
-- Lifecycle
-- ============================================================
local NPCService = {}

-- Pause: stops ticking, leaves every set standing. Reversible via enable().
function NPCService.disable()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	log:info("Disabled — tick loop stopped")
end

function NPCService.enable()
	if heartbeatConn then
		return
	end
	heartbeatConn = RunService.Heartbeat:Connect(tickAllControllers)
	log:info("Tick loop started")
end

-- Permanent teardown: every set, every NPC, every listener.
function NPCService.destroy()
	NPCService.disable()
	for _, conn in eventConns do
		conn:Disconnect()
	end
	table.clear(eventConns)

	local arenaIds: { string } = {}
	for arenaId in sets do
		table.insert(arenaIds, arenaId)
	end
	for _, arenaId in arenaIds do
		teardownArena(arenaId)
	end
	log:info("Destroyed")
end

-- ============================================================
-- Initialize
-- ============================================================
local function initialize()
	log:info("Initializing...")
	log:info("Loaded archetype:", Patroller.name, "(walkSpeed=" .. tostring(Patroller.walkSpeed) .. ")")
	log:info("Detection range:", NPCConstants.DETECTION_RANGE)

	-- Wait for WorldDataManager to finish snapshotting before spawning NPCs
	WorldDataManager.waitForInit()

	-- Listen first, then reconcile: a round that starts after this line is
	-- caught by the event, one that started before it by the reconcile.
	table.insert(eventConns, roundStartedEvent.Event:Connect(onRoundStarted))
	table.insert(eventConns, roundEndedEvent.Event:Connect(onRoundEnded))
	reconcile()

	NPCService.enable()
	game:BindToClose(NPCService.destroy)

	log:info("Initialized")
end

initialize()
