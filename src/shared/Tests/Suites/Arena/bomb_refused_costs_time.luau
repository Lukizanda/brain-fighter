--!strict

----------------------------------------------------------------------
-- bomb_refused_costs_time — a refused tap keeps the progress and moves BombHatchAt earlier by the penalty; a locked letter is a no-op; resting reach is from the puzzle's centre; a part that is not there is invalid
----------------------------------------------------------------------
-- MODULE LEVEL: BossBombs on a stand-in boss, ticked by hand with an injected
-- clock; the harness player taps (reach is the tap service's check, not
-- BossBombs.tap's).
--   Reach     while resting every letter's reach point is the puzzle's centre
--             (BombCentre), whatever the letter, with reach bombTapReach; a
--             letter that does not exist has none;
--   Invalid   a tap on a letter index the puzzle does not have is Invalid and
--             changes nothing;
--   Refused   a tap that takes the spelling off every allowed word returns
--             Refused: the part is still there and unhatched, BombAccepted is
--             unchanged, BombBroken is false, BombHatchAt moved earlier by
--             exactly bombWrongTapPenaltySec (twice for two refusals), the boss
--             is unhurt and BombPopped(false) fired once per refusal;
--   Locked    tapping a letter that is already locked returns Locked and
--             changes nothing: no penalty, no event, BombAccepted as it was;
--   Progress  after the refusals and the locked tap, the right taps still
--             complete the word and hurt the boss.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)
local BossBombs = require(ServerScriptService.Server.Boss.Scripts.BossBombs)

local ARENA_ID = "BombRefuse"
local MAX_HEALTH = 1000
local MAX_TAPS = 10
local MISSING_OFFSET = 1
local RESULT = BombConstants.TapResult

