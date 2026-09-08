--!strict

----------------------------------------------------------------------
-- hud_tests — autorunner wrapper for Hud.__tests (HudGate)
----------------------------------------------------------------------
-- Hud.__tests requires Players.LocalPlayer at scenario time and errors
-- immediately on a VM with no local player (see Hud/__tests.luau's
-- "Client only" note). TestAutoRunner.server.luau only ever runs on
-- the server, so this suite cannot execute there — there is no client
-- autorunner yet (see wiki/systems/Tests.md).
--
-- Rather than report a false [TEST FAIL] for a harness gap instead of
-- a real regression, this wrapper checks RunService:IsServer() and
-- reports a passing-but-explicit skip when there's no client to run
-- on. On an actual client VM it runs for real.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

type Ctx = { skipped: boolean? }

return {
	name = "hud_tests",

	run = function(ctx: Ctx)
		if RunService:IsServer() then
			ctx.skipped = true
			return
		end
		require(ReplicatedStorage.Shared.Hud:FindFirstChild("__tests") :: ModuleScript).run()
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.skipped then
			return true, "skipped — client-only (Players.LocalPlayer required); no client autorunner exists yet"
		end
		return true
	end,
}
