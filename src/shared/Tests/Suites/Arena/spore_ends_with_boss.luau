--!strict

----------------------------------------------------------------------
-- spore_ends_with_boss — spores are removed when the boss dies or the round ends
----------------------------------------------------------------------
-- REAL BOSS (as hunger_ends_with_boss): the real BossService spawns a real
-- rig in a throwaway arena (bossEntranceFixture), whose type carries the spore
-- config, so BossController builds a BossSpores object for it. The player is
-- far out of its detection range, so it never attacks. Two spores with a long
-- fuse are put in the arena's pool through BlockPoolRegistry; then, in two
-- scenarios, each with its own boss and arena:
--   death     the boss's health goes to 0 (its death handler destroys the
--             controller);
--   roundEnd  the round ends (BossService destroys the controller).
-- Both spores are gone afterwards, and neither burst (no damage event with
-- the SporeBurst cause).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local BlockPoolRegistry = require(ServerScriptService.Server.BlockSpawner.BlockPoolRegistry)
local bossEntranceFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bossEntranceFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)
local sporeFixture = require(ReplicatedStorage.Shared.Tests.Helpers.sporeFixture)

local playerDamagedEvent = ServerScriptService.Server.Health.Events.PlayerDamaged :: BindableEvent

local SPAWN_TIMEOUT_SEC = 3
local SETTLE_SEC = 1
local REMOVED_TIMEOUT_SEC = 2
local ZONE_OFFSET = Vector3.new(40, 0, 0)
local SPORE_OFFSETS = { Vector3.new(0, 0, 15), Vector3.new(0, 0, -15) }
local SPORE_LETTER = "E"
local SPORE_COLOR = "blue"
local LONG_FUSE_SEC = 600
local NEVER_REFILL_SEC = 600

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
			sporeFixture.apply(spec)
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

	local pool = hf:pool({ hf:zone(root.Position + ZONE_OFFSET) }, NEVER_REFILL_SEC)
	local spores: { Model } = {}
	for _, offset in SPORE_OFFSETS do
		local spore = BlockPoolRegistry.spawnSpore(bf.arenaId, SPORE_LETTER, SPORE_COLOR, root.Position + offset, LONG_FUSE_SEC)
		if spore then
			table.insert(spores, spore)
		end
	end
	if #spores ~= #SPORE_OFFSETS then
		return "the pool would not spawn the spores"
	end

	scenario.finish(bf, humanoid)
	ctx.removed[scenario.name] = bf:waitFor(function()
		for _, spore in spores do
			if spore.Parent ~= nil then
				return false
			end
		end
		return true
	end, REMOVED_TIMEOUT_SEC) ~= nil
	ctx.poolEmpty[scenario.name] = #pool:getSpores() == 0
	return nil
end

return {
	name = "spore_ends_with_boss",

	setup = function(ctx: any)
		ctx.bfs = {}
		ctx.hfs = {}
		ctx.removed = {}
		ctx.poolEmpty = {}
		ctx.bursts = 0
		ctx.connection = playerDamagedEvent.Event:Connect(function(_source: any, _humanoid: Humanoid, result: any)
			if result and result.cause == BossConstants.SPORE_BURST_CAUSE then
				ctx.bursts += 1
			end
		end)
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
			if not ctx.removed[name] or not ctx.poolEmpty[name] then
				return false, name .. ": the spores were still in the world after it ended"
			end
		end
		if ctx.bursts ~= 0 then
			return false, "a spore burst while the boss was ending"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.connection then
			ctx.connection:Disconnect()
		end
		for _, hf in ctx.hfs do
			hf:destroy()
		end
		for _, bf in ctx.bfs do
			bf:cleanup(ctx.player)
		end
	end,
}
