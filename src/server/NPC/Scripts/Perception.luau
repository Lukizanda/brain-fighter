--[[
	Perception
	----------
	Reads the world and writes observations to the blackboard.
	Pure observer — never modifies state or triggers actions directly.
	The Decision layer reads blackboard fields and reacts.

	Outputs:
	- nearestPlayer, distanceToNearest: closest player of this NPC's arena
	  within DETECTION_RANGE (the arena is the NPC Model's ArenaId attribute)
	- targetHumanoid, targetRootPart: cached refs for the Action layer
	- canSeeTarget: raycast-based line-of-sight check (blocked by walls/terrain)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BroadcastAudience = require(ReplicatedStorage.Shared.GameMode.BroadcastAudience)
local Hittables = require(ReplicatedStorage.Shared.Skills.Hittables)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local NPCConstants = require(ReplicatedStorage.Shared.NPC.NPCConstants)
local NPCTypes = require(ReplicatedStorage.Shared.NPC.NPCTypes)

type Blackboard = NPCTypes.Blackboard

local log = Logger.new("Perception")

local Perception = {}

-- Per-NPC log throttle counters so we don't spam every frame
local logCounters: { [Blackboard]: number } = {}

-- Reusable raycast params — filter out the NPC and Damageable NPCs/dummies so
-- our own body doesn't block the ray. Rebuilt per NPC (cached on the blackboard).
local raycastParamsCache: { [Blackboard]: RaycastParams } = {}

local function getRaycastParams(bb: Blackboard): RaycastParams
	local cached = raycastParamsCache[bb]
	if cached then
		return cached
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bb.npc }
	params.IgnoreWater = true
	raycastParamsCache[bb] = params
	return params
end

-- Cast a ray from the NPC's head position to the target's HRP position.
-- Returns true if nothing blocks the line between them, false otherwise.
local function hasLineOfSight(bb: Blackboard, targetRootPart: BasePart): boolean
	local origin = bb.humanoidRootPart.Position + Vector3.new(0, NPCConstants.EYE_HEIGHT, 0)
	local targetPos = targetRootPart.Position
	local direction = targetPos - origin

	local result = Workspace:Raycast(origin, direction, getRaycastParams(bb))
	if not result then
		return true -- nothing hit = clear line of sight
	end

	-- If the ray hit something, check if it's part of the target's character
	local hit = result.Instance
	local targetCharacter = targetRootPart.Parent
	if hit and targetCharacter and hit:IsDescendantOf(targetCharacter) then
		return true -- hit the target itself = line of sight
	end

	return false
end

function Perception.update(bb: Blackboard)
	if not bb.humanoidRootPart or not bb.humanoidRootPart.Parent then
		return
	end

	local npcPos = bb.humanoidRootPart.Position

	local nearestPlayer: Player? = nil
	local nearestDistance = math.huge
	local nearestHumanoid: Humanoid? = nil
	local nearestRootPart: BasePart? = nil

	-- Candidates are the roster of this NPC's arena — read off the ArenaId
	-- attribute the spawning service stamped on it — filtered through the
	-- same Hittables definition the skill pipeline lands on. Players only:
	-- an NPC (or the boss, which shares this scan) hunts the roster, never
	-- the boss or another NPC. A hub player is never here because nothing
	-- hostile carries the Lobby id.
	local arenaId = Arena.idOf(bb.npc)
	for _, hittable in Hittables.collect(BroadcastAudience.forArena(arenaId), arenaId) do
		local player = hittable.player
		if not player then
			continue
		end
		local hum = hittable.hum
		local hrp = hittable.hrp

		local distance = (hrp.Position - npcPos).Magnitude
		local perceptionRange = (bb :: any).perceptionRange or NPCConstants.DETECTION_RANGE
		if distance < nearestDistance and distance <= perceptionRange then
			nearestDistance = distance
			nearestPlayer = player
			nearestHumanoid = hum
			nearestRootPart = hrp
		end
	end

	-- Line-of-sight: only raycast if we found a nearby player (expensive)
	local canSee = false
	if nearestRootPart then
		canSee = hasLineOfSight(bb, nearestRootPart)
	end

	-- Write observations to the blackboard
	bb.nearestPlayer = nearestPlayer
	bb.distanceToNearest = nearestDistance
	bb.targetHumanoid = nearestHumanoid
	bb.targetRootPart = nearestRootPart
	bb.canSeeTarget = canSee

	-- Throttled log: every ~60 ticks per NPC, only if there's a player nearby
	local count = (logCounters[bb] or 0) + 1
	logCounters[bb] = count
	if count >= NPCConstants.LOG_THROTTLE_INTERVAL then
		logCounters[bb] = 0
		if nearestPlayer then
			log:info(string.format("%s: nearest=%s distance=%.1f los=%s",
				bb.npc.Name, nearestPlayer.Name, nearestDistance, tostring(canSee)))
		end
	end
end

-- Public: clear cached state when an NPC is destroyed
function Perception.cleanup(bb: Blackboard)
	logCounters[bb] = nil
	raycastParamsCache[bb] = nil
end

return Perception
