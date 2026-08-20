local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)

local TEST_TARGET = 12
local BOX_MIN = Vector3.new(-15, 10, -15)
local BOX_MAX = Vector3.new(15, 20, 15)
local TOLERANCE = 0.01
local TEST_ARENA_ID = "TestBoundsCheck"

return {
	name = "BlockSpawner blocks spawn within configured bounding box",

	setup = function(ctx)
		local container = Instance.new("Folder")
		container.Name = "TestBoundsContainer"
		container.Parent = workspace
		ctx.container = container

		-- Its own arena, so the assertion below is about this pool's boxes
		-- rather than every BlockSpawnVolume in the place. Under the
		-- singleton this fixture had to stop the live spawner to keep the
		-- shipped arena's blocks out of getActiveBlocks().
		ctx.spawner = BlockSpawner.new({
			arenaId = TEST_ARENA_ID,
			targetCount = TEST_TARGET,
			boxMin = BOX_MIN,
			boxMax = BOX_MAX,
			parent = container,
		})
		ctx.spawner:start()
	end,

	verify = function(ctx)
		local blocks = ctx.spawner:getActiveBlocks()
		for _, block in blocks do
			local pos = block:GetPivot().Position
			if pos.X < BOX_MIN.X - TOLERANCE or pos.X > BOX_MAX.X + TOLERANCE
				or pos.Y < BOX_MIN.Y - TOLERANCE or pos.Y > BOX_MAX.Y + TOLERANCE
				or pos.Z < BOX_MIN.Z - TOLERANCE or pos.Z > BOX_MAX.Z + TOLERANCE then
				return false, string.format(
					"block at (%.1f, %.1f, %.1f) outside box [(%.0f,%.0f,%.0f)-(%.0f,%.0f,%.0f)]",
					pos.X, pos.Y, pos.Z,
					BOX_MIN.X, BOX_MIN.Y, BOX_MIN.Z,
					BOX_MAX.X, BOX_MAX.Y, BOX_MAX.Z
				)
			end
		end
		return true, string.format("all %d blocks within bounds", #blocks)
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
