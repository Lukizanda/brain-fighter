--!strict

----------------------------------------------------------------------
-- hunger_popped_midtow — a player can pop a letter in tow; the boss goes hungry
----------------------------------------------------------------------
-- REAL BOSS (as hunger_eats_nearest), with a slow pull so the letter is in
-- the air for seconds. Once a letter is in tow the test pops it the way the
-- BlockShoot service does on an accepted tap (the block is destroyed). The
-- boss does not heal, the zone refills (short respawn delay) and the interval
-- starts again from zero: the next pull begins no sooner than one interval
-- after the pop, and then does begin.
--
-- NOT covered: the tap itself (remote, raycast, rate limit): the validation
-- of a moving block is in hunger_tow_poppable.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local bossEntranceFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bossEntranceFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local INTERVAL_SEC = 0.6
local RADIUS_STUDS = 60
local PULL_SPEED = 8
local REACH_STUDS = 4
local FRACTION = 0.1
local START_HEALTH_FRACTION = 0.5
local ZONE_OFFSET = Vector3.new(40, 0, 0)
local SPAWN_TIMEOUT_SEC = 3
local SETTLE_SEC = 1
local TOW_TIMEOUT_SEC = 3
local IN_FLIGHT_SEC = 0.3
local RESPAWN_SEC = 0.05
local SECOND_TOW_TIMEOUT_SEC = 3
-- Slack for the poll between the pop and noticing the next tow.
local RESTART_SLACK_SEC = 0.1

return {
	name = "hunger_popped_midtow",

	setup = function(ctx: any)
		ctx.bf = bossEntranceFixture.new()
	end,

	run = function(ctx: any)
		local player: Player? = ctx.player
		if not player then
			return
		end
		local bf = ctx.bf
		ctx.built = bf:build(player, {
			entranceDelaySec = nil,
			withPad = false,
			configureSpec = function(spec: any)
				spec.eatIntervalSec = INTERVAL_SEC
				spec.eatRadius = RADIUS_STUDS
				spec.eatPullSpeed = PULL_SPEED
				spec.eatReach = REACH_STUDS
				spec.eatHealFraction = FRACTION
			end,
		})
		if not ctx.built then
			return
		end
		local hf = hungerFixture.new(bf.arenaId)
		ctx.hf = hf

		bf:startRound()
		if bf:waitFor(function() return bf:boss() ~= nil end, SPAWN_TIMEOUT_SEC) == nil then
			return
		end
		task.wait(SETTLE_SEC)
		local boss = bf:boss()
		local humanoid = boss and boss:FindFirstChildOfClass("Humanoid")
		local root = boss and boss:FindFirstChild("HumanoidRootPart")
		if not boss or not humanoid or not root or not root:IsA("BasePart") then
			return
		end
		ctx.spawned = true

		local zoneAt = root.Position + ZONE_OFFSET
		local pool = hf:pool({ hf:zone(zoneAt) }, RESPAWN_SEC)
		humanoid.Health = humanoid.MaxHealth * START_HEALTH_FRACTION
		local startHealth = humanoid.Health

		local first: Model? = nil
		bf:waitFor(function()
			first = hf:towed(pool)[1]
			return first ~= nil
		end, TOW_TIMEOUT_SEC)
		if first == nil then
			return
		end
		ctx.towStarted = true
		task.wait(IN_FLIGHT_SEC)
		ctx.stillInFlight = first.Parent ~= nil and pool:isTowed(first)

		-- The pop.
		first:Destroy()
		local poppedAt = os.clock()
		task.wait()
		ctx.healthAfterPop = humanoid.Health
		ctx.noTowAfterPop = #hf:towed(pool) == 0

		local second: Model? = nil
		bf:waitFor(function()
			second = hf:towed(pool)[1]
			return second ~= nil
		end, SECOND_TOW_TIMEOUT_SEC)
		ctx.secondTowed = second ~= nil and second ~= first
		ctx.restartSec = os.clock() - poppedAt
		ctx.healthAtSecond = humanoid.Health
		ctx.startHealth = startHealth
		ctx.count = #pool:getActiveBlocks()
		ctx.target = pool:getTargetCount()
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.built then
			return false, "no player on the server, or the transfer failed"
		end
		if not ctx.spawned then
			return false, "the boss did not spawn"
		end
		if not ctx.towStarted then
			return false, "the boss never started pulling a letter"
		end
		if not ctx.stillInFlight then
			return false, "fixture: the letter arrived before it could be popped"
		end
		if ctx.healthAfterPop ~= ctx.startHealth or ctx.healthAtSecond ~= ctx.startHealth then
			return false, "the boss healed from a letter that was popped"
		end
		if not ctx.noTowAfterPop then
			return false, "something was still in tow right after the pop"
		end
		if not ctx.secondTowed then
			return false, "the boss never pulled again after the pop (zone not refilled, or hunger stuck)"
		end
		if ctx.restartSec < INTERVAL_SEC - RESTART_SLACK_SEC then
			return false, string.format(
				"the boss pulled again %.2f s after the pop, sooner than one interval (%.2f s)", ctx.restartSec, INTERVAL_SEC
			)
		end
		if ctx.count ~= ctx.target then
			return false, string.format("pool holds %s blocks, expected %s", tostring(ctx.count), tostring(ctx.target))
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
		if ctx.bf then
			ctx.bf:cleanup(ctx.player)
		end
	end,
}
