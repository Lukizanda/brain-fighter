--!strict

----------------------------------------------------------------------
-- bomb_seeker_pop_harmless — popping a chasing seeker only removes it (Harmless: no lock, no reward, no event); its reach is measured to that seeker; popping what is gone or not hatched yet is Invalid
----------------------------------------------------------------------
-- MODULE LEVEL with the harness player: BossBombs on a stand-in boss in the
-- throwaway arena, ticked by hand with an injected clock; the player is parked
-- bombFixture.FAR_STUDS away so the seekers fly but never arrive.
--   Reach     while chasing, reachOf gives that seeker's own position (not the
--             puzzle's centre) and bombSeekerTapReach; after a step it follows
--             the seeker; a letter with no live seeker has none;
--   Pop       a tap on a hatched seeker returns Harmless: its part is gone, the
--             live count dropped, BombAccepted is unchanged, no BombPopped, no
--             BombDefused, the boss is unhurt;
--   Invalid   the same seeker tapped again, a letter that has not hatched yet
--             (during the stagger) and a letter that was locked before the
--             hatch are all Invalid;
--   End       popping the rest removes the Model, silently: no burst, no
--             BombDefused.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)

local RESULT = BombConstants.TapResult
local MOVE_TOLERANCE = 0.001

return {
	name = "bomb_seeker_pop_harmless",

	setup = function(ctx: any)
		bombFixture.record(ctx)
		ctx.problems = {}
	end,

	run = function(ctx: any)
		if not bombFixture.begin(ctx) then
			return
		end
		local player: Player = ctx.player
		local bombs = ctx.bombs
		local clock = ctx.clock
		local root: BasePart = ctx.root
		local spec = ctx.spec
		local problems: { string } = ctx.problems
		local function expect(ok: boolean, message: string)
			if not ok then
				table.insert(problems, message)
			end
		end

		local farAt = root.Position + Vector3.new(0, 0, bombFixture.FAR_STUDS)
		if not bombFixture.placePlayer(player, farAt) then
			return
		end
		ctx.placed = true
		local bossBefore = ctx.humanoid.Health
		local model = bombFixture.lobAndLand(bombs, clock, root.Position, bombFixture.rootOf(player))
		if not model then
			return
		end
		ctx.landedOk = true
		local count = #bombFixture.letters(model)

		-- One letter locked before the hatch.
		local lockedIndex = bombFixture.rightTile(model) :: number
		expect(bombs:tap(player, model, lockedIndex) == RESULT.Accepted, "the first right tap was not accepted")
		-- BindableEvents are deferred: let the accepted tap's BombPopped arrive
		-- before counting, or it is blamed on the chasing pops below.
		task.wait(bombFixture.SETTLE_SEC)
		local acceptedBefore = model:GetAttribute(BombConstants.ACCEPTED_ATTRIBUTE)
		local poppedEventsBefore = #ctx.popped

		-- Hatch only the first unlocked letter.
		bombFixture.expire(bombs, clock, model)
		local first = 1
		if first == lockedIndex then
			first = 2
		end
		local firstPart = bombFixture.seeker(model, first)
		expect(firstPart ~= nil, "the first unlocked letter did not hatch")
		expect(bombs:tap(player, model, lockedIndex) == RESULT.Invalid, "a tap on a letter locked before the hatch was not Invalid")
		local notYet = 0
		for index = 1, count do
			if index ~= lockedIndex and bombFixture.seeker(model, index) == nil then
				notYet = index
			end
		end
		expect(notYet ~= 0 and bombs:tap(player, model, notYet) == RESULT.Invalid, "a tap on a letter that had not hatched was not Invalid")

		-- Reach is measured to the seeker itself.
		if firstPart ~= nil then
			local point, reach = bombs:reachOf(model, first)
			expect(point == firstPart.Position and reach == spec.bombSeekerTapReach, "a seeker's reach point was not its own position with bombSeekerTapReach")
			expect(point ~= model:GetAttribute(BombConstants.CENTRE_ATTRIBUTE), "a seeker's reach point was the puzzle's centre")
			local before = firstPart.Position
			bombFixture.advance(bombs, clock, bombFixture.STEP_SEC)
			local moved = firstPart.Position
			expect((moved - before).Magnitude > MOVE_TOLERANCE, "the seeker did not move")
			local after = bombs:reachOf(model, first)
			expect(after ~= nil and (after - moved).Magnitude <= MOVE_TOLERANCE, "the reach point did not follow the seeker")
		end
		expect(select(1, bombs:reachOf(model, lockedIndex)) == nil, "a removed letter still had a reach point")

		-- Pop the rest as they hatch.
		local live = bombs:liveCount()
		expect(bombs:tap(player, model, first) == RESULT.Harmless, "popping a seeker was not Harmless")
		expect(bombFixture.part(model, first) == nil and bombs:liveCount() == live - 1, "a popped seeker was not removed")
		expect(bombs:tap(player, model, first) == RESULT.Invalid, "popping the same seeker twice was not Invalid")
		expect(model:GetAttribute(BombConstants.ACCEPTED_ATTRIBUTE) == acceptedBefore, "a chasing pop changed BombAccepted")

		for _ = 1, count do
			bombFixture.jump(bombs, clock, bombFixture.STAGGER_SEC)
			for index = 1, count do
				if model.Parent ~= nil and bombFixture.seeker(model, index) ~= nil then
					bombs:tap(player, model, index)
				end
			end
		end
		task.wait(bombFixture.SETTLE_SEC)
		ctx.modelGone = model.Parent == nil
		ctx.bossLoss = bossBefore - ctx.humanoid.Health
		expect(#ctx.popped == poppedEventsBefore, "a chasing pop fired BombPopped")
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.player then
			return false, "no player on the server"
		end
		if not ctx.bombs then
			return false, "BossBombs.new returned nil, or the arena build failed"
		end
		if not ctx.placed or not ctx.landedOk then
			return false, "the player was not placed, or no puzzle landed"
		end
		if #ctx.problems > 0 then
			return false, ctx.problems[1]
		end
		if not ctx.modelGone then
			return false, "popping every seeker did not remove the Model"
		end
		if #ctx.bursts ~= 0 or #ctx.defused ~= 0 then
			return false, "popped seekers burst, or the word was credited"
		end
		if ctx.bossLoss ~= 0 then
			return false, "popping a seeker hurt the boss"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		bombFixture.finish(ctx)
	end,
}
