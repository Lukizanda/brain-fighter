--!strict

----------------------------------------------------------------------
-- fossil_publish_roll
----------------------------------------------------------------------
-- A wall with `FossilTable` holds one letter from THAT table, published as
-- FossilLetter / FossilColor:
--   - walls present when the watcher starts are published at start-up; a
--     wall made (and given its table) afterwards is picked up too;
--   - Common / Premium / Standard rolls stay inside their table across many
--     rounds; Wildcard is the wildcard letter in the wildcard colour;
--   - a wall with no FossilTable gets neither attribute;
--   - the colour is a spell colour (or the wildcard's gold).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.Core.Colors)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)
local fossilFixture = require(ReplicatedStorage.Shared.Tests.Helpers.fossilFixture)

local TEST_ARENA = "TestFossilPublish"
local ROUNDS = 12

type Ctx = {
	fix: fossilFixture.Fixture?,
	failure: string?,
}

local function inList(list: { string }, value: any): boolean
	return table.find(list, value) ~= nil
end

return {
	name = "fossil_publish_roll",

	setup = function(ctx: Ctx)
		ctx.fix = fossilFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fix = ctx.fix :: fossilFixture.Fixture

		local pool = fix:pool()
		local wallsByTable: { [string]: BasePart } = {}
		for _, tableName in LetterTables.names() do
			wallsByTable[tableName] = fix:fossilWall("Wall" .. tableName, tableName)
		end
		local plain = fix:fossilWall("PlainWall", nil)

		local watcher = fix:watcher({ [TEST_ARENA] = pool })

		local function check(label: string): boolean
			for tableName, wall in wallsByTable do
				local letter, color = fix:publishedLetter(wall), fix:publishedColor(wall)
				if type(letter) ~= "string" or type(color) ~= "string" then
					ctx.failure = string.format("%s: %s wall published letter %s colour %s", label, tableName, tostring(letter), tostring(color))
					return false
				end
				if not inList(LetterTables.members(tableName), letter) then
					ctx.failure = string.format("%s: %s wall holds '%s', not in that table", label, tableName, letter)
					return false
				end
				local colourOk = if Wildcard.isWildcard(letter)
					then color == Wildcard.COLOR
					else inList(Colors.SPELL_COLORS :: { string }, color)
				if not colourOk then
					ctx.failure = string.format("%s: %s wall holds '%s' in '%s'", label, tableName, letter, color)
					return false
				end
			end
			if fix:publishedLetter(plain) ~= nil or fix:publishedColor(plain) ~= nil then
				ctx.failure = label .. ": a wall with no FossilTable published a fossil"
				return false
			end
			return true
		end

		-- Start-up.
		if not check("start-up") then
			return
		end
		if watcher:fossilCount() ~= #LetterTables.names() then
			ctx.failure = string.format("watcher holds %d fossils, expected %d", watcher:fossilCount(), #LetterTables.names())
			return
		end
		local wildWall = wallsByTable[LetterTables.WILDCARD]
		if fix:publishedLetter(wildWall) ~= Wildcard.CHAR then
			ctx.failure = "the Wildcard table did not roll a wildcard"
			return
		end

		-- A wall made after the watcher started.
		local late = fix:fossilWall("LateWall", LetterTables.PREMIUM)
		if not inList(LetterTables.members(LetterTables.PREMIUM), fix:publishedLetter(late)) then
			ctx.failure = "a wall made after start-up did not get a Premium letter"
			return
		end

		-- Many rounds: each re-roll stays in its table.
		for round = 1, ROUNDS do
			fix.walls:roundStarted(TEST_ARENA)
			if not check("round " .. round) then
				return
			end
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, "each table's wall holds a letter of that table (wildcards gold), start-up, late walls and re-rolls; plain walls hold none"
	end,

	teardown = function(ctx: Ctx)
		if ctx.fix then
			ctx.fix:destroy()
		end
	end,
}
