----------------------------------------------------------------------
-- restoreToSafeSpawn
----------------------------------------------------------------------
-- Teleports the player's HumanoidRootPart to a known-safe SpawnLocation
-- and zeroes its velocity. Tests that move HRP (e.g. zone-presence
-- checks) call this in teardown to leave the character at a stable
-- CFrame on solid ground — so the next test (and the post-autorun
-- player position) starts from a deterministic, grounded state.
--
-- Background: the previous pattern snapshotted `hrp.CFrame` at setup
-- and restored to that snapshot in teardown. If a prior test in the
-- same suite already moved HRP (so the snapshot was airborne / inside
-- a part / mid-fall), teardown restored to the same bad state — and
-- the player would fall through the world after autorun finished.
-- See `wiki/status/PlaytestVerification.md` (latent-issues section,
-- 2026-05-08 entry) for the full story.
--
-- Don't call this in setup — every Red SpawnLocation overlaps the
-- `RespawnZone`-tagged SpawnZoneBox, and starting a Touched-sensitive
-- test from inside the zone causes Roblox to fire Touched/TouchEnded
-- in unreliable order on the next big CFrame jump. Teardown-only is
-- both sufficient (each test starts where the prior one left them =
-- spawn, on solid ground) and avoids that race.
--
-- Spawn selection rules:
--   * If the player has a Team that is not Neutral, prefer a non-Neutral
--     SpawnLocation whose TeamColor matches.
--   * Else fall back to the first SpawnLocation found in Workspace.
--   * If no SpawnLocation exists at all, the function is a no-op (and
--     emits a warn log so a regression that delete spawn locations is
--     visible). Tests that depend on a fresh spawn state should also
--     verify their character is alive after this call.
----------------------------------------------------------------------

local Workspace = game:GetService("Workspace")

local SPAWN_HEIGHT_OFFSET = 5 -- studs above the SpawnLocation's top face

local Helpers = {}

local function findTeamSpawn(team: Team): SpawnLocation?
	for _, instance in Workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") and not instance.Neutral
			and instance.TeamColor == team.TeamColor then
			return instance
		end
	end
	return nil
end

local function findAnySpawn(): SpawnLocation?
	for _, instance in Workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") then
			return instance
		end
	end
	return nil
end

function Helpers.restoreToSafeSpawn(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	local spawn: SpawnLocation? = nil
	if player.Team and not player.Neutral then
		spawn = findTeamSpawn(player.Team)
	end
	if not spawn then
		spawn = findAnySpawn()
	end
	if not spawn then
		warn("[restoreToSafeSpawn] no SpawnLocation found in Workspace; HRP not moved")
		return
	end

	-- Place HRP above the spawn's top face. SpawnLocation.Position is the
	-- centre, so add half its Y size to land on top, then a small offset
	-- so we don't penetrate the spawn part itself.
	local landing = spawn.Position + Vector3.new(0, spawn.Size.Y * 0.5 + SPAWN_HEIGHT_OFFSET, 0)
	hrp.CFrame = CFrame.new(landing)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

return Helpers
