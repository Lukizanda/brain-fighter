--!strict

----------------------------------------------------------------------
-- wordkit_target_counts
----------------------------------------------------------------------
-- Kits add to the arena's block count the way quota blocks do, and stay out
-- of the density pool:
--   - a pool with no kit volume resolves to exactly the target it did before
--     kits existed (the same two boxes and density as
--     blockspawner_no_attributes_unchanged);
--   - the same pool plus a kit volume has the same DENSITY target, a total
--     raised by the kit's word length, and no density block spawns in the
--     kit's volume or counts against the kit;
--   - the kit's own volume does not feed the density computation, even when
--     it is far larger than the density boxes.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local wordKitFixture = require(ReplicatedStorage.Shared.Tests.Helpers.wordKitFixture)

local TEST_ARENA_ID = "TestKitCounts"
local WITH_KIT_ARENA_ID = "TestKitCountsWithKit"

-- Two plain boxes, 4000 + 1000 cubic studs; the pre-kit target is
-- round(density * totalVolume / 1000) = round(2 * 5) = 10.
local DENSITY = 2
local EXPECTED_DENSITY_TARGET = 10
-- The density boxes top out at Y 20; the fixture puts kits thousands of studs up.
local KIT_MIN_HEIGHT = 1000

type Ctx = {
	kit: wordKitFixture.Fixture?,
	plain: any,
	withKit: any,
}

local function densityBoxes()
	return {
		{ boxMin = Vector3.new(-10, 10, -10), boxMax = Vector3.new(10, 20, 10) },
		{ boxMin = Vector3.new(100, 10, -5), boxMax = Vector3.new(110, 20, 5) },
	}
end

return {
	name = "wordkit_target_counts",

	setup = function(ctx: Ctx)
		local kit = wordKitFixture.new(TEST_ARENA_ID)
		ctx.kit = kit

		ctx.plain = kit:pool({ arenaId = TEST_ARENA_ID, boxes = densityBoxes(), density = DENSITY, minSpacing = 0 })
		ctx.plain:start()

		local boxes: { any } = densityBoxes()
		-- A kit volume far larger than the density boxes: if it fed the
		-- density computation the target would balloon.
		table.insert(boxes, kit:kitBox({ boxMin = Vector3.new(-5000, 4000, -5000), boxMax = Vector3.new(5000, 4100, 5000) }))
		ctx.withKit = kit:pool({ arenaId = WITH_KIT_ARENA_ID, boxes = boxes, density = DENSITY, minSpacing = 0 })
		ctx.withKit:start()
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local plain, withKit = ctx.plain, ctx.withKit
		if plain:getTargetCount() ~= EXPECTED_DENSITY_TARGET or plain:getDensityTarget() ~= EXPECTED_DENSITY_TARGET then
			return false, string.format(
				"no-kit pool: total %d / density %d, expected %d",
				plain:getTargetCount(), plain:getDensityTarget(), EXPECTED_DENSITY_TARGET
			)
		end
		if plain:getKitTotal() ~= 0 or #plain:getActiveBlocks() ~= EXPECTED_DENSITY_TARGET then
			return false, "the no-kit pool reports kit blocks, or did not fill to the old target"
		end

		local length = wordKitFixture.KIT_WORD_LENGTH
		if withKit:getDensityTarget() ~= EXPECTED_DENSITY_TARGET then
			return false, string.format(
				"density target %d with a kit volume, expected the old %d: the kit fed the density pool",
				withKit:getDensityTarget(), EXPECTED_DENSITY_TARGET
			)
		end
		if withKit:getKitTotal() ~= length or withKit:getTargetCount() ~= EXPECTED_DENSITY_TARGET + length then
			return false, string.format(
				"total %d / kit %d, expected %d / %d",
				withKit:getTargetCount(), withKit:getKitTotal(), EXPECTED_DENSITY_TARGET + length, length
			)
		end
		if #withKit:getActiveBlocks() ~= EXPECTED_DENSITY_TARGET + length then
			return false, string.format("%d live blocks, expected %d", #withKit:getActiveBlocks(), EXPECTED_DENSITY_TARGET + length)
		end
		if withKit:getQuotaTotal() ~= 0 then
			return false, "a kit counted as quota"
		end

		-- Density blocks stay in the density boxes: none at the kit's height.
		local kitBlocks = 0
		for _, block in withKit:getActiveBlocks() do
			if block:GetPivot().Position.Y > KIT_MIN_HEIGHT then
				kitBlocks += 1
			end
		end
		if kitBlocks ~= length then
			return false, string.format("%d blocks at the kit's height, expected %d: density blocks leaked into the kit volume", kitBlocks, length)
		end
		return true, string.format("no kit: %d (as before); with a %d-letter kit: %d density + %d kit", EXPECTED_DENSITY_TARGET, length, EXPECTED_DENSITY_TARGET, length)
	end,

	teardown = function(ctx: Ctx)
		if ctx.kit then
			ctx.kit:destroy()
		end
	end,
}
