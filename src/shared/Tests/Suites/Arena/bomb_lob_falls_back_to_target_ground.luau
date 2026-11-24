--!strict

----------------------------------------------------------------------
-- bomb_lob_falls_back_to_target_ground — a landing point with no ground, no floor-like surface or a ground at the wrong height is never used; after the retries the puzzle lands on the target's own ground
----------------------------------------------------------------------
-- MODULE LEVEL: BossBombs on a stand-in boss, ticked by hand with an injected
-- clock; no player needed. Two bare worlds:
--   Island   the target stands on a small plate with nothing else around: every
--            random landing point has no ground, so the puzzle lands exactly on
--            the target's own ground, under the target;
--   Ledge    the target stands on a small plate and a big floor lies far below
--            it (more than the height tolerance): every random point's ground is
--            at the wrong height, so again the target's own ground is used.
-- Both are repeated a few times (the landing points are random).
--
-- NOT covered: the wall (overlap) guard, which needs a placed obstacle at the
-- centre of a random point; the guards share one retry loop.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)
local BossBombs = require(ServerScriptService.Server.Boss.Scripts.BossBombs)

local ARENA_ID = "BombLandFallback"
local ATTEMPTS = 4
local PLATE_SIZE = Vector3.new(2, 1, 2)
local PLATE_DROP_STUDS = 3
local FAR_BELOW_STUDS = 60
local FLOOR_SIZE = Vector3.new(600, 2, 600)
-- A random point may happen to fall on the plate itself: that is the target's
-- ground too, so the centre only has to be within the plate's reach.
local POSITION_TOLERANCE = PLATE_SIZE.X

-- A plate under `target` whose top is PLATE_DROP_STUDS under it, in `parent`.
local function plateUnder(parent: Instance, target: Vector3): number
	local plate = Instance.new("Part")
	plate.Name = "BombTestPlate"
	plate.Anchored = true
	plate.CanCollide = true
	plate.Size = PLATE_SIZE
	plate.Position = target - Vector3.new(0, PLATE_DROP_STUDS + PLATE_SIZE.Y / 2, 0)
	plate.Parent = parent
	return plate.Position.Y + PLATE_SIZE.Y / 2
end

return {
	name = "bomb_lob_falls_back_to_target_ground",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
		ctx.problems = {}
	end,

	run = function(ctx: any)
		local boss, humanoid, root = ctx.hf:fakeBoss()
		local spec = bombFixture.spec()
		local problems: { string } = ctx.problems
		local target = root.Position
		local plateTop = plateUnder(ctx.hf.container, target)
		ctx.built = true

		for _, world in { "island", "ledge" } do
			local floor: Part? = nil
			if world == "ledge" then
				floor = Instance.new("Part")
				floor.Name = "BombTestLowFloor"
				floor.Anchored = true
				floor.CanCollide = true
				floor.Size = FLOOR_SIZE
				floor.Position = Vector3.new(target.X, plateTop - FAR_BELOW_STUDS - FLOOR_SIZE.Y / 2, target.Z)
				floor.Parent = ctx.hf.container
			end
			for attempt = 1, ATTEMPTS do
				local bombs = BossBombs.new(boss, humanoid, root, spec)
				if not bombs then
					ctx.built = false
					return
				end
				local clock = bombFixture.clock()
				local model = bombFixture.lobAndLand(bombs, clock, target, nil)
				local centre = if model then model:GetAttribute(BombConstants.CENTRE_ATTRIBUTE) else nil
				if typeof(centre) ~= "Vector3" then
					table.insert(problems, string.format("%s %d: no puzzle landed", world, attempt))
				else
					local expected = Vector3.new(target.X, plateTop + spec.bombHoverHeight, target.Z)
					if (centre - expected).Magnitude > POSITION_TOLERANCE then
						table.insert(problems, string.format("%s %d: landed at %s, expected the target's ground %s", world, attempt, tostring(centre), tostring(expected)))
					end
				end
				bombs:destroy()
			end
			if floor then
				floor:Destroy()
			end
		end
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.built then
			return false, "BossBombs.new returned nil for a bomb-configured type"
		end
		if #ctx.problems > 0 then
			return false, ctx.problems[1]
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
