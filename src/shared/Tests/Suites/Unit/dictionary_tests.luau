--!strict

----------------------------------------------------------------------
-- dictionary_tests — autorunner wrapper for Dictionary.__tests
----------------------------------------------------------------------
-- isWord/resolve/isSpellable smoke suite plus getStats bootstrap-size
-- sanity check.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return {
	name = "dictionary_tests",

	run = function(_ctx: any)
		require(ReplicatedStorage.Shared.Dictionary:FindFirstChild("__tests") :: ModuleScript).run()
	end,
}
