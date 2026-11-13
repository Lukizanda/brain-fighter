--!strict

----------------------------------------------------------------------
-- fossil_other_arena
----------------------------------------------------------------------
-- A FossilWatcher leaves alone every wall whose arena it has no pool for.
-- Several watchers share one scene (the game's own and each test's), and a
-- watcher that cleared "walls it cannot serve" wiped the letters another
-- watcher had published: the bug this pins, found when the boss island's
-- rocks first carried FossilTable.
--   - a second watcher with a pool for a different arena starts, sees a
--     round start in its own arena, and is destroyed: the first watcher's
--     wall keeps the letter and colour it published throughout;
--   - the second watcher holds no fossil for that wall.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local fossilFixture = require(ReplicatedStorage.Shared.Tests.Helpers.fossilFixture)

local TEST_ARENA = "TestFossilOwner"
local OTHER_ARENA = "TestFossilStranger"

type Ctx = {
	fix: fossilFixture.Fixture?,
	failure: string?,
}

return {
	name = "fossil_other_arena",

	setup = function(ctx: Ctx)
		ctx.fix = fossilFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fix = ctx.fix :: fossilFixture.Fixture

		local pool = fix:pool()
		local wall = fix:fossilWall("OwnedWall", LetterTables.STANDARD)
		fix:watcher({ [TEST_ARENA] = pool })

		local letter, color = fix:publishedLetter(wall), fix:publishedColor(wall)
		if type(letter) ~= "string" or type(color) ~= "string" then
			ctx.failure = "the owning watcher published nothing"
			return
		end

		local function unchanged(label: string): boolean
			if fix:publishedLetter(wall) ~= letter or fix:publishedColor(wall) ~= color then
				ctx.failure = string.format(
					"%s: the wall shows %s/%s, the owner published %s/%s",
					label, tostring(fix:publishedLetter(wall)), tostring(fix:publishedColor(wall)), letter, color
				)
				return false
			end
			return true
		end

		local otherPool = fix:pool(OTHER_ARENA)
		local stranger = fix:watcher({ [OTHER_ARENA] = otherPool })
		if not unchanged("after another arena's watcher started") then
			return
		end
		if stranger:fossilCount() ~= 0 then
			ctx.failure = string.format("the other arena's watcher holds %d fossil(s), expected 0", stranger:fossilCount())
			return
		end

		fix.walls:roundStarted(OTHER_ARENA)
		if not unchanged("after the other arena's round started") then
			return
		end

		stranger:destroy()
		if not unchanged("after the other arena's watcher was destroyed") then
			return
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, "a watcher for another arena starts, sees a round and is destroyed without touching the wall"
	end,

	teardown = function(ctx: Ctx)
		if ctx.fix then
			ctx.fix:destroy()
		end
	end,
}
