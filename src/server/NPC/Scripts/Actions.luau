--[[
	Actions
	-------
	Action layer for NPCs. Each function takes a blackboard, performs a
	side effect, and returns an ActionResult ("Running" | "Success" | "Failure").

	Actions are idempotent — calling the same action with the same target
	twice in a row will not restart the action. The blackboard tracks
	action state (currentPath, targetPos, moveStartTime) so the action
	knows whether it's continuing or starting fresh.

	This contract matches BT leaf node semantics, so swapping the decision
	layer to a behavior tree later won't require changing actions.
]]

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local NPCConstants = require(ReplicatedStorage.Shared.NPC.NPCConstants)
local NPCTypes = require(ReplicatedStorage.Shared.NPC.NPCTypes)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local laserBeamEffect = require(ReplicatedStorage.Shared.Weapon.Scripts.Effects.laserBeamEffect)
local MeleeConstants = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeConstants)
local MeleeHitDetector = require(ReplicatedStorage.Shared.Weapon.Melee.MeleeHitDetector)

-- HealthService exports applyDamage.process() for server-originated damage
-- (NPC shots don't go through the player RemoteEvent validation path)
local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)

type Blackboard = NPCTypes.Blackboard
type ActionResult = NPCTypes.ActionResult

local log = Logger.new("Actions")

local Actions = {}

-- ============================================================
-- Internal helpers
-- ============================================================

-- Verify the NPC's humanoid + HRP are still valid (NPC may have been destroyed)
local function isAlive(bb: Blackboard): boolean
	if not bb.humanoid or not bb.humanoid.Parent then
		return false
	end
	if bb.humanoid.Health <= 0 then
		return false
	end
	if not bb.humanoidRootPart or not bb.humanoidRootPart.Parent then
		return false
	end
	return true
end

local function clearMoveState(bb: Blackboard)
	bb.currentPath = nil
	bb.targetPos = nil
	bb.currentWaypointIndex = 1
	bb.moveStartTime = 0
end

local function isSameTarget(a: Vector3?, b: Vector3, tolerance: number): boolean
	if not a then return false end
	return (a - b).Magnitude < tolerance
end

-- ============================================================
-- MoveTo: walk directly to a position (no pathfinding)
-- Use for short distances or when you know the path is clear.
-- ============================================================
function Actions.MoveTo(bb: Blackboard, target: Vector3): ActionResult
	if not isAlive(bb) then
		clearMoveState(bb)
		return NPCConstants.ActionResult.Failure
	end

	-- Idempotency: if we're already moving toward this target, just continue
	local continuation = isSameTarget(bb.targetPos, target, 1)

	if not continuation then
		-- New move — reset timer
		bb.targetPos = target
		bb.moveStartTime = os.clock()
	end

	-- Reached the target?
	local distance = (bb.humanoidRootPart.Position - target).Magnitude
	if distance < NPCConstants.WAYPOINT_REACHED_DISTANCE then
		clearMoveState(bb)
		return NPCConstants.ActionResult.Success
	end

	-- Timed out?
	if os.clock() - bb.moveStartTime > NPCConstants.MOVE_TIMEOUT_SECONDS then
		clearMoveState(bb)
		return NPCConstants.ActionResult.Failure
	end

	-- Issue the move (Humanoid:MoveTo is idempotent — calling with the same
	-- target each tick is fine and resets the engine's internal 8s timeout)
	bb.humanoid:MoveTo(target)
	return NPCConstants.ActionResult.Running
end

-- ============================================================
-- MoveToWithPath: navigate to a position using PathfindingService
-- Handles walls, terrain, and elevation changes via waypoints.
-- ============================================================
function Actions.MoveToWithPath(bb: Blackboard, finalTarget: Vector3): ActionResult
	if not isAlive(bb) then
		clearMoveState(bb)
		return NPCConstants.ActionResult.Failure
	end

	local hasPath = bb.currentPath ~= nil
	local sameTarget = isSameTarget(bb.targetPos, finalTarget, NPCConstants.PATH_RECOMPUTE_DISTANCE)

	-- Compute a new path if we don't have one or the target moved significantly
	if not (hasPath and sameTarget) then
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
		})

		local ok, err = pcall(function()
			path:ComputeAsync(bb.humanoidRootPart.Position, finalTarget)
		end)

		if not ok then
			log:warn("Path compute error:", err)
			clearMoveState(bb)
			return NPCConstants.ActionResult.Failure
		end

		if path.Status ~= Enum.PathStatus.Success then
			log:warn("Path status:", tostring(path.Status), "for target", tostring(finalTarget))
			clearMoveState(bb)
			return NPCConstants.ActionResult.Failure
		end

		local waypoints = path:GetWaypoints()
		if #waypoints == 0 then
			clearMoveState(bb)
			return NPCConstants.ActionResult.Failure
		end

		-- Convert PathWaypoint -> Vector3 list (we don't need the action enum)
		local positions = {}
		for _, wp in waypoints do
			table.insert(positions, wp.Position)
		end

		bb.currentPath = positions
		bb.currentWaypointIndex = 1
		bb.targetPos = finalTarget
		bb.moveStartTime = os.clock()
	end

	-- Overall timeout check (covers the entire path traversal)
	if os.clock() - bb.moveStartTime > NPCConstants.MOVE_TIMEOUT_SECONDS then
		clearMoveState(bb)
		return NPCConstants.ActionResult.Failure
	end

	local positions = bb.currentPath :: { Vector3 } -- not nil at this point
	local idx = bb.currentWaypointIndex
	local currentWaypoint = positions[idx]

	-- Reached current waypoint? Advance to next
	local distanceToWaypoint = (bb.humanoidRootPart.Position - currentWaypoint).Magnitude
	if distanceToWaypoint < NPCConstants.WAYPOINT_REACHED_DISTANCE then
		idx += 1
		if idx > #positions then
			-- Reached the final waypoint
			clearMoveState(bb)
			return NPCConstants.ActionResult.Success
		end
		bb.currentWaypointIndex = idx
		currentWaypoint = positions[idx]
	end

	-- Continue moving toward the current waypoint
	bb.humanoid:MoveTo(currentWaypoint)
	return NPCConstants.ActionResult.Running
end

-- ============================================================
-- StopMoving: cancel any in-progress movement
-- ============================================================
function Actions.StopMoving(bb: Blackboard): ActionResult
	if not isAlive(bb) then
		clearMoveState(bb)
		return NPCConstants.ActionResult.Success
	end

	-- Setting MoveTo to current position is the standard way to stop
	bb.humanoid:MoveTo(bb.humanoidRootPart.Position)
	clearMoveState(bb)
	return NPCConstants.ActionResult.Success
end

-- ============================================================
-- Shoot: fire a hitscan ray at a target humanoid
-- - Reads target from blackboard (targetHumanoid, targetRootPart)
-- - Applies spread (NPC accuracy is configurable via COMBAT_SPREAD_DEGREES)
-- - Rate-of-fire throttled via bb.lastShotTime
-- - Calls applyDamage.process() directly on hit (sourcePlayer = nil for NPC shots)
-- Returns Running while on cooldown, Success on a shot fired, Failure if no target
-- ============================================================

-- Reusable shoot raycast params — filter out the NPC itself
local shootRaycastCache: { [Blackboard]: RaycastParams } = {}

local function getShootRaycastParams(bb: Blackboard): RaycastParams
	local cached = shootRaycastCache[bb]
	if cached then
		return cached
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bb.npc }
	params.IgnoreWater = true
	shootRaycastCache[bb] = params
	return params
