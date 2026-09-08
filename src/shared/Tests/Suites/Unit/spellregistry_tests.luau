--!strict

----------------------------------------------------------------------
-- spellregistry_tests — autorunner wrapper for SpellRegistry.__tests
----------------------------------------------------------------------
-- Pure-Luau getSpell/listAffordableSpells case table. Unlike the
-- run()-throws suites, SpellRegistry.__tests exposes runAll(), which
-- returns (passed, failed) counts instead of raising — mirrors
-- Suites/Skills/spellexecutor_tests.luau's wrapper shape.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

type Ctx = { passed: number?, failed: number? }

return {
	name = "spellregistry_tests",

	run = function(ctx: Ctx)
		local tests = require(
			ReplicatedStorage.Shared.SpellRegistry:FindFirstChild("__tests") :: ModuleScript
		)
		ctx.passed, ctx.failed = tests.runAll()
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		local passed = ctx.passed or 0
		local failed = ctx.failed or 0
		return failed == 0, string.format("%d passed, %d failed", passed, failed)
	end,
}
