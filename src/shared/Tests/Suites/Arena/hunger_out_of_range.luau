--!strict

----------------------------------------------------------------------
-- hunger_out_of_range — only blocks in reach, in the boss's own arena
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on a stand-in boss, ticked by hand. A block beyond
-- the eat radius is left alone and nothing heals; a block sitting right next
-- to the boss but in ANOTHER arena's pool is left alone too.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossHunger = require(ServerScriptService.Server.Boss.Scripts.BossHunger)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local ARENA_ID = "HungerRange"
local OTHER_ARENA_ID = "HungerRangeOther"
local INTERVAL_SEC = 5
local RADIUS_STUDS = 25
local FRACTION = 0.1
local START_HEALTH = 500
local FAR_OFFSET = Vector3.new(30, 0, 0)
local OTHER_ARENA_OFFSET = Vector3.new(3, 0, 0)
local NEVER_REFILL_SEC = 600

return {
	name = "hunger_out_of_range",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss(nil, START_HEALTH)
		local farAt = root.Position + FAR_OFFSET
		local otherAt = root.Position + OTHER_ARENA_OFFSET
		local pool = hf:pool({ hf:zone(farAt) }, NEVER_REFILL_SEC)
		local otherPool = hf:pool({ hf:zone(otherAt) }, NEVER_REFILL_SEC, OTHER_ARENA_ID)
		local hunger = BossHunger.new(boss, humanoid, root, hungerFixture.spec(INTERVAL_SEC, RADIUS_STUDS, FRACTION))
		if not hunger then
			return
		end
		ctx.enabled = true

		hunger:tick(INTERVAL_SEC)
		hunger:tick(INTERVAL_SEC)
		ctx.farKept = hf:blockAt(pool, farAt) ~= nil
		ctx.otherKept = hf:blockAt(otherPool, otherAt) ~= nil
		ctx.health = humanoid.Health
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.enabled then
			return false, "BossHunger.new returned nil for a spec with eat values"
		end
		if not ctx.farKept then
			return false, "a block beyond the eat radius was eaten"
		end
		if not ctx.otherKept then
			return false, "a block in another arena's pool was eaten"
		end
		if ctx.health ~= START_HEALTH then
			return false, "the boss healed with nothing in range"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
