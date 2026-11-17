--!strict

----------------------------------------------------------------------
-- BlockPoolRegistry
----------------------------------------------------------------------
-- How other server systems reach an arena's block pool. The pools are built
-- inside BlockSpawnerService (a Script, which cannot be required), so the
-- service registers each one here and anything that needs to ask a pool for
-- something requires this module instead. A module rather than a
-- BindableFunction, the way the project already did it for SessionRegistry
-- (refactor chunk 8): typed calls, no yield-forever trap when nothing is
-- bound, and a test can register a pool in its own arena id without touching
-- the game's.
--
-- It holds references and forwards questions; it owns no block state. The
-- pool owns the blocks and decides what is eligible.
--
-- Today's askers are the boss: its hunger (Boss/Scripts/BossHunger), through
-- the pool's tow API (begin a tow, advance it each tick, cancel it), and its
-- spore lob (Boss/Scripts/BossSpores): spawn a spore, remove it, clear them.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)

local pools: { [string]: BlockSpawner.BlockSpawner } = {}

local BlockPoolRegistry = {}

export type Tow = BlockSpawner.Tow
export type TowStep = BlockSpawner.TowStep

function BlockPoolRegistry.register(arenaId: string, pool: BlockSpawner.BlockSpawner)
	pools[arenaId] = pool
end

-- Forget `arenaId`'s pool, but only if it is still `pool`: a test that
-- registered over a real arena id must not unregister whoever came after.
function BlockPoolRegistry.unregister(arenaId: string, pool: BlockSpawner.BlockSpawner)
	if pools[arenaId] == pool then
		pools[arenaId] = nil
	end
end

-- Start towing the nearest eligible block within `radius` (horizontal) of
-- `point` in `arenaId`'s pool. nil when the arena has no pool or nothing
-- eligible is in range.
function BlockPoolRegistry.beginTow(arenaId: string, point: Vector3, radius: number): Tow?
	local pool = pools[arenaId]
	if pool == nil then
		return nil
	end
	return pool:beginTow(point, radius)
end

-- One tick of a tow begun in `arenaId`. "gone" when the arena has no pool
-- (the block went with it).
function BlockPoolRegistry.advanceTow(
	arenaId: string,
	block: Model,
	target: Vector3,
	speed: number,
	reach: number,
	dt: number
): TowStep
	local pool = pools[arenaId]
	if pool == nil then
		return "gone"
	end
	return pool:advanceTow(block, target, speed, reach, dt)
end

-- End a tow by removing the block.
function BlockPoolRegistry.cancelTow(arenaId: string, block: Model)
	local pool = pools[arenaId]
	if pool ~= nil then
		pool:cancelTow(block)
	end
end

-- Spawns a spore (a timed, marked, poppable block; see BlockSpawner.spawnSpore)
-- at `position` in `arenaId`'s pool, with a fuse of `fuseSec`. nil when the
-- arena has no pool.
function BlockPoolRegistry.spawnSpore(
	arenaId: string,
	letter: string,
	color: string,
	position: Vector3,
	fuseSec: number
): Model?
	local pool = pools[arenaId]
	if pool == nil then
		return nil
	end
	return pool:spawnSpore(letter, color, position, fuseSec)
end

-- Removes one spore (it burst). False when the arena has no pool or the block
-- is not one of its live spores.
function BlockPoolRegistry.removeSpore(arenaId: string, block: Model): boolean
	local pool = pools[arenaId]
	if pool == nil then
		return false
	end
	return pool:removeSpore(block)
end

-- Removes every live spore of `arenaId`; returns how many.
function BlockPoolRegistry.clearSpores(arenaId: string): number
	local pool = pools[arenaId]
	if pool == nil then
		return 0
	end
	return pool:clearSpores()
end

return BlockPoolRegistry
