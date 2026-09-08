--!strict

----------------------------------------------------------------------
-- memorizeaction_tests — autorunner wrapper for MemorizeAction.__tests
----------------------------------------------------------------------
-- Empty/invalid/mono-color/mixed-color tryMemorize scenarios (NIM-6).
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return {
	name = "memorizeaction_tests",

	run = function(_ctx: any)
		require(ReplicatedStorage.Shared.MemorizeAction:FindFirstChild("__tests") :: ModuleScript).run()
	end,
}
