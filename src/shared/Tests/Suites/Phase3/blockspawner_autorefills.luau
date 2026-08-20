local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)

local TEST_TARGET = 6
local TEST_PARENT_NAME = "TestRefillContainer"
local TEST_ARENA_ID = "TestAutoRefills"

return {
	name = "BlockSpawner auto-refills when a block is destroyed",

	setup = function(ctx)
		local container = Instance.new("Folder")
		container.Name = TEST_PARENT_NAME
		container.Parent = workspace
		ctx.container = container

		-- Its own pool in its own arena, so the shipped arena's spawner
		-- keeps running alongside it. The removed signal is global, so this
		-- also covers the isolation the per-arena split depends on: the
		-- live arena's blocks fire the same signal and must not be counted
		-- or refilled here.
		ctx.spawner = BlockSpawner.new({
			arenaId = TEST_ARENA_ID,
			targetCount = TEST_TARGET,
			boxMin = Vector3.new(-10, 10, -10),
			boxMax = Vector3.new(10, 18, 10),
			parent = container,
			-- Pinned explicitly: this case is "a destroyed block gets
			-- replaced at all", not "how long that takes". The cooldown
			-- is covered by blockspawner_respawn_delay.
			respawnDelay = 0,
		})
		ctx.spawner:start()
	end,

	run = function(ctx)
		local blocks = ctx.spawner:getActiveBlocks()
		ctx.destroyedBlock = blocks[1]
		blocks[1]:Destroy()
		task.wait(0.1)
	end,

	verify = function(ctx)
		local blocks = ctx.spawner:getActiveBlocks()
		if #blocks ~= TEST_TARGET then
			return false, string.format("expected %d blocks after refill, got %d", TEST_TARGET, #blocks)
		end
		return true, string.format("refilled to %d after destroy", #blocks)
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
