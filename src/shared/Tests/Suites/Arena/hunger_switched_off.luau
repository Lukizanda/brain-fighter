--!strict

----------------------------------------------------------------------
-- hunger_switched_off — no interval, radius, pull speed or reach means no appetite
----------------------------------------------------------------------
-- MODULE LEVEL, on the spec only: BossHunger builds no hunger (so the
-- controller holds no timer) for an interval or radius of 0, a negative one,
-- or one that is missing. A type that has both but no positive pull speed or
-- reach is a config mistake: also no hunger (it warns). It also pins the
-- shipped config: Brain eats at the starting values and Wizard (which has
-- none) does not.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local BossHunger = require(ServerScriptService.Server.Boss.Scripts.BossHunger)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local ARENA_ID = "HungerOff"
local INTERVAL_SEC = 5
local RADIUS_STUDS = 60
local FRACTION = 0.01
local PULL_SPEED = 12
local REACH_STUDS = 8
local BRAIN_INTERVAL_SEC = 5
local BRAIN_RADIUS_STUDS = 60
local BRAIN_PULL_SPEED = 12
local BRAIN_REACH_STUDS = 8
local BRAIN_FRACTION = 0.01
local NEGATIVE = -1

type Case = { label: string, spec: any, shouldEat: boolean }

local function spec(interval: number?, radius: number?, fraction: number?, pull: number?, reach: number?): any
	return hungerFixture.spec(interval, radius, fraction, pull, reach)
end

local CASES: { Case } = {
	{ label = "interval 0", spec = spec(0, RADIUS_STUDS, FRACTION, PULL_SPEED, REACH_STUDS), shouldEat = false },
	{ label = "radius 0", spec = spec(INTERVAL_SEC, 0, FRACTION, PULL_SPEED, REACH_STUDS), shouldEat = false },
	{ label = "negative interval", spec = spec(NEGATIVE, RADIUS_STUDS, FRACTION, PULL_SPEED, REACH_STUDS), shouldEat = false },
	{ label = "negative radius", spec = spec(INTERVAL_SEC, NEGATIVE, FRACTION, PULL_SPEED, REACH_STUDS), shouldEat = false },
	{ label = "no interval", spec = spec(nil, RADIUS_STUDS, FRACTION, PULL_SPEED, REACH_STUDS), shouldEat = false },
	{ label = "no radius", spec = spec(INTERVAL_SEC, nil, FRACTION, PULL_SPEED, REACH_STUDS), shouldEat = false },
	{ label = "no pull speed", spec = spec(INTERVAL_SEC, RADIUS_STUDS, FRACTION, nil, REACH_STUDS), shouldEat = false },
	{ label = "pull speed 0", spec = spec(INTERVAL_SEC, RADIUS_STUDS, FRACTION, 0, REACH_STUDS), shouldEat = false },
	{ label = "no reach", spec = spec(INTERVAL_SEC, RADIUS_STUDS, FRACTION, PULL_SPEED, nil), shouldEat = false },
	{ label = "reach 0", spec = spec(INTERVAL_SEC, RADIUS_STUDS, FRACTION, PULL_SPEED, 0), shouldEat = false },
	{ label = "all five present", spec = spec(INTERVAL_SEC, RADIUS_STUDS, FRACTION, PULL_SPEED, REACH_STUDS), shouldEat = true },
	{ label = "no fraction", spec = spec(INTERVAL_SEC, RADIUS_STUDS, nil, PULL_SPEED, REACH_STUDS), shouldEat = true },
}

return {
	name = "hunger_switched_off",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss()
		local wrong: { string } = {}
		for _, case in CASES do
			local hunger = BossHunger.new(boss, humanoid, root, case.spec)
			if (hunger ~= nil) ~= case.shouldEat or BossHunger.isEnabledFor(case.spec) ~= case.shouldEat then
				table.insert(wrong, case.label)
			end
		end
		ctx.wrong = wrong

		local brain = BossConfig.BOSS_TYPES.Brain
		ctx.brainOk = brain ~= nil
			and brain.eatIntervalSec == BRAIN_INTERVAL_SEC
			and brain.eatRadius == BRAIN_RADIUS_STUDS
			and brain.eatPullSpeed == BRAIN_PULL_SPEED
			and brain.eatReach == BRAIN_REACH_STUDS
			and brain.eatHealFraction == BRAIN_FRACTION
			and BossHunger.isEnabledFor(brain)
		local wizard = BossConfig.BOSS_TYPES.Wizard
		ctx.wizardEats = wizard ~= nil and BossHunger.isEnabledFor(wizard)
	end,

	verify = function(ctx: any): (boolean, string?)
		if #ctx.wrong > 0 then
			return false, "wrong on/off decision for: " .. table.concat(ctx.wrong, ", ")
		end
		if not ctx.brainOk then
			return false, "the Brain boss type does not carry the starting eat values"
		end
		if ctx.wizardEats then
			return false, "the Wizard type (no eat values) eats"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
