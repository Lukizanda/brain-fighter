--!strict

----------------------------------------------------------------------
-- hunger_one_at_a_time — one letter in tow at a time; the rest stay put
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on a stand-in boss, ticked by hand, with a pull
-- so slow that nothing arrives. Two letters are in range. The first interval
-- takes the nearer one into tow; over several more intervals the boss still
-- has exactly that one in tow, the other has not moved and is not in tow, and
-- no second tow was begun. The pool's count is unchanged throughout.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossHunger = require(ServerScriptService.Server.Boss.Scripts.BossHunger)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local ARENA_ID = "HungerOne"
local INTERVAL_SEC = 1
local RADIUS_STUDS = 25
local SLOW_PULL_SPEED = 0.1
local REACH_STUDS = 1
local NEAR_OFFSET = Vector3.new(8, 0, 0)
local OTHER_OFFSET = Vector3.new(0, 0, 14)
local FURTHER_TICKS = 4
local NEVER_REFILL_SEC = 600
local MOVED_TOLERANCE_STUDS = 0.01

return {
	name = "hunger_one_at_a_time",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss()
		local nearAt = root.Position + NEAR_OFFSET
		local otherAt = root.Position + OTHER_OFFSET
		local pool = hf:pool({ hf:zone(nearAt), hf:zone(otherAt) }, NEVER_REFILL_SEC)
		local hunger = BossHunger.new(boss, humanoid, root, hungerFixture.spec(
			INTERVAL_SEC, RADIUS_STUDS, 0, SLOW_PULL_SPEED, REACH_STUDS
		))
		if not hunger then
			return
		end
		ctx.enabled = true
		local nearBlock = hf:blockAt(pool, nearAt)
		local otherBlock = hf:blockAt(pool, otherAt)
		ctx.fixtureOk = nearBlock ~= nil and otherBlock ~= nil
		if not nearBlock or not otherBlock then
			return
		end

		-- Blocks sit anywhere within their zones, so compare with where it was.
		local otherStart = otherBlock:GetPivot().Position
		hunger:tick(INTERVAL_SEC)
		local first = hf:towed(pool)
		ctx.firstIsNear = #first == 1 and first[1] == nearBlock

		ctx.alwaysOne = true
		for _ = 1, FURTHER_TICKS do
			hunger:tick(INTERVAL_SEC)
			local now = hf:towed(pool)
			if #now ~= 1 or now[1] ~= nearBlock then
				ctx.alwaysOne = false
			end
		end
		ctx.otherUntouched = otherBlock.Parent ~= nil and not pool:isTowed(otherBlock)
			and (otherBlock:GetPivot().Position - otherStart).Magnitude < MOVED_TOLERANCE_STUDS
		ctx.count = #pool:getActiveBlocks()
		ctx.target = pool:getTargetCount()
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.enabled or not ctx.fixtureOk then
			return false, "fixture: no hunger object or the two blocks were not there"
		end
		if not ctx.firstIsNear then
			return false, "the first interval did not put exactly the nearer letter in tow"
		end
		if not ctx.alwaysOne then
			return false, "over later intervals more than the first letter (or a different one) was in tow"
		end
		if not ctx.otherUntouched then
			return false, "the second letter was moved or taken into tow"
		end
		if ctx.count ~= ctx.target then
			return false, string.format("pool holds %s blocks, expected %s", tostring(ctx.count), tostring(ctx.target))
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
