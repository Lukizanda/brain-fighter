--!strict

----------------------------------------------------------------------
-- hunger_ends_with_boss — a letter in tow is removed when the boss dies or the round ends
----------------------------------------------------------------------
-- REAL BOSS (as hunger_eats_nearest), with a slow pull so a letter is in tow
-- for seconds. Two scenarios, each with its own boss and arena:
--   death     the boss's health goes to 0 (its death handler destroys the
--             controller): the letter is removed, the boss does not heal
--             from it, and the zone refills (short respawn delay);
--   roundEnd  the round ends (BossService destroys the controller): the same.
-- The zone refilling is the pool's normal reply to a removal, which is what
-- "removed as after a pop" means.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local bossEntranceFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bossEntranceFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local INTERVAL_SEC = 0.4
local RADIUS_STUDS = 60
local PULL_SPEED = 5
local REACH_STUDS = 4
local FRACTION = 0.1
local ZONE_OFFSET = Vector3.new(40, 0, 0)
local SPAWN_TIMEOUT_SEC = 3
local SETTLE_SEC = 1
local TOW_TIMEOUT_SEC = 3
local REMOVED_TIMEOUT_SEC = 2
local REFILL_TIMEOUT_SEC = 2
local RESPAWN_SEC = 0.05

type Scenario = { name: string, finish: (bf: any, humanoid: Humanoid) -> () }

local SCENARIOS: { Scenario } = {
	{ name = "death", finish = function(_bf: any, humanoid: Humanoid) humanoid.Health = 0 end },
	{ name = "roundEnd", finish = function(bf: any, _humanoid: Humanoid) bf:endRound() end },
}

-- Returns nil when the scenario ran, otherwise why it could not.
local function runScenario(ctx: any, scenario: Scenario): string?
	local player: Player = ctx.player
	local bf = bossEntranceFixture.new()
	ctx.bfs[scenario.name] = bf
	if not bf:build(player, {
		entranceDelaySec = nil,
		withPad = false,
		configureSpec = function(spec: any)
			spec.eatIntervalSec = INTERVAL_SEC
			spec.eatRadius = RADIUS_STUDS
			spec.eatPullSpeed = PULL_SPEED
			spec.eatReach = REACH_STUDS
			spec.eatHealFraction = FRACTION
		end,
	}) then
		return "no player on the server, or the transfer failed"
	end
	local hf = hungerFixture.new(bf.arenaId)
	ctx.hfs[scenario.name] = hf

	bf:startRound()
	if bf:waitFor(function() return bf:boss() ~= nil end, SPAWN_TIMEOUT_SEC) == nil then
		return "the boss did not spawn"
	end
	task.wait(SETTLE_SEC)
	local boss = bf:boss()
	local humanoid = boss and boss:FindFirstChildOfClass("Humanoid")
	local root = boss and boss:FindFirstChild("HumanoidRootPart")
	if not boss or not humanoid or not root or not root:IsA("BasePart") then
		return "the boss has no humanoid or root"
	end

	local zoneAt = root.Position + ZONE_OFFSET
	local pool = hf:pool({ hf:zone(zoneAt) }, RESPAWN_SEC)
	humanoid.Health = humanoid.MaxHealth / 2
	local startHealth = humanoid.Health

	local towed: Model? = nil
	bf:waitFor(function()
		towed = hf:towed(pool)[1]
		return towed ~= nil
	end, TOW_TIMEOUT_SEC)
	local block = towed
	if block == nil then
		return "the boss never started pulling a letter"
	end

	scenario.finish(bf, humanoid)
	local removed = bf:waitFor(function()
		return block.Parent == nil
	end, REMOVED_TIMEOUT_SEC) ~= nil
	ctx.removed[scenario.name] = removed
	-- A boss that dies stays dead; one whose round ended has no boss left.
	ctx.noHeal[scenario.name] = humanoid.Health <= startHealth
	ctx.refilled[scenario.name] = bf:waitFor(function()
		local live = 0
		for _, other in pool:getActiveBlocks() do
			if other ~= block and other.Parent ~= nil then
				live += 1
			end
		end
		return live == pool:getTargetCount()
	end, REFILL_TIMEOUT_SEC) ~= nil
	ctx.noTow[scenario.name] = #hf:towed(pool) == 0
	return nil
end

return {
	name = "hunger_ends_with_boss",

	setup = function(ctx: any)
		ctx.bfs = {}
		ctx.hfs = {}
		ctx.removed = {}
		ctx.noHeal = {}
		ctx.refilled = {}
		ctx.noTow = {}
	end,

	run = function(ctx: any)
		if not ctx.player then
			return
		end
		for _, scenario in SCENARIOS do
			local problem = runScenario(ctx, scenario)
			if problem then
				ctx.problem = scenario.name .. ": " .. problem
				return
			end
			-- Tear this scenario's arena down before the next one builds.
			ctx.hfs[scenario.name]:destroy()
			ctx.hfs[scenario.name] = nil
			ctx.bfs[scenario.name]:cleanup(ctx.player)
			ctx.bfs[scenario.name] = nil
		end
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.player then
			return false, "no player on the server"
		end
		if ctx.problem then
			return false, ctx.problem
		end
		for _, scenario in SCENARIOS do
			local name = scenario.name
			if not ctx.removed[name] then
				return false, name .. ": the letter in tow was still in the world after it ended"
			end
			if not ctx.noHeal[name] then
				return false, name .. ": the boss healed from a letter it did not eat"
			end
			if not ctx.refilled[name] or not ctx.noTow[name] then
				return false, name .. ": the zone did not refill (or something is still in tow)"
			end
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		for _, hf in ctx.hfs do
			hf:destroy()
		end
		for _, bf in ctx.bfs do
			bf:cleanup(ctx.player)
		end
	end,
}
