--!strict

----------------------------------------------------------------------
-- bomb_ends_with_boss — a puzzle is removed silently when the boss dies or the controller is destroyed, in every phase: lob in the air, resting, chasing
----------------------------------------------------------------------
-- MODULE LEVEL: BossBombs on a stand-in boss, ticked by hand with an injected
-- clock. For each phase of a puzzle's life (in flight, resting, chasing) it
-- ends two ways: the controller's destroy(), and the boss's health going to 0
-- followed by the next tick.
-- After each: the Model is gone (or never appears), nothing is live or in the
-- air, the attack's callback never ran for a lob that never landed, and with
-- the clock moved past the landing, the timer and a lifetime nothing appears,
-- hatches or bursts: no BombLanded for the lob that was dropped, no BombBurst,
-- no BombDefused, no BombBroken, no BombHatched and no damage event.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)
local BossBombs = require(ServerScriptService.Server.Boss.Scripts.BossBombs)

local ARENA_ID = "BombEnds"
-- Past a flight, a timer and any seeker's lifetime.
local PAST_EVERYTHING_SEC = 60
local PHASES = { "flight", "resting", "chasing" }
local WAYS = { "destroy", "death" }

return {
	name = "bomb_ends_with_boss",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
		bombFixture.record(ctx)
		ctx.gone = {}
	end,

	run = function(ctx: any)
		local spec = bombFixture.spec()
		ctx.built = true
		ctx.reached = {}

		for _, phase in PHASES do
			for _, way in WAYS do
				local key = phase .. "/" .. way
				local boss, humanoid, root = ctx.hf:fakeBoss()
				local bombs = BossBombs.new(boss, humanoid, root, spec)
				if not bombs then
					ctx.built = false
					return
				end
				local clock = bombFixture.clock()
				local started, state = bombFixture.lob(bombs, clock, root.Position, nil)
				local model: Model? = nil
				if phase ~= "flight" then
					model = bombFixture.land(bombs, clock)
				end
				if phase == "chasing" and model ~= nil then
					bombFixture.hatchAll(bombs, clock, model)
				end
				local expectedHere = started and (phase == "flight" or model ~= nil)
				ctx.reached[key] = expectedHere
				if phase == "chasing" and model ~= nil and bombs:liveCount() == 0 then
					ctx.reached[key] = false
				end

				if way == "destroy" then
					bombs:destroy()
				else
					humanoid.Health = 0
					bombFixture.jump(bombs, clock, 0)
				end
				bombFixture.jump(bombs, clock, PAST_EVERYTHING_SEC)
				ctx.gone[key] = (model == nil or model.Parent == nil)
					and bombs:liveCount() == 0
					and #bombs:liveModels() == 0
					and not bombs:isInFlight()
					and (phase ~= "flight" or not state.landed)
				bombs:destroy()
				task.wait(bombFixture.SETTLE_SEC)
			end
		end
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.built then
			return false, "BossBombs.new returned nil for a bomb-configured type"
		end
		for _, phase in PHASES do
			for _, way in WAYS do
				local key = phase .. "/" .. way
				if not ctx.reached[key] then
					return false, key .. ": the puzzle never reached that phase"
				end
				if not ctx.gone[key] then
					return false, key .. ": the puzzle was still in the world or in the air, or its attack callback ran"
				end
			end
		end
		-- BombLanded fires for the resting and chasing cases only (4 puzzles).
		if #ctx.landed ~= 4 then
			return false, string.format("BombLanded fired %d times, expected 4 (a dropped lob never lands)", #ctx.landed)
		end
		if #ctx.bursts ~= 0 or #ctx.defused ~= 0 or #ctx.damage ~= 0 then
			return false, "a puzzle burst, was solved or hurt someone while the boss was ending"
		end
		-- The two chasing puzzles hatched before they were ended; nothing after.
		if #ctx.broken ~= 2 or #ctx.hatched ~= 2 then
			return false, string.format("BombBroken fired %d and BombHatched %d times, expected 2 each (the chasing cases only)", #ctx.broken, #ctx.hatched)
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		bombFixture.disconnect(ctx)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
