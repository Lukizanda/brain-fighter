--!strict

----------------------------------------------------------------------
-- spore_pop_hurts_boss — a popped spore does not burst; the boss loses 3% of its max health, credited to the popper
----------------------------------------------------------------------
-- MODULE LEVEL with the harness player: BossSpores on a stand-in boss in the
-- throwaway arena the player is moved into, ticked by hand. The spore lands
-- on the (anchored) player, so a burst would hurt them. The pop is what
-- BlockShootService does on a consume, minus the remote: read the spore mark
-- with BlockShoot.isSpore, destroy the block, fire BlockConsumed with the
-- trailing flag. Then:
--   * the boss lost sporePopDamageFraction of its max health, and the damage
--     event names the player as the source with cause SporePop;
--   * the spore did not burst: past its fuse the player is unhurt;
--   * a pop of an ordinary block (flag false) costs the boss nothing, and so
--     does a spore popped in another arena.
--
-- NOT covered: the real ConsumeBlock remote and BlockShootService reading the
-- mark off a real client's tap (needs a client); only the mark read and the
-- boss side are tested here.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BlockShoot = require(ReplicatedStorage.Shared.BlockShoot)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local BossSpores = require(ServerScriptService.Server.Boss.Scripts.BossSpores)
local bossEntranceFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bossEntranceFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)
local restoreToSafeSpawn = require(ReplicatedStorage.Shared.Tests.Helpers.restoreToSafeSpawn)
local sporeFixture = require(ReplicatedStorage.Shared.Tests.Helpers.sporeFixture)

local playerDamagedEvent = ServerScriptService.Server.Health.Events.PlayerDamaged :: BindableEvent
local blockConsumedEvent = ServerScriptService.Server.BlockShoot.Events.BlockConsumed :: BindableEvent

local PLAYER_OFFSET = Vector3.new(0, 0, 100)
local ZONE_OFFSET = Vector3.new(0, 0, -60)
local LAND_RADIUS = 1
local BOSS_MAX_HEALTH = 1000
local NEVER_REFILL_SEC = 600
-- BindableEvent handlers run deferred; one frame is enough, this is slack.
local SETTLE_SEC = 0.2
local HEALTH_TOLERANCE = 0.01
local PAST_FUSE_SEC = 0.5
local OTHER_ARENA = "SporePopOtherArena"
local FUSE_SEC = 1.2

local function popOf(block: Model, player: Player, arenaId: string, flagged: boolean)
	local letter, color = BlockShoot.readBlock(block)
	local wasSpore = flagged and BlockShoot.isSpore(block)
	block:Destroy()
	blockConsumedEvent:Fire(player, letter, color, arenaId, wasSpore)
end

