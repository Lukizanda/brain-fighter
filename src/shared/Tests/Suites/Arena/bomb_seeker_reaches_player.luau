--!strict

----------------------------------------------------------------------
-- bomb_seeker_reaches_player — hatched seekers chase their player and burst on them for bombBurstDamage; the word is already broken and no word is credited
----------------------------------------------------------------------
-- MODULE LEVEL with the harness player: BossBombs on a stand-in boss in the
-- throwaway arena the player is moved into (bossEntranceFixture, no round),
-- ticked by hand with an injected clock and dt. A floor slab lies under the
-- boss; the player's root is parked, anchored, 60 studs away at the boss's
-- height. The puzzle is lobbed at the player, left to run out, and its seekers
-- chase.
--   Chase     the seekers arrive and burst: BombBurst fires once per unlocked
--             letter and reports the player hit (1); the player lost
--             bombBurstDamage per burst, cause BombBurst, no source player;
--   Broken    BombBroken fired once (at the hatch), the Model's BombBroken is
--             true;
--   End       no seeker is left and the Model is gone, silently, no BombDefused.
-- Health may regen a point or two while the test runs, hence the slack.
--
-- NOT covered: the burst cue (a client view is needed) and a second player; a
-- burst outside the radius is bomb_seeker_hits_wall / bomb_seeker_lifetime.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)

local PLAYER_OFFSET = Vector3.new(0, 0, 60)
local REGEN_SLACK = 3

return {
	name = "bomb_seeker_reaches_player",

	setup = function(ctx: any)
		bombFixture.record(ctx)
	end,

	run = function(ctx: any)
		if not bombFixture.begin(ctx) then
			return
		end
		local player: Player = ctx.player
		local bombs = ctx.bombs
		local clock = ctx.clock
		local root: BasePart = ctx.root
		bombFixture.addFloor(ctx)

		local playerAt = root.Position + PLAYER_OFFSET
		local playerHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not bombFixture.placePlayer(player, playerAt) or not playerHumanoid then
			return
		end
		ctx.placed = true
		playerHumanoid.Health = playerHumanoid.MaxHealth
		local before = playerHumanoid.Health

		local model = bombFixture.lobAndLand(bombs, clock, playerAt, bombFixture.rootOf(player))
		if not model then
			return
		end
		ctx.landedOk = true
		ctx.letterCount = #bombFixture.letters(model)
		bombFixture.hatchAll(bombs, clock, model)

		ctx.done = bombFixture.runUntil(bombs, clock, bombFixture.STEP_SEC, function()
			return model.Parent == nil
		end)
		task.wait(bombFixture.SETTLE_SEC)
		ctx.loss = before - playerHumanoid.Health
		ctx.brokenAttr = model:GetAttribute(BombConstants.BROKEN_ATTRIBUTE)
		ctx.maxHealth = playerHumanoid.MaxHealth
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.player then
			return false, "no player on the server"
		end
		if not ctx.bombs then
			return false, "BossBombs.new returned nil, or the arena build failed"
		end
		if not ctx.placed then
			return false, "the transfer failed, or the character has no root"
		end
		if not ctx.landedOk then
			return false, "no puzzle landed"
		end
		if not ctx.done then
			return false, "the seekers never all burst (they should have reached their player)"
		end
		if #ctx.hatched ~= 1 or ctx.hatched[1].seekerCount ~= ctx.letterCount then
			return false, "BombHatched did not report every letter as a seeker"
		end
		if #ctx.bursts ~= ctx.letterCount then
			return false, string.format("%d bursts, expected %d (one per seeker)", #ctx.bursts, ctx.letterCount)
		end
		for _, burst in ctx.bursts do
			if burst.hitCount ~= 1 then
				return false, "a burst on the player reported " .. tostring(burst.hitCount) .. " hit"
			end
		end
		local expected = ctx.spec.bombBurstDamage * ctx.letterCount
		if ctx.loss < expected - REGEN_SLACK then
			return false, string.format("the player lost %.2f, expected at least %s", ctx.loss, tostring(expected))
		end
		local event = ctx.damage[1]
		if not event then
			return false, "no PlayerDamaged event for the burst"
		end
		if event.source ~= nil or event.cause ~= BombConstants.BURST_CAUSE then
			return false, string.format("burst damage had source %s and cause %s", tostring(event.source), tostring(event.cause))
		end
		if #ctx.broken ~= 1 or ctx.brokenAttr ~= true then
			return false, string.format("BombBroken fired %d times, attribute %s", #ctx.broken, tostring(ctx.brokenAttr))
		end
		if #ctx.defused ~= 0 then
			return false, "a hatched puzzle also completed the word"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		bombFixture.finish(ctx)
	end,
}
