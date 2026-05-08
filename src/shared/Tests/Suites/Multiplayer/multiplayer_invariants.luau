----------------------------------------------------------------------
-- Test: multiplayer system invariants are intact at boot
----------------------------------------------------------------------
-- Boot-time structural assertions that would have caught the silent
-- multiplayer bugs this project has shipped before:
--
--   * `ShotReplication.client.luau` parented in ReplicatedStorage instead
--     of StarterPlayerScripts → never auto-runs → remote shot FX silently
--     don't replicate to other clients (bug shipped from project setup
--     until 2026-04-30).
--   * One of the GameMode / Weapon / Health remotes silently missing
--     because of a meta.json with `children` array (RoundStarted /
--     RoundEnded silent-fail trap, fixed Phase A1 validator).
--   * Team / SpawnLocation infrastructure dropped during a refactor.
--
-- This test is fast (< 1s), runs server-side, and asserts only invariants
-- that should hold for the lifetime of any TDM playtest. If one fails,
-- something has structurally regressed.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local Teams = game:GetService("Teams")

local function findDescendantByName(root: Instance, name: string): Instance?
	for _, descendant in root:GetDescendants() do
		if descendant.Name == name then
			return descendant
		end
	end
	return nil
end

return {
	name = "Multiplayer system invariants — script placement, remotes, teams",

	verify = function(_ctx)
		local failures: { string } = {}

		-- 1. ShotReplication must auto-run on every client. That means the
		-- .client.luau must end up in StarterPlayerScripts (or descendants),
		-- not ReplicatedStorage.
		local shotReplication = findDescendantByName(StarterPlayer.StarterPlayerScripts, "ShotReplication")
		if not shotReplication or not shotReplication:IsA("LocalScript") then
			table.insert(failures, "ShotReplication LocalScript missing from StarterPlayerScripts (placement bug — see concepts/LocalScriptPlacement)")
		end
		-- And it must NOT be sitting in ReplicatedStorage.Shared.* — that's
		-- where it lived as dead code for the project's lifetime.
		local strayInShared = findDescendantByName(ReplicatedStorage.Shared, "ShotReplication")
		if strayInShared and strayInShared:IsA("LocalScript") then
			table.insert(failures, string.format(
				"ShotReplication LocalScript also exists in ReplicatedStorage at %s — Roblox doesn't auto-run LocalScripts in ReplicatedStorage; remove it",
				strayInShared:GetFullName()
			))
		end

		-- 2. Multiplayer-critical RemoteEvents must exist at their expected paths.
		local expectedRemotes = {
			{ "ReplicatedStorage.Shared.Weapon.Remotes.Shoot",        ReplicatedStorage.Shared.Weapon.Remotes:FindFirstChild("Shoot") },
			{ "ReplicatedStorage.Shared.Weapon.Remotes.Reload",       ReplicatedStorage.Shared.Weapon.Remotes:FindFirstChild("Reload") },
			{ "ReplicatedStorage.Shared.Weapon.Remotes.ReplicateShot", ReplicatedStorage.Shared.Weapon.Remotes:FindFirstChild("ReplicateShot") },
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

		-- 3. Server-side BindableEvents the GameMode + Health systems wire on.
		local healthEvents = ServerScriptService.Server.Health:FindFirstChild("Events")
		for _, name in { "PlayerDamaged", "PlayerEliminated", "PlayerRespawned" } do
			local instance = healthEvents and healthEvents:FindFirstChild(name)
			if not instance or not instance:IsA("BindableEvent") then
				table.insert(failures, string.format("ServerScriptService.Server.Health.Events.%s missing or wrong class", name))
			end
		end

		-- 4. TDM team infrastructure: when TDM is active, both Red and Blue
		-- Team instances must exist with non-Neutral SpawnLocations matching
		-- their TeamColor (otherwise team-aware spawning breaks).
		local activeMode = workspace:GetAttribute("ActiveGameMode")
		if activeMode == "TeamDeathmatch" then
			for _, teamName in { "Red", "Blue" } do
				local team = Teams:FindFirstChild(teamName)
				if not team or not team:IsA("Team") then
					table.insert(failures, string.format("TDM active but Teams.%s missing", teamName))
				else
					local matched = false
					for _, instance in workspace:GetDescendants() do
						if instance:IsA("SpawnLocation") and not instance.Neutral and instance.TeamColor == team.TeamColor then
							matched = true
							break
						end
					end
					if not matched then
						table.insert(failures, string.format("TDM active but no non-Neutral SpawnLocation matches Teams.%s.TeamColor", teamName))
					end
				end
			end
		end

		-- 5. Players service should exist with at least one player (the test
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
