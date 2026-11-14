--!strict

----------------------------------------------------------------------
-- hunger_spares_rewards — a kit letter and a freed fossil letter are never pulled
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on a stand-in boss, ticked by hand. A word-kit's
-- letters and a timed block (the fossil letter's kind of block) sit right
-- next to the boss; an ordinary block sits farther away. The ordinary one is
-- the one pulled, though it is farther; the rewards are not touched. Then a
-- pool with ONLY the rewards: nothing is pulled at all.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossHunger = require(ServerScriptService.Server.Boss.Scripts.BossHunger)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local ARENA_ID = "HungerRewards"
local INTERVAL_SEC = 5
local RADIUS_STUDS = 25
local FRACTION = 0.1
local START_HEALTH = 500
local KIT_OFFSET = Vector3.new(2, 0, 0)
local TIMED_OFFSET = Vector3.new(0, 0, 1)
local ZONE_OFFSET = Vector3.new(0, 0, 20)
local TIMED_LETTER = "A"
local TIMED_COLOR = "red"
local TIMED_LIFETIME_SEC = 60
local NEVER_REFILL_SEC = 600
local MOVED_TOLERANCE_STUDS = 0.01

return {
	name = "hunger_spares_rewards",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss(nil, START_HEALTH)
		local kitAt = root.Position + KIT_OFFSET
		local zoneAt = root.Position + ZONE_OFFSET
		local pool = hf:pool({ hf:kit(kitAt), hf:zone(zoneAt) }, NEVER_REFILL_SEC)
		local timed = pool:spawnTimedBlock(
			TIMED_LETTER, TIMED_COLOR, CFrame.new(root.Position + TIMED_OFFSET), TIMED_LIFETIME_SEC
		)
		ctx.timedMade = timed ~= nil
		local kitBefore = {}
		for _, block in pool:getActiveBlocks() do
			if hf:blockAt(pool, zoneAt) ~= block then
				kitBefore[block] = block:GetPivot().Position
			end
		end
		ctx.kitBefore = 0
		for _ in kitBefore do
			ctx.kitBefore += 1
		end
		local hunger = BossHunger.new(boss, humanoid, root, hungerFixture.spec(
			INTERVAL_SEC, RADIUS_STUDS, FRACTION, hungerFixture.FAST_PULL_SPEED, hungerFixture.REACH_STUDS
		))
		if not hunger then
			return
		end
		ctx.enabled = true

		hunger:tick(INTERVAL_SEC)
		local towed = hf:towed(pool)
		ctx.zoneTowed = #towed == 1 and towed[1] == hf:blockAt(pool, zoneAt)
		ctx.timedUntouched = timed ~= nil and timed.Parent ~= nil and not pool:isTowed(timed)
		ctx.kitUntouched = true
		for block, position in kitBefore do
			if block.Parent == nil or pool:isTowed(block)
				or (block:GetPivot().Position - position).Magnitude > MOVED_TOLERANCE_STUDS then
				ctx.kitUntouched = false
			end
		end

		-- Eat the one ordinary block, then only rewards remain.
		hunger:tick(INTERVAL_SEC)
		task.wait()
		ctx.zoneEaten = hf:blockAt(pool, zoneAt) == nil
		local healthAfterZone = humanoid.Health
		hunger:tick(INTERVAL_SEC)
		hunger:tick(INTERVAL_SEC)
		task.wait()
		ctx.nothingElsePulled = #hf:towed(pool) == 0 and humanoid.Health == healthAfterZone
		ctx.timedAfter = timed ~= nil and timed.Parent ~= nil
		local kitAfter = 0
		for _, block in pool:getActiveBlocks() do
			if block.Parent ~= nil then
				kitAfter += 1
			end
		end
		ctx.kitAfter = kitAfter
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.enabled or not ctx.timedMade then
			return false, "fixture: no hunger object or no timed block"
		end
		if ctx.kitBefore ~= hungerFixture.KIT_LENGTH then
			return false, string.format(
				"fixture: the kit holds %s letters, expected %d", tostring(ctx.kitBefore), hungerFixture.KIT_LENGTH
			)
		end
		if not ctx.zoneTowed then
			return false, "the ordinary block (farther away) was not the one pulled"
		end
		if not ctx.timedUntouched or not ctx.kitUntouched then
			return false, "a reward (kit letter or timed block) was pulled or moved"
		end
		if not ctx.zoneEaten then
			return false, "the ordinary block was not eaten"
		end
		if not ctx.nothingElsePulled then
			return false, "with only rewards left, something was pulled or the boss healed"
		end
		if not ctx.timedAfter or ctx.kitAfter ~= hungerFixture.KIT_LENGTH then
			return false, "a reward was removed"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
