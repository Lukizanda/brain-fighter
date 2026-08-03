--!strict

----------------------------------------------------------------------
-- cast_refund_on_failure — CastAction refund guarantee
----------------------------------------------------------------------
-- When the executor refuses a cast, CastAction must hand the mana back:
-- it drains before executing, so a downstream rejection would otherwise
-- charge the player for nothing.
--
-- Phase 5.1 exercised this through the shield/wall/buff stubs, which
-- always failed with reason="unimplemented". Those are real effects as
-- of 5.2, so the refund path is driven here by a genuine rejection
-- instead: Frost Nip is a targeted spell, and `freeze` refuses a cast
-- with no Humanoid to freeze.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CastAction       = require(ReplicatedStorage.Shared.CastAction)
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)

local INITIAL_BLUE = 30
-- Blue T1 (Frost Nip). Its onImpact leads with `freeze`, which requires a
-- Humanoid target and has no self-fallback.
local TARGETED_TIER = 1

type Ctx = {
	model: Model?,
	reservoir: any,
	result: any,
}

return {
	name = "cast_refund_on_failure",

	setup = function(ctx: Ctx)
		local model = Instance.new("Model")
		model.Name = "RefundTestDummy"
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
		model.Parent = workspace
		ctx.model = model

		local reservoir = EnergyReservoirs.new()
		reservoir:add("blue", INITIAL_BLUE)
		ctx.reservoir = reservoir

		-- Caster present, target absent — the executor should refuse.
		ctx.result = CastAction.castSpecific("blue", TARGETED_TIER, reservoir, humanoid, nil)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local res = ctx.result
		if res.ok ~= false then
			return false, "targetless cast should fail, got ok=" .. tostring(res.ok)
		end
		local blue = ctx.reservoir:get("blue")
		if blue ~= INITIAL_BLUE then
			return false, string.format("mana not refunded: expected %d blue, got %s",
				INITIAL_BLUE, tostring(blue))
		end
		return true, "cast refused and mana refunded"
	end,

	teardown = function(ctx: Ctx)
		if ctx.model then ctx.model:Destroy() end
		if ctx.reservoir then ctx.reservoir:destroy() end
	end,
}