end

-- Apply a random spread cone to the direction vector
local function applySpread(direction: Vector3, spreadDegrees: number): Vector3
	if spreadDegrees <= 0 then
		return direction
	end
	-- Random spread within a cone: rotate around up axis (yaw) then right axis (pitch)
	local yaw = math.rad((math.random() * 2 - 1) * spreadDegrees)
	local pitch = math.rad((math.random() * 2 - 1) * spreadDegrees)
	local cf = CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(pitch, yaw, 0)
	return cf.LookVector
end

-- Determine hit zone from the instance hit (for damage modifiers like headshots)
local function getHitZone(instance: Instance): string
	local name = instance.Name
	if name == "Head" then
		return DamageTypes.HitZone.Head
	elseif name == "UpperTorso" or name == "LowerTorso" or name == "Torso" then
		return DamageTypes.HitZone.Torso
	end
	return DamageTypes.HitZone.Limb
end

-- Find a MuzzleAttachment on the weapon for visual shot origin.
-- Falls back to the weapon's Handle or the NPC HRP eye-level.
local function getShotOrigin(bb: Blackboard): Vector3
	local weapon = bb.weapon
	if weapon and weapon.Parent then
		local muzzle = weapon:FindFirstChild("MuzzleAttachment", true)
		if muzzle and muzzle:IsA("Attachment") then
			return muzzle.WorldPosition
		end
		local handle = weapon:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			return handle.Position
		end
	end
	-- Fallback: NPC eye level
	return bb.humanoidRootPart.Position + Vector3.new(0, 1.5, 0)
end

