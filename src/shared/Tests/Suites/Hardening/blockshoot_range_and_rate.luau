--!strict

----------------------------------------------------------------------
-- blockshoot_range_and_rate — ConsumeBlock range + throttle (5.4)
----------------------------------------------------------------------
-- The two checks that could plausibly break real play if mis-tuned, so
-- both directions are asserted: the bound rejects abuse AND a player
-- tapping blocks as fast as the input allows is never throttled.
--
-- The rate half runs in real time against the production constants
-- (~1.5s) rather than a stubbed clock, because the thing worth testing
-- is the tuning, not the arithmetic.
----------------------------------------------------------------------

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BlockTapConfig       = require(ReplicatedStorage.Shared.BlockShoot.BlockTapConfig)
local BlockShootConstants  = require(ServerScriptService.Server.BlockShoot.BlockShootConstants)
local BlockShootValidation = require(ServerScriptService.Server.BlockShoot.BlockShootValidation)
local RateLimiter          = require(ServerScriptService.Server.Utility.RateLimiter)

-- Shots a real player gets off at the weapon's cooldown. Enough to
-- drain the burst allowance and then run on refill alone.
local SUSTAINED_SHOTS = 6
-- A remote loop with no cooldown: comfortably more than the bucket holds.
local FLOOD_SHOTS = 30

local ORIGIN = Vector3.new(0, 50, 0)
local NEAR_OFFSET = Vector3.new(0, 0, 20)
local FAR_OFFSET = Vector3.new(0, 0, BlockShootConstants.MAX_CONSUME_DISTANCE_STUDS + 100)

type Ctx = {
	created: { Instance },
	character: Model,
	nearBlock: Model,
	farBlock: Model,
	sustainedRejects: number,
	floodRejects: number,
}

local function makeAnchoredModel(ctx: Ctx, name: string, position: Vector3, partName: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local part = Instance.new("Part")
	part.Name = partName
	part.Anchored = true
	part.Size = Vector3.one
	part.Position = position
	part.Parent = model
	model.PrimaryPart = part
	model.Parent = workspace
	table.insert(ctx.created, model)
	return model
end

return {
	name = "blockshoot_range_and_rate",

	setup = function(ctx: Ctx)
		ctx.created = {}
		ctx.character = makeAnchoredModel(ctx, "HardeningCaster", ORIGIN, "HumanoidRootPart")
		ctx.nearBlock = makeAnchoredModel(ctx, "HardeningNearBlock", ORIGIN + NEAR_OFFSET, "Cube")
		ctx.farBlock = makeAnchoredModel(ctx, "HardeningFarBlock", ORIGIN + FAR_OFFSET, "Cube")
	end,

	run = function(ctx: Ctx)
		local limiter = RateLimiter.new(
			BlockShootConstants.CONSUME_BURST_CAPACITY,
			BlockShootConstants.CONSUME_REFILL_PER_SEC
		)
		local key = "hardening-sustained"

		ctx.sustainedRejects = 0
		for shot = 1, SUSTAINED_SHOTS do
			if not limiter:consume(key) then
				ctx.sustainedRejects += 1
			end
			if shot < SUSTAINED_SHOTS then
				task.wait(BlockTapConfig.COOLDOWN)
			end
		end

		local floodLimiter = RateLimiter.new(
			BlockShootConstants.CONSUME_BURST_CAPACITY,
			BlockShootConstants.CONSUME_REFILL_PER_SEC
		)
		ctx.floodRejects = 0
		for _ = 1, FLOOD_SHOTS do
			if not floodLimiter:consume("hardening-flood") then
				ctx.floodRejects += 1
			end
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		-- Range: a block the player is standing next to passes.
		local nearOk, nearReason = BlockShootValidation.checkRange(ctx.character, ctx.nearBlock)
		if not nearOk then
			return false, string.format("rejected an in-range block: %s", tostring(nearReason))
		end

		-- Range: a block across the map does not.
		local farOk = BlockShootValidation.checkRange(ctx.character, ctx.farBlock)
		if farOk then
			return false, string.format(
				"accepted a block %d studs away (limit %d)",
				(FAR_OFFSET).Magnitude,
				BlockShootConstants.MAX_CONSUME_DISTANCE_STUDS
			)
		end

		-- A character with no HumanoidRootPart is not a valid firer.
		local rootless = Instance.new("Model")
		local rootlessOk = BlockShootValidation.checkRange(rootless, ctx.nearBlock)
		rootless:Destroy()
		if rootlessOk then
			return false, "accepted a character with no HumanoidRootPart"
		end
		if BlockShootValidation.checkRange(nil, ctx.nearBlock) then
			return false, "accepted a nil character"
		end

		-- Rate: legitimate fire cadence must pass untouched.
		if ctx.sustainedRejects > 0 then
			return false, string.format(
				"throttled %d/%d shots fired at the weapon's own cooldown",
				ctx.sustainedRejects, SUSTAINED_SHOTS
			)
		end

		-- Rate: an uncooled loop must not.
		local expectedFloodRejects = FLOOD_SHOTS - BlockShootConstants.CONSUME_BURST_CAPACITY
		if ctx.floodRejects < expectedFloodRejects then
			return false, string.format(
				"flood of %d only lost %d (expected at least %d)",
				FLOOD_SHOTS, ctx.floodRejects, expectedFloodRejects
			)
		end

		-- The rejection-log budget is the same limiter at capacity 1. It
		-- must report the FIRST hit of each (player, reason) key —
		-- Logger:warnThrottled counts calls rather than seconds, so
		-- using it here would have made a single probe silent.
		local budget = RateLimiter.new(1, 1 / BlockShootConstants.REJECTION_LOG_THROTTLE_SEC)
		if not budget:consume("7:out of range") then
			return false, "log budget swallowed the first rejection"
		end
		if budget:consume("7:out of range") then
			return false, "log budget let a repeat rejection through immediately"
		end
		if not budget:consume("7:rate limit") then
			return false, "log budget conflated two different rejection reasons"
		end

		-- A leaving player's compound keys must be evictable.
		budget:forgetPrefix("7:")
		if not budget:consume("7:out of range") then
			return false, "forgetPrefix did not evict the leaver's keys"
		end
		budget:consume("99:out of range")
		budget:forgetPrefix("7:")
		if budget:consume("99:out of range") then
			return false, "forgetPrefix evicted a non-matching key"
		end

		return true, string.format(
			"range bound %d studs; %d/%d legit shots passed, %d/%d flood shots dropped",
			BlockShootConstants.MAX_CONSUME_DISTANCE_STUDS,
			SUSTAINED_SHOTS - ctx.sustainedRejects, SUSTAINED_SHOTS,
			ctx.floodRejects, FLOOD_SHOTS
		)
	end,

	teardown = function(ctx: Ctx)
		for _, inst in ctx.created do
			inst:Destroy()
		end
	end,
}
