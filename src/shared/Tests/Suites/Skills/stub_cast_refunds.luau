--!strict

----------------------------------------------------------------------
-- stub_cast_refunds — Phase 5.1 refund milestone check
----------------------------------------------------------------------
-- Casting a spell whose effect is still a stub (Blue T2 Shield) must
-- fail with reason="unimplemented" and leave the reservoir untouched:
-- CastAction drains, the executor refuses, CastAction refunds.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CastAction       = require(ReplicatedStorage.Shared.CastAction)
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)

local INITIAL_BLUE = 30

type Ctx = {
	model: Model?,
	reservoir: any,
	result: any,
}

return {
	name = "stub_cast_refunds",

	setup = function(ctx: Ctx)
		local model = Instance.new("Model")
		model.Name = "StubRefundTestDummy"
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
		model.Parent = workspace
		ctx.model = model

		local reservoir = EnergyReservoirs.new()
		reservoir:add("blue", INITIAL_BLUE)
		ctx.reservoir = reservoir

		ctx.result = CastAction.castSpecific("blue", 2, reservoir, humanoid, humanoid)
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local res = ctx.result
		if res.ok ~= false then
			return false, "stub cast should fail, got ok=" .. tostring(res.ok)
		end
		local reason = tostring(res.reason)
		if not string.find(reason, "unimplemented", 1, true) then
			return false, "reason should mention unimplemented, got: " .. reason
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
