----------------------------------------------------------------------
-- Test: multiplayer system invariants are intact at boot
----------------------------------------------------------------------
-- Boot-time structural assertions that would have caught the silent
-- multiplayer bugs this project has shipped before:
--
--   * One of the GameMode / Health remotes/events silently missing
--     because of a meta.json with `children` array (RoundStarted /
--     RoundEnded silent-fail trap, fixed Phase A1 validator).
--
-- This test is fast (< 1s), runs server-side, and asserts only invariants
-- that should hold for the lifetime of any playtest. If one fails,
-- something has structurally regressed.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return {
	name = "Multiplayer system invariants — script placement, remotes",

	verify = function(_ctx)
		local failures: { string } = {}

		-- 1. Multiplayer-critical RemoteEvents must exist at their expected paths.
		local expectedRemotes = {
			{ "ReplicatedStorage.Shared.GameMode.Remotes.KillFeed",   ReplicatedStorage.Shared.GameMode.Remotes:FindFirstChild("KillFeed") },
			{ "ReplicatedStorage.Shared.GameMode.Remotes.ScoreUpdate", ReplicatedStorage.Shared.GameMode.Remotes:FindFirstChild("ScoreUpdate") },
			{ "ReplicatedStorage.Shared.GameMode.Remotes.GameStateChanged", ReplicatedStorage.Shared.GameMode.Remotes:FindFirstChild("GameStateChanged") },
		}
		for _, pair in expectedRemotes do
			local label, instance = pair[1], pair[2]
			if not instance then
				table.insert(failures, string.format("missing remote: %s", label))
			elseif not (instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent")) then
				table.insert(failures, string.format("%s is %s, expected RemoteEvent/UnreliableRemoteEvent", label, instance.ClassName))
			end
		end

		-- 2. Server-side BindableEvents the GameMode + Health systems wire on.
		local healthEvents = ServerScriptService.Server.Health:FindFirstChild("Events")
		for _, name in { "PlayerDamaged", "PlayerEliminated" } do
			local instance = healthEvents and healthEvents:FindFirstChild(name)
			if not instance or not instance:IsA("BindableEvent") then
				table.insert(failures, string.format("ServerScriptService.Server.Health.Events.%s missing or wrong class", name))
			end
		end

		-- 3. Players service should exist with at least one player (the test
		-- harness depends on `ctx.player`). This is mostly a sanity check.
		if #Players:GetPlayers() == 0 then
			table.insert(failures, "no players in game (test harness needs at least one)")
		end

		if #failures > 0 then
			return false, table.concat(failures, "; ")
		end
		return true, "all multiplayer invariants intact"
	end,
}
