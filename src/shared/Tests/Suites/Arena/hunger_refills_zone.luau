--!strict

----------------------------------------------------------------------
-- hunger_refills_zone — an eaten or popped letter's zone refills as after a pop
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on a stand-in boss, ticked by hand, against a
-- pool with a real respawn delay. While a letter is in tow its zone still
-- counts it (the pool does not refill early). Once it is EAten the zone is
-- empty at once, still empty before the delay has passed, and refilled (in
-- that zone, with the pool's counts back at target) after it. The same again
-- for a letter POPPED mid-tow (destroyed, the way a pop removes it).
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
local SLOW_PULL_SPEED = 0.01

local function waitForZone(hf: any, pool: any, at: Vector3): boolean
	local waited = 0
	while waited < REFILL_TIMEOUT_SEC and hf:blockAt(pool, at) == nil do
		task.wait(POLL_SEC)
		waited += POLL_SEC
	end
	return hf:blockAt(pool, at) ~= nil
end

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
		local fast = BossHunger.new(boss, humanoid, root, hungerFixture.spec(
			INTERVAL_SEC, RADIUS_STUDS, 0, hungerFixture.FAST_PULL_SPEED, hungerFixture.REACH_STUDS
		))
		local slow = BossHunger.new(boss, humanoid, root, hungerFixture.spec(
			INTERVAL_SEC, RADIUS_STUDS, 0, SLOW_PULL_SPEED, hungerFixture.REACH_STUDS
		))
		if not fast or not slow then
			return
		end
		ctx.enabled = true
		ctx.target = pool:getTargetCount()
		ctx.before = #pool:getActiveBlocks()

		-- In tow: the zone still holds it, nothing is refilled yet.
		slow:tick(INTERVAL_SEC)
		task.wait()
		ctx.inTowCount = #pool:getActiveBlocks()
		ctx.inTow = #hf:towed(pool) == 1

		-- Popped mid-tow: destroyed, as a pop removes it. (The slow object
		-- is dropped; the pool hears the removal a frame later, as for a pop.)
		local towed = hf:towed(pool)[1]
		if towed then
			towed:Destroy()
		end
		slow:destroy()
		task.wait()
		ctx.afterPop = #pool:getActiveBlocks()
		ctx.popZoneEmptyAtOnce = hf:blockAt(pool, nearAt) == nil
		ctx.popRefilled = waitForZone(hf, pool, nearAt)
		ctx.afterPopRefill = #pool:getActiveBlocks()

		-- Eaten on arrival.
		fast:tick(INTERVAL_SEC)
		fast:tick(INTERVAL_SEC)
		task.wait()
		ctx.afterBite = #pool:getActiveBlocks()
		ctx.zoneEmptyAtOnce = hf:blockAt(pool, nearAt) == nil
		task.wait(TOO_EARLY_SEC)
		ctx.countTooEarly = #pool:getActiveBlocks()
		ctx.refilledInZone = waitForZone(hf, pool, nearAt)
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
		if not ctx.inTow or ctx.inTowCount ~= ZONES then
			return false, string.format("a letter in tow: pool held %s blocks, expected %d", tostring(ctx.inTowCount), ZONES)
		end
		if ctx.afterPop ~= ZONES - 1 or not ctx.popZoneEmptyAtOnce then
			return false, string.format(
				"after the pop the pool held %s blocks (zone empty: %s), expected %d",
				tostring(ctx.afterPop), tostring(ctx.popZoneEmptyAtOnce), ZONES - 1
			)
		end
		if not ctx.popRefilled or ctx.afterPopRefill ~= ZONES then
			return false, "the popped letter's zone was not refilled after the delay"
		end
		if ctx.afterBite ~= ZONES - 1 or not ctx.zoneEmptyAtOnce then
			return false, string.format(
				"after the meal the pool held %s blocks (zone empty: %s), expected %d",
				tostring(ctx.afterBite), tostring(ctx.zoneEmptyAtOnce), ZONES - 1
			)
		end
		if ctx.countTooEarly ~= ZONES - 1 then
			return false, "the zone refilled before the respawn delay"
		end
		if not ctx.refilledInZone then
			return false, "the eaten letter's zone was not refilled after the delay"
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
