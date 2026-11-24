--!strict

----------------------------------------------------------------------
-- bomb_hatches_unlocked_only — when the timer ends only the letters that are not locked hatch, staggered, the word breaks, the puzzle turns Chasing and BombHatched reports the count
----------------------------------------------------------------------
-- MODULE LEVEL with the harness player: BossBombs on a stand-in boss in the
-- throwaway arena, ticked by hand with an injected clock; the player is parked
-- bombFixture.FAR_STUDS away and time is jumped (dt 0), so nothing flies.
--   Early     just before BombHatchAt nothing has hatched: still Resting, no
--             BombBroken / BombHatched, every part resting;
--   Hatch     at BombHatchAt (one letter locked first): BombBroken fired once,
--             BombHatched fired once with N-1, BombPhase is Chasing, BombBroken
--             is true, BombTargetUserId is the player's, the locked letter's
--             part is gone at once, and exactly one seeker is out (the lowest
--             unlocked index) with Hatched true and SeekerExpiresAt = now + the
--             lifetime; the others still rest, without those attributes;
--   Stagger   one bombHatchStaggerSec later one more seeker, and so on in index
--             order until N-1 seekers fly; the locked letter never hatches;
--   Locked    a tap on the locked letter is Invalid now; a tap on a letter that
--             has not hatched yet (during the stagger) is Invalid.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local bombFixture = require(ReplicatedStorage.Shared.Tests.Helpers.bombFixture)

local EARLY_MARGIN_SEC = 0.1
local RESULT = BombConstants.TapResult

return {
	name = "bomb_hatches_unlocked_only",

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
		local model = bombFixture.lobAndLand(bombs, clock, root.Position, bombFixture.rootOf(player))
		if not model then
			return
		end
		ctx.landedOk = true
		local count = #bombFixture.letters(model)

		-- Lock one letter.
		local lockedIndex = bombFixture.rightTile(model) :: number
		expect(bombs:tap(player, model, lockedIndex) == RESULT.Accepted, "the first right tap was not accepted")
		local hatchAt = model:GetAttribute(BombConstants.HATCH_AT_ATTRIBUTE) :: number

		-- Early.
		clock.now = hatchAt - EARLY_MARGIN_SEC
		bombs:tick(0, clock.now)
		task.wait(bombFixture.POLL_SEC)
		expect(model:GetAttribute(BombConstants.PHASE_ATTRIBUTE) == BombConstants.Phase.Resting, "the puzzle left Resting before the timer ended")
		expect(#ctx.broken == 0 and #ctx.hatched == 0, "BombBroken / BombHatched fired before the timer ended")
		expect(bombFixture.seekerCount(model) == 0 and bombFixture.partCount(model) == count, "a letter hatched or went before the timer ended")

		-- The hatch.
		clock.now = hatchAt
		bombs:tick(0, clock.now)
		task.wait(bombFixture.SETTLE_SEC)
		expect(#ctx.broken == 1, "BombBroken fired " .. #ctx.broken .. " times at the hatch")
		expect(#ctx.hatched == 1 and ctx.hatched[1].seekerCount == count - 1, "BombHatched did not report " .. (count - 1) .. " seekers")
		expect(model:GetAttribute(BombConstants.PHASE_ATTRIBUTE) == BombConstants.Phase.Chasing, "BombPhase is not Chasing after the hatch")
		expect(model:GetAttribute(BombConstants.BROKEN_ATTRIBUTE) == true, "BombBroken attribute is not true after the hatch")
		expect(model:GetAttribute(BombConstants.TARGET_USER_ID_ATTRIBUTE) == player.UserId, "BombTargetUserId is not the player's after the hatch")
		expect(bombFixture.part(model, lockedIndex) == nil, "the locked letter's part was not removed at the hatch")
		expect(bombFixture.seekerCount(model) == 1, "expected exactly one seeker right at the hatch, found " .. bombFixture.seekerCount(model))
		expect(bombs:tap(player, model, lockedIndex) == RESULT.Invalid, "a tap on the locked letter after the hatch was not Invalid")

		-- Stagger, in index order.
		local order: { number } = {}
		for index = 1, count do
			if index ~= lockedIndex then
				table.insert(order, index)
			end
		end
		local hatchedAtByIndex: { [number]: number } = { [order[1]] = hatchAt }
		for position = 1, #order do
			local index = order[position]
			local part = bombFixture.seeker(model, index)
			expect(part ~= nil, "letter " .. index .. " had not hatched in its turn")
			if part ~= nil then
				expect(part:GetAttribute(BombConstants.HATCHED_ATTRIBUTE) == true, "hatched part " .. index .. " lacks Hatched")
				local expires = part:GetAttribute(BombConstants.SEEKER_EXPIRES_ATTRIBUTE)
				local wanted = (hatchedAtByIndex[index] or clock.now) + spec.bombSeekerLifetimeSec
				expect(type(expires) == "number" and math.abs(expires - wanted) <= bombFixture.TIME_TOLERANCE_SEC, "part " .. index .. " has the wrong SeekerExpiresAt")
			end
			local next = order[position + 1]
			if next ~= nil then
				-- The next letter still rests, without hatch attributes, and cannot be tapped.
				local resting = bombFixture.part(model, next)
				expect(resting ~= nil and resting:GetAttribute(BombConstants.HATCHED_ATTRIBUTE) == nil and resting:GetAttribute(BombConstants.SEEKER_EXPIRES_ATTRIBUTE) == nil, "letter " .. next .. " carried hatch attributes before its turn")
				expect(bombs:tap(player, model, next) == RESULT.Invalid, "a tap on letter " .. next .. " before it hatched was not Invalid")
				expect(bombFixture.seekerCount(model) == position, "expected " .. position .. " seekers before the next stagger")
				bombFixture.jump(bombs, clock, bombFixture.STAGGER_SEC)
				hatchedAtByIndex[next] = clock.now
			end
		end
		expect(bombFixture.seekerCount(model) == count - 1, "not every unlocked letter hatched")
		expect(bombFixture.part(model, lockedIndex) == nil, "the locked letter came back")
		expect(#ctx.hatched == 1 and #ctx.broken == 1, "BombHatched / BombBroken fired again during the stagger")
		expect(#ctx.bursts == 0 and #ctx.defused == 0, "something burst or was solved during the hatch")
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
		return true, nil
	end,

	teardown = function(ctx: any)
		bombFixture.finish(ctx)
	end,
}
