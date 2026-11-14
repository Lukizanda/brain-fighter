--!strict

----------------------------------------------------------------------
-- hunger_frozen_holds — a frozen boss starts no pull and leaves a letter in tow hanging
----------------------------------------------------------------------
-- REAL BOSS (as hunger_eats_nearest). The freeze is signalled the way the
-- game signals it, by the `_frozen` attribute on the boss's character
-- (SkillConstants.FROZEN_ATTRIBUTE), which the test sets and clears by hand:
-- it does not cast a freeze spell.
--   A. Frozen from the start: over several intervals nothing goes into tow.
--   B. Thawed, a letter goes into tow; frozen again mid-tow, the letter hangs
--      exactly where it is and the boss does not heal; thawed, it carries on
--      and the boss eats it.
--
-- Stun: no stun status exists in the code today, so there is nothing to test.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local bossEntranceFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bossEntranceFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local INTERVAL_SEC = 0.4
local RADIUS_STUDS = 60
local PULL_SPEED = 20
local REACH_STUDS = 4
local FRACTION = 0.1
local START_HEALTH_FRACTION = 0.5
local NEAR_OFFSET = Vector3.new(40, 0, 0)
local SPAWN_TIMEOUT_SEC = 3
local SETTLE_SEC = 1
-- Several intervals' worth of frozen time.
local FROZEN_OBSERVE_SEC = INTERVAL_SEC * 4
local TOW_TIMEOUT_SEC = 3
local EAT_TIMEOUT_SEC = 5
local HELD_TOLERANCE_STUDS = 0.01
local NEVER_REFILL_SEC = 600

return {
	name = "hunger_frozen_holds",

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

		local nearAt = root.Position + NEAR_OFFSET
		-- Frozen before the pool exists, so there is no window in which it
		-- could pull between creating the block and setting the flag.
		boss:SetAttribute(SkillConstants.FROZEN_ATTRIBUTE, true)
		local pool = hf:pool({ hf:zone(nearAt) }, NEVER_REFILL_SEC)
		humanoid.Health = humanoid.MaxHealth * START_HEALTH_FRACTION
		local startHealth = humanoid.Health
		ctx.startHealth = startHealth

		-- A. frozen from the start: nothing goes into tow.
		task.wait(FROZEN_OBSERVE_SEC)
		ctx.noTowWhileFrozen = #hf:towed(pool) == 0 and hf:blockAt(pool, nearAt) ~= nil

		-- B. thaw: a letter goes into tow; freeze it mid-flight.
		boss:SetAttribute(SkillConstants.FROZEN_ATTRIBUTE, nil)
		local towedBlock: Model? = nil
		bf:waitFor(function()
			towedBlock = hf:towed(pool)[1]
			return towedBlock ~= nil
		end, TOW_TIMEOUT_SEC)
		local block = towedBlock
		if block == nil then
			return
		end
		ctx.towAfterThaw = true
		boss:SetAttribute(SkillConstants.FROZEN_ATTRIBUTE, true)
		-- One frame for a tick already in flight to land before the position
		-- is taken.
		task.wait()
		local heldAt = block:GetPivot().Position
		task.wait(FROZEN_OBSERVE_SEC)
		ctx.hung = block.Parent ~= nil and pool:isTowed(block)
			and (block:GetPivot().Position - heldAt).Magnitude <= HELD_TOLERANCE_STUDS
		ctx.healthWhileFrozen = humanoid.Health

		boss:SetAttribute(SkillConstants.FROZEN_ATTRIBUTE, nil)
		ctx.ateAfterThaw = bf:waitFor(function()
			return block.Parent == nil
		end, EAT_TIMEOUT_SEC) ~= nil
		ctx.healthAfterThaw = humanoid.Health
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.built then
			return false, "no player on the server, or the transfer failed"
		end
		if not ctx.spawned then
			return false, "the boss did not spawn"
		end
		if not ctx.noTowWhileFrozen then
			return false, "the frozen boss pulled a letter"
		end
		if not ctx.towAfterThaw then
			return false, "the boss did not start pulling after the freeze lifted"
		end
		if not ctx.hung then
			return false, "a letter in tow kept moving (or went) while the boss was frozen"
		end
		if ctx.healthWhileFrozen ~= ctx.startHealth then
			return false, "the frozen boss healed"
		end
		if not ctx.ateAfterThaw then
			return false, "the boss did not finish the meal after the freeze lifted"
		end
		if ctx.healthAfterThaw <= ctx.startHealth then
			return false, "the boss did not heal after eating once thawed"
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
