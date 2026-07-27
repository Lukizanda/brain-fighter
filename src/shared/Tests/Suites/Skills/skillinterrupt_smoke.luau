--!strict

----------------------------------------------------------------------
-- skillinterrupt_smoke — autorunner wrapper for Skills.__tests
----------------------------------------------------------------------
-- Runs the SkillInterrupt/SkillEffects smoke suite (token lifecycle,
-- silence, and the Phase 5.1 death-cleanup purges) inside the RunTests
-- flow. The __tests module raises on any failed scenario, which the
-- TestRunner's pcall converts into a [TEST FAIL] with the message.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return {
	name = "skillinterrupt_smoke",

	run = function(_ctx: any)
		require(ReplicatedStorage.Shared.Skills:FindFirstChild("__tests") :: ModuleScript).run()
	end,
}
