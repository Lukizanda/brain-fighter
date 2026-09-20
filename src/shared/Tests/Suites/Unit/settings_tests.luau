--!strict

----------------------------------------------------------------------
-- settings_tests — autorunner wrapper for Settings.__tests
----------------------------------------------------------------------
-- Defaults, clamp/snap, garbage → default, changed-signal count, and
-- the Colors palette round-trip.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return {
	name = "settings_tests",

	run = function(_ctx: any)
		require(ReplicatedStorage.Shared.Settings:FindFirstChild("__tests") :: ModuleScript).run()
	end,
}
