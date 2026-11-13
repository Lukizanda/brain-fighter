local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)

local TEST_QUOTA = 5
local TEST_DELAY = 0.4
local TEST_PARENT_NAME = "TestQuotaContainer"
local TEST_ARENA_ID = "TestQuotaRefills"
local TEST_BOX_MIN = Vector3.new(-6, 10, -6)
local TEST_BOX_MAX = Vector3.new(6, 18, 6)
local TEST_MIN_SPACING = 1.5
local DESTROY_COUNT = 2

local DURING_COOLDOWN_WAIT = 0.15
local PAST_COOLDOWN_WAIT = 0.6

local function insideBox(position: Vector3): boolean
	return position.X >= TEST_BOX_MIN.X and position.X <= TEST_BOX_MAX.X
		and position.Y >= TEST_BOX_MIN.Y and position.Y <= TEST_BOX_MAX.Y
		and position.Z >= TEST_BOX_MIN.Z and position.Z <= TEST_BOX_MAX.Z
end

return {
	name = "BlockSpawner quota volume holds exactly its quota and refills in place",

	setup = function(ctx)
		local container = Instance.new("Folder")
		container.Name = TEST_PARENT_NAME
		container.Parent = workspace
		ctx.container = container

		-- A quota box and nothing else: no density box, so the pool's whole
		-- target is the quota.
		ctx.spawner = BlockSpawner.new({
			arenaId = TEST_ARENA_ID,
			boxes = { {
				boxMin = TEST_BOX_MIN,
				boxMax = TEST_BOX_MAX,
				quota = TEST_QUOTA,
				label = "TestQuotaVolume",
			} },
			parent = container,
			respawnDelay = TEST_DELAY,
			minSpacing = TEST_MIN_SPACING,
		})
		ctx.spawner:start()
	end,

	run = function(ctx)
		local blocks = ctx.spawner:getActiveBlocks()
		ctx.initialCount = #blocks
		for i = 1, DESTROY_COUNT do
			blocks[i]:Destroy()
		end

		task.wait(DURING_COOLDOWN_WAIT)
		ctx.duringCooldown = #ctx.spawner:getActiveBlocks()

		task.wait(PAST_COOLDOWN_WAIT)
		ctx.after = ctx.spawner:getActiveBlocks()
	end,

	verify = function(ctx)
		if ctx.initialCount ~= TEST_QUOTA then
			return false, string.format("expected %d blocks at start, got %d", TEST_QUOTA, ctx.initialCount)
		end
		if ctx.spawner:getDensityTarget() ~= 0 or ctx.spawner:getTargetCount() ~= TEST_QUOTA then
			return false, string.format(
				"expected density 0 / total %d, got %d / %d",
				TEST_QUOTA, ctx.spawner:getDensityTarget(), ctx.spawner:getTargetCount()
			)
		end
		local expectedDuring = TEST_QUOTA - DESTROY_COUNT
		if ctx.duringCooldown ~= expectedDuring then
			return false, string.format("expected %d during cooldown, got %d", expectedDuring, ctx.duringCooldown)
		end
		if #ctx.after ~= TEST_QUOTA then
			return false, string.format("expected %d after refill, got %d", TEST_QUOTA, #ctx.after)
		end
		for _, block in ctx.after do
			if not insideBox(block:GetPivot().Position) then
				return false, "a refilled block spawned outside the quota volume"
			end
		end
		return true, string.format("held exactly %d, dipped to %d, refilled in place", TEST_QUOTA, expectedDuring)
	end,

	teardown = function(ctx)
		if ctx.spawner then
			ctx.spawner:destroy()
		end
		if ctx.container then
			ctx.container:Destroy()
		end
	end,
}
