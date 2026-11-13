--!strict

----------------------------------------------------------------------
-- hungerFixture
----------------------------------------------------------------------
-- Runtime fixture for the hungry-brain tests (Arena suite, hunger_*).
-- Everything lives in the test's own arena id and is removed by `destroy()`:
--
--   * a block pool of the test's own, built from tiny one-block volumes at
--     chosen points, so a block's position is known to within a stud and
--     "nearest" is decided by the test, not by a random roll. The pool is
--     registered with BlockPoolRegistry under the test's arena id, which is
--     the only door the boss has to a pool, so the game's pools are never
--     involved;
--   * for module-level tests, a stand-in boss (a Model with a Humanoid and an
--     anchored HumanoidRootPart carrying the arena id) to hand to BossHunger
--     directly and tick by hand with a chosen dt;
--   * helpers to build a boss-type spec with the three eat values.
--
-- Real-boss tests build their boss with bossEntranceFixture and use only
-- `pool` / `zone` / `kit` / `blockAt` from here.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)
local BlockPoolRegistry = require(ServerScriptService.Server.BlockSpawner.BlockPoolRegistry)

local CONTAINER_NAME = "HungerTestContainer"
-- Half the side of a one-block volume: the block sits within about a stud of
-- the zone's centre.
local ZONE_HALF = Vector3.new(0.5, 0.5, 0.5)
-- A kit row of this length (X) holds its letters within ~2.5 studs of centre.
local KIT_SIZE = Vector3.new(5, 1, 1)
local KIT_LENGTH = 5
-- How close a block must be to a zone's centre to count as that zone's.
local ZONE_MATCH_STUDS = 2
-- Stand-in boss: far above the playable place, out of everything's way.
local FAKE_BOSS_ORIGIN = Vector3.new(0, 5600, 0)
local DEFAULT_MAX_HEALTH = 1000

local fixture = {}
fixture.__index = fixture

fixture.FAKE_BOSS_ORIGIN = FAKE_BOSS_ORIGIN
fixture.KIT_LENGTH = KIT_LENGTH

export type Fixture = typeof(setmetatable({} :: {
	arenaId: string,
	container: Folder,
	pools: { { arenaId: string, pool: BlockSpawner.BlockSpawner } },
}, fixture))

function fixture.new(arenaId: string): Fixture
	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME
	container.Parent = workspace
	return setmetatable({
		arenaId = arenaId,
		container = container,
		pools = {},
	}, fixture)
end

-- A one-block quota volume centred on `center`.
function fixture.zone(_self: Fixture, center: Vector3): BlockSpawner.BoxDef
	return {
		boxMin = center - ZONE_HALF,
		boxMax = center + ZONE_HALF,
		quota = 1,
		label = "HungerZone",
	}
end

-- A word-kit volume centred on `center`.
function fixture.kit(_self: Fixture, center: Vector3): BlockSpawner.BoxDef
	return {
		boxMin = center - KIT_SIZE * 0.5,
		boxMax = center + KIT_SIZE * 0.5,
		wordKit = KIT_LENGTH,
		cframe = CFrame.new(center),
		size = KIT_SIZE,
		label = "HungerKit",
	}
end

-- A started pool over `volumes`, registered for `arenaId` (default the
-- fixture's). `respawnDelay` is what a consumed block waits to be replaced.
function fixture.pool(
	self: Fixture,
	volumes: { BlockSpawner.BoxDef },
	respawnDelay: number,
	arenaId: string?
): BlockSpawner.BlockSpawner
	local id = arenaId or self.arenaId
	local pool = BlockSpawner.new({
		arenaId = id,
		parent = self.container,
		boxes = volumes,
		respawnDelay = respawnDelay,
	})
	pool:start()
	BlockPoolRegistry.register(id, pool)
	table.insert(self.pools, { arenaId = id, pool = pool })
	return pool
end

-- The live block of `pool` sitting at a zone centred on `center`, if any.
function fixture.blockAt(_self: Fixture, pool: BlockSpawner.BlockSpawner, center: Vector3): Model?
	for _, block in pool:getActiveBlocks() do
		if block.Parent ~= nil and (block:GetPivot().Position - center).Magnitude <= ZONE_MATCH_STUDS then
			return block
		end
	end
	return nil
end

-- A boss-type spec carrying only the eat values (BossHunger reads nothing
-- else). Pass nil for a value to leave it out.
function fixture.spec(intervalSec: number?, radius: number?, healFraction: number?): any
	return {
		eatIntervalSec = intervalSec,
		eatRadius = radius,
		eatHealFraction = healFraction,
	}
end

-- A stand-in boss at `position` (default the fixture origin) in `arenaId`
-- (default the fixture's), with `health` of `maxHealth`.
function fixture.fakeBoss(
	self: Fixture,
	maxHealth: number?,
	health: number?,
	position: Vector3?,
	arenaId: string?
): (Model, Humanoid, BasePart)
	local boss = Instance.new("Model")
	boss.Name = "HungerStandInBoss"
	boss:SetAttribute(Arena.ID_ATTRIBUTE, arenaId or self.arenaId)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.CanCollide = false
	root.Size = Vector3.one
	root.Position = position or FAKE_BOSS_ORIGIN
	root.Parent = boss

	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = maxHealth or DEFAULT_MAX_HEALTH
	humanoid.Health = health or humanoid.MaxHealth
	humanoid.Parent = boss

	boss.Parent = self.container
	return boss, humanoid, root
end

function fixture.destroy(self: Fixture)
	for _, entry in self.pools do
		BlockPoolRegistry.unregister(entry.arenaId, entry.pool)
		entry.pool:destroy()
	end
	table.clear(self.pools)
	self.container:Destroy()
end

return fixture
