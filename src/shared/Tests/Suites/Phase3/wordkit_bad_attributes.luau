--!strict

----------------------------------------------------------------------
-- wordkit_bad_attributes
----------------------------------------------------------------------
-- Bad kit authoring degrades to something that works and says so, naming
-- the part:
--   - an unsupported WordKit length warns and falls back to the nearest
--     supported length (7 -> 6, 3 -> 5), so the kit still holds a word;
--   - BlockQuota and LetterTable on a kit volume are ignored with a warning
--     (the Premium table has no vowels, so honouring it could not spell);
--   - a kit that is too short for its letters to sit a block apart warns
--     ONCE, across any number of rolls, and a roomy one never warns.
-- Warnings are read off LogService, since the pool logs through Logger.
----------------------------------------------------------------------

local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local wordKitFixture = require(ReplicatedStorage.Shared.Tests.Helpers.wordKitFixture)

local TEST_ARENA_ID = "TestKitBadAttrs"
local TOO_LONG = 7
local TOO_SHORT = 3
local NEAREST_TO_TOO_LONG = 6
local NEAREST_TO_TOO_SHORT = 5
local QUOTA_ON_A_KIT = 2
-- Too short for six letters a block apart (the fixture's spacing is 10).
local CRAMPED_ROW_STUDS = 20
local CRAMPED_THICKNESS = 6
local ROLLS = 4
-- LogService delivers MessageOut on a later step.
local LOG_SETTLE_SEC = 0.1

type Ctx = {
	kit: wordKitFixture.Fixture?,
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
	name = "wordkit_bad_attributes",

	setup = function(ctx: Ctx)
		ctx.kit = wordKitFixture.new(TEST_ARENA_ID)
		ctx.warnings = {}
		ctx.connection = LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
			if messageType == Enum.MessageType.MessageWarning then
				table.insert(ctx.warnings, message)
			end
		end)
	end,

	run = function(ctx: Ctx)
		local kit = ctx.kit :: wordKitFixture.Fixture

		-- Unsupported lengths, and quota/table ignored, on three volumes in one pool.
		local pool = kit:pool({ boxes = {
			kit:kitBox({ wordKit = TOO_LONG, label = "TooLongKit" }),
			kit:kitBox({ wordKit = TOO_SHORT, label = "TooShortKit" }),
			kit:kitBox({ quota = QUOTA_ON_A_KIT, letterTable = LetterTables.PREMIUM, label = "QuotaKit" }),
		} })
		local expected = NEAREST_TO_TOO_LONG + NEAREST_TO_TOO_SHORT + wordKitFixture.KIT_WORD_LENGTH
		if pool:getTargetCount() ~= expected or pool:getQuotaTotal() ~= 0 then
			ctx.failure = string.format(
				"target %d / quota %d, expected %d / 0 (nearest lengths, quota ignored)",
				pool:getTargetCount(), pool:getQuotaTotal(), expected
			)
			return
		end
		pool:start()
		if #pool:getActiveBlocks() ~= expected then
			ctx.failure = string.format("%d live blocks, expected %d", #pool:getActiveBlocks(), expected)
			return
		end
		-- All three kits hold a word (the Premium table, honoured, would
		-- have left the QuotaKit with no vowels).
		if #pool:getKitWords() ~= 3 then
			ctx.failure = string.format("%d kits report a word, expected 3", #pool:getKitWords())
			return
		end

		-- Cramped vs roomy rows.
		local crampedBox = kit:kitBox({
			size = Vector3.new(CRAMPED_ROW_STUDS, CRAMPED_THICKNESS, CRAMPED_THICKNESS),
			wordKit = NEAREST_TO_TOO_LONG,
			label = "CrampedKit",
		})
		local roomyBox = kit:kitBox({ label = "RoomyKit" })
		local rowPool = kit:pool({ boxes = { crampedBox, roomyBox } })
		rowPool:start()
		for _ = 1, ROLLS do
			rowPool:rerollKits()
		end
		task.wait(LOG_SETTLE_SEC)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		local checks = {
			{ "TooLongKit", 1 },
			{ "TooShortKit", 1 },
			{ "QuotaKit", 2 }, -- BlockQuota and LetterTable are both ignored
			{ "CrampedKit", 1 },
			{ "RoomyKit", 0 },
		}
		for _, check in checks do
			local label, wanted = check[1] :: string, check[2] :: number
			local got = warningsNaming(ctx, label)
			if got ~= wanted then
				return false, string.format("%s: %d warning(s) naming it, expected %d", label, got, wanted)
			end
		end
		return true, "bad length -> nearest, quota/table ignored with a warning, spacing warns once and only when cramped"
	end,

	teardown = function(ctx: Ctx)
		if ctx.connection then
			ctx.connection:Disconnect()
		end
		if ctx.kit then
			ctx.kit:destroy()
		end
	end,
}