return {
	name = "bomb_refused_costs_time",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
		bombFixture.record(ctx)
	end,

	run = function(ctx: any)
		if ctx.player == nil then
			return
		end
		local tapper: Player = ctx.player
		local boss, humanoid, root = ctx.hf:fakeBoss(MAX_HEALTH)
		local spec = bombFixture.spec()
		ctx.spec = spec
		local bombs = BossBombs.new(boss, humanoid, root, spec)
		if not bombs then
			return
		end
		ctx.bombs = bombs
		local clock = bombFixture.clock()

		local model = bombFixture.lobAndLand(bombs, clock, root.Position, nil)
		if not model then
			return
		end
		-- BindableEvents are deferred: BombLanded reaches the recorder after a frame.
		task.wait(bombFixture.SETTLE_SEC)
		ctx.didLand = #ctx.landed > 0
		local count = #bombFixture.letters(model)
		local centre = model:GetAttribute(BombConstants.CENTRE_ATTRIBUTE)

		-- Reach from the centre, for every letter; none for a letter that is not there.
		ctx.reachOk = true
		for index = 1, count do
			local point, reach = bombs:reachOf(model, index)
			if point ~= centre or reach ~= spec.bombTapReach then
				ctx.reachOk = false
			end
		end
		local missingPoint = bombs:reachOf(model, count + MISSING_OFFSET)
		ctx.noReachForMissing = missingPoint == nil

		-- Invalid.
		ctx.invalidResult = bombs:tap(tapper, model, count + MISSING_OFFSET)
		ctx.invalidPoppedEvents = #ctx.popped

		-- Refused.
		local wrong = bombFixture.wrongTile(model)
		ctx.hadWrong = wrong ~= nil
		if wrong == nil then
			return
		end
		local hatchAt0 = model:GetAttribute(BombConstants.HATCH_AT_ATTRIBUTE) :: number
		local acceptedBefore = model:GetAttribute(BombConstants.ACCEPTED_ATTRIBUTE)
		ctx.refusedResult = bombs:tap(tapper, model, wrong)
		ctx.partStays = bombFixture.part(model, wrong) ~= nil and bombFixture.seekerCount(model) == 0
		ctx.acceptedSame = model:GetAttribute(BombConstants.ACCEPTED_ATTRIBUTE) == acceptedBefore
		ctx.notBroken = model:GetAttribute(BombConstants.BROKEN_ATTRIBUTE) == false
		ctx.hatchAt1 = model:GetAttribute(BombConstants.HATCH_AT_ATTRIBUTE)
		ctx.refusedAgain = bombs:tap(tapper, model, wrong)
		ctx.hatchAt2 = model:GetAttribute(BombConstants.HATCH_AT_ATTRIBUTE)
		ctx.hatchAt0 = hatchAt0
		task.wait(bombFixture.SETTLE_SEC)
		ctx.refusedEvents = 0
		for _, popped in ctx.popped do
			if not popped.accepted then
				ctx.refusedEvents += 1
			end
		end

		-- Locked.
		local right = bombFixture.rightTile(model)
		if right == nil then
			return
		end
		ctx.firstTap = bombs:tap(tapper, model, right)
		-- Let the accepted tap's BombPopped arrive before counting (deferred events).
		task.wait(bombFixture.SETTLE_SEC)
		local acceptedAfterFirst = model:GetAttribute(BombConstants.ACCEPTED_ATTRIBUTE)
		local hatchAtBefore = model:GetAttribute(BombConstants.HATCH_AT_ATTRIBUTE)
		local eventsBefore = #ctx.popped
		ctx.lockedResult = bombs:tap(tapper, model, right)
		task.wait(bombFixture.SETTLE_SEC)
		ctx.lockedNoop = model:GetAttribute(BombConstants.ACCEPTED_ATTRIBUTE) == acceptedAfterFirst
			and model:GetAttribute(BombConstants.HATCH_AT_ATTRIBUTE) == hatchAtBefore
			and #ctx.popped == eventsBefore
			and bombFixture.part(model, right) ~= nil

		-- Progress was kept: finishing the word still works.
		for _ = 1, MAX_TAPS do
			if bombFixture.tapRight(bombs, tapper, model) == nil then
				break
			end
		end
		task.wait(bombFixture.SETTLE_SEC)
		ctx.finished = model.Parent == nil
		ctx.bossLoss = humanoid.MaxHealth - humanoid.Health
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.player then
			return false, "no player on the server"
		end
		if not ctx.bombs then
			return false, "BossBombs.new returned nil for a bomb-configured type"
		end
		if not ctx.didLand then
			return false, "no puzzle landed"
		end
		if not ctx.reachOk then
			return false, "a resting letter's reach point was not the puzzle's centre with bombTapReach"
		end
		if not ctx.noReachForMissing then
			return false, "a letter that does not exist had a reach point"
		end
		if ctx.invalidResult ~= RESULT.Invalid or ctx.invalidPoppedEvents ~= 0 then
			return false, "a tap on a letter that is not there was " .. tostring(ctx.invalidResult)
		end
		if not ctx.hadWrong then
			return false, "no out-of-order letter to refuse (the scramble gave none)"
		end
		if ctx.refusedResult ~= RESULT.Refused or ctx.refusedAgain ~= RESULT.Refused then
			return false, string.format("an out-of-order tap returned %s then %s", tostring(ctx.refusedResult), tostring(ctx.refusedAgain))
		end
		if not ctx.partStays then
			return false, "a refused tap removed or hatched the letter"
		end
		if not ctx.acceptedSame then
			return false, "a refused tap changed BombAccepted"
		end
		if not ctx.notBroken then
			return false, "a refused tap broke the puzzle"
		end
		local penalty = ctx.spec.bombWrongTapPenaltySec
		if math.abs((ctx.hatchAt0 - ctx.hatchAt1) - penalty) > bombFixture.TIME_TOLERANCE_SEC then
			return false, string.format("one refusal moved BombHatchAt %.3f s earlier, expected %s", ctx.hatchAt0 - ctx.hatchAt1, tostring(penalty))
		end
		if math.abs((ctx.hatchAt0 - ctx.hatchAt2) - 2 * penalty) > bombFixture.TIME_TOLERANCE_SEC then
			return false, string.format("two refusals moved BombHatchAt %.3f s earlier, expected %s", ctx.hatchAt0 - ctx.hatchAt2, tostring(2 * penalty))
		end
		if ctx.refusedEvents ~= 2 then
			return false, string.format("BombPopped(false) fired %d times, expected 2", ctx.refusedEvents)
		end
		if ctx.firstTap ~= RESULT.Accepted then
			return false, "the right tap returned " .. tostring(ctx.firstTap)
		end
		if ctx.lockedResult ~= RESULT.Locked or not ctx.lockedNoop then
			return false, string.format("tapping a locked letter returned %s (expected Locked, nothing changed: %s)", tostring(ctx.lockedResult), tostring(ctx.lockedNoop))
		end
		if not ctx.finished then
			return false, "the word could not be finished after refusals (progress lost)"
		end
		if #ctx.bursts ~= 0 or #ctx.broken ~= 0 or #ctx.hatched ~= 0 then
			return false, "a refusal caused a hatch, a burst or a break"
		end
		if ctx.bossLoss <= 0 then
			return false, "completing the word after refusals did not hurt the boss"
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
