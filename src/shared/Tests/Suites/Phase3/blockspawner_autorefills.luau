local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)

local TEST_TARGET = 6
local TEST_PARENT_NAME = "TestRefillContainer"

return {
	name = "BlockSpawner auto-refills when a block is destroyed",

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
		})
	end,

	run = function(ctx)
		local blocks = BlockSpawner.getActiveBlocks()
		ctx.destroyedBlock = blocks[1]
		blocks[1]:Destroy()
		task.wait(0.1)
	end,

	verify = function(ctx)
		local blocks = BlockSpawner.getActiveBlocks()
		if #blocks ~= TEST_TARGET then
			return false, string.format("expected %d blocks after refill, got %d", TEST_TARGET, #blocks)
		end
		return true, string.format("refilled to %d after destroy", #blocks)
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
