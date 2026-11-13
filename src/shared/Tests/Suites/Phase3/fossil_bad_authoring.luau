--!strict

----------------------------------------------------------------------
-- fossil_bad_authoring
----------------------------------------------------------------------
-- Bad fossil authoring degrades to "no fossil" and says so ONCE, naming the
-- part (warnings read off LogService):
--   - a regenerating wall (RegenSec > 0) with FossilTable, whichever
--     attribute was set first;
--   - an unknown table name;
-- and neither publishes FossilLetter / FossilColor nor frees a block when it
-- breaks, across several rounds. A good wall beside them never warns.
----------------------------------------------------------------------

local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local FossilConstants = require(ReplicatedStorage.Shared.BlockSpawner.FossilConstants)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local fossilFixture = require(ReplicatedStorage.Shared.Tests.Helpers.fossilFixture)

local TEST_ARENA = "TestFossilBad"
local REGEN_SEC = 30
local ROUNDS = 3
local LOG_SETTLE_SEC = 0.1

type Ctx = {
	fix: fossilFixture.Fixture?,
	warnings: { string },
	connection: RBXScriptConnection?,
	failure: string?,
}

local function warningsNaming(ctx: Ctx, label: string): number
	local count = 0
	for _, message in ctx.warnings do
		if string.find(message, label, 1, true) then
			count += 1
		end
	end
	return count
end

return {
	name = "fossil_bad_authoring",

	setup = function(ctx: Ctx)
		ctx.fix = fossilFixture.new(TEST_ARENA)
		ctx.warnings = {}
		ctx.connection = LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
			if messageType == Enum.MessageType.MessageWarning then
				table.insert(ctx.warnings, message)
			end
		end)
	end,

	run = function(ctx: Ctx)
		local fix = ctx.fix :: fossilFixture.Fixture
		local pool = fix:pool()
		fix:watcher({ [TEST_ARENA] = pool })

		local regenWall = fix:fossilWall("RegenFossilWall", LetterTables.STANDARD, { regenSec = REGEN_SEC })
		local unknownWall = fix:fossilWall("UnknownFossilWall", "NoSuchTable")
		local goodWall = fix:fossilWall("GoodFossilWall", LetterTables.COMMON)
		-- Valid first, then made a regenerating wall.
		local switchedWall = fix:fossilWall("SwitchedFossilWall", LetterTables.STANDARD)
		if type(fix:publishedLetter(switchedWall)) ~= "string" then
			ctx.failure = "the late-regen wall held no letter before it regenerated"
			return
		end
		switchedWall:SetAttribute(C.Authored.RegenSec, REGEN_SEC)
		fix.walls:settle()

		for _ = 1, ROUNDS do
			fix.walls:roundStarted(TEST_ARENA)
		end

		for _, wall in { regenWall, unknownWall, switchedWall } do
			if fix:publishedLetter(wall) ~= nil or fix:publishedColor(wall) ~= nil then
				ctx.failure = wall.Name .. " published a fossil it should not hold"
				return
			end
		end
		if type(fix:publishedLetter(goodWall)) ~= "string" then
			ctx.failure = "the good wall holds no fossil"
			return
		end

		-- None of the bad ones frees anything when broken.
		for _, wall in { regenWall, unknownWall, switchedWall } do
			fix:breakWall(wall)
			if fix.walls:stateOf(wall) ~= C.State.Broken then
				ctx.failure = wall.Name .. " did not break"
				return
			end
		end
		if #pool:getTimedBlocks() ~= 0 then
			ctx.failure = string.format("%d block(s) freed by walls that hold no fossil", #pool:getTimedBlocks())
			return
		end
		task.wait(LOG_SETTLE_SEC)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		local checks = {
			{ "RegenFossilWall", 1 },
			{ "UnknownFossilWall", 1 },
			{ "SwitchedFossilWall", 1 },
			{ "GoodFossilWall", 0 },
		}
		for _, check in checks do
			local label, wanted = check[1] :: string, check[2] :: number
			local got = warningsNaming(ctx, label)
			if got ~= wanted then
				return false, string.format("%s: %d warning(s) naming it, expected %d", label, got, wanted)
			end
		end
		return true, string.format("regen walls and unknown tables warn once, hold no %s and free nothing; a good wall never warns", FossilConstants.LETTER_ATTRIBUTE)
	end,

	teardown = function(ctx: Ctx)
		if ctx.connection then
			ctx.connection:Disconnect()
		end
		if ctx.fix then
			ctx.fix:destroy()
		end
	end,
}
