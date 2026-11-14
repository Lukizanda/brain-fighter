--!strict

----------------------------------------------------------------------
-- hunger_eats_nearest — a real boss pulls the nearest letter (by horizontal
-- distance, even a high one), eats it on arrival and heals
----------------------------------------------------------------------
-- REAL BOSS: the real BossService spawns a real rig in a throwaway arena
-- (bossEntranceFixture); BossController ticks its hunger on Heartbeat with a
-- short interval and a modest pull speed from config. Three blocks of the
-- test's own pool: one HIGH above the boss but close horizontally (the
-- farthest in 3D, the nearest horizontally), one low and farther
-- horizontally (the nearest in 3D), one beyond the radius. The first tow takes
-- the high one, which moves toward the boss, and on arrival is eaten and
-- raises health by the configured fraction of max health; the others stay.
--
-- NOT covered: the tether the players would see (a client view is needed,
-- vfx-sfx.md).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local bossEntranceFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bossEntranceFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local INTERVAL_SEC = 0.4
local RADIUS_STUDS = 50
local PULL_SPEED = 60
local REACH_STUDS = 4
local FRACTION = 0.1
local START_HEALTH_FRACTION = 0.5
-- Horizontal 15, 45 up: 3D distance ~47.
local HIGH_OFFSET = Vector3.new(15, 45, 0)
-- Horizontal 30, level: 3D distance 30, so 3D "nearest" would pick this.
local LOW_OFFSET = Vector3.new(0, 0, 30)
local BEYOND_OFFSET = Vector3.new(80, 0, 0)
local SPAWN_TIMEOUT_SEC = 3
-- The boss is dropped onto its BossPoint; let it settle before measuring.
local SETTLE_SEC = 1
local TOW_TIMEOUT_SEC = 3
local EAT_TIMEOUT_SEC = 4
-- How far a block may already have travelled when first seen in tow.
local FIRST_SEEN_SLACK_STUDS = 8
local PROGRESS_WAIT_SEC = 0.15
local PROGRESS_MIN_STUDS = 1
local NEVER_REFILL_SEC = 600
local HEALTH_TOLERANCE = 0.01

return {
	name = "hunger_eats_nearest",

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

		local highAt = root.Position + HIGH_OFFSET
		local lowAt = root.Position + LOW_OFFSET
		local beyondAt = root.Position + BEYOND_OFFSET
		local pool = hf:pool({ hf:zone(highAt), hf:zone(lowAt), hf:zone(beyondAt) }, NEVER_REFILL_SEC)

		humanoid.Health = humanoid.MaxHealth * START_HEALTH_FRACTION
		local startHealth = humanoid.Health
		ctx.expectedGain = humanoid.MaxHealth * FRACTION

		local towedBlock: Model? = nil
		bf:waitFor(function()
			towedBlock = hf:towed(pool)[1]
			return towedBlock ~= nil
		end, TOW_TIMEOUT_SEC)
		local block = towedBlock
		if block == nil then
			return
		end
		ctx.towStarted = true
		ctx.pulledHigh = (block:GetPivot().Position - highAt).Magnitude <= FIRST_SEEN_SLACK_STUDS

		local before = (block:GetPivot().Position - root.Position).Magnitude
		task.wait(PROGRESS_WAIT_SEC)
		ctx.moving = block.Parent ~= nil
			and (block:GetPivot().Position - root.Position).Magnitude < before - PROGRESS_MIN_STUDS

		ctx.healed = bf:waitFor(function()
			return humanoid.Health > startHealth
		end, EAT_TIMEOUT_SEC) ~= nil
		ctx.gain = humanoid.Health - startHealth
		ctx.highGone = block.Parent == nil
		ctx.lowKept = hf:blockAt(pool, lowAt) ~= nil
		ctx.beyondKept = hf:blockAt(pool, beyondAt) ~= nil
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.built then
			return false, "no player on the server, or the transfer failed"
		end
		if not ctx.spawned then
			return false, "the boss did not spawn"
		end
		if not ctx.towStarted then
			return false, "the boss never started pulling a letter within the timeout"
		end
		if not ctx.pulledHigh then
			return false, "the first letter pulled was not the horizontally nearest (high) one"
		end
		if not ctx.moving then
			return false, "the letter in tow did not move toward the boss"
		end
		if not ctx.healed then
			return false, "the boss never ate and healed within the timeout"
		end
		if math.abs(ctx.gain - ctx.expectedGain) > HEALTH_TOLERANCE then
			return false, string.format("health rose by %s, expected %s", tostring(ctx.gain), tostring(ctx.expectedGain))
		end
		if not ctx.highGone then
			return false, "the pulled letter is still in the world after the boss healed"
		end
		if not ctx.lowKept or not ctx.beyondKept then
			return false, "a letter that was not the nearest was eaten on the first meal"
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
