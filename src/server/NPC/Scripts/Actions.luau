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
-- Path requests (asynchronous on purpose)
-- ============================================================
-- `PathfindingService:ComputeAsync` yields. Called straight from a state's
-- update fn it parks the whole decision tick, and the next Heartbeat starts
-- a second tick on a fresh thread while the first is still inside the
-- compute. Two ticks then race over one blackboard, and a stale Patrol
-- update issues `Humanoid:MoveTo` seconds after the machine entered Combat
-- — the rig walks away from the player it is supposed to be shooting.
-- So the compute runs on its own thread and the action reports Running
-- until the result lands. Actions never yield their caller.
local PathRequestStatus = {
	Pending = "Pending",
	Ready   = "Ready",
	Failed  = "Failed",
}

type PathRequest = {
	target: Vector3,
	token: number,
	status: string,
	waypoints: { Vector3 }?,
}

-- Pathfinding agent envelope — the Patroller/Boss rigs are R15-sized.
local AGENT_RADIUS = 2
local AGENT_HEIGHT = 5
-- A rig pathing somewhere unreachable retries every time its state re-runs.
-- Warn at most this often per NPC so one stuck rig cannot flood the console
-- (it used to bury whole test suites).
local PATH_WARN_INTERVAL_SECONDS = 5

local pathRequests: { [Blackboard]: PathRequest } = {}
-- Monotonic per-NPC counter: a result whose token is stale lost the race to
-- a newer request (or to the NPC being destroyed) and is dropped.
local pathTokens: { [Blackboard]: number } = {}
local pathWarnAt: { [Blackboard]: number } = {}

local function warnThrottled(bb: Blackboard, ...: any)
	local now = os.clock()
	if now - (pathWarnAt[bb] or 0) < PATH_WARN_INTERVAL_SECONDS then
		return
	end
	pathWarnAt[bb] = now
	log:warn(...)
end

local function startPathRequest(bb: Blackboard, finalTarget: Vector3)
	local token = (pathTokens[bb] or 0) + 1
	pathTokens[bb] = token
	pathRequests[bb] = {
		target = finalTarget,
		token = token,
		status = PathRequestStatus.Pending,
		waypoints = nil,
	}

	local origin = bb.humanoidRootPart.Position
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = AGENT_RADIUS,
			AgentHeight = AGENT_HEIGHT,
			AgentCanJump = true,
		})

		local ok, err = pcall(function()
			path:ComputeAsync(origin, finalTarget)
		end)

		-- Superseded while we were computing, or the NPC is gone.
		local request = pathRequests[bb]
		if not request or request.token ~= token then
			return
		end

		if not ok then
			warnThrottled(bb, "Path compute error:", err)
			request.status = PathRequestStatus.Failed
			return
		end

		if path.Status ~= Enum.PathStatus.Success then
			warnThrottled(bb, "Path status:", tostring(path.Status), "for target", tostring(finalTarget))
			request.status = PathRequestStatus.Failed
			return
		end

		-- Convert PathWaypoint -> Vector3 list (we don't need the action enum)
		local positions: { Vector3 } = {}
		for _, wp in path:GetWaypoints() do
			table.insert(positions, wp.Position)
		end
		if #positions == 0 then
			request.status = PathRequestStatus.Failed
			return
		end

		request.waypoints = positions
		request.status = PathRequestStatus.Ready
	end)
end

-- ============================================================
-- MoveToWithPath: navigate to a position using PathfindingService
-- Handles walls, terrain, and elevation changes via waypoints.
-- Returns Running while a path is still being computed.
-- ============================================================
function Actions.MoveToWithPath(bb: Blackboard, finalTarget: Vector3): ActionResult
	if not isAlive(bb) then
		clearMoveState(bb)
		pathRequests[bb] = nil
		return NPCConstants.ActionResult.Failure
	end

	local hasPath = bb.currentPath ~= nil
	local sameTarget = isSameTarget(bb.targetPos, finalTarget, NPCConstants.PATH_RECOMPUTE_DISTANCE)

	-- No usable path for this target: drive the request state machine.
	if not (hasPath and sameTarget) then
		local request = pathRequests[bb]
		local requestMatches = request ~= nil
			and isSameTarget(request.target, finalTarget, NPCConstants.PATH_RECOMPUTE_DISTANCE)

		if not requestMatches then
			startPathRequest(bb, finalTarget)
			return NPCConstants.ActionResult.Running
		end

		local pending = request :: PathRequest
		if pending.status == PathRequestStatus.Pending then
			return NPCConstants.ActionResult.Running
		end

		pathRequests[bb] = nil

		if pending.status ~= PathRequestStatus.Ready or not pending.waypoints then
			clearMoveState(bb)
			return NPCConstants.ActionResult.Failure
		end

		bb.currentPath = pending.waypoints
		bb.currentWaypointIndex = 1
		bb.targetPos = pending.target
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
	-- Drop any in-flight path too, or its result lands a tick later and
	-- walks the rig off again after whoever called this asked it to stand.
	pathRequests[bb] = nil
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

-- What the kill feed credits an NPC kill to: the archetype name NPCService
-- stamped on the Model. A rig spawned by something else (a test fixture)
-- carries none and reports Unknown, which is what it used to say always.
local function npcCause(bb: Blackboard): string
	local archetype = bb.npc:GetAttribute(NPCConstants.ARCHETYPE_ATTRIBUTE)
	return if type(archetype) == "string" and archetype ~= "" then archetype else DamageTypes.Cause.Unknown
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
	return bb.humanoidRootPart.Position + Vector3.new(0, NPCConstants.EYE_HEIGHT, 0)
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
	local aimOrigin = bb.humanoidRootPart.Position + Vector3.new(0, NPCConstants.EYE_HEIGHT, 0)
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
		cause = npcCause(bb),
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
			cause = npcCause(bb),
			timestamp = now,
		})
	end

	log:info(string.format("%s: MeleeAttack hit %d target(s)", bb.npc.Name, #hits))
	return NPCConstants.ActionResult.Success
end

-- Public: clear cached raycast params when an NPC is destroyed
function Actions.cleanup(bb: Blackboard)
	shootRaycastCache[bb] = nil
	pathRequests[bb] = nil
	pathTokens[bb] = nil
	pathWarnAt[bb] = nil
end

return Actions
