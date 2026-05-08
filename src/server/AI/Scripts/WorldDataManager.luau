----------------------------------------------------------------------
-- WorldDataManager
----------------------------------------------------------------------
-- Server library that scans tagged AI markers in the workspace on
-- startup, snapshots their positions/attributes, and exposes a clean
-- read-only API for the NPC system.
--
-- The markers in workspace act as edit-time placement helpers. At
-- runtime, WorldDataManager takes a snapshot and (optionally) destroys
-- the visible markers — the AI system reads from the snapshot going
-- forward.
--
-- Design goals:
--   - Single source of truth for AI world data at runtime
--   - Extensible: new marker types can be added without changing consumers
--   - Deterministic: snapshot is taken once on initialize()
--   - Read-only API for consumers
--
-- Usage:
--   local WorldDataManager = require(path.to.WorldDataManager)
--   WorldDataManager.initialize()  -- called by WorldDataService on startup
--   local spawns = WorldDataManager.getSpawns()
--   local patrolPoints = WorldDataManager.getPatrolPoints()
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local NPCConstants = require(ReplicatedStorage.Shared.NPC.NPCConstants)

local log = Logger.new("WorldDataManager")

----------------------------------------------------------------------
-- Types
----------------------------------------------------------------------
export type MarkerSnapshot = {
	name: string,
	position: Vector3,
	cframe: CFrame,
	size: Vector3,
	attributes: { [string]: any },
}

----------------------------------------------------------------------
-- Internal state
----------------------------------------------------------------------
local snapshots: { [string]: { MarkerSnapshot } } = {} -- keyed by tag name
local initialized = false
local initializedEvent = Instance.new("BindableEvent")

----------------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------------
local function snapshotMarker(part: BasePart): MarkerSnapshot
	local attributes = {}
	for name, value in part:GetAttributes() do
		attributes[name] = value
	end

	return {
		name = part.Name,
		position = part.Position,
		cframe = part.CFrame,
		size = part.Size,
		attributes = attributes,
	}
end

local function scanTag(tagName: string): { MarkerSnapshot }
	local results = {}
	for _, instance in CollectionService:GetTagged(tagName) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(results, snapshotMarker(instance))
		end
	end
	return results
end

--[[
	Destroys all tagged markers in the workspace after snapshotting.
	Called at the end of initialize() to hide edit-time placement helpers
	from players during gameplay. Markers still exist in Studio edit mode
	(saved in .rbxlx) — this only affects the runtime instance.
]]
local function destroyMarkers()
	local tagsToDestroy = {
		NPCConstants.TAG_NPC_SPAWN,
		NPCConstants.TAG_PATROL_POINT,
	}

	local destroyed = 0
	for _, tagName in tagsToDestroy do
		for _, instance in CollectionService:GetTagged(tagName) do
			if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
				instance:Destroy()
				destroyed += 1
			end
		end
	end

	return destroyed
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
local WorldDataManager = {}

--[[
	Scans tagged markers in the workspace and snapshots them.
	Safe to call multiple times — re-scans each call.
	Consumers should call this once on server startup.
]]
function WorldDataManager.initialize()
	-- Scan each known tag type
	snapshots[NPCConstants.TAG_NPC_SPAWN] = scanTag(NPCConstants.TAG_NPC_SPAWN)
	snapshots[NPCConstants.TAG_PATROL_POINT] = scanTag(NPCConstants.TAG_PATROL_POINT)

	log:info(string.format(
		"Snapshotted %d spawns, %d patrol points",
		#snapshots[NPCConstants.TAG_NPC_SPAWN],
		#snapshots[NPCConstants.TAG_PATROL_POINT]
	))

	-- Destroy edit-time markers — players shouldn't see them at runtime
	local destroyed = destroyMarkers()
	log:info(string.format("Destroyed %d edit-time markers", destroyed))

	initialized = true
	initializedEvent:Fire()
end

--[[
	Returns true if initialize() has been called.
]]
function WorldDataManager.isInitialized(): boolean
	return initialized
end

--[[
	Yields until initialize() has been called.
	Safe to call from any thread at any time.
]]
function WorldDataManager.waitForInit()
	if initialized then
		return
	end
	initializedEvent.Event:Wait()
end

--[[
	Returns the snapshot list for NPCSpawn-tagged markers.
	Empty table if none or if not yet initialized.
]]
function WorldDataManager.getSpawns(): { MarkerSnapshot }
	return snapshots[NPCConstants.TAG_NPC_SPAWN] or {}
end

--[[
	Returns the snapshot list for PatrolPoint-tagged markers.
	Empty table if none or if not yet initialized.
]]
function WorldDataManager.getPatrolPoints(): { MarkerSnapshot }
	return snapshots[NPCConstants.TAG_PATROL_POINT] or {}
end

--[[
	Returns the snapshot list for an arbitrary tag.
	Use this for custom tag types not covered by dedicated getters.
]]
function WorldDataManager.getMarkersByTag(tagName: string): { MarkerSnapshot }
	return snapshots[tagName] or {}
end

return WorldDataManager
