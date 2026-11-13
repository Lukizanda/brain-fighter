--!strict

----------------------------------------------------------------------
-- BreakableWallService
----------------------------------------------------------------------
-- Owns the health of every BasePart tagged "BreakableWall", and with it
-- the three things that make a wall a wall: `CanCollide`, `CanQuery` and
-- `CanTouch`, plus the two attributes it publishes, `WallHealth` and
-- `WallState`. Nothing else writes any of those five. The client owns what
-- the wall looks and sounds like and only reads `WallState`
-- (client/Arena/BreakableWallVisuals). See wiki/design/boss-arena.md
-- § Contract between the three pieces.
--
-- Damage arrives as two server-side BindableEvents that SkillDelivery fires
-- on the authoritative run (shared/Skills/SkillEvents):
--
--   WorldImpact(hitInstance, hitPosition, skillName, source)
--       a projectile stopped on world geometry; if that geometry is a wall
--       it takes FIREBALL_WALL_DAMAGE
--   AoeImpact(center, radius, skillName, source)
--       an aoe landed; every wall whose nearest point is inside the radius
--       takes SLAM_WALL_DAMAGE
--
-- Boss attacks only. A source that does not carry the boss tag is ignored,
-- because opening a vault with your own Fireball would remove the baiting
-- the layout is built around.
--
-- A broken wall stays in the DataModel, non-colliding and non-queryable,
-- so it can re-seal and so taps and fireballs pass through it.
--   RegenSec > 0 : re-seals that many seconds after breaking, but not
--                  while a character overlaps it (retried on an interval)
--   otherwise    : stays broken until the arena's next RoundStarted
-- Every wall of an arena returns to intact when that arena's round starts.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BreakableWallConstants = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local BossSpawner = require(ServerScriptService.Server.Boss.Scripts.BossSpawner)

local log = Logger.new("BreakableWallService")

local C = BreakableWallConstants
local State = C.State

local worldImpactEvent = ReplicatedStorage.Shared.Skills.SkillEvents.WorldImpact :: BindableEvent
local aoeImpactEvent = ReplicatedStorage.Shared.Skills.SkillEvents.AoeImpact :: BindableEvent
local roundStartedEvent = ServerScriptService.Server.GameMode.Events.RoundStarted :: BindableEvent

type Wall = {
	part: BasePart,
	health: number,
	state: string,
	-- The collision flags the part had when it was registered; a re-seal
	-- puts exactly these back rather than assuming true.
	canCollide: boolean,
	canQuery: boolean,
	canTouch: boolean,
	regenThread: thread?,
}

local walls: { [BasePart]: Wall } = {}
local eventConns: { RBXScriptConnection } = {}
local tagConns: { RBXScriptConnection } = {}
local enabled = false

----------------------------------------------------------------------
-- Authored attributes, read at use so a designer can retune live
----------------------------------------------------------------------

local function maxHealthOf(part: BasePart): number
	local value = part:GetAttribute(C.Authored.MaxHealth)
	if type(value) == "number" and value > 0 then
		return value
	end
	return C.DEFAULT_MAX_HEALTH
end

local function regenSecOf(part: BasePart): number
	local value = part:GetAttribute(C.Authored.RegenSec)
	if type(value) == "number" and value > 0 then
		return value
	end
	return 0
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

local function stateFor(health: number, maxHealth: number): string
	if health <= 0 then
		return State.Broken
	elseif health <= maxHealth * C.CRITICAL_AT_FRACTION then
		return State.Critical
	elseif health <= maxHealth * C.CRACKED_AT_FRACTION then
		return State.Cracked
	end
	return State.Intact
end

-- The single place the five owned properties are written. Health first,
-- state last: a client that wakes on the state change reads a health that
-- already matches it.
local function publish(wall: Wall)
	local part = wall.part
	local broken = wall.state == State.Broken
	part.CanCollide = if broken then false else wall.canCollide
	part.CanQuery = if broken then false else wall.canQuery
	part.CanTouch = if broken then false else wall.canTouch
	part:SetAttribute(C.Published.Health, wall.health)
	part:SetAttribute(C.Published.State, wall.state)
end

local function cancelRegen(wall: Wall)
	local thread = wall.regenThread
	if thread then
		wall.regenThread = nil
		pcall(task.cancel, thread)
	end
end

local function reset(wall: Wall)
	cancelRegen(wall)
	wall.health = maxHealthOf(wall.part)
	wall.state = State.Intact
	publish(wall)
end

-- Is any character inside the wall's volume? A wall that closed on someone
-- would trap them or push them through the world, so a re-seal waits.
local function characterOverlaps(part: BasePart): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { part }
	for _, hit in workspace:GetPartsInPart(part, params) do
		local model = hit:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			return true
		end
	end
	return false
end

local function tryReseal(wall: Wall)
	wall.regenThread = nil
	if wall.state ~= State.Broken or not wall.part.Parent then
		return
	end
	if characterOverlaps(wall.part) then
		wall.regenThread = task.delay(C.REGEN_RETRY_SEC, tryReseal, wall)
		return
	end
	reset(wall)
	log:info(string.format("%s re-sealed", wall.part:GetFullName()))
