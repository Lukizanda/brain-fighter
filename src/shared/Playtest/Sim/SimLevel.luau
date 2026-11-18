--!strict

----------------------------------------------------------------------
-- SimLevel
----------------------------------------------------------------------
-- Reads one arena out of the DataModel into the plain table the fight
-- simulator plays on: letter zones, breakable walls, the boss point, the
-- arrival point and the geometry the rays are cast against.
--
-- The simulator is abstract about the players and the boss but NOT
-- about the level: line of sight for taps and the path of every boss
-- fireball are real `workspace:Raycast` calls against the authored
-- greybox, so a rock that hides a letter in the game hides it here.
--
-- Runs in Studio's Edit DataModel (letter blocks do not exist there, so
-- nothing but level geometry is in the way of a ray). Dev tooling: no
-- game system requires this module.
-- See wiki/design/ai-playtest.md.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BreakableWallConstants = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)

local SimLevel = {}

-- Tags and attributes of the level contract (wiki/design/boss-arena.md).
local TAG_ZONE = "BlockSpawnVolume"
local TAG_WALL = "BreakableWall"
local TAG_ARRIVAL = "ArenaArrivalPoint"
local ATTR_ARENA = "ArenaId"
local BOSS_POINT_NAME = "BossPoint"

-- A zone or kit counts as "behind" a regenerating gate when the gate is
-- the nearest one and no further away than this. Measured on the review
-- island: ledge zones sit 20 to 60 studs beyond their gate, the cave kit
-- 16 studs behind its plug.
local GATE_OWNERSHIP_RADIUS = 70

-- Height above the floor probe starts from and how far down it looks.
local FLOOR_PROBE_UP = 80
local FLOOR_PROBE_DOWN = 200

export type Zone = {
	name: string,
	part: BasePart,
	center: Vector3,
	size: Vector3,
	letterTable: string,
	colorOnly: string?,
	quota: number,
	kitLength: number?,
	gateId: string?,
}

export type Wall = {
	name: string,
	part: BasePart,
	position: Vector3,
	maxHealth: number,
	regenSec: number,
	fossilTable: string?,
	gateId: string?,
}

export type Level = {
	arenaId: string,
	bossPoint: Vector3,
	floorY: number,
	arrival: Vector3,
	zones: { Zone },
	walls: { Wall },
	-- Key letters as built in the level: the key kit volumes (KitOpensGate),
	-- by the gate they open. FightSim hangs its own keys from these numbers.
	keyKits: { [string]: { count: number, popReach: number? } },
	lint: { string },
}

local function inArena(instance: Instance, arenaId: string): boolean
	return instance:GetAttribute(ATTR_ARENA) == arenaId
end

local function horizontal(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Scan `arenaId` out of the DataModel. Errors if the arena has no boss
-- point or no zones, since a simulation of nothing would report numbers.
function SimLevel.fromWorkspace(arenaId: string): Level
	local bossPart: BasePart? = nil
	for _, d in workspace:GetDescendants() do
		if d.Name == BOSS_POINT_NAME and d:IsA("BasePart") and inArena(d, arenaId) then
			bossPart = d
			break
		end
	end
	assert(bossPart, "SimLevel: no BossPoint with ArenaId " .. arenaId)

	local walls: { Wall } = {}
	for _, inst in CollectionService:GetTagged(TAG_WALL) do
		if inst:IsA("BasePart") and inArena(inst, arenaId) then
			table.insert(walls, {
				name = inst.Name,
				part = inst,
				position = inst.Position,
				maxHealth = (inst:GetAttribute("MaxHealth") :: number?) or BreakableWallConstants.DEFAULT_MAX_HEALTH,
				regenSec = (inst:GetAttribute("RegenSec") :: number?) or 0,
				fossilTable = inst:GetAttribute("FossilTable") :: string?,
				gateId = inst:GetAttribute("GateId") :: string?,
			})
		end
	end

	local zones: { Zone } = {}
	local lint: { string } = {}
	local keyKits: { [string]: { count: number, popReach: number? } } = {}
	for _, inst in CollectionService:GetTagged(TAG_ZONE) do
		if inst:IsA("BasePart") and inArena(inst, arenaId) and inst:GetAttribute("KitOpensGate") == true then
			-- A gate's key letters, not a letter zone: FightSim models them.
			local gate = inst:GetAttribute("KitGate")
			if type(gate) == "string" and gate ~= "" then
				keyKits[gate] = {
					count = (inst:GetAttribute("WordKit") :: number?) or 0,
					popReach = inst:GetAttribute("PopReach") :: number?,
				}
			end
		elseif inst:IsA("BasePart") and inArena(inst, arenaId) then
			local kit = inst:GetAttribute("WordKit") :: number?
			local tableName = (inst:GetAttribute("LetterTable") :: string?) or LetterTables.DEFAULT
			local quota = (inst:GetAttribute("BlockQuota") :: number?) or 0
			if kit then
				quota = kit
			end

			-- Which gate, if any, stands between the island and this zone.
			local gateId: string? = inst:GetAttribute("KitGate") :: string?
			if not gateId and tableName == LetterTables.WILDCARD then
				local best = GATE_OWNERSHIP_RADIUS
				for _, wall in walls do
					if wall.gateId and wall.regenSec > 0 then
						local d = horizontal(wall.position, inst.Position)
						if d < best then
							best = d
							gateId = wall.gateId
						end
					end
				end
			end

			if quota <= 0 then
				table.insert(lint, string.format("zone %s has no BlockQuota and no WordKit; the sim gives it 0 blocks", inst.Name))
			end
			if inst.CanQuery then
				table.insert(lint, string.format("zone %s is CanQuery: a tap ray stops on the volume itself", inst.Name))
			end

			table.insert(zones, {
				name = inst.Name,
				part = inst,
				center = inst.Position,
				size = inst.Size,
				letterTable = tableName,
				colorOnly = inst:GetAttribute("ColorOnly") :: string?,
				quota = quota,
				kitLength = kit,
				gateId = gateId,
			})
		end
	end
	assert(#zones > 0, "SimLevel: no BlockSpawnVolume with ArenaId " .. arenaId)
	table.sort(zones, function(a: Zone, b: Zone): boolean
		return a.name < b.name
	end)

	local arrival = bossPart.Position
	for _, inst in CollectionService:GetTagged(TAG_ARRIVAL) do
		if inst:IsA("BasePart") and inArena(inst, arenaId) then
			arrival = inst.Position
			break
		end
	end

	-- Invisible parts that still answer raycasts stop taps and shots
	-- without the player seeing why. Reported, not fixed.
	local slot = bossPart:FindFirstAncestorWhichIsA("Model")
	if slot then
		for _, d in slot:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency >= 1 and d.CanQuery and not d.CanCollide then
				table.insert(lint, string.format("%s is invisible, non-colliding and CanQuery: rays stop on it", d.Name))
			end
		end
	end

	return {
		arenaId = arenaId,
		bossPoint = bossPart.Position,
		floorY = bossPart.Position.Y - bossPart.Size.Y / 2,
		arrival = arrival,
		zones = zones,
		walls = walls,
		keyKits = keyKits,
		lint = lint,
	}
end

-- Height of the walkable surface under (x, z), or nil over open air.
function SimLevel.floorAt(level: Level, x: number, z: number, params: RaycastParams): number?
	local origin = Vector3.new(x, level.floorY + FLOOR_PROBE_UP, z)
	local hit = workspace:Raycast(origin, Vector3.new(0, -FLOOR_PROBE_DOWN, 0), params)
	if hit then
		return hit.Position.Y
	end
	return nil
end

return SimLevel
