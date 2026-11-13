--!strict

----------------------------------------------------------------------
-- fossilFixture
----------------------------------------------------------------------
-- Phase3 fossil suites: the REAL BreakableWallService (through
-- breakableWallFixture: real tag, real WallState, real boss fireballs and
-- RoundStarted) plus the test's own pools and FossilWatcher, all in the
-- test's own arena ids. Everything it makes is destroyed by `destroy()`,
-- which every test calls from teardown.
--
-- Walls sit far above the playable place; the pools' quota volumes sit
-- elsewhere above it, so a freed fossil block is never confused with a
-- pool block by position.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)
local FossilConstants = require(ReplicatedStorage.Shared.BlockSpawner.FossilConstants)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local breakableWallFixture = require(ReplicatedStorage.Shared.Tests.Helpers.breakableWallFixture)
local FossilWatcher = require(ServerScriptService.Server.BlockSpawner.FossilWatcher)

local CONTAINER_NAME = "FossilTestContainer"
local POOL_ORIGIN = Vector3.new(0, 5200, 0)
local POOL_BOX_STUDS = Vector3.new(40, 10, 40)
-- Blocks the test pool holds (one quota volume).
local POOL_QUOTA = 3
-- Two hits break a wall of this health; one hit does not.
local WALL_HEALTH = 2
local HALF = 0.5

local fixture = {}
fixture.__index = fixture

fixture.POOL_QUOTA = POOL_QUOTA
fixture.WALL_HEALTH = WALL_HEALTH

export type Fixture = typeof(setmetatable({} :: {
	arenaId: string,
	container: Folder,
	walls: breakableWallFixture.Fixture,
	boss: Model,
	pools: { BlockSpawner.BlockSpawner },
	watchers: { FossilWatcher.FossilWatcher },
}, fixture))

function fixture.new(arenaId: string): Fixture
	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME
	container.Parent = workspace
	local walls = breakableWallFixture.new(arenaId)
	return setmetatable({
		arenaId = arenaId,
		container = container,
		walls = walls,
		boss = walls:boss(),
		pools = {},
		watchers = {},
	}, fixture)
end

-- A started pool in `arenaId` (default the fixture's) holding POOL_QUOTA
-- blocks in one quota volume, parented to the container. No refill delay.
function fixture.pool(self: Fixture, arenaId: string?): BlockSpawner.BlockSpawner
	local pool = BlockSpawner.new({
		arenaId = arenaId or self.arenaId,
		parent = self.container,
		boxes = { {
			boxMin = POOL_ORIGIN - POOL_BOX_STUDS * HALF,
			boxMax = POOL_ORIGIN + POOL_BOX_STUDS * HALF,
			quota = POOL_QUOTA,
			label = "FossilTestVolume",
		} },
	})
	pool:start()
	table.insert(self.pools, pool)
	return pool
end

-- A started watcher over `pools` (arena id -> pool).
function fixture.watcher(
	self: Fixture,
	pools: { [string]: BlockSpawner.BlockSpawner },
	lifetimeSec: number?
): FossilWatcher.FossilWatcher
	local watcher = FossilWatcher.new(pools, { lifetimeSec = lifetimeSec })
	watcher:start()
	table.insert(self.watchers, watcher)
	return watcher
end

-- A breakable wall (WALL_HEALTH, no regeneration unless `regenSec`) that
-- asks for a fossil from `tableName`. The attribute goes on after the wall
-- is tagged, which is also the "authored live" path.
function fixture.fossilWall(
	self: Fixture,
	name: string,
	tableName: string?,
	options: breakableWallFixture.WallOptions?
): BasePart
	local opts: breakableWallFixture.WallOptions = options or {}
	if opts.maxHealth == nil then
		opts.maxHealth = WALL_HEALTH
	end
	local wall = self.walls:wall(name, opts)
	if tableName ~= nil then
		wall:SetAttribute(FossilConstants.TABLE_ATTRIBUTE, tableName)
	end
	self.walls:settle()
	return wall
end

function fixture.breakWall(self: Fixture, wall: BasePart, hits: number?)
	self.walls:fireballs(wall, self.boss, hits or WALL_HEALTH)
end

-- Where a fossil block of `wall` should be.
function fixture.expectedPosition(_self: Fixture, wall: BasePart): Vector3
	return wall.Position
		+ Vector3.new(0, -wall.Size.Y * HALF + FossilConstants.HEIGHT_ABOVE_BASE_STUDS, 0)
end

function fixture.letterOf(_self: Fixture, block: Instance): any
	return block:GetAttribute(LetterBlocks.LETTER_ATTRIBUTE)
end

function fixture.colorOf(_self: Fixture, block: Instance): any
	return block:GetAttribute(LetterBlocks.COLOR_ATTRIBUTE)
end

function fixture.publishedLetter(_self: Fixture, wall: BasePart): any
	return wall:GetAttribute(FossilConstants.LETTER_ATTRIBUTE)
end

function fixture.publishedColor(_self: Fixture, wall: BasePart): any
	return wall:GetAttribute(FossilConstants.COLOR_ATTRIBUTE)
end

function fixture.destroy(self: Fixture)
	for _, watcher in self.watchers do
		watcher:destroy()
	end
	table.clear(self.watchers)
	for _, pool in self.pools do
		pool:destroy()
	end
	table.clear(self.pools)
	self.walls:destroy()
	self.container:Destroy()
end

return fixture
