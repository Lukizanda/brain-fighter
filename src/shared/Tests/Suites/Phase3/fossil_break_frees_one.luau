--!strict

----------------------------------------------------------------------
-- fossil_break_frees_one
----------------------------------------------------------------------
-- Boss fire breaks a fossil wall (REAL BreakableWallService); the watcher
-- frees its letter:
--   - cracking the wall (not breaking it) frees nothing;
--   - breaking it yields exactly one LetterBlock of the published letter and
--     colour, at the wall's base + HEIGHT_ABOVE_BASE_STUDS, stamped with the
--     wall's arena (the stamp ConsumeBlock checks) and not in any other;
--   - the block is outside the pool: target count and active set unchanged,
--     and popping it does not refill;
--   - a second break in the same round (state poked back to intact and to
--     broken again) pays nothing, and neither does more fire on a broken wall;
--   - the height clears the floor by the block's tumble radius.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local FossilConstants = require(ReplicatedStorage.Shared.BlockSpawner.FossilConstants)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local fossilFixture = require(ReplicatedStorage.Shared.Tests.Helpers.fossilFixture)

local TEST_ARENA = "TestFossilBreak"
local OTHER_ARENA = "TestFossilBreakOther"
local LONG_LIFETIME_SEC = 60
local THREE_HEALTH = 3
local POSITION_TOLERANCE_STUDS = 0.05
local HALF = 0.5

type Ctx = {
	fix: fossilFixture.Fixture?,
	failure: string?,
}

return {
	name = "fossil_break_frees_one",

	setup = function(ctx: Ctx)
		ctx.fix = fossilFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fix = ctx.fix :: fossilFixture.Fixture

		if FossilConstants.HEIGHT_ABOVE_BASE_STUDS <= LetterBlocks.tumbleDiameter() * HALF then
			ctx.failure = string.format(
				"fossil height %.1f does not clear the floor by the tumble radius %.1f",
				FossilConstants.HEIGHT_ABOVE_BASE_STUDS, LetterBlocks.tumbleDiameter() * HALF
			)
			return
		end

		local pool = fix:pool()
		local otherPool = fix:pool(OTHER_ARENA)
		fix:watcher({ [TEST_ARENA] = pool, [OTHER_ARENA] = otherPool }, LONG_LIFETIME_SEC)

		local target = pool:getTargetCount()
		local activeBefore = #pool:getActiveBlocks()
		local otherActiveBefore = #otherPool:getActiveBlocks()

		-- Cracked is not broken.
		local wall = fix:fossilWall("StagedWall", LetterTables.STANDARD, { maxHealth = THREE_HEALTH })
		local letter, color = fix:publishedLetter(wall), fix:publishedColor(wall)
		fix:breakWall(wall, 1)
		if fix.walls:stateOf(wall) ~= C.State.Cracked then
			ctx.failure = "expected the 3-health wall cracked after one hit, got " .. tostring(fix.walls:stateOf(wall))
			return
		end
		if #pool:getTimedBlocks() ~= 0 then
			ctx.failure = "a cracked wall freed its letter"
			return
		end

		-- Broken pays exactly one.
		fix:breakWall(wall, THREE_HEALTH)
		if fix.walls:stateOf(wall) ~= C.State.Broken then
			ctx.failure = "the wall did not break, state " .. tostring(fix.walls:stateOf(wall))
			return
		end
		local freed = pool:getTimedBlocks()
		if #freed ~= 1 or #otherPool:getTimedBlocks() ~= 0 then
			ctx.failure = string.format("%d block(s) freed in the wall's arena, %d in the other; expected 1 and 0", #freed, #otherPool:getTimedBlocks())
			return
		end
		local block = freed[1]
		if fix:letterOf(block) ~= letter or fix:colorOf(block) ~= color then
			ctx.failure = string.format(
				"freed block is %s/%s, the wall published %s/%s",
				tostring(fix:letterOf(block)), tostring(fix:colorOf(block)), tostring(letter), tostring(color)
			)
			return
		end
		if not CollectionService:HasTag(block, LetterBlocks.TAG) then
			ctx.failure = "the freed block is not a LetterBlock"
			return
		end
		if block:GetAttribute(Arena.ID_ATTRIBUTE) ~= TEST_ARENA then
			ctx.failure = "the freed block is not stamped with the wall's arena: " .. tostring(block:GetAttribute(Arena.ID_ATTRIBUTE))
			return
		end
		local off = (block:GetPivot().Position - fix:expectedPosition(wall)).Magnitude
		if off > POSITION_TOLERANCE_STUDS then
			ctx.failure = string.format("the freed block is %.2f studs from its expected spot", off)
			return
		end

		-- Outside the pool.
		if pool:getTargetCount() ~= target or #pool:getActiveBlocks() ~= activeBefore
			or #otherPool:getActiveBlocks() ~= otherActiveBefore then
			ctx.failure = "the freed block changed a pool's target or active set"
			return
		end
		if table.find(pool:getActiveBlocks(), block) ~= nil then
			ctx.failure = "the freed block is in the pool's active set"
			return
		end

		-- One break pays once: poke the state off and back on, and fire at it.
		wall:SetAttribute(C.Published.State, C.State.Intact)
		fix.walls:settle()
		wall:SetAttribute(C.Published.State, C.State.Broken)
		fix.walls:settle()
		fix:breakWall(wall, 1)
		if #pool:getTimedBlocks() ~= 1 or table.find(pool:getTimedBlocks(), block) == nil then
			ctx.failure = "a second break in the same round freed another block"
			return
		end

		-- Popped (consumed): gone, not refilled, and the repeated break still pays nothing.
		block:Destroy()
		fix.walls:settle()
		if #pool:getTimedBlocks() ~= 0 or #pool:getActiveBlocks() ~= activeBefore then
			ctx.failure = string.format("after the pop: %d timed, %d active (expected 0 and %d)", #pool:getTimedBlocks(), #pool:getActiveBlocks(), activeBefore)
			return
		end
		wall:SetAttribute(C.Published.State, C.State.Intact)
		fix.walls:settle()
		wall:SetAttribute(C.Published.State, C.State.Broken)
		fix.walls:settle()
		if #pool:getTimedBlocks() ~= 0 then
			ctx.failure = "a repeat break after the pop freed another block"
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, "crack frees nothing; break frees one block of the published letter at the wall, outside the pool; a repeat break pays nothing"
	end,

	teardown = function(ctx: Ctx)
		if ctx.fix then
			ctx.fix:destroy()
		end
	end,
}
