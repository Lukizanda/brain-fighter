--!strict

----------------------------------------------------------------------
-- energyeconomy_tests — autorunner wrapper for EnergyEconomy.__tests
----------------------------------------------------------------------
-- Pinned word-energy and color-split cases (see gameplay-loop.md
-- worked examples), including wildcard splits.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return {
	name = "energyeconomy_tests",

	run = function(_ctx: any)
		require(ReplicatedStorage.Shared.EnergyEconomy:FindFirstChild("__tests") :: ModuleScript).run()
	end,
}
