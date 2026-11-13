--!strict

----------------------------------------------------------------------
-- wordkit_zigzag
----------------------------------------------------------------------
-- A WordKit volume too short for a straight row zig-zags: letters keep
-- their even cells along the part's local X axis but alternate front and
-- back along its local Z, so every pair of letters is still at least
-- `minSpacing` apart. The boss island's cave is this case: its chamber is
-- about 32 studs wide and a straight 5-letter row needs about 52.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local wordKitFixture = require(ReplicatedStorage.Shared.Tests.Helpers.wordKitFixture)

local TEST_ARENA_ID = "TestKitZigzag"
-- Shorter than 5 x TEST_MIN_SPACING (so not a straight row) but at least
-- half of it (so letters two apart still clear each other).
local SHORT_ROW_STUDS = 26
local ROW_HEIGHT_STUDS = 6
local ROW_DEPTH_STUDS = 12
local KIT_YAW_DEGREES = 30
local KIT_ORIGIN = Vector3.new(0, 5000, 0)
local HALF = 0.5

type Ctx = {
	kit: wordKitFixture.Fixture?,
	failure: string?,
	stagger: number?,
}

return {
	name = "wordkit_zigzag",

	setup = function(ctx: Ctx)
		ctx.kit = wordKitFixture.new(TEST_ARENA_ID)
	end,

	run = function(ctx: Ctx)
		local kit = ctx.kit :: wordKitFixture.Fixture
		local size = Vector3.new(SHORT_ROW_STUDS, ROW_HEIGHT_STUDS, ROW_DEPTH_STUDS)
		local cframe = CFrame.new(KIT_ORIGIN) * CFrame.Angles(0, math.rad(KIT_YAW_DEGREES), 0)
		local box = kit:kitBox({
			size = size,
			cframe = cframe,
			boxMin = KIT_ORIGIN - size * HALF,
			boxMax = KIT_ORIGIN + size * HALF,
		})
		local length = wordKitFixture.KIT_WORD_LENGTH
		local minSpacing = wordKitFixture.TEST_MIN_SPACING
		local tolerance = wordKitFixture.LOCAL_TOLERANCE_STUDS
		local cell = SHORT_ROW_STUDS / length
		local expectedStagger = math.sqrt(minSpacing * minSpacing - cell * cell)
		ctx.stagger = expectedStagger

		local pool = kit:pool({ boxes = { box } })
		pool:start()
		local blocks = pool:getActiveBlocks()
		if #blocks ~= length then
			ctx.failure = string.format("%d blocks, expected %d", #blocks, length)
			return
		end

		local locals: { Vector3 } = {}
		for _, block in blocks do
			table.insert(locals, cframe:PointToObjectSpace(block:GetPivot().Position))
		end
		table.sort(locals, function(a, b)
			return a.X < b.X
		end)

		for i, position in locals do
			local expectedX = (i - HALF) * cell - SHORT_ROW_STUDS * HALF
			if math.abs(position.X - expectedX) > tolerance then
				ctx.failure = string.format("letter %d at local X %.3f, expected %.3f", i, position.X, expectedX)
				return
			end
			if math.abs(position.Y) > tolerance then
				ctx.failure = string.format("letter %d is off the row's height by %.3f", i, position.Y)
				return
			end
			if math.abs(math.abs(position.Z) - expectedStagger * HALF) > tolerance then
				ctx.failure = string.format(
					"letter %d at local Z %.3f, expected +/-%.3f", i, position.Z, expectedStagger * HALF
				)
				return
			end
			if i > 1 and (position.Z > 0) == (locals[i - 1].Z > 0) then
				ctx.failure = string.format("letters %d and %d sit on the same side; they must alternate", i - 1, i)
				return
			end
		end

		for i = 1, #locals do
			for j = i + 1, #locals do
				local distance = (locals[i] - locals[j]).Magnitude
				if distance < minSpacing - tolerance then
					ctx.failure = string.format(
						"letters %d and %d are %.3f studs apart, closer than %d", i, j, distance, minSpacing
					)
					return
				end
			end
		end
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, string.format("a short row zig-zags %.2f studs deep and keeps every pair apart", ctx.stagger or 0)
	end,

	teardown = function(ctx: Ctx)
		if ctx.kit then
			ctx.kit:destroy()
		end
	end,
}
