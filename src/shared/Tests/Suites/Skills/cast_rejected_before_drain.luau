--!strict

----------------------------------------------------------------------
-- cast_rejected_before_drain — CastAction charges nothing for a cast
-- that cannot resolve
----------------------------------------------------------------------
-- Supersedes `cast_refund_on_failure` (Phase 5.6 Stage 5). The guarantee
-- the player experiences is unchanged — a cast that lands nowhere costs
-- no mana — but the mechanism is now the opposite way round, and the
-- distinction is the whole point of the stage:
--
--   before: drain → run the spell → notice it refused → hand the mana back
--   now:    ask whether it can resolve → refuse → never touch the mana
--
-- The old suite could not tell those apart. It compared the reservoir
-- before and after, and drain-then-refund leaves the same number behind
-- as never-drain. So this one watches `EnergyReservoirs.changed` instead:
-- a drain followed by a refund fires it twice, and never draining fires it
-- not at all. Zero fires is the assertion.
--
-- That matters beyond tidiness. Once delivery is authoritative-only
-- (Stage 4) the casting client no longer sees the executor's verdict, so
-- there is nothing left to trigger a refund. If the precondition check
-- ever silently stopped running, the old assertion would still pass while
-- players quietly lost mana; this one fails.
--
-- Frost Nip (blue T1) drives it: a targeted spell whose `freeze` effect
-- has no self-fallback, cast with no target.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CastAction       = require(ReplicatedStorage.Shared.CastAction)
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)

local INITIAL_BLUE = 30
-- Blue T1 (Frost Nip). Its onImpact leads with `freeze`, which requires a
-- Humanoid target and has no self-fallback.
local TARGETED_TIER = 1
-- `.changed` is a BindableEvent and this place runs them Deferred, so
-- handlers land on the next resumption cycle rather than inline. Give them
-- one before counting, or a fire that DID happen would be missed and the
-- test would pass for the wrong reason.
local DEFERRED_SETTLE_SEC = 0.1

type Ctx = {
	model: Model?,
	reservoir: any,
	result: any,
	changedFires: number,
	conn: RBXScriptConnection?,
}

return {
	name = "cast_rejected_before_drain",

	setup = function(ctx: Ctx)
		local model = Instance.new("Model")
		model.Name = "RejectBeforeDrainDummy"
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
		model.Parent = workspace
		ctx.model = model

		local reservoir = EnergyReservoirs.new()
		reservoir:add("blue", INITIAL_BLUE)
		ctx.reservoir = reservoir

		-- Connect AFTER the seeding add, so only the cast's own activity
		-- is counted.
		ctx.changedFires = 0
		ctx.conn = reservoir.changed:Connect(function()
			ctx.changedFires += 1
		end)
		task.wait(DEFERRED_SETTLE_SEC)
		ctx.changedFires = 0

		-- Caster present, target absent — the cast cannot resolve.
		ctx.result = CastAction.castSpecific("blue", TARGETED_TIER, reservoir, humanoid, nil)
		task.wait(DEFERRED_SETTLE_SEC)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local res = ctx.result
		if res.ok ~= false then
			return false, "targetless cast should fail, got ok=" .. tostring(res.ok)
		end

		local blue = ctx.reservoir:get("blue")
		if blue ~= INITIAL_BLUE then
			return false, string.format("mana changed: expected %d blue, got %s",
				INITIAL_BLUE, tostring(blue))
		end

		-- The load-bearing assertion. Nonzero means the reservoir was
		-- drained and put back, i.e. the precondition check did not gate
		-- the drain and we are relying on the refund path again.
		if ctx.changedFires ~= 0 then
			return false, string.format(
				"reservoir was mutated %d time(s) — cast was drained and refunded " ..
				"rather than refused before the drain",
				ctx.changedFires
			)
		end

		return true, "cast refused before the drain; reservoir never touched"
	end,

	teardown = function(ctx: Ctx)
		if ctx.conn then ctx.conn:Disconnect() end
		if ctx.model then ctx.model:Destroy() end
		if ctx.reservoir then ctx.reservoir:destroy() end
	end,
}