end

local function scheduleRegen(wall: Wall)
	cancelRegen(wall)
	local regenSec = regenSecOf(wall.part)
	if regenSec > 0 then
		wall.regenThread = task.delay(regenSec, tryReseal, wall)
	end
end

local function applyDamage(wall: Wall, amount: number)
	if wall.state == State.Broken then
		return
	end
	local before = wall.state
	wall.health = math.max(0, wall.health - amount)
	wall.state = stateFor(wall.health, maxHealthOf(wall.part))
	publish(wall)
	if wall.state ~= before then
		log:info(string.format("%s %s -> %s (health %.1f)", wall.part:GetFullName(), before, wall.state, wall.health))
		if wall.state == State.Broken then
			scheduleRegen(wall)
		end
	end
end

----------------------------------------------------------------------
-- Impacts
----------------------------------------------------------------------

local function isBoss(source: any): boolean
	return typeof(source) == "Instance" and CollectionService:HasTag(source, BossSpawner.BOSS_TAG)
end

-- Distance from a point to the nearest point of the part's box. Greybox
-- walls are blocks; a non-block part is treated as its bounding box.
local function distanceToPart(part: BasePart, point: Vector3): number
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local nearest = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return (localPoint - nearest).Magnitude
end

local function onWorldImpact(hitInstance: any, _hitPosition: any, _skillName: any, source: any)
	if not isBoss(source) or typeof(hitInstance) ~= "Instance" then
		return
	end
	local wall = walls[hitInstance :: BasePart]
	if wall then
		applyDamage(wall, C.FIREBALL_WALL_DAMAGE)
	end
end

local function onAoeImpact(center: any, radius: any, _skillName: any, source: any)
	if not isBoss(source) or typeof(center) ~= "Vector3" or type(radius) ~= "number" then
		return
	end
	for part, wall in walls do
		if wall.state ~= State.Broken and distanceToPart(part, center) <= radius then
			applyDamage(wall, C.SLAM_WALL_DAMAGE)
		end
	end
end

local function onRoundStarted(_roster: any, arenaId: any)
	if type(arenaId) ~= "string" then
		return
	end
	local count = 0
	for part, wall in walls do
		if Arena.idOf(part) == arenaId then
			reset(wall)
			count += 1
		end
	end
	if count > 0 then
		log:info(string.format("[%s] round started - %d wall(s) reset", arenaId, count))
	end
end

----------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------

local function register(instance: Instance)
	if not instance:IsA("BasePart") or walls[instance] then
		return
	end
	local wall: Wall = {
		part = instance,
		health = 0,
		state = State.Intact,
		canCollide = instance.CanCollide,
		canQuery = instance.CanQuery,
		canTouch = instance.CanTouch,
		regenThread = nil,
	}
	walls[instance] = wall
	reset(wall)
end

local function unregister(instance: Instance)
	local wall = walls[instance :: BasePart]
	if wall then
		cancelRegen(wall)
		walls[instance :: BasePart] = nil
	end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
local BreakableWallService = {}

-- Pause: stop listening and stop every pending re-seal. Walls keep the
-- state they have. Reversible via enable().
function BreakableWallService.disable()
	enabled = false
	for _, conn in eventConns do
		conn:Disconnect()
	end
	table.clear(eventConns)
	for _, wall in walls do
		cancelRegen(wall)
	end
	log:info("Disabled")
end

function BreakableWallService.enable()
	if enabled then
		return
	end
	enabled = true
	table.insert(eventConns, worldImpactEvent.Event:Connect(onWorldImpact))
	table.insert(eventConns, aoeImpactEvent.Event:Connect(onAoeImpact))
	table.insert(eventConns, roundStartedEvent.Event:Connect(onRoundStarted))
	-- A wall that broke before a pause still owes its re-seal.
	for _, wall in walls do
		if wall.state == State.Broken then
			scheduleRegen(wall)
		end
	end
	log:info("Enabled")
end

-- Permanent teardown. Leaves the parts as they are; only the service's own
-- state goes.
function BreakableWallService.destroy()
	BreakableWallService.disable()
	for _, conn in tagConns do
		conn:Disconnect()
	end
	table.clear(tagConns)
	table.clear(walls)
	log:info("Destroyed")
end

----------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------
-- Listen for new tags first, then take the existing ones, so a wall tagged
-- between the two is not missed.
table.insert(tagConns, CollectionService:GetInstanceAddedSignal(C.TAG):Connect(register))
table.insert(tagConns, CollectionService:GetInstanceRemovedSignal(C.TAG):Connect(unregister))
for _, instance in CollectionService:GetTagged(C.TAG) do
	register(instance)
end
BreakableWallService.enable()
game:BindToClose(BreakableWallService.destroy)

local registered = 0
for _ in walls do
	registered += 1
end
log:info(string.format("BreakableWallService ready - %d wall(s)", registered))
