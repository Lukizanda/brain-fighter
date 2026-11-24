--!strict

----------------------------------------------------------------------
-- bomb_lob_lands_near_target — the lobbed puzzle lands bombFlightSec later within bombLandRadius of the target, on the ground; the Model exists only from the landing, resting on a circle with the whole contract on it
----------------------------------------------------------------------
-- MODULE LEVEL with the harness player: BossBombs on a stand-in boss in the
-- throwaway arena, ticked by hand with an injected clock. A floor slab lies
-- under the boss; the lob is thrown at the boss's own position, LOBS times.
--   Flight    after beginLob and before the flight time is up there is no Model,
--             the lob is in the air, a second beginLob is refused, the attack's
--             callback has not run and BombLanded has not fired;
--   Landing   at the flight time the Model exists (tagged, in the container,
--             arena-stamped), the callback ran once, BombLanded fired once with
--             the letter count, and nothing is in the air;
--   Place     BombCentre is within bombLandRadius (horizontal) of the target
--             and bombHoverHeight over the floor, BombGroundY is the floor top;
--   Contract  BombPhase Resting, BombBroken false, BombTargetUserId 0,
--             BombReach / BombSeekerReach / BombFuseSec / BombHatchAt / BombHintAt
--             as configured, BombAccepted empty;
--   Parts     one resting part per letter on a circle of REST_RADIUS_STUDS
--             round the centre, none hatched (no Hatched, no SeekerExpiresAt),
--             anchored, non-colliding, queryable, each carrying its index.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)
local BossBombs = require(ServerScriptService.Server.Boss.Scripts.BossBombs)

local LOBS = 6
local EARLY_MARGIN_SEC = 0.1
local DISTANCE_TOLERANCE = 0.05
local HEIGHT_TOLERANCE = 0.05

-- Horizontal distance.
local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

