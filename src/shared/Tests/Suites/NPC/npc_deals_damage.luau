----------------------------------------------------------------------
-- Test: NPC deals damage to the player while in Combat
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ensurePatroller = require(ReplicatedStorage.Shared.Tests.Helpers.ensurePatroller)

local ENGAGE_OFFSET = 25
local ENGAGE_TIMEOUT_SECONDS = 5 -- max time to wait for NPC to enter Combat
local ENGAGE_POLL_INTERVAL = 0.25 -- re-teleport player near NPC each tick (NPC may be patrolling)
local DAMAGE_WAIT_SECONDS = 4 -- enough time for 2+ shots at 120 RPM

-- A preceding test (e.g. combat_disengages) can leave the player mid-fall,
-- mid-respawn, or mid-relocation (DeathZone -> lobby transfer). Starting
-- this test's engage-poll loop while that's still settling snapshots an
-- initial health right before another respawn silently resets it again,
-- which reads as "no damage dealt" even though the NPC never got a fair
-- shot. Wait for a genuinely settled character first.
local HEALTH_STABLE_WINDOW_SECONDS = 1
local HEALTH_STABLE_POLL_INTERVAL = 0.1
local HEALTH_STABLE_TIMEOUT_SECONDS = 8

local function waitForStableFullHealth(player: Player): (Humanoid?, string?)
	local deadline = os.clock() + HEALTH_STABLE_TIMEOUT_SECONDS
	local lastHumanoid: Humanoid? = nil
	local stableSince: number? = nil

	while os.clock() < deadline do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if humanoid and humanoid.Parent then
			if humanoid ~= lastHumanoid then
				-- New character/Humanoid since we last looked (a respawn
				-- happened mid-wait) — the stability window restarts.
				lastHumanoid = humanoid
				stableSince = nil
			end

			if humanoid.Health >= humanoid.MaxHealth then
				stableSince = stableSince or os.clock()
				if os.clock() - stableSince >= HEALTH_STABLE_WINDOW_SECONDS then
					return humanoid, nil
				end
			else
				stableSince = nil
			end
		else
			lastHumanoid = nil
			stableSince = nil
		end

		task.wait(HEALTH_STABLE_POLL_INTERVAL)
	end

	return nil, string.format(
		"player character/health never stabilised at max health within %ds",
		HEALTH_STABLE_TIMEOUT_SECONDS
	)
end

return {
	name = "NPC deals damage to player in Combat",

	setup = function(ctx)
		local fixture = ensurePatroller.ensure()
		assert(fixture, "Could not obtain a Patroller_1 NPC (no boot spawn and no AIWorldData.Rigs.Patroller template)")
		assert(ctx.player, "No local player")

		local settledHumanoid, stabiliseErr = waitForStableFullHealth(ctx.player)
		assert(settledHumanoid, stabiliseErr)

		ctx.npcFixture = fixture
		local npc = fixture.npc
		ctx.npc = npc

		-- Poll-teleport: re-fetch character each tick in case the player died
		-- in a prior test and respawned. Also re-snap to NPC position since it
		-- may be patrolling between ticks.
		local deadline = os.clock() + ENGAGE_TIMEOUT_SECONDS
		while os.clock() < deadline do
			local character = ctx.player.Character
			if character then
				local hum = character:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local npcPos = npc:GetPivot().Position
					character:PivotTo(CFrame.new(npcPos + Vector3.new(0, 0, ENGAGE_OFFSET), npcPos))
					if npc:GetAttribute("CurrentState") == "Combat" then
						break
					end
				end
			end
			task.wait(ENGAGE_POLL_INTERVAL)
		end

		-- Precondition: NPC must actually be in Combat or the damage check is meaningless
		assert(npc:GetAttribute("CurrentState") == "Combat",
			"Precondition failed: NPC did not enter Combat within " .. ENGAGE_TIMEOUT_SECONDS .. "s")

		-- Re-fetch humanoid fresh and heal AFTER combat entry so incidental damage
		-- during the engage wait doesn't poison the initial reading
		local character = ctx.player.Character
		assert(character, "Player has no character after engage")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		assert(humanoid, "Player has no Humanoid after engage")
		ctx.humanoid = humanoid
		humanoid.Health = humanoid.MaxHealth
		ctx.initialHealth = humanoid.Health
	end,

	run = function(_ctx)
		task.wait(DAMAGE_WAIT_SECONDS)
	end,

	verify = function(ctx)
		local healthNow = ctx.humanoid.Health
		if healthNow < ctx.initialHealth then
			return true, string.format("Player took %d damage (%d -> %d)",
				ctx.initialHealth - healthNow, ctx.initialHealth, healthNow)
		end
		return false, string.format("Player took no damage (still at %d HP)", healthNow)
	end,

	teardown = function(ctx)
		-- Restore health so follow-up tests start clean
		if ctx.humanoid and ctx.humanoid.Parent then
			ctx.humanoid.Health = ctx.humanoid.MaxHealth
		end
		ensurePatroller.teardown(ctx.npcFixture)
	end,
}
