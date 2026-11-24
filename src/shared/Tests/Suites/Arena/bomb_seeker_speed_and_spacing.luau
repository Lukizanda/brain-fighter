--!strict

----------------------------------------------------------------------
-- bomb_seeker_speed_and_spacing — a seeker's speed ramps linearly with its age; each seeker holds its own side slot until the converge distance, then closes to the player
----------------------------------------------------------------------
-- MODULE LEVEL with the harness player: BossBombs on a stand-in boss, ticked
-- by hand with an injected clock and dt.
--   Speed     BossBombs.speedAt is bombSeekerSpeed at age 0, bombSeekerSpeedMax
--             at the lifetime (and beyond), the mean halfway; a step really is
--             speedAt(age) x dt: at age 0, and near the end of the lifetime. The
--             shipped speed and maximum are equal (a flat 20), so this runs on an
--             object whose maximum is raised, to keep the ramp code tested;
--   Spacing   after the hatch every seeker's step points along the aim the rule
--             gives it: the line to the player turned sideways by its slot
--             (slot x bombSeekerSpacing, the slots centred on 0, so the middle
--             seeker of three aims straight), the slot shrinking in proportion
--             to the distance inside bombSeekerConvergeStuds (so the near
--             player is aimed at more directly than the far one).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)
local BossBombs = require(ServerScriptService.Server.Boss.Scripts.BossBombs)

local STEP_SEC = 0.1
-- Inside the converge distance, and farther from every resting letter than the
-- trigger distance, so nothing bursts at the hatch.
local NEAR_STUDS = 8
local SPACED_STUDS = 100
local NEAR_END_SEC = 0.01
local EPSILON = 0.01
local DIRECTION_TOLERANCE = 0.0001
-- The ramp object: a floor and a ceiling that differ.
local RAMP_SPEED = 4
local RAMP_SPEED_MAX = 14

-- The aim the rule gives seeker `index` of `count` from `from` toward `target`.
local function expectedAim(spec: any, index: number, count: number, from: Vector3, target: Vector3): Vector3
	local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
	local distance = flat.Magnitude
	local heading = flat.Unit
	local slot = index - (count + 1) / 2
	local lateral = slot * spec.bombSeekerSpacing * math.clamp(distance / spec.bombSeekerConvergeStuds, 0, 1)
	local side = Vector3.new(-heading.Z, 0, heading.X)
	return (flat + side * lateral).Unit
end

-- Land, hatch everything and take one STEP_SEC tick with the player `distance`
-- studs away along +Z. Returns, per seeker, the position before the tick and the
-- movement of the tick; nil when the setup failed.
local function stepOnce(ctx: any, distance: number): ({ { from: Vector3, move: Vector3 } }?, Vector3?)
	local player: Player = ctx.player
	local bombs = ctx.bombs
	local clock = ctx.clock
	local root: BasePart = ctx.root
	local playerAt = root.Position + Vector3.new(0, 0, distance)
	if not bombFixture.placePlayer(player, playerAt) then
		return nil, nil
	end
	local model = bombFixture.lobAndLand(bombs, clock, root.Position, bombFixture.rootOf(player))
	if not model then
		return nil, nil
	end
	bombFixture.hatchAll(bombs, clock, model)
	local count = #bombFixture.letters(model)
	local before: { Vector3 } = {}
	for index = 1, count do
		local part = bombFixture.seeker(model, index)
		if not part then
			return nil, nil
		end
		before[index] = part.Position
	end
	bombFixture.advance(bombs, clock, STEP_SEC)
	local out: { { from: Vector3, move: Vector3 } } = {}
	for index = 1, count do
		local part = bombFixture.seeker(model, index)
		if not part then
			return nil, nil
		end
		out[index] = { from = before[index], move = part.Position - before[index] }
	end
	-- Clear the puzzle for the next case.
	bombs:destroy()
	return out, playerAt
end

