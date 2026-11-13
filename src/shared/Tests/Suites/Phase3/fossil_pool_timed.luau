--!strict

----------------------------------------------------------------------
-- fossil_pool_timed
----------------------------------------------------------------------
-- The pool's timed-block method on its own (no watcher, no walls):
--   - a pool that never spawns one reports none and its counts are as ever;
--   - a timed block is stamped with the arena and tagged, but is in no
--     count: target count and active set unchanged, and popping it does not
--     refill;
--   - rerollAll() and disable() leave it standing; clearTimedBlocks() and
--     destroy() remove it; a destroyed pool refuses a new one.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local fossilFixture = require(ReplicatedStorage.Shared.Tests.Helpers.fossilFixture)

local TEST_ARENA = "TestFossilPool"
local LONG_LIFETIME_SEC = 60
local SETTLE_SEC = 0.2
local HERE = CFrame.new(0, 5400, 0)

type Ctx = {
	fix: fossilFixture.Fixture?,
	failure: string?,
}

return {
	name = "fossil_pool_timed",

	setup = function(ctx: Ctx)
		ctx.fix = fossilFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fix = ctx.fix :: fossilFixture.Fixture
		local pool = fix:pool()

		-- No fossils: as before.
		if pool:getTargetCount() ~= fossilFixture.POOL_QUOTA or #pool:getActiveBlocks() ~= fossilFixture.POOL_QUOTA
			or #pool:getTimedBlocks() ~= 0 then
			ctx.failure = "a pool with no fossils is not the plain pool"
			return
		end

		local block = pool:spawnTimedBlock("Q", "red", HERE, LONG_LIFETIME_SEC)
		if block == nil then
			ctx.failure = "spawnTimedBlock returned nil"
			return
		end
		if block:GetAttribute(Arena.ID_ATTRIBUTE) ~= TEST_ARENA or not CollectionService:HasTag(block, LetterBlocks.TAG)
			or block:GetAttribute(LetterBlocks.LETTER_ATTRIBUTE) ~= "Q" then
			ctx.failure = "the timed block is not a stamped, tagged Q"
			return
		end
		if pool:getTargetCount() ~= fossilFixture.POOL_QUOTA or #pool:getActiveBlocks() ~= fossilFixture.POOL_QUOTA
			or #pool:getTimedBlocks() ~= 1 then
			ctx.failure = "the timed block changed a count"
			return
		end

		-- rerollAll leaves it; the pool's own blocks come back.
		pool:rerollAll()
		task.wait(SETTLE_SEC)
		if block.Parent == nil or #pool:getActiveBlocks() ~= fossilFixture.POOL_QUOTA then
			ctx.failure = string.format("rerollAll: timed block alive %s, %d active blocks", tostring(block.Parent ~= nil), #pool:getActiveBlocks())
			return
		end

		-- Popping it does not refill.
		block:Destroy()
		task.wait(SETTLE_SEC)
		if #pool:getTimedBlocks() ~= 0 or #pool:getActiveBlocks() ~= fossilFixture.POOL_QUOTA then
			ctx.failure = "popping a timed block changed the pool"
			return
		end

		-- disable leaves it; clearTimedBlocks removes it.
		local second = pool:spawnTimedBlock("Z", "blue", HERE, LONG_LIFETIME_SEC) :: Model
		pool:disable()
		if second.Parent == nil then
			ctx.failure = "disable() removed the timed block"
			return
		end
		pool:start()
		if pool:clearTimedBlocks() ~= 1 or second.Parent ~= nil then
			ctx.failure = "clearTimedBlocks() did not remove the block"
			return
		end

		-- destroy removes it, and a destroyed pool refuses a new one.
		local third = pool:spawnTimedBlock("X", "green", HERE, LONG_LIFETIME_SEC) :: Model
		pool:destroy()
		if third.Parent ~= nil then
			ctx.failure = "destroy() left the timed block standing"
			return
		end
		if pool:spawnTimedBlock("A", "red", HERE, LONG_LIFETIME_SEC) ~= nil then
			ctx.failure = "a destroyed pool spawned a timed block"
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, "timed blocks are stamped and poppable but in no count, never refilled; rerollAll/disable keep them; clear/destroy remove them"
	end,

	teardown = function(ctx: Ctx)
		if ctx.fix then
			ctx.fix:destroy()
		end
	end,
}
