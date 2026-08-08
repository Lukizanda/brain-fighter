local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)

local TEST_TARGET = 6
local TEST_DELAY = 1.2
local TEST_PARENT_NAME = "TestRespawnDelayContainer"

-- Two blocks, so the test also catches the failure mode where the first
-- expiring timer refills the whole arena instead of one block.
local DESTROY_COUNT = 2

-- Well inside the cooldown — nothing should have come back yet.
local DURING_COOLDOWN_WAIT = 0.4
-- Enough to clear the remaining cooldown plus scheduler slack.
local PAST_COOLDOWN_WAIT = 1.4

return {
	name = "BlockSpawner holds a consumed block for respawnDelay before replacing it",

	setup = function(ctx)
		BlockSpawner.stop()

		local container = Instance.new("Folder")
		container.Name = TEST_PARENT_NAME
		container.Parent = workspace
		ctx.container = container

		BlockSpawner.start({
			targetCount = TEST_TARGET,
			boxMin = Vector3.new(-10, 10, -10),
			boxMax = Vector3.new(10, 18, 10),
			parent = container,
			respawnDelay = TEST_DELAY,
		})
	end,

	run = function(ctx)
		local blocks = BlockSpawner.getActiveBlocks()
		ctx.initialCount = #blocks

		for i = 1, DESTROY_COUNT do
			blocks[i]:Destroy()
		end

		task.wait(DURING_COOLDOWN_WAIT)
		ctx.duringCooldown = #BlockSpawner.getActiveBlocks()

		task.wait(PAST_COOLDOWN_WAIT)
		ctx.afterCooldown = #BlockSpawner.getActiveBlocks()
	end,

	verify = function(ctx)
		if ctx.initialCount ~= TEST_TARGET then
			return false, string.format(
				"setup did not fill to target: expected %d, got %d",
				TEST_TARGET, ctx.initialCount
			)
		end

		local expectedDuring = TEST_TARGET - DESTROY_COUNT
		if ctx.duringCooldown ~= expectedDuring then
			return false, string.format(
				"expected %d blocks %.1fs into a %.1fs cooldown, got %d — refill did not wait",
				expectedDuring, DURING_COOLDOWN_WAIT, TEST_DELAY, ctx.duringCooldown
			)
		end

		-- Equality, not >=: one destroy must produce exactly one spawn.
		-- A greater count means a timer refilled to target rather than
		-- replacing its own block.
		if ctx.afterCooldown ~= TEST_TARGET then
			return false, string.format(
				"expected %d blocks after the cooldown elapsed, got %d",
				TEST_TARGET, ctx.afterCooldown
			)
		end

		return true, string.format(
			"held at %d during the %.1fs cooldown, back to %d after",
			expectedDuring, TEST_DELAY, ctx.afterCooldown
		)
	end,

	teardown = function(ctx)
		BlockSpawner.stop()
		for _, block in BlockSpawner.getActiveBlocks() do
			block:Destroy()
		end
		if ctx.container then
			ctx.container:Destroy()
		end
	end,
}
