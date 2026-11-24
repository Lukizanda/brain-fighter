--!strict

----------------------------------------------------------------------
-- spore_not_towed — hunger never pulls a spore, even the nearest letter
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on a stand-in boss, ticked by hand (as
-- hunger_spares_rewards). A spore sits one stud from the boss; an ordinary
-- block sits farther away. The ordinary one is the one pulled and eaten; the
-- spore is untouched. Then only the spore is left in reach: nothing is pulled
-- and the boss does not heal.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossHunger = require(ServerScriptService.Server.Boss.Scripts.BossHunger)
local BlockPoolRegistry = require(ServerScriptService.Server.BlockSpawner.BlockPoolRegistry)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local ARENA_ID = "SporeNotTowed"
local INTERVAL_SEC = 5
local RADIUS_STUDS = 25
local FRACTION = 0.1
local START_HEALTH = 500
local SPORE_OFFSET = Vector3.new(0, 0, 1)
local ZONE_OFFSET = Vector3.new(0, 0, 20)
local SPORE_LETTER = "A"
local SPORE_COLOR = "red"
local SPORE_FUSE_SEC = 60
local NEVER_REFILL_SEC = 600
local MOVED_TOLERANCE_STUDS = 0.01

return {
	name = "spore_not_towed",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss(nil, START_HEALTH)
		local zoneAt = root.Position + ZONE_OFFSET
		local pool = hf:pool({ hf:zone(zoneAt) }, NEVER_REFILL_SEC)
		local sporeAt = root.Position + SPORE_OFFSET
		local spore = BlockPoolRegistry.spawnSpore(ARENA_ID, SPORE_LETTER, SPORE_COLOR, sporeAt, SPORE_FUSE_SEC)
		ctx.sporeMade = spore ~= nil
		local hunger = BossHunger.new(boss, humanoid, root, hungerFixture.spec(
			INTERVAL_SEC, RADIUS_STUDS, FRACTION, hungerFixture.FAST_MARK_SEC, hungerFixture.FAST_SNAP_SEC, hungerFixture.REACH_STUDS
		))
		if not hunger or not spore then
			return
		end
		ctx.enabled = true

		hunger:tick(INTERVAL_SEC)
		local towed = hf:towed(pool)
		ctx.zonePulled = #towed == 1 and towed[1] == hf:blockAt(pool, zoneAt)
		ctx.sporeUntouched = spore.Parent ~= nil and not pool:isTowed(spore)
			and (spore:GetPivot().Position - sporeAt).Magnitude <= MOVED_TOLERANCE_STUDS

		-- Eat the ordinary block; only the spore is left.
		hunger:tick(INTERVAL_SEC)
		task.wait()
		ctx.zoneEaten = hf:blockAt(pool, zoneAt) == nil
		local healthAfterZone = humanoid.Health
		hunger:tick(INTERVAL_SEC)
		hunger:tick(INTERVAL_SEC)
		task.wait()
		ctx.nothingElsePulled = #hf:towed(pool) == 0 and humanoid.Health == healthAfterZone
		ctx.sporeKept = spore.Parent ~= nil and #pool:getSpores() == 1
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.enabled or not ctx.sporeMade then
			return false, "fixture: no hunger object or no spore"
		end
		if not ctx.zonePulled then
			return false, "the ordinary block (farther away) was not the one pulled"
		end
		if not ctx.sporeUntouched then
			return false, "the spore was pulled or moved"
		end
		if not ctx.zoneEaten then
			return false, "the ordinary block was not eaten"
		end
		if not ctx.nothingElsePulled then
			return false, "with only a spore left, something was pulled or the boss healed"
		end
		if not ctx.sporeKept then
			return false, "the spore was removed by hunger"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
