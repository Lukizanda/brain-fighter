--!strict

----------------------------------------------------------------------
-- spellexecutor_tests — autorunner wrapper for SpellExecutor.__tests
----------------------------------------------------------------------
-- Runs the SpellExecutor case table (damage/heal/freeze plus the
-- Phase 5.2 defensive effects: shield grants an absorb pool, buff
-- applies a damageAmp, and world_spawn places a barrier).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

type Ctx = { passed: number?, failed: number? }

return {
	name = "spellexecutor_tests",

	run = function(ctx: Ctx)
		local tests = require(
			ReplicatedStorage.Shared.SpellExecutor:FindFirstChild("__tests") :: ModuleScript
		)
		ctx.passed, ctx.failed = tests.runAll()
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local passed = ctx.passed or 0
		local failed = ctx.failed or 0
		return failed == 0, string.format("%d passed, %d failed", passed, failed)
	end,
}