return {
	name = "bomb_lob_lands_near_target",

	setup = function(ctx: any)
		bombFixture.record(ctx)
		ctx.problems = {}
	end,

	run = function(ctx: any)
		if not bombFixture.begin(ctx) then
			return
		end
		ctx.ran = true
		local bombs = ctx.bombs
		local clock = ctx.clock
		local spec = ctx.spec
		local root: BasePart = ctx.root
		local floorTop = bombFixture.addFloor(ctx)
		local problems: { string } = ctx.problems
		local function expect(ok: boolean, message: string)
			if not ok then
				table.insert(problems, message)
			end
		end

		for lob = 1, LOBS do
			local landedBefore = #ctx.landed
			local started, state = bombFixture.lob(bombs, clock, root.Position, nil)
			expect(started, "lob " .. lob .. ": beginLob refused")
			if not started then
				return
			end
			local thrownAt = clock.now
			expect(bombs:isInFlight(), "lob " .. lob .. ": not in flight after the throw")
			expect(not bombs:beginLob(root.Position, function() end, nil, clock.now), "lob " .. lob .. ": a second lob started while one was in the air")

			bombFixture.jump(bombs, clock, spec.bombFlightSec - EARLY_MARGIN_SEC)
			task.wait(bombFixture.POLL_SEC)
			expect(#bombs:liveModels() == 0 and not state.landed and #ctx.landed == landedBefore, "lob " .. lob .. ": the puzzle existed before the flight time was up")
			expect(bombs:isInFlight(), "lob " .. lob .. ": left flight early")

			bombFixture.jump(bombs, clock, EARLY_MARGIN_SEC)
			task.wait(bombFixture.SETTLE_SEC)
			local models = bombs:liveModels()
			local model = models[#models]
			expect(model ~= nil and state.landed, "lob " .. lob .. ": nothing landed at the flight time")
			expect(not bombs:isInFlight(), "lob " .. lob .. ": still in flight after landing")
			expect(#ctx.landed == landedBefore + 1, "lob " .. lob .. ": BombLanded did not fire exactly once")
			if model == nil then
				return
			end
			local count = #bombFixture.letters(model)
			expect(ctx.landed[#ctx.landed].letterCount == count, "lob " .. lob .. ": BombLanded reported the wrong letter count")
			expect(CollectionService:HasTag(model, BombConstants.TAG), "lob " .. lob .. ": the Model is not tagged")
			expect(model.Parent ~= nil and model.Parent.Name == BombConstants.CONTAINER_NAME, "lob " .. lob .. ": not in the container")
			expect(model:GetAttribute(Arena.ID_ATTRIBUTE) == ctx.bf.arenaId, "lob " .. lob .. ": not stamped with the arena")

			local centre = model:GetAttribute(BombConstants.CENTRE_ATTRIBUTE)
			if typeof(centre) ~= "Vector3" then
				expect(false, "lob " .. lob .. ": BombCentre is " .. typeof(centre))
				return
			end
			expect(flat(centre, root.Position) <= spec.bombLandRadius + DISTANCE_TOLERANCE, string.format("lob %d: landed %.1f studs from the target (radius %s)", lob, flat(centre, root.Position), tostring(spec.bombLandRadius)))
			expect(math.abs(centre.Y - (floorTop + spec.bombHoverHeight)) <= HEIGHT_TOLERANCE, string.format("lob %d: centre at y=%.2f, expected %.2f", lob, centre.Y, floorTop + spec.bombHoverHeight))
			local groundY = model:GetAttribute(BombConstants.GROUND_Y_ATTRIBUTE)
			expect(type(groundY) == "number" and math.abs(groundY - floorTop) <= HEIGHT_TOLERANCE, "lob " .. lob .. ": BombGroundY is not the floor top")

			expect(model:GetAttribute(BombConstants.PHASE_ATTRIBUTE) == BombConstants.Phase.Resting, "lob " .. lob .. ": not Resting")
			expect(model:GetAttribute(BombConstants.BROKEN_ATTRIBUTE) == false, "lob " .. lob .. ": BombBroken is not false")
			expect(model:GetAttribute(BombConstants.TARGET_USER_ID_ATTRIBUTE) == 0, "lob " .. lob .. ": BombTargetUserId is not 0")
			expect(model:GetAttribute(BombConstants.REACH_ATTRIBUTE) == spec.bombTapReach, "lob " .. lob .. ": BombReach is not bombTapReach")
			expect(model:GetAttribute(BombConstants.SEEKER_REACH_ATTRIBUTE) == spec.bombSeekerTapReach, "lob " .. lob .. ": BombSeekerReach is not bombSeekerTapReach")
			expect(model:GetAttribute(BombConstants.BURST_RADIUS_ATTRIBUTE) == spec.bombBurstRadius, "lob " .. lob .. ": BombBurstRadius is wrong")
			expect(model:GetAttribute(BombConstants.ACCEPTED_ATTRIBUTE) == "", "lob " .. lob .. ": BombAccepted is not empty")
			local fuse = spec.bombFuseSecByLetters[count]
			local landedAt = thrownAt + spec.bombFlightSec
			expect(model:GetAttribute(BombConstants.FUSE_SEC_ATTRIBUTE) == fuse, "lob " .. lob .. ": BombFuseSec is wrong")
			local hatchAt = model:GetAttribute(BombConstants.HATCH_AT_ATTRIBUTE)
			expect(type(hatchAt) == "number" and math.abs(hatchAt - (landedAt + fuse)) <= bombFixture.TIME_TOLERANCE_SEC, "lob " .. lob .. ": BombHatchAt is not landing plus the timer")
			local hintAt = model:GetAttribute(BombConstants.HINT_AT_ATTRIBUTE)
			expect(type(hintAt) == "number" and math.abs(hintAt - (landedAt + spec.bombHintAfterSec)) <= bombFixture.TIME_TOLERANCE_SEC, "lob " .. lob .. ": BombHintAt is not landing plus bombHintAfterSec")

			expect(bombFixture.partCount(model) == count, "lob " .. lob .. ": part count is not the letter count")
			for index = 1, count do
				local part = bombFixture.part(model, index)
				if part == nil then
					expect(false, "lob " .. lob .. ": no part " .. index)
					continue
				end
				local onCircle = math.abs(flat(part.Position, centre) - BombConstants.REST_RADIUS_STUDS) <= DISTANCE_TOLERANCE
					and math.abs(part.Position.Y - centre.Y) <= HEIGHT_TOLERANCE
				expect(onCircle, "lob " .. lob .. ": part " .. index .. " is not on the resting circle")
				expect(part.Anchored and not part.CanCollide and part.CanQuery, "lob " .. lob .. ": part " .. index .. " has the wrong physics flags")
				expect(part:GetAttribute(BombConstants.TILE_INDEX_ATTRIBUTE) == index, "lob " .. lob .. ": part " .. index .. " has the wrong BombTileIndex")
				expect(part:GetAttribute(BombConstants.HATCHED_ATTRIBUTE) == nil and part:GetAttribute(BombConstants.SEEKER_EXPIRES_ATTRIBUTE) == nil, "lob " .. lob .. ": a resting part carries hatch attributes")
			end

			-- Away for the next lob.
			bombs:destroy()
			local fresh = BossBombs.new(ctx.boss, ctx.humanoid, ctx.root, ctx.spec)
			ctx.bombs = fresh
			if fresh == nil then
				return
			end
			bombs = fresh
		end
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.player then
			return false, "no player on the server"
		end
		if not ctx.ran then
			return false, "BossBombs.new returned nil, or the arena build failed"
		end
		if #ctx.problems > 0 then
			return false, ctx.problems[1]
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		bombFixture.finish(ctx)
	end,
}
