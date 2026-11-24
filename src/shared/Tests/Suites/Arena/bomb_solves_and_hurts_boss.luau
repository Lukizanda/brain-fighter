--!strict

----------------------------------------------------------------------
-- bomb_solves_and_hurts_boss — tapping the resting letters in order locks them, solves the puzzle, hurts the boss by the letter count's share and fires BombDefused with the scale
----------------------------------------------------------------------
-- MODULE LEVEL: BossBombs on a stand-in boss (hungerFixture), ticked by hand
-- with an injected clock. The player taps the right letter until the word is
-- complete, at phase 1 (3 letters) and phase 2 (4 letters).
--   Locking   after each accepted tap the letter's part is still there, resting,
--             and BombAccepted grew by that index;
--   Done      the Model is gone and nothing is live;
--   Damage    the boss lost bombDefuseDamageByLetters[n] x its max health;
--   Event     BombDefused fired once with the player, an allowed word of n
--             letters, the colour, the arena, n and the type's
--             bombEnergyScale; BombLanded fired with n; BombPopped(true) n
--             times; BombBurst, BombBroken and BombHatched never fired.
--
-- NOT covered: a client's tap through the remote (BombTapService) and the
-- word credit (the Economy's, ledger_grants_bomb_word).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)
local BossBombs = require(ServerScriptService.Server.Boss.Scripts.BossBombs)

local ARENA_ID = "BombSolve"
local MAX_HEALTH = 1000
local PHASES = { 1, 2 }
local LETTERS_BY_PHASE = { 3, 4 }
local HEALTH_TOLERANCE = 0.5
local MAX_TAPS = 10
local RESULT = BombConstants.TapResult

return {
	name = "bomb_solves_and_hurts_boss",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
		bombFixture.record(ctx)
		ctx.results = {}
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
		local clock = bombFixture.clock()
		for _, phase in PHASES do
			boss:SetAttribute(BossConstants.PHASE_ATTRIBUTE, phase)
			local before = humanoid.Health
			local model = bombFixture.lobAndLand(bombs, clock, root.Position, nil)
			local result: any = { phase = phase }
			table.insert(ctx.results, result)
			if not model then
				return
			end
			result.landed = true
			result.lockedEach = true
			for _ = 1, MAX_TAPS do
				local tile = bombFixture.rightTile(model)
				if tile == nil then
					break
				end
				local acceptedBefore = #bombFixture.accepted(model)
				local tapResult = bombs:tap(player, model, tile)
				if model.Parent ~= nil then
					-- Not the last: the letter is locked and its part still rests.
					if tapResult ~= RESULT.Accepted or bombFixture.part(model, tile) == nil
						or #bombFixture.accepted(model) ~= acceptedBefore + 1
						or bombFixture.seekerCount(model) ~= 0
					then
						result.lockedEach = false
					end
				elseif tapResult ~= RESULT.Accepted then
					result.lockedEach = false
				end
			end
			task.wait(bombFixture.SETTLE_SEC)
			result.gone = model.Parent == nil and bombs:liveCount() == 0 and #bombs:liveModels() == 0
			result.loss = before - humanoid.Health
		end
		ctx.maxHealth = humanoid.MaxHealth
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.player then
			return false, "no player on the server"
		end
		if not ctx.bombs then
			return false, "BossBombs.new returned nil for a bomb-configured type"
		end
		for index, result in ctx.results do
			local letters = LETTERS_BY_PHASE[index]
			if not result.landed then
				return false, "no puzzle landed at phase " .. result.phase
			end
			if not result.lockedEach then
				return false, "an accepted tap did not lock its letter (and leave the part resting) at phase " .. result.phase
			end
			if not result.gone then
				return false, "the solved puzzle was still in the world at phase " .. result.phase
			end
			local expected = ctx.maxHealth * ctx.spec.bombDefuseDamageByLetters[letters]
			if math.abs(result.loss - expected) > HEALTH_TOLERANCE then
				return false, string.format("boss lost %.2f at phase %d, expected %.2f", result.loss, result.phase, expected)
			end
			local event = ctx.defused[index]
			if not event then
				return false, "no BombDefused event at phase " .. result.phase
			end
			if event.player ~= ctx.player or event.letterCount ~= letters or #event.word ~= letters or event.arenaId ~= ARENA_ID then
				return false, string.format(
					"BombDefused was (%s, %s, %s, %s, %s)",
					tostring(event.player), event.word, event.color, event.arenaId, tostring(event.letterCount)
				)
			end
			if event.scale ~= ctx.spec.bombEnergyScale then
				return false, string.format("BombDefused carried scale %s, expected %s", tostring(event.scale), tostring(ctx.spec.bombEnergyScale))
			end
			if ctx.landed[index] == nil or ctx.landed[index].letterCount ~= letters then
				return false, "BombLanded did not report " .. letters .. " letters"
			end
		end
		if #ctx.defused ~= #PHASES then
			return false, "BombDefused fired " .. #ctx.defused .. " times"
		end
		if #ctx.landed ~= #PHASES then
			return false, "BombLanded fired " .. #ctx.landed .. " times, expected once per puzzle"
		end
		local expectedTaps = 0
		for _, letters in LETTERS_BY_PHASE do
			expectedTaps += letters
		end
		if #ctx.popped ~= expectedTaps then
			return false, string.format("BombPopped fired %d times, expected %d", #ctx.popped, expectedTaps)
		end
		for _, popped in ctx.popped do
			if not popped.accepted then
				return false, "BombPopped reported a refusal for an in-order tap"
			end
		end
		if #ctx.bursts ~= 0 or #ctx.broken ~= 0 or #ctx.hatched ~= 0 then
			return false, "a solved puzzle also hatched, burst or broke"
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
