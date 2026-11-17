--!strict

----------------------------------------------------------------------
-- spore_bursts_at_fuse — a spore bursts when its fuse runs out: it hurts a player inside the radius, not one outside, and is gone
----------------------------------------------------------------------
-- MODULE LEVEL with the harness player: BossSpores on a stand-in boss in the
-- throwaway arena the player is moved into (bossEntranceFixture, no round),
-- ticked by hand. The lob's land radius is cut to 1 stud so where a spore
-- lands is known to within a stud, and the count to 1. The player's root is
-- parked, anchored, in the air (the arena has no floor).
--   Outside   the spore lands 20 studs from the player (burst radius 8): at
--             the fuse it is gone and the player's health is untouched.
--   Inside    the spore lands on the player: at the fuse it is gone and the
--             player lost sporeBurstDamage, with cause SporeBurst and no
--             source player (read off the PlayerDamaged event).
-- Health may regen a point or two while waiting, hence the slack.
--
-- NOT covered: the burst cue (a client view is needed), a second player, and
-- a burst through the real boss's tick (the real boss is covered by
-- spore_ends_with_boss for its ending only).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local BossSpores = require(ServerScriptService.Server.Boss.Scripts.BossSpores)
local bossEntranceFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bossEntranceFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)
local restoreToSafeSpawn = require(ReplicatedStorage.Shared.Tests.Helpers.restoreToSafeSpawn)
local sporeFixture = require(ReplicatedStorage.Shared.Tests.Helpers.sporeFixture)

local playerDamagedEvent = ServerScriptService.Server.Health.Events.PlayerDamaged :: BindableEvent

local PLAYER_OFFSET = Vector3.new(0, 0, 100)
local TARGET_OUTSIDE_OFFSET = Vector3.new(20, 0, 0)
local LAND_RADIUS = 1
local NEVER_REFILL_SEC = 600
local BURST_TIMEOUT_SEC = 3
local REGEN_SLACK = 3
-- The pool the spores land in needs a field volume; it sits well away.
local ZONE_OFFSET = Vector3.new(0, 0, -60)

-- Lob at `target` and tick until the spore is gone (burst); false if it never
-- landed or never went.
local function lobAndWait(spores: any, target: Vector3): boolean
	if sporeFixture.landSpores(spores, target) == nil then
		return false
	end
	local started = os.clock()
	while spores:liveCount() > 0 and os.clock() - started < BURST_TIMEOUT_SEC do
		task.wait(sporeFixture.POLL_SEC)
		spores:tick()
	end
	return spores:liveCount() == 0
end

return {
	name = "spore_bursts_at_fuse",

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
		local boss, humanoid, root = hf:fakeBoss()
		hf:pool({ hf:zone(root.Position + ZONE_OFFSET) }, NEVER_REFILL_SEC)
		local spec = sporeFixture.spec({ sporeCount = 1, sporeLandRadius = LAND_RADIUS })
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

		-- Outside the radius.
		local outsideBurst = lobAndWait(spores, playerAt + TARGET_OUTSIDE_OFFSET)
		ctx.outsideGone = outsideBurst
		ctx.outsideHealth = playerHumanoid.Health
		ctx.outsideDamageEvents = #ctx.damage

		-- Inside the radius.
		local before = playerHumanoid.Health
		ctx.insideGone = lobAndWait(spores, playerAt)
		task.wait(sporeFixture.POLL_SEC)
		ctx.insideLoss = before - playerHumanoid.Health
		ctx.insideEvent = ctx.damage[ctx.outsideDamageEvents + 1]
		ctx.maxHealth = playerHumanoid.MaxHealth
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.placed then
			return false, "no player on the server, the transfer failed, or the character has no root"
		end
		if not ctx.built then
			return false, "BossSpores.new returned nil for a spore-configured type"
		end
		if not ctx.outsideGone then
			return false, "the spore landed outside the radius never burst (or was never removed)"
		end
		if ctx.outsideHealth < ctx.maxHealth - 0.01 or ctx.outsideDamageEvents ~= 0 then
			return false, "a player 20 studs from a burst (radius 8) was hurt"
		end
		if not ctx.insideGone then
			return false, "the spore landed on the player never burst (or was never removed)"
		end
		local expected = ctx.spec.sporeBurstDamage
		if ctx.insideLoss > expected + 0.01 or ctx.insideLoss < expected - REGEN_SLACK then
			return false, string.format("a player inside the radius lost %.2f, expected %s", ctx.insideLoss, tostring(expected))
		end
		local event = ctx.insideEvent
		if not event then
			return false, "no PlayerDamaged event for the burst"
		end
		if event.source ~= nil or event.cause ~= BossConstants.SPORE_BURST_CAUSE then
			return false, string.format("burst damage had source %s and cause %s", tostring(event.source), tostring(event.cause))
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
