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
-- It holds references and forwards one question; it owns no block state. The
-- pool owns the blocks and decides what is eligible.
--
-- Today's only asker is the boss's hunger (Boss/Scripts/BossHunger).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)

local pools: { [string]: BlockSpawner.BlockSpawner } = {}

local BlockPoolRegistry = {}

export type TakenBlock = BlockSpawner.TakenBlock

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

-- Take the nearest eligible block within `radius` of `point` out of `arenaId`'s
-- pool, through the pool's normal removal path. nil when the arena has no pool
-- or nothing eligible is in range.
function BlockPoolRegistry.takeNearestEligible(arenaId: string, point: Vector3, radius: number): TakenBlock?
	local pool = pools[arenaId]
	if pool == nil then
		return nil
	end
	return pool:takeNearestEligible(point, radius)
end

return BlockPoolRegistry
