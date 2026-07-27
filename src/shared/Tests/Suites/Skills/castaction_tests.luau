--!strict

----------------------------------------------------------------------
-- castaction_tests — autorunner wrapper for CastAction.__tests
----------------------------------------------------------------------
-- Runs the CastAction scenario harness (drain → execute → refund
-- pipeline, including the existing refund-on-executor-failure path the
-- Phase 5.1 stub change relies on). The harness raises on any failed
-- scenario; TestRunner's pcall converts that into a [TEST FAIL].
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return {
	name = "castaction_tests",

	run = function(_ctx: any)
		require(ReplicatedStorage.Shared.CastAction:FindFirstChild("__tests") :: ModuleScript).run()
	end,
}
