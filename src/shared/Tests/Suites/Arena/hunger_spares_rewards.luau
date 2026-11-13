--!strict

----------------------------------------------------------------------
-- hunger_spares_rewards — a kit letter and a freed fossil letter are never eaten
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on a stand-in boss, ticked by hand. A word-kit's
-- letters and a timed block (the fossil letter's kind of block) sit right
-- next to the boss; an ordinary block sits farther away. The ordinary one is
-- eaten even though it is farther; the rewards are untouched; with nothing
-- else eligible a second bite does nothing at all.
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

return {
	name = "hunger_spares_rewards",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss(nil, START_HEALTH)
		local zoneAt = root.Position + ZONE_OFFSET
		local pool = hf:pool({ hf:kit(root.Position + KIT_OFFSET), hf:zone(zoneAt) }, NEVER_REFILL_SEC)
		local timed = pool:spawnTimedBlock(
			TIMED_LETTER, TIMED_COLOR, CFrame.new(root.Position + TIMED_OFFSET), TIMED_LIFETIME_SEC
		)
		ctx.timedMade = timed ~= nil
		ctx.kitBefore = #pool:getActiveBlocks() - 1 -- minus the ordinary zone block
		local hunger = BossHunger.new(boss, humanoid, root, hungerFixture.spec(INTERVAL_SEC, RADIUS_STUDS, FRACTION))
		if not hunger then
			return
		end
		ctx.enabled = true

		-- The pool hears a removal one frame after Destroy (as for a pop), so
		-- its counts are read after a yield.
		hunger:tick(INTERVAL_SEC)
		task.wait()
		ctx.zoneEaten = hf:blockAt(pool, zoneAt) == nil
		ctx.healthAfterFirst = humanoid.Health
		ctx.activeAfterFirst = #pool:getActiveBlocks()
		ctx.timedAfterFirst = timed ~= nil and timed.Parent ~= nil

		hunger:tick(INTERVAL_SEC)
		task.wait()
		ctx.activeAfterSecond = #pool:getActiveBlocks()
		ctx.timedAfterSecond = timed ~= nil and timed.Parent ~= nil
		ctx.healthAfterSecond = humanoid.Health
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
		if not ctx.zoneEaten then
			return false, "the ordinary block was not eaten (it is the only eligible one)"
		end
		if ctx.activeAfterFirst ~= hungerFixture.KIT_LENGTH then
			return false, string.format(
				"%s pool blocks left after the first bite, expected the %d kit letters",
				tostring(ctx.activeAfterFirst), hungerFixture.KIT_LENGTH
			)
		end
		if not ctx.timedAfterFirst or not ctx.timedAfterSecond then
			return false, "the timed (fossil-kind) block was eaten"
		end
		if ctx.activeAfterSecond ~= ctx.activeAfterFirst then
			return false, "a kit letter was eaten on the second bite"
		end
		if ctx.healthAfterSecond ~= ctx.healthAfterFirst then
			return false, "the boss healed on a bite with nothing eligible"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
