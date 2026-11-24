--!strict

----------------------------------------------------------------------
-- hunger_lash_yank — a letter in tow is held for the mark, then yanked on the ease-in curve, and lands exactly at mark + snap
----------------------------------------------------------------------
-- MODULE LEVEL: BossHunger on a stand-in boss, ticked by hand in steps that
-- are exact in binary, so the clock adds up with no rounding. A boss that does
-- not move, a letter 9 studs away, a 1 s mark and a 0.5 s snap:
--   * the tow publishes its schedule on the letter (snap time = begin + mark,
--     arrive time = snap + snap length, in server time) and on the boss;
--   * through the whole mark the letter does not move;
--   * once the mark is over it sits on TowCurve's curve at each step (the
--     same function the client draws from), on the way to the boss;
--   * it is NOT eaten a tick early and IS eaten on the tick that completes
--     mark + snap, healing nothing here (fraction 0);
--   * the boss's yank times stay published after the eat (the body's gulp
--     reads them) and EatingAt is cleared.
--
-- NOT covered: what the client draws from these times (a live view is needed,
-- vfx-sfx.md); a boss that moves during the yank.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local TowConstants = require(ReplicatedStorage.Shared.BlockSpawner.TowConstants)
local TowCurve = require(ReplicatedStorage.Shared.BlockSpawner.TowCurve)
local BossHunger = require(ServerScriptService.Server.Boss.Scripts.BossHunger)
local hungerFixture = require(ReplicatedStorage.Shared.Tests.Helpers.hungerFixture)

local ARENA_ID = "HungerLash"
local INTERVAL_SEC = 1
local RADIUS_STUDS = 25
local REACH_STUDS = 1
local BLOCK_OFFSET = Vector3.new(8, 4, 0)
-- Powers of two, so the sums are exact.
local STEP_SEC = 0.125
local MARK_STEPS = 8
local SNAP_STEPS = 4
local MARK_SEC = STEP_SEC * MARK_STEPS
local SNAP_SEC = STEP_SEC * SNAP_STEPS
local NEVER_REFILL_SEC = 600
local POSITION_TOLERANCE_STUDS = 0.01
local TIME_TOLERANCE_SEC = 0.01

return {
	name = "hunger_lash_yank",

	setup = function(ctx: any)
		ctx.hf = hungerFixture.new(ARENA_ID)
	end,

	run = function(ctx: any)
		local hf = ctx.hf
		local boss, humanoid, root = hf:fakeBoss()
		local zoneAt = root.Position + BLOCK_OFFSET
		local pool = hf:pool({ hf:zone(zoneAt) }, NEVER_REFILL_SEC)
		local hunger = BossHunger.new(boss, humanoid, root, hungerFixture.spec(
			INTERVAL_SEC, RADIUS_STUDS, 0, MARK_SEC, SNAP_SEC, REACH_STUDS
		))
		local block = hf:blockAt(pool, zoneAt)
		if not hunger or not block then
			return
		end
		ctx.fixtureOk = true
		local startAt = block:GetPivot().Position

		hunger:tick(INTERVAL_SEC) -- begins the tow
		local beganNow = workspace:GetServerTimeNow()
		ctx.towed = pool:isTowed(block)

		-- The published schedule.
		local snapAt = block:GetAttribute(TowConstants.SNAP_AT_ATTRIBUTE)
		local arriveAt = block:GetAttribute(TowConstants.ARRIVE_AT_ATTRIBUTE)
		local beganAt = block:GetAttribute(TowConstants.BEGAN_AT_ATTRIBUTE)
		ctx.scheduleOk = type(snapAt) == "number" and type(arriveAt) == "number" and type(beganAt) == "number"
			and math.abs(snapAt - beganAt - MARK_SEC) < TIME_TOLERANCE_SEC
			and math.abs(arriveAt - snapAt - SNAP_SEC) < TIME_TOLERANCE_SEC
			and math.abs(beganAt - beganNow) < TIME_TOLERANCE_SEC * 10
			and block:GetAttribute(TowConstants.PAUSED_AT_ATTRIBUTE) == nil
		local from = block:GetAttribute(TowConstants.FROM_ATTRIBUTE)
		ctx.fromOk = typeof(from) == "Vector3" and (from - startAt).Magnitude < POSITION_TOLERANCE_STUDS
		ctx.bossTimesOk = boss:GetAttribute(BossConstants.EAT_SNAP_AT_ATTRIBUTE) == snapAt
			and boss:GetAttribute(BossConstants.EAT_LANDS_AT_ATTRIBUTE) == arriveAt

		-- The mark: never moves.
		ctx.heldThroughMark = true
		for _ = 1, MARK_STEPS do
			hunger:tick(STEP_SEC)
			if block.Parent == nil or (block:GetPivot().Position - startAt).Magnitude > POSITION_TOLERANCE_STUDS then
				ctx.heldThroughMark = false
			end
		end

		-- The yank: on the curve at every step, and not eaten before the last.
		ctx.onCurve = true
		ctx.notEarly = true
		for step = 1, SNAP_STEPS - 1 do
			hunger:tick(STEP_SEC)
			if block.Parent == nil then
				ctx.notEarly = false
				break
			end
			local expected = startAt:Lerp(root.Position, TowCurve.fraction(step * STEP_SEC, SNAP_SEC))
			if (block:GetPivot().Position - expected).Magnitude > POSITION_TOLERANCE_STUDS then
				ctx.onCurve = false
			end
		end
		ctx.stillInTow = block.Parent ~= nil and pool:isTowed(block)

		hunger:tick(STEP_SEC) -- completes mark + snap
		ctx.eatenOnTime = block.Parent == nil
		ctx.eatingAtCleared = boss:GetAttribute(BossConstants.EATING_AT_ATTRIBUTE) == nil
		ctx.timesKept = boss:GetAttribute(BossConstants.EAT_SNAP_AT_ATTRIBUTE) == snapAt
			and boss:GetAttribute(BossConstants.EAT_LANDS_AT_ATTRIBUTE) == arriveAt
	end,

	verify = function(ctx: any): (boolean, string?)
		if not ctx.fixtureOk then
			return false, "fixture: no hunger object or no block at the zone"
		end
		if not ctx.towed then
			return false, "the letter was not in tow after the interval"
		end
		if not ctx.scheduleOk or not ctx.fromOk then
			return false, "the letter's published schedule (began, snap, arrive, from) is missing or wrong"
		end
		if not ctx.bossTimesOk then
			return false, "the boss's EatSnapAt / EatLandsAt do not match the letter's schedule"
		end
		if not ctx.heldThroughMark then
			return false, "the letter moved during the mark"
		end
		if not ctx.notEarly then
			return false, "the letter was eaten before the yank finished"
		end
		if not ctx.onCurve then
			return false, "during the yank the letter was off TowCurve's curve"
		end
		if not ctx.stillInTow then
			return false, "the letter left tow before the last step of the yank"
		end
		if not ctx.eatenOnTime then
			return false, "the letter was not eaten on the tick that completes mark + snap"
		end
		if not ctx.eatingAtCleared then
			return false, "EatingAt was not cleared when the letter was eaten"
		end
		if not ctx.timesKept then
			return false, "the boss's yank times were cleared on an eat (the gulp needs them)"
		end
		return true, nil
	end,

	teardown = function(ctx: any)
		if ctx.hf then
			ctx.hf:destroy()
		end
	end,
}
