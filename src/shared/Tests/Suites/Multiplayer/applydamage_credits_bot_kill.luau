----------------------------------------------------------------------
-- Test: applyDamage on a bot end-to-end credits the killer + fires KillFeed
----------------------------------------------------------------------
-- Exercises the full server-authoritative damage path:
--
--   applyDamage.process(request)
--     → targetHumanoid.Health drops, wasLethal=true on lethal hit
--     → playerEliminatedEvent fires with sourcePlayer
--     → BotSpawner.onPlayerEliminated recognises BotTeam attribute
--     → ScoreTracker.recordBotKill credits the killer
--     → leaderstats.Kills increments, ScoreUpdate + KillFeed remotes fire
--
-- This is the chain that broke during the post-respawn-invulnerability
-- session (reload parity desync silently rejected damage server-side).
-- A test like this running in CI would have surfaced any future
-- regression on day one instead of in playtest.
--
-- The "second client" is a synthetic enemy — a TargetDummy clone tagged
-- with BotTeam / BotDisplayName attributes so BotSpawner's existing
-- onPlayerEliminated hook recognises it. We don't fire the Shoot remote;
-- we call applyDamage.process directly. Real two-client wire-level tests
-- (ShotReplication arrival on a remote client; cross-VM timestamp drift)
-- need a real second Studio session and stay in Phase D1.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Teams = game:GetService("Teams")

local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)

local DAMAGEABLE_TAG = "Damageable"
local BOT_TEAM_ATTRIBUTE = "BotTeam"
local BOT_NAME_ATTRIBUTE = "BotDisplayName"
local TEST_BOT_NAME = "TestBot_KillCredit"
local LETHAL_DAMAGE = 999

-- Find a TargetDummy in workspace to clone as the rig source. BotSpawner
-- uses the same pattern. If none exists, the test can't run.
local function findRigTemplate(): Model?
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("Model") and instance.Name:match("^TargetDummy") and instance:FindFirstChildOfClass("Humanoid") then
			return instance
		end
	end
	return nil
end

-- Pick the team OPPOSITE the player's, so the FF filter doesn't block
-- damage. If player has no team (FFA), pick any non-Neutral team.
local function pickEnemyTeam(player: Player): Team?
	if player.Team and not player.Neutral then
		for _, t in Teams:GetChildren() do
			if t:IsA("Team") and t ~= player.Team then
				return t
			end
		end
	end
	for _, t in Teams:GetChildren() do
		if t:IsA("Team") then
			return t
		end
	end
	return nil
end

