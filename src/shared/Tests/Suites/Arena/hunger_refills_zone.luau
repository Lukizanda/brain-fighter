--!strict

----------------------------------------------------------------------
-- hunger_refills_zone — an eaten block is replaced as after a pop
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on a stand-in boss, ticked by hand, against a
-- pool with a real respawn delay. The eaten block's zone is empty at once,
-- still empty before the delay has passed, and refilled (in that zone, and the
-- pool's counts back at target) after it.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossHunger = require(ServerScriptService.Server.Boss.Scripts.BossHunger)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local ARENA_ID = "HungerRefill"
local INTERVAL_SEC = 5
local RADIUS_STUDS = 25
local NEAR_OFFSET = Vector3.new(8, 0, 0)
local BEYOND_OFFSET = Vector3.new(40, 0, 0)
local RESPAWN_SEC = 0.5
local TOO_EARLY_SEC = 0.15
local REFILL_TIMEOUT_SEC = 2
local POLL_SEC = 0.05
local ZONES = 2

return {
	name = "hunger_refills_zone",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss()
		local nearAt = root.Position + NEAR_OFFSET
		local beyondAt = root.Position + BEYOND_OFFSET
		local pool = hf:pool({ hf:zone(nearAt), hf:zone(beyondAt) }, RESPAWN_SEC)
		local hunger = BossHunger.new(boss, humanoid, root, hungerFixture.spec(INTERVAL_SEC, RADIUS_STUDS, 0))
		if not hunger then
			return
		end
		ctx.enabled = true
		ctx.target = pool:getTargetCount()
		ctx.before = #pool:getActiveBlocks()

		-- The pool hears a removal one frame after Destroy (as for a pop), so
		-- its counts are read after a yield; the respawn delay is far longer.
		hunger:tick(INTERVAL_SEC)
		task.wait()
		ctx.afterBite = #pool:getActiveBlocks()
		ctx.zoneEmptyAtOnce = hf:blockAt(pool, nearAt) == nil

		task.wait(TOO_EARLY_SEC)
		ctx.countTooEarly = #pool:getActiveBlocks()

		local waited = 0
		while waited < REFILL_TIMEOUT_SEC and hf:blockAt(pool, nearAt) == nil do
			task.wait(POLL_SEC)
			waited += POLL_SEC
		end
		ctx.refilledInZone = hf:blockAt(pool, nearAt) ~= nil
		ctx.after = #pool:getActiveBlocks()
		ctx.beyondKept = hf:blockAt(pool, beyondAt) ~= nil
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.enabled then
			return false, "BossHunger.new returned nil for a spec with eat values"
		end
		if ctx.target ~= ZONES or ctx.before ~= ZONES then
			return false, string.format(
				"fixture: pool target %s, holding %s, expected %d", tostring(ctx.target), tostring(ctx.before), ZONES
			)
		end
		if ctx.afterBite ~= ZONES - 1 or not ctx.zoneEmptyAtOnce then
			return false, string.format(
				"after the bite the pool held %s blocks (zone empty: %s), expected %d",
				tostring(ctx.afterBite), tostring(ctx.zoneEmptyAtOnce), ZONES - 1
			)
		end
		if ctx.countTooEarly ~= ZONES - 1 then
			return false, "the zone refilled before the respawn delay"
		end
		if not ctx.refilledInZone then
			return false, "the eaten block's zone was not refilled after the delay"
		end
		if ctx.after ~= ZONES or not ctx.beyondKept then
			return false, string.format("pool counts after the refill: %s, expected %d", tostring(ctx.after), ZONES)
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
