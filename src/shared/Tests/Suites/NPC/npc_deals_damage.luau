----------------------------------------------------------------------
-- Test: NPC deals damage to the player while in Combat
----------------------------------------------------------------------

local ENGAGE_OFFSET = 25
local ENGAGE_TIMEOUT_SECONDS = 5 -- max time to wait for NPC to enter Combat
local ENGAGE_POLL_INTERVAL = 0.25 -- re-teleport player near NPC each tick (NPC may be patrolling)
local DAMAGE_WAIT_SECONDS = 4 -- enough time for 2+ shots at 120 RPM

return {
	name = "NPC deals damage to player in Combat",

	setup = function(ctx)
		local npc = workspace:FindFirstChild("Patroller_1")
		assert(npc, "No Patroller_1 NPC in workspace")
		assert(ctx.player, "No local player")

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
	end,
}
