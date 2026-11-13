--!strict

----------------------------------------------------------------------
-- fossil_expiry
----------------------------------------------------------------------
-- A freed fossil block is removed after its lifetime (a short one through
-- the watcher's option, not a 20 s wait):
--   - it is there before the lifetime and gone after it, and the pool never
--     refills it;
--   - it carries FossilExpiresAt in server time, about now + lifetime;
--   - the shipped lifetime is the contract's 20 s.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FossilConstants = require(ReplicatedStorage.Shared.BlockSpawner.FossilConstants)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local fossilFixture = require(ReplicatedStorage.Shared.Tests.Helpers.fossilFixture)

local TEST_ARENA = "TestFossilExpiry"
local LIFETIME_SEC = 1
local SHIPPED_LIFETIME_SEC = 20
-- The expiry stamp is taken a frame or two after the break.
local EXPIRY_SLACK_SEC = 0.6
local PAST_EXPIRY_SEC = 1

type Ctx = {
	fix: fossilFixture.Fixture?,
	failure: string?,
}

return {
	name = "fossil_expiry",

	setup = function(ctx: Ctx)
		ctx.fix = fossilFixture.new(TEST_ARENA)
	end,

	run = function(ctx: Ctx)
		local fix = ctx.fix :: fossilFixture.Fixture

		if FossilConstants.LIFETIME_SEC ~= SHIPPED_LIFETIME_SEC then
			ctx.failure = string.format("shipped lifetime is %s, the contract says %d", tostring(FossilConstants.LIFETIME_SEC), SHIPPED_LIFETIME_SEC)
			return
		end

		local pool = fix:pool()
		fix:watcher({ [TEST_ARENA] = pool }, LIFETIME_SEC)
		local activeBefore = #pool:getActiveBlocks()
		local wall = fix:fossilWall("ExpiringWall", LetterTables.COMMON)

		local brokeAt = workspace:GetServerTimeNow()
		fix:breakWall(wall)
		local freed = pool:getTimedBlocks()
		if #freed ~= 1 then
			ctx.failure = string.format("%d blocks freed, expected 1", #freed)
			return
		end
		local expiresAt = freed[1]:GetAttribute(FossilConstants.EXPIRES_ATTRIBUTE)
		if type(expiresAt) ~= "number" then
			ctx.failure = "the freed block has no " .. FossilConstants.EXPIRES_ATTRIBUTE
			return
		end
		local expected = brokeAt + LIFETIME_SEC
		if expiresAt < expected - EXPIRY_SLACK_SEC or expiresAt > expected + EXPIRY_SLACK_SEC then
			ctx.failure = string.format("expiry %.2f, expected about %.2f (server time)", expiresAt, expected)
			return
		end

		-- Still there before the lifetime is up.
		task.wait(LIFETIME_SEC * 0.3)
		if freed[1].Parent == nil then
			ctx.failure = "the block was removed before its lifetime"
			return
		end

		-- Gone after it, and not refilled.
		task.wait(LIFETIME_SEC + PAST_EXPIRY_SEC)
		if freed[1].Parent ~= nil or #pool:getTimedBlocks() ~= 0 then
			ctx.failure = "the block outlived its lifetime"
			return
		end
		if #pool:getActiveBlocks() ~= activeBefore then
			ctx.failure = "the pool changed when the fossil expired"
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, "freed block lives its lifetime then goes, carries a server-time expiry, is never refilled; shipped lifetime 20 s"
	end,

	teardown = function(ctx: Ctx)
		if ctx.fix then
			ctx.fix:destroy()
		end
	end,
}
