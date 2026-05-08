--[[
	Perception
	----------
	Reads the world and writes observations to the blackboard.
	Pure observer — never modifies state or triggers actions directly.
	The Decision layer reads blackboard fields and reacts.

	Outputs:
	- nearestPlayer, distanceToNearest: closest player within DETECTION_RANGE
	- targetHumanoid, targetRootPart: cached refs for the Action layer
	- canSeeTarget: raycast-based line-of-sight check (blocked by walls/terrain)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

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
	local origin = bb.humanoidRootPart.Position + Vector3.new(0, 1.5, 0) -- eye height
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

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		local hum = character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			continue
		end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then
			continue
		end

		local distance = (hrp.Position - npcPos).Magnitude
		if distance < nearestDistance and distance <= NPCConstants.DETECTION_RANGE then
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
