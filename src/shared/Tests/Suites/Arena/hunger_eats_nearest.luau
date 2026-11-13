--!strict

----------------------------------------------------------------------
-- hunger_eats_nearest — a real boss eats the nearest block in reach and heals
----------------------------------------------------------------------
-- REAL BOSS: the real BossService spawns a real rig in a throwaway arena
-- (bossEntranceFixture); BossController ticks its hunger on Heartbeat with
-- a short interval from config. Three blocks of the test's own pool: one
-- near the boss, one farther but in reach, one out of reach. The first bite
-- takes the near one and raises health by the configured fraction of max
-- health; the others stay.
--
-- NOT covered: the stream and heal cue the players would see (a client view
-- is needed, vfx-sfx.md).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local bossEntranceFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bossEntranceFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local INTERVAL_SEC = 0.4
local RADIUS_STUDS = 25
local FRACTION = 0.1
local START_HEALTH_FRACTION = 0.5
local NEAR_OFFSET = Vector3.new(6, 0, 0)
local MID_OFFSET = Vector3.new(0, 0, 15)
local FAR_OFFSET = Vector3.new(40, 0, 0)
local SPAWN_TIMEOUT_SEC = 3
-- The boss is dropped onto its BossPoint; let it settle before measuring.
local SETTLE_SEC = 1
local BITE_TIMEOUT_SEC = 3
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

		local nearAt = root.Position + NEAR_OFFSET
		local midAt = root.Position + MID_OFFSET
		local farAt = root.Position + FAR_OFFSET
		local pool = hf:pool({ hf:zone(nearAt), hf:zone(midAt), hf:zone(farAt) }, NEVER_REFILL_SEC)

		humanoid.Health = humanoid.MaxHealth * START_HEALTH_FRACTION
		local startHealth = humanoid.Health
		ctx.expectedGain = humanoid.MaxHealth * FRACTION
		ctx.bitten = bf:waitFor(function()
			return humanoid.Health > startHealth
		end, BITE_TIMEOUT_SEC) ~= nil
		ctx.gain = humanoid.Health - startHealth
		ctx.nearGone = hf:blockAt(pool, nearAt) == nil
		ctx.midKept = hf:blockAt(pool, midAt) ~= nil
		ctx.farKept = hf:blockAt(pool, farAt) ~= nil
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.built then
			return false, "no player on the server, or the transfer failed"
		end
		if not ctx.spawned then
			return false, "the boss did not spawn"
		end
		if not ctx.bitten then
			return false, "the boss never ate and healed within the timeout"
		end
		if math.abs(ctx.gain - ctx.expectedGain) > HEALTH_TOLERANCE then
			return false, string.format("health rose by %s, expected %s", tostring(ctx.gain), tostring(ctx.expectedGain))
		end
		if not ctx.nearGone then
			return false, "the nearest block was not the one eaten"
		end
		if not ctx.midKept or not ctx.farKept then
			return false, "a block that was not the nearest was eaten on the first bite"
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
