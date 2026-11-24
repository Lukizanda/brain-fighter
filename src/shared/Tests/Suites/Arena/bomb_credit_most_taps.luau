--!strict

----------------------------------------------------------------------
-- bomb_credit_most_taps — a solved puzzle is credited to the player with the most accepted taps, ties to the earliest; a player who left gets nil
----------------------------------------------------------------------
-- MODULE LEVEL with the harness player P and stand-ins for a second player F
-- (a table: BossBombs only keys taps by it and reads `.Parent`; see
-- bombFixture.standIn). F never wins in the first two cases, so Health is
-- never handed a stand-in.
--   most      3 letters, F taps first then P twice: P has 2 taps to F's 1,
--             though F tapped first and P tapped last: credited P.
--   tie       4 letters, P F P F: 2 each, P reached 2 first: credited P.
--   left      3 letters, F (who has left) taps twice, P once: F has the most
--             but has left, so the event carries nil and the boss is still
--             hurt.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)
local BossBombs = require(ServerScriptService.Server.Boss.Scripts.BossBombs)

local ARENA_ID = "BombCredit"
local MAX_HEALTH = 1000
local HEALTH_TOLERANCE = 0.5

return {
	name = "bomb_credit_most_taps",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
		bombFixture.record(ctx)
	end,

	run = function(ctx: any)
		local player: Player? = ctx.player
		if not player then
			return
		end
		local boss, humanoid, root = ctx.hf:fakeBoss(MAX_HEALTH)
		local spec = bombFixture.spec()
		ctx.spec = spec
		local bombs = BossBombs.new(boss, humanoid, root, spec)
		if not bombs then
			return
		end
		ctx.bombs = bombs
		ctx.built = true
		local clock = bombFixture.clock()
		local present = bombFixture.standIn(false)
		local left = bombFixture.standIn(true)

		-- Each case: the phase (letter count) and who taps, in order.
		local cases: { { phase: number, order: { any } } } = {
			{ phase = 1, order = { present, player, player } },
			{ phase = 2, order = { player, present, player, present } },
			{ phase = 1, order = { left, player, left } },
		}
		ctx.cases = #cases
		ctx.losses = {}
		for _, case in cases do
			boss:SetAttribute(BossConstants.PHASE_ATTRIBUTE, case.phase)
			local before = humanoid.Health
			local model = bombFixture.lobAndLand(bombs, clock, root.Position, nil)
			if not model then
				return
			end
			for _, tapper in case.order do
				bombFixture.tapRight(bombs, tapper, model)
			end
			task.wait(bombFixture.SETTLE_SEC)
			table.insert(ctx.losses, before - humanoid.Health)
		end
		ctx.ran = true
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.player then
			return false, "no player on the server"
		end
		if not ctx.built then
			return false, "BossBombs.new returned nil for a bomb-configured type"
		end
		if not ctx.ran then
			return false, "a salvo never started"
		end
		if #ctx.defused ~= ctx.cases then
			return false, "BombDefused fired " .. #ctx.defused .. " times, expected " .. ctx.cases
		end
		if ctx.defused[1].player ~= ctx.player then
			return false, "most taps (P 2, F 1) was not credited to P"
		end
		if ctx.defused[2].player ~= ctx.player then
			return false, "a 2-2 tie was not credited to the player who reached 2 first"
		end
		if ctx.defused[3].player ~= nil then
			return false, "a player who left was still credited"
		end
		local expected = { 3, 4, 3 }
		for index, loss in ctx.losses do
			local want = ctx.spec.bombDefuseDamageByLetters[expected[index]] * MAX_HEALTH
			if math.abs(loss - want) > HEALTH_TOLERANCE then
				return false, string.format("case %d: the boss lost %.2f, expected %.2f", index, loss, want)
			end
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		bombFixture.disconnect(ctx)
		if ctx.bombs then
			ctx.bombs:destroy()
		end
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