function Actions.Shoot(bb: Blackboard): ActionResult
	if not isAlive(bb) then
		return NPCConstants.ActionResult.Failure
	end

	local targetHumanoid = bb.targetHumanoid
	local targetRootPart = bb.targetRootPart
	if not targetHumanoid or not targetRootPart or not targetRootPart.Parent then
		return NPCConstants.ActionResult.Failure
	end
	if targetHumanoid.Health <= 0 then
		return NPCConstants.ActionResult.Failure
	end

	-- Rate-of-fire throttle
	local secondsBetweenShots = 60 / NPCConstants.COMBAT_RATE_OF_FIRE
	local now = os.clock()
	if now - bb.lastShotTime < secondsBetweenShots then
		return NPCConstants.ActionResult.Running
	end
	bb.lastShotTime = now

	-- Play the shoot animation (non-looping, Action priority so it plays over idle/walk)
	local shootTrack = bb.animations.shoot
	if shootTrack then
		shootTrack.Looped = false
		shootTrack.Priority = Enum.AnimationPriority.Action
		shootTrack:Play(0)
	end

	-- Aim direction uses eye-level for accuracy (avoids weapon mesh jitter affecting aim)
	local aimOrigin = bb.humanoidRootPart.Position + Vector3.new(0, 1.5, 0)
	local targetPos = targetRootPart.Position
	local direction = (targetPos - aimOrigin).Unit
	direction = applySpread(direction, NPCConstants.COMBAT_SPREAD_DEGREES)

	-- Visual beam uses the weapon muzzle (or fallback) for a nicer look
	local visualOrigin = getShotOrigin(bb)

	local rayVec = direction * NPCConstants.COMBAT_RANGE
	local result = Workspace:Raycast(aimOrigin, rayVec, getShootRaycastParams(bb))

	local beamEnd: Vector3
	local hitInstance: BasePart? = nil
	if result then
		beamEnd = result.Position
		hitInstance = result.Instance
	else
		beamEnd = aimOrigin + rayVec
	end

	-- Draw the laser beam from the weapon muzzle to the hit/end point
	pcall(function()
		laserBeamEffect(visualOrigin, beamEnd)
	end)

	if not hitInstance then
		return NPCConstants.ActionResult.Success
	end

	-- Check if we hit the target's character
	local targetCharacter = targetRootPart.Parent
	if not targetCharacter or not hitInstance:IsDescendantOf(targetCharacter) then
		-- Missed — hit a wall or unrelated object
		return NPCConstants.ActionResult.Success
	end

	-- Apply damage via the existing pipeline
	applyDamage.process({
		sourcePlayer = nil, -- NPC shots don't credit any player
		targetHumanoid = targetHumanoid,
		baseDamage = NPCConstants.COMBAT_DAMAGE,
		damageType = DamageTypes.DamageType.Bullet,
		hitZone = getHitZone(hitInstance),
		sourceWeapon = bb.weapon,
		timestamp = now,
	})

	return NPCConstants.ActionResult.Success
end

-- ============================================================
-- Actions.MeleeAttack (framework — not yet wired into any archetype)
-- ============================================================
-- Performs a single melee swing: cooldown check, hit detection via
-- the shared MeleeHitDetector, damage via applyDamage.
--
-- Reads the NPC's melee params from the archetype blackboard entry
-- `meleeAttack` (see NPCTypes). Returns Success when a swing landed,
-- Failure when the swing missed or cooldown wasn't ready.
--
-- Intended to be called from a future Combat sub-state (e.g. "Melee")
-- inside PatrollerStates or a new archetype. Kept minimal on purpose —
-- when we wire the first melee archetype we can add pursuit/facing.
-- ============================================================

local MELEE_COOLDOWN_DEFAULT = 1.0
local MELEE_REACH_DEFAULT = 6
local MELEE_WIDTH_DEFAULT = 5
local MELEE_HEIGHT_DEFAULT = 5
local MELEE_DAMAGE_DEFAULT = 15

function Actions.MeleeAttack(bb: Blackboard): ActionResult
	if not bb.humanoidRootPart or not bb.npc then
		return NPCConstants.ActionResult.Failure
	end

	local params = (bb :: any).meleeAttack or {}
	local cooldown = params.cooldownSeconds or MELEE_COOLDOWN_DEFAULT
	local now = os.clock()
	local last = (bb :: any).lastMeleeTime or 0
	if now - last < cooldown then
		return NPCConstants.ActionResult.Failure
	end

	local sweepParams = {
		originCFrame = bb.humanoidRootPart.CFrame,
		reach = params.reach or MELEE_REACH_DEFAULT,
		width = params.width or MELEE_WIDTH_DEFAULT,
		height = params.height or MELEE_HEIGHT_DEFAULT,
		attackerCharacter = bb.npc,
		hitMode = params.hitMode or MeleeConstants.HitMode.Single,
	}
	local hits = MeleeHitDetector.sweep(sweepParams);
	(bb :: any).lastMeleeTime = now

	if #hits == 0 then
		return NPCConstants.ActionResult.Failure
	end

	local damage = params.damage or MELEE_DAMAGE_DEFAULT
	for _, hit in hits do
		applyDamage.process({
			sourcePlayer = nil, -- NPC-originated damage
			targetHumanoid = hit.humanoid,
			baseDamage = damage,
			damageType = DamageTypes.DamageType.Melee,
			hitZone = DamageTypes.HitZone.Torso,
			sourceWeapon = bb.weapon,
			timestamp = now,
		})
	end

	log:info(string.format("%s: MeleeAttack hit %d target(s)", bb.npc.Name, #hits))
	return NPCConstants.ActionResult.Success
end

-- Public: clear cached raycast params when an NPC is destroyed
function Actions.cleanup(bb: Blackboard)
	shootRaycastCache[bb] = nil
end

return Actions
