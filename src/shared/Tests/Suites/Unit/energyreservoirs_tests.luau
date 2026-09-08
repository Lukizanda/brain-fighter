--!strict

----------------------------------------------------------------------
-- energyreservoirs_tests — autorunner wrapper for EnergyReservoirs.__tests
----------------------------------------------------------------------
-- add/drain/cap/reset scenarios, including Deferred BindableEvent
-- signal-fire counts.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return {
	name = "energyreservoirs_tests",

	run = function(_ctx: any)
		require(ReplicatedStorage.Shared.EnergyReservoirs:FindFirstChild("__tests") :: ModuleScript).run()
	end,
}
