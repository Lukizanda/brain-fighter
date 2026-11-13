local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)

local TEST_PARENT_NAME = "TestQuotaSplitContainer"
local TEST_ARENA_ID = "TestQuotaSplit"

-- Density box 20 x 10 x 20 = 4000 cubic studs. At density 2 per 1000 that
-- is 8 blocks. The quota box is a separate, far-away room of 1000 cubic
-- studs: had it joined the density pool the target would be round(2 * 5) = 10.
local DENSITY = 2
local DENSITY_BOX_MIN = Vector3.new(-10, 10, -10)
local DENSITY_BOX_MAX = Vector3.new(10, 20, 10)
local QUOTA_BOX_MIN = Vector3.new(200, 10, -5)
local QUOTA_BOX_MAX = Vector3.new(210, 20, 5)
local EXPECTED_DENSITY_TARGET = 8
local TEST_QUOTA = 7
local EXPECTED_TOTAL = EXPECTED_DENSITY_TARGET + TEST_QUOTA
local REFILL_WAIT = 0.2

local function inQuotaBox(position: Vector3): boolean
	return position.X >= QUOTA_BOX_MIN.X
end

return {
	name = "BlockSpawner density target comes from non-quota boxes only",

	setup = function(ctx)
		local container = Instance.new("Folder")
		container.Name = TEST_PARENT_NAME
		container.Parent = workspace
		ctx.container = container

		ctx.spawner = BlockSpawner.new({
			arenaId = TEST_ARENA_ID,
			boxes = {
				{ boxMin = DENSITY_BOX_MIN, boxMax = DENSITY_BOX_MAX, label = "TestOpenVolume" },
				{ boxMin = QUOTA_BOX_MIN, boxMax = QUOTA_BOX_MAX, quota = TEST_QUOTA, label = "TestVaultVolume" },
			},
			density = DENSITY,
			parent = container,
		})
		ctx.spawner:start()
	end,

	run = function(ctx)
		-- Consume one block from each side; each must come back in its own.
		local destroyedQuota, destroyedDensity = false, false
		for _, block in ctx.spawner:getActiveBlocks() do
			if inQuotaBox(block:GetPivot().Position) then
				if not destroyedQuota then
					destroyedQuota = true
					block:Destroy()
				end
			elseif not destroyedDensity then
				destroyedDensity = true
				block:Destroy()
			end
		end
		task.wait(REFILL_WAIT)
	end,

	verify = function(ctx)
		local spawner = ctx.spawner
		if spawner:getDensityTarget() ~= EXPECTED_DENSITY_TARGET then
			return false, string.format("density target: expected %d, got %d", EXPECTED_DENSITY_TARGET, spawner:getDensityTarget())
		end
		if spawner:getQuotaTotal() ~= TEST_QUOTA then
			return false, string.format("quota total: expected %d, got %d", TEST_QUOTA, spawner:getQuotaTotal())
		end
		if spawner:getTargetCount() ~= EXPECTED_TOTAL then
			return false, string.format("total target: expected %d, got %d", EXPECTED_TOTAL, spawner:getTargetCount())
		end

		local inQuota, inDensity = 0, 0
		for _, block in spawner:getActiveBlocks() do
			if inQuotaBox(block:GetPivot().Position) then
				inQuota += 1
			else
				inDensity += 1
			end
		end
		if inQuota ~= TEST_QUOTA or inDensity ~= EXPECTED_DENSITY_TARGET then
			return false, string.format(
				"after refill expected %d quota + %d density, got %d + %d",
				TEST_QUOTA, EXPECTED_DENSITY_TARGET, inQuota, inDensity
			)
		end
		return true, string.format("%d density + %d quota = %d, each refilled in its own volume", inDensity, inQuota, EXPECTED_TOTAL)
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
