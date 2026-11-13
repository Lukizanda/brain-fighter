local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)

local TEST_PARENT_NAME = "TestNoAttributesContainer"
local TEST_ARENA_ID = "TestNoAttributes"
local TEST_FALLBACK_ARENA_ID = "TestBadAttributes"

-- Two plain boxes, 4000 + 1000 cubic studs. The pre-zone target was
-- round(density * totalVolume / 1000) = round(2 * 5) = 10.
local DENSITY = 2
local EXPECTED_TARGET = 10
local FALLBACK_TARGET = 30
local MIN_DISTINCT_COLORS = 2

return {
	-- Kept short: the autorunner writes the name into a workspace attribute
	-- (100-character limit including the TestResult_Phase3_ prefix).
	name = "BlockSpawner no-attribute pool keeps old target, bad values fall back",

	setup = function(ctx)
		local container = Instance.new("Folder")
		container.Name = TEST_PARENT_NAME
		container.Parent = workspace
		ctx.container = container

		ctx.spawner = BlockSpawner.new({
			arenaId = TEST_ARENA_ID,
			boxes = {
				{ boxMin = Vector3.new(-10, 10, -10), boxMax = Vector3.new(10, 20, 10) },
				{ boxMin = Vector3.new(100, 10, -5), boxMax = Vector3.new(110, 20, 5) },
			},
			density = DENSITY,
			parent = container,
		})
		ctx.spawner:start()

		-- Unknown values must warn and fall back, never spawn nothing.
		ctx.fallback = BlockSpawner.new({
			arenaId = TEST_FALLBACK_ARENA_ID,
			boxes = { {
				boxMin = Vector3.new(-10, 10, -10),
				boxMax = Vector3.new(10, 20, 10),
				letterTable = "NoSuchTable",
				colorOnly = "purple",
				quota = 0,
				label = "TestBadVolume",
			} },
			targetCount = FALLBACK_TARGET,
			parent = container,
		})
		ctx.fallback:start()
	end,

	verify = function(ctx)
		local spawner = ctx.spawner
		if spawner:getTargetCount() ~= EXPECTED_TARGET or spawner:getDensityTarget() ~= EXPECTED_TARGET then
			return false, string.format(
				"expected target %d, got total %d / density %d",
				EXPECTED_TARGET, spawner:getTargetCount(), spawner:getDensityTarget()
			)
		end
		if spawner:getQuotaTotal() ~= 0 then
			return false, "a pool with no quota boxes reported a quota total"
		end
		if #spawner:getActiveBlocks() ~= EXPECTED_TARGET then
			return false, string.format("expected %d blocks, got %d", EXPECTED_TARGET, #spawner:getActiveBlocks())
		end

		local fallbackBlocks = ctx.fallback:getActiveBlocks()
		if #fallbackBlocks ~= FALLBACK_TARGET then
			return false, string.format("bad-attribute volume: expected %d blocks, got %d", FALLBACK_TARGET, #fallbackBlocks)
		end
		if ctx.fallback:getQuotaTotal() ~= 0 then
			return false, "quota 0 should have been ignored, not treated as a quota volume"
		end
		local colors: { [string]: boolean } = {}
		local colorCount = 0
		for _, block in fallbackBlocks do
			local color = tostring(block:GetAttribute(LetterBlocks.COLOR_ATTRIBUTE))
			if not colors[color] then
				colors[color] = true
				colorCount += 1
			end
		end
		if colorCount < MIN_DISTINCT_COLORS then
			return false, "bad ColorOnly value should fall back to mixed colours"
		end

		return true, string.format(
			"no-attribute pool target %d (as before); bad %s/ColorOnly/BlockQuota fell back to defaults",
			EXPECTED_TARGET, LetterTables.DEFAULT
		)
	end,

	teardown = function(ctx)
		if ctx.spawner then
			ctx.spawner:destroy()
		end
		if ctx.fallback then
			ctx.fallback:destroy()
		end
		if ctx.container then
			ctx.container:Destroy()
		end
	end,
}
