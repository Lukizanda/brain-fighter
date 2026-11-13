--!strict

----------------------------------------------------------------------
-- hunger_zero_fraction — a heal fraction of 0 still eats, and heals nothing
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on two stand-in bosses (fraction 0, and fraction
-- left out of the spec), ticked by hand. Each takes a block and neither
-- raises its health. Not covered: that no heal cue is sent (a VfxBroadcast
-- payload is not observable from the server; a client view is needed).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossHunger = require(ServerScriptService.Server.Boss.Scripts.BossHunger)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local ARENA_ID = "HungerZeroHeal"
local INTERVAL_SEC = 5
local RADIUS_STUDS = 25
local START_HEALTH = 400
local FIRST_OFFSET = Vector3.new(5, 0, 0)
local SECOND_OFFSET = Vector3.new(0, 0, 8)
local NEVER_REFILL_SEC = 600

return {
	name = "hunger_zero_fraction",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local bossA, humanoidA, rootA = hf:fakeBoss(nil, START_HEALTH)
		local bossB, humanoidB, rootB = hf:fakeBoss(nil, START_HEALTH)
		local firstAt = rootA.Position + FIRST_OFFSET
		local secondAt = rootA.Position + SECOND_OFFSET
		local pool = hf:pool({ hf:zone(firstAt), hf:zone(secondAt) }, NEVER_REFILL_SEC)
		local zero = BossHunger.new(bossA, humanoidA, rootA, hungerFixture.spec(INTERVAL_SEC, RADIUS_STUDS, 0))
		local absent = BossHunger.new(bossB, humanoidB, rootB, hungerFixture.spec(INTERVAL_SEC, RADIUS_STUDS, nil))
		ctx.enabled = zero ~= nil and absent ~= nil
		if not zero or not absent then
			return
		end

		-- The pool hears a removal one frame after Destroy (as for a pop), so
		-- its counts are read after a yield.
		zero:tick(INTERVAL_SEC)
		task.wait()
		ctx.activeAfterZero = #pool:getActiveBlocks()
		ctx.healthAfterZero = humanoidA.Health

		absent:tick(INTERVAL_SEC)
		task.wait()
		ctx.activeAfterAbsent = #pool:getActiveBlocks()
		ctx.healthAfterAbsent = humanoidB.Health
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.enabled then
			return false, "a spec with a 0 or missing heal fraction was switched off (it must still eat)"
		end
		if ctx.activeAfterZero ~= 1 then
			return false, string.format("fraction 0 left %s blocks, expected 1 (it must eat one)", tostring(ctx.activeAfterZero))
		end
		if ctx.healthAfterZero ~= START_HEALTH then
			return false, "fraction 0 raised health"
		end
		if ctx.activeAfterAbsent ~= 0 then
			return false, string.format("a missing fraction left %s blocks, expected 0", tostring(ctx.activeAfterAbsent))
		end
		if ctx.healthAfterAbsent ~= START_HEALTH then
			return false, "a missing fraction raised health"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