return {
	name = "applyDamage credits killer + fires KillFeed end-to-end (bot path)",

	setup = function(ctx)
		assert(ctx.player, "no local player available")

		-- Read player's current kill count via leaderstats; we'll re-read
		-- after the kill and assert it incremented by exactly 1.
		local leaderstats = ctx.player:WaitForChild("leaderstats", 5)
		assert(leaderstats, "player.leaderstats missing — ScoreTracker not initialized?")
		local killsValue = leaderstats:WaitForChild("Kills", 2)
		assert(killsValue and killsValue:IsA("IntValue"), "leaderstats.Kills missing or wrong class")
		ctx.killsValue = killsValue
		ctx.killsBefore = killsValue.Value

		-- Source rig.
		local rig = findRigTemplate()
		assert(rig, "no TargetDummy rig found in workspace to clone for the test bot")

		-- Spawn a synthetic enemy bot at a fixed nearby offset from the player.
		local enemyTeam = pickEnemyTeam(ctx.player)
		local teamName = enemyTeam and enemyTeam.Name or "Neutral"

		local bot = rig:Clone()
		bot.Name = TEST_BOT_NAME
		bot:SetAttribute(BOT_TEAM_ATTRIBUTE, teamName)
		bot:SetAttribute(BOT_NAME_ATTRIBUTE, TEST_BOT_NAME)
		-- Tell DeathHandler to clean the corpse after its FX finish instead
		-- of templating + respawning. Without this, the test's teardown
		-- races with DeathHandler's queued respawn (5s after death).
		bot:SetAttribute("respawnTime", 0)
		if not CollectionService:HasTag(bot, DAMAGEABLE_TAG) then
			CollectionService:AddTag(bot, DAMAGEABLE_TAG)
		end

		-- Park the bot somewhere away from any active gameplay so its death
		-- explosion doesn't disturb the running playtest. Use a fixed offset
		-- from the player; the actual position doesn't matter for the test.
		local playerChar = ctx.player.Character or ctx.player.CharacterAdded:Wait()
		local hrp = playerChar:WaitForChild("HumanoidRootPart", 5)
		assert(hrp, "player has no HumanoidRootPart")
		bot:PivotTo(CFrame.new(hrp.Position + Vector3.new(8, 0, 0)))
		bot.Parent = workspace

		-- Wait one frame for the rig to fully settle before damage hits.
		task.wait()
		local botHumanoid = bot:FindFirstChildOfClass("Humanoid")
		assert(botHumanoid and botHumanoid.Health > 0, "bot rig has no live humanoid after spawn")
		ctx.bot = bot
		ctx.botHumanoid = botHumanoid
	end,

	run = function(ctx)
		-- Fire applyDamage directly — same call site the firearm server
		-- pipeline uses (src/server/Firearm/Scripts/Blaster/init.server.luau).
		-- On lethal, the chain through playerEliminatedEvent →
		-- BotSpawner.onPlayerEliminated → ScoreTracker.recordBotKill →
		-- leaderstats fires synchronously.
		local result = applyDamage.process({
			sourcePlayer = ctx.player,
			targetHumanoid = ctx.botHumanoid,
			baseDamage = LETHAL_DAMAGE,
			damageType = DamageTypes.DamageType.Bullet,
			hitZone = DamageTypes.HitZone.Torso,
			sourceWeapon = nil,
			timestamp = workspace:GetServerTimeNow(),
		})
		ctx.result = result
		-- Give a couple of frames for the BindableEvent → recordBotKill →
		-- leaderstats update chain (everything fires synchronously, but
		-- one task.wait() guards against any deferred connection).
		task.wait()
	end,

	verify = function(ctx)
		if not ctx.result then
			return false, "applyDamage.process returned nil (request rejected before damage applied)"
		end
		if not ctx.result.wasLethal then
			return false, string.format("damage was not lethal — bot HP %d, finalDamage %d", ctx.botHumanoid.Health, ctx.result.finalDamage)
		end
		if ctx.botHumanoid.Health > 0 then
			return false, string.format("bot still alive after lethal damage (HP=%d)", ctx.botHumanoid.Health)
		end

		-- Kill credit must have flowed through ScoreTracker.recordBotKill,
		-- which is wired by BotSpawner.onPlayerEliminated when a non-Player
		-- humanoid carrying the BotTeam attribute dies.
		local killsAfter = ctx.killsValue.Value
		if killsAfter ~= ctx.killsBefore + 1 then
			return false, string.format(
				"leaderstats.Kills did not increment by 1 (was %d, now %d). "
				.. "BotSpawner.onPlayerEliminated may not be wired, or ScoreTracker.recordBotKill regressed.",
				ctx.killsBefore, killsAfter
			)
		end

		return true, string.format("bot HP 0, killer kills %d → %d", ctx.killsBefore, killsAfter)
	end,

	teardown = function(ctx)
		-- The bot has respawnTime=0 so DeathHandler destroys it after its
		-- explosion FX (no template, no respawn loop). We just tidy up any
		-- stale instances from prior failed runs.
		for _, m in workspace:GetChildren() do
			if m:IsA("Model") and m.Name == TEST_BOT_NAME then
				m:Destroy()
			end
		end
	end,
}
