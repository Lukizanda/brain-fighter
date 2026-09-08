--!strict

----------------------------------------------------------------------
-- wordbuffer_tests — autorunner wrapper for WordBuffer.__tests
----------------------------------------------------------------------
-- Pure-Luau buffer smoke suite: append/size/isFull, color-bag counts,
-- reorder/remove/clear, fill-to-cap rejection, changed-signal fire
-- counts, wildcard tiles, and removeLastMatching rollback semantics.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return {
	name = "wordbuffer_tests",

	run = function(_ctx: any)
		require(ReplicatedStorage.Shared.WordBuffer:FindFirstChild("__tests") :: ModuleScript).run()
	end,
}
