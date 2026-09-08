--!strict

----------------------------------------------------------------------
-- mindfullmanager_tests — autorunner wrapper for MindFullManager.__tests
----------------------------------------------------------------------
-- mindFull/mindFreed transition-edge scenarios, including the
-- born-full and destroy-cleanup cases.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return {
	name = "mindfullmanager_tests",

	run = function(_ctx: any)
		require(ReplicatedStorage.Shared.MindFullManager:FindFirstChild("__tests") :: ModuleScript).run()
	end,
}