return {
	name = "spore_pop_hurts_boss",

	setup = function(ctx: any)
		ctx.damage = {}
		ctx.connection = playerDamagedEvent.Event:Connect(function(sourcePlayer: any, humanoid: Humanoid, result: any)
			table.insert(ctx.damage, { source = sourcePlayer, humanoid = humanoid, cause = result and result.cause })
		end)
	end,

	run = function(ctx: any)
		local player: Player? = ctx.player
		if not player then
			return
		end
		local bf = bossEntranceFixture.new()
		ctx.bf = bf
		if not bf:build(player, { entranceDelaySec = nil, withPad = false }) then
			return
		end
		local hf = hungerFixture.new(bf.arenaId)
		ctx.hf = hf
		local boss, humanoid, root = hf:fakeBoss(BOSS_MAX_HEALTH)
		local pool = hf:pool({ hf:zone(root.Position + ZONE_OFFSET) }, NEVER_REFILL_SEC)
		local spec = sporeFixture.spec({ sporeCount = 1, sporeLandRadius = LAND_RADIUS, sporeFuseSec = FUSE_SEC })
		ctx.spec = spec
		local spores = BossSpores.new(boss, humanoid, root, spec)
		if not spores then
			return
		end
		ctx.built = true

		local playerAt = root.Position + PLAYER_OFFSET
		local character = player.Character
		local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not sporeFixture.placePlayer(player, playerAt) or not playerHumanoid then
			return
		end
		ctx.placed = true
		playerHumanoid.Health = playerHumanoid.MaxHealth

		-- An ordinary block popped: nothing.
		local field = pool:getActiveBlocks()[1]
		if field then
			popOf(field, player, bf.arenaId, true)
			task.wait(SETTLE_SEC)
			ctx.fieldPopCost = BOSS_MAX_HEALTH - humanoid.Health
		end
		if sporeFixture.landSpores(spores, playerAt) == nil then
			return
		end
		ctx.landed = true
		local block = pool:getSpores()[1]
		if not block then
			return
		end
		-- A spore pop reported for another arena must not reach this boss.
		blockConsumedEvent:Fire(player, "A", "red", OTHER_ARENA, true)
		task.wait(SETTLE_SEC)
		ctx.otherArenaCost = BOSS_MAX_HEALTH - humanoid.Health

		local damageEventsBefore = #ctx.damage
		popOf(block, player, bf.arenaId, true)
		task.wait(SETTLE_SEC)
		spores:tick()
		ctx.popCost = BOSS_MAX_HEALTH - humanoid.Health
		ctx.popEvent = ctx.damage[damageEventsBefore + 1]
		ctx.liveAfterPop = spores:liveCount()
		ctx.humanoid = humanoid

		-- Past the fuse: no burst.
		local endAt = os.clock() + spec.sporeFuseSec + PAST_FUSE_SEC
		while os.clock() < endAt do
			task.wait(sporeFixture.POLL_SEC)
			spores:tick()
		end
		ctx.playerHealthAfter = playerHumanoid.Health
		ctx.playerMax = playerHumanoid.MaxHealth
		ctx.burstEvents = 0
		for _, event in ctx.damage do
			if event.cause == BossConstants.SPORE_BURST_CAUSE then
				ctx.burstEvents += 1
			end
		end
		ctx.done = true
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.placed then
			return false, "no player on the server, the transfer failed, or the character has no root"
		end
		if not ctx.built or not ctx.landed or not ctx.done then
			return false, "fixture: the spore did not land or the test did not finish"
		end
		if ctx.fieldPopCost == nil or ctx.fieldPopCost > HEALTH_TOLERANCE then
			return false, "popping an ordinary block cost the boss " .. tostring(ctx.fieldPopCost)
		end
		if ctx.otherArenaCost > HEALTH_TOLERANCE then
			return false, "a spore pop reported for another arena cost this boss " .. tostring(ctx.otherArenaCost)
		end
		local expected = BOSS_MAX_HEALTH * ctx.spec.sporePopDamageFraction
		if math.abs(ctx.popCost - expected) > HEALTH_TOLERANCE then
			return false, string.format("the boss lost %s, expected %s (%s of max)", tostring(ctx.popCost), tostring(expected), tostring(ctx.spec.sporePopDamageFraction))
		end
		local event = ctx.popEvent
		if not event or event.source ~= ctx.player or event.humanoid ~= ctx.humanoid or event.cause ~= BossConstants.SPORE_POP_CAUSE then
			return false, "the pop damage was not credited to the popper with cause SporePop"
		end
		if ctx.liveAfterPop ~= 0 then
			return false, "the boss still tracks a spore that was popped"
		end
		if ctx.burstEvents ~= 0 or ctx.playerHealthAfter < ctx.playerMax - HEALTH_TOLERANCE then
			return false, "a popped spore still burst and hurt the player"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.connection then
			ctx.connection:Disconnect()
		end
		sporeFixture.releasePlayer(ctx.player)
		if ctx.hf then
			ctx.hf:destroy()
		end
		if ctx.bf then
			ctx.bf:cleanup(ctx.player)
		end
		if ctx.player then
			restoreToSafeSpawn.restoreToSafeSpawn(ctx.player)
		end
	end,
}