return {
	name = "bomb_seeker_speed_and_spacing",

	setup = function(_ctx: any) end,

	run = function(ctx: any)
		if not bombFixture.begin(ctx) then
			return
		end
		local spec = ctx.spec
		local lifetime: number = spec.bombSeekerLifetimeSec

		-- Speed, on an object with a real ramp.
		local rampSpec = bombFixture.spec({ bombSeekerSpeed = RAMP_SPEED, bombSeekerSpeedMax = RAMP_SPEED_MAX })
		local ramp = BossBombs.new(ctx.boss, ctx.humanoid, ctx.root, rampSpec)
		if not ramp then
			return
		end
		ctx.ramp = ramp
		ctx.speedAtZero = ramp:speedAt(0)
		ctx.speedAtEnd = ramp:speedAt(lifetime)
		ctx.speedPast = ramp:speedAt(lifetime * 2)
		ctx.speedHalf = ramp:speedAt(lifetime / 2)
		ctx.expectedHalf = (RAMP_SPEED + RAMP_SPEED_MAX) / 2
		ctx.shippedFlat = ctx.bombs:speedAt(lifetime / 2)

		local player: Player = ctx.player
		local root: BasePart = ctx.root
		local clock = ctx.clock
		local farAt = root.Position + Vector3.new(0, 0, bombFixture.FAR_STUDS)
		if not bombFixture.placePlayer(player, farAt) then
			return
		end
		local model = bombFixture.lobAndLand(ramp, clock, root.Position, bombFixture.rootOf(player))
		if not model then
			return
		end
		bombFixture.expire(ramp, clock, model)
		local part = bombFixture.seeker(model, 1)
		if not part then
			return
		end
		-- One step at age 0: the same `now`, so the age is exactly 0.
		local start = part.Position
		ramp:tick(STEP_SEC, clock.now)
		ctx.stepAtZero = (part.Position - start).Magnitude
		-- Jump to just before the lifetime ends (dt 0, nothing flies), then one step.
		bombFixture.jump(ramp, clock, lifetime - NEAR_END_SEC)
		local mid = part.Position
		ramp:tick(STEP_SEC, clock.now)
		ctx.stepAtEnd = (part.Position - mid).Magnitude
		ctx.expectedEnd = ramp:speedAt(lifetime - NEAR_END_SEC) * STEP_SEC
		ctx.rampSpec = rampSpec
		ctx.speedGood = true
		ramp:destroy()
		ctx.ramp = nil
		task.wait(bombFixture.SETTLE_SEC)

		-- Spacing: a fresh object per distance.
		local function fresh(): boolean
			local made = BossBombs.new(ctx.boss, ctx.humanoid, ctx.root, spec)
			ctx.bombs = made
			ctx.clock = bombFixture.clock()
			return made ~= nil
		end
		ctx.bombs:destroy()
		if not fresh() then
			return
		end
		ctx.far, ctx.farAt = stepOnce(ctx, SPACED_STUDS)
		if not fresh() then
			return
		end
		ctx.near, ctx.nearAt = stepOnce(ctx, NEAR_STUDS)
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.player or not ctx.speedGood then
			return false, "no player on the server, or the arena build failed"
		end
		local spec = ctx.spec
		if math.abs(ctx.shippedFlat - spec.bombSeekerSpeed) > EPSILON or spec.bombSeekerSpeed ~= spec.bombSeekerSpeedMax then
			return false, "the shipped speeds are not the flat value the design asks for"
		end
		if math.abs(ctx.speedAtZero - RAMP_SPEED) > EPSILON then
			return false, "speed at age 0 was " .. tostring(ctx.speedAtZero)
		end
		if math.abs(ctx.speedAtEnd - RAMP_SPEED_MAX) > EPSILON or math.abs(ctx.speedPast - RAMP_SPEED_MAX) > EPSILON then
			return false, string.format("speed at the full age was %s (past it %s)", tostring(ctx.speedAtEnd), tostring(ctx.speedPast))
		end
		if math.abs(ctx.speedHalf - ctx.expectedHalf) > EPSILON then
			return false, "speed at half the lifetime was " .. tostring(ctx.speedHalf)
		end
		if math.abs(ctx.stepAtZero - RAMP_SPEED * STEP_SEC) > EPSILON then
			return false, string.format("a step at age 0 moved %.3f, expected %.3f", ctx.stepAtZero, RAMP_SPEED * STEP_SEC)
		end
		if math.abs(ctx.stepAtEnd - ctx.expectedEnd) > EPSILON
			or math.abs(ctx.stepAtEnd - RAMP_SPEED_MAX * STEP_SEC) > EPSILON
		then
			return false, string.format(
				"a step near the end of the lifetime moved %.3f, expected about %.3f", ctx.stepAtEnd, RAMP_SPEED_MAX * STEP_SEC
			)
		end

		if ctx.far == nil or ctx.near == nil then
			return false, "the spacing cases could not be set up"
		end
		for _, case in { { list = ctx.far, at = ctx.farAt, name = "far" }, { list = ctx.near, at = ctx.nearAt, name = "near" } } do
			local list: { { from: Vector3, move: Vector3 } } = case.list
			for index, entry in list do
				local aim = expectedAim(spec, index, #list, entry.from, case.at)
				local direction = entry.move.Unit
				if 1 - direction:Dot(aim) > DIRECTION_TOLERANCE then
					return false, string.format(
						"seeker %d (%s player) stepped %s, expected a step along %s", index, case.name, tostring(direction), tostring(aim)
					)
				end
			end
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.ramp then
			ctx.ramp:destroy()
		end
		bombFixture.finish(ctx)
	end,
}
