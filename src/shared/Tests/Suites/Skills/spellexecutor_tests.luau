--!strict

----------------------------------------------------------------------
-- spellexecutor_tests — autorunner wrapper for SpellExecutor.__tests
----------------------------------------------------------------------
-- Runs the SpellExecutor case table (damage/heal/freeze plus the
-- Phase 5.1 stub expectations: shield/wall/buff fail with
-- reason="unimplemented" so casts refund).
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
