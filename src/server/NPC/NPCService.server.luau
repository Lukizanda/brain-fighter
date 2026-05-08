--[[
	NPCService
	----------
	Top-level NPC orchestrator. Spawns NPCs from tagged spawn points,
	creates an NPCController per NPC, ticks them on Heartbeat.

	Phase 3: NPCController + StateMachine + Patrol state.
	NPCs autonomously cycle patrol points.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local NPCConstants = require(ReplicatedStorage.Shared.NPC.NPCConstants)
local NPCTypes = require(ReplicatedStorage.Shared.NPC.NPCTypes)
local Patroller = require(ReplicatedStorage.Shared.NPC.Archetypes.Patroller)

local scriptsFolder = script.Parent.Scripts
local NPCController = require(scriptsFolder.NPCController)

-- AIWorldData — authoritative source for spawn/patrol positions
local WorldDataManager = require(ServerScriptService.Server.AI.Scripts.WorldDataManager)

local log = Logger.new("NPCService")

-- ============================================================
-- State
-- ============================================================
type Archetype = NPCTypes.Archetype

local controllers: { NPCController.NPCControllerInstance } = {}
local spawnCounter = 0

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
	local scriptsFolder = weapon:FindFirstChild("Scripts")
	if scriptsFolder then
		scriptsFolder:Destroy()
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

local function spawnNPCAtPosition(
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

	-- Tag for queries / cleanup
	CollectionService:AddTag(npc, NPCConstants.TAG_NPC)

	npc.Parent = Workspace

	-- Equip visual weapon (if specified by archetype)
	local weapon = equipWeapon(npc, archetype.weaponTemplateName)

	-- Create the controller for this NPC
	local controller = NPCController.new(npc, archetype, weapon)
	if controller then
		table.insert(controllers, controller)
	else
		log:warn("Failed to create controller for", npc.Name)
	end

	log:info(string.format("Spawned %s at %s", npc.Name, spawnName))
	return npc
end

local function spawnAllFromWorldData()
	local spawns = WorldDataManager.getSpawns()

	for _, snapshot in spawns do
		spawnNPCAtPosition(snapshot.name, snapshot.position, Patroller)
	end

	log:info(string.format("Processed %d spawn points, spawned %d controllers", #spawns, #controllers))
end

-- ============================================================
-- Tick loop
-- ============================================================
local function tickAllControllers(dt: number)
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

-- ============================================================
-- Initialize
-- ============================================================
local function initialize()
	log:info("Initializing...")
	log:info("Loaded archetype:", Patroller.name, "(walkSpeed=" .. tostring(Patroller.walkSpeed) .. ")")
	log:info("Detection range:", NPCConstants.DETECTION_RANGE)

	-- Wait for WorldDataManager to finish snapshotting before spawning NPCs
	WorldDataManager.waitForInit()

	spawnAllFromWorldData()

	-- Start the tick loop after a brief delay so spawned NPCs have time
	-- to settle on the floor before we start commanding them
	task.delay(2, function()
		RunService.Heartbeat:Connect(tickAllControllers)
		log:info("Tick loop started for", #controllers, "controllers")
	end)

	log:info("Initialized")
end

initialize()
