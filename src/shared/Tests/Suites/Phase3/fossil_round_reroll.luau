--!strict

----------------------------------------------------------------------
-- fossil_round_reroll
----------------------------------------------------------------------
-- A new round (the real RoundStarted event, handled by the real
-- BreakableWallService and the watcher):
--   - removes a fossil block left over from last round;
--   - re-rolls the wall's letter (over many rounds a Premium wall does not
--     hold one letter forever) and lets the reset wall pay again when it
--     next breaks;
--   - touches only that arena: another arena's fossil block survives;
--   - destroy() of the watcher removes what it freed and the published
--     attributes.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local FossilConstants = require(ReplicatedStorage.Shared.BlockSpawner.FossilConstants)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local fossilFixture = require(ReplicatedStorage.Shared.Tests.Helpers.fossilFixture)

local TEST_ARENA = "TestFossilRound"
local OTHER_ARENA = "TestFossilRoundOther"
local LONG_LIFETIME_SEC = 60
-- Premium has about a dozen letters; twelve rolls that all match would be
-- a (1/10)^11-ish event.
local ROUNDS = 12
local MIN_DISTINCT_LETTERS = 2

type Ctx = {
	fix: fossilFixture.Fixture?,
	failure: string?,
}

return {
	name = "fossil_round_reroll",

	setup = function(ctx: Ctx)
		ctx.fix = fossilFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fix = ctx.fix :: fossilFixture.Fixture

		local pool = fix:pool()
		local otherPool = fix:pool(OTHER_ARENA)
		local watcher = fix:watcher({ [TEST_ARENA] = pool, [OTHER_ARENA] = otherPool }, LONG_LIFETIME_SEC)

		local wall = fix:fossilWall("RoundWall", LetterTables.PREMIUM)
		local otherBlock = otherPool:spawnTimedBlock("Q", "red", CFrame.new(fix:expectedPosition(wall)), LONG_LIFETIME_SEC)
		if otherBlock == nil then
			ctx.failure = "could not spawn the other arena's timed block"
			return
		end

		-- Break it: a leftover block exists.
		fix:breakWall(wall)
		local leftover = pool:getTimedBlocks()
		if #leftover ~= 1 then
			ctx.failure = string.format("%d blocks after the first break, expected 1", #leftover)
			return
		end

		-- A new round clears it, resets the wall, and a new break pays again.
		fix.walls:roundStarted(TEST_ARENA)
		if leftover[1].Parent ~= nil or #pool:getTimedBlocks() ~= 0 then
			ctx.failure = "a fossil block survived the next RoundStarted"
			return
		end
		if otherBlock.Parent == nil then
			ctx.failure = "a round in one arena removed another arena's fossil block"
			return
		end
		if fix.walls:stateOf(wall) ~= C.State.Intact then
			ctx.failure = "the wall was not reset by the round"
			return
		end
		if type(fix:publishedLetter(wall)) ~= "string" then
			ctx.failure = "the wall holds no letter after the round"
			return
		end
		fix:breakWall(wall)
		if #pool:getTimedBlocks() ~= 1 then
			ctx.failure = string.format("the wall freed %d blocks on its next-round break, expected 1", #pool:getTimedBlocks())
			return
		end

		-- Re-rolls vary.
		local seen: { [string]: boolean } = {}
		local distinct = 0
		for _ = 1, ROUNDS do
			fix.walls:roundStarted(TEST_ARENA)
			local letter = fix:publishedLetter(wall)
			if type(letter) == "string" and not seen[letter] then
				seen[letter] = true
				distinct += 1
			end
		end
		if distinct < MIN_DISTINCT_LETTERS then
			ctx.failure = string.format("%d rounds produced %d distinct letter(s)", ROUNDS, distinct)
			return
		end

		-- destroy() removes what the watcher freed and un-publishes.
		fix:breakWall(wall)
		local last = pool:getTimedBlocks()
		if #last ~= 1 then
			ctx.failure = "expected one block before destroying the watcher"
			return
		end
		watcher:destroy()
		if last[1].Parent ~= nil then
			ctx.failure = "destroy() left a freed block standing"
			return
		end
		if wall:GetAttribute(FossilConstants.LETTER_ATTRIBUTE) ~= nil then
			ctx.failure = "destroy() left FossilLetter on the wall"
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, "a new round clears the leftover block, re-rolls the letter and lets the wall pay again; other arenas untouched; destroy cleans up"
	end,

	teardown = function(ctx: Ctx)
		if ctx.fix then
			ctx.fix:destroy()
		end
	end,
}
