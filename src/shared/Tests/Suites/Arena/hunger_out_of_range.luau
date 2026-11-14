--!strict

----------------------------------------------------------------------
-- hunger_out_of_range — nothing beyond eatRadius (horizontally) is pulled
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on a stand-in boss, ticked by hand. A letter just
-- beyond the radius horizontally is never pulled however many intervals pass,
-- and does not move. Then a letter just inside the radius horizontally but far
-- above the boss (out of reach in 3D) IS pulled: the radius ignores height.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossHunger = require(ServerScriptService.Server.Boss.Scripts.BossHunger)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local ARENA_ID = "HungerRange"
local INTERVAL_SEC = 5
local RADIUS_STUDS = 25
local FRACTION = 0.1
local START_HEALTH = 500
local JUST_OUTSIDE_OFFSET = Vector3.new(26, 0, 0)
-- Just inside horizontally, 90 up: 3D distance ~93.
local JUST_INSIDE_HIGH_OFFSET = Vector3.new(0, 90, 24)
local INTERVALS_OBSERVED = 3
local NEVER_REFILL_SEC = 600
local MOVED_TOLERANCE_STUDS = 0.01

return {
	name = "hunger_out_of_range",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss(nil, START_HEALTH)
		local outsideAt = root.Position + JUST_OUTSIDE_OFFSET
		local pool = hf:pool({ hf:zone(outsideAt) }, NEVER_REFILL_SEC)
		local hunger = BossHunger.new(boss, humanoid, root, hungerFixture.spec(
			INTERVAL_SEC, RADIUS_STUDS, FRACTION, hungerFixture.FAST_PULL_SPEED, hungerFixture.REACH_STUDS
		))
		if not hunger then
			return
		end
		ctx.enabled = true

		local outsideBlock = hf:blockAt(pool, outsideAt)
		-- Blocks sit anywhere within their zones, so compare with where it was.
		local outsideStart = if outsideBlock then outsideBlock:GetPivot().Position else outsideAt
		for _ = 1, INTERVALS_OBSERVED do
			hunger:tick(INTERVAL_SEC)
		end
		ctx.outsideKept = outsideBlock ~= nil and outsideBlock.Parent ~= nil
			and (outsideBlock:GetPivot().Position - outsideStart).Magnitude < MOVED_TOLERANCE_STUDS
		ctx.outsideNotTowed = #hf:towed(pool) == 0
		ctx.healthOutside = humanoid.Health

		-- The high one is in its own pool so the first one cannot be what is
		-- pulled; the registry points at the newer pool.
		local highAt = root.Position + JUST_INSIDE_HIGH_OFFSET
		local highPool = hf:pool({ hf:zone(highAt) }, NEVER_REFILL_SEC)
		hunger:tick(INTERVAL_SEC)
		ctx.highTowed = #hf:towed(highPool) == 1
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.enabled then
			return false, "BossHunger.new returned nil for a spec with eat values"
		end
		if not ctx.outsideKept then
			return false, "a letter beyond the radius was moved or removed"
		end
		if not ctx.outsideNotTowed or ctx.healthOutside ~= START_HEALTH then
			return false, "a letter beyond the radius was pulled or the boss healed"
		end
		if not ctx.highTowed then
			return false, "a letter inside the radius horizontally, but high above the boss, was not pulled"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
