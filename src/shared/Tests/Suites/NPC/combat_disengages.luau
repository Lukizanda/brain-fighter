----------------------------------------------------------------------
-- Test: NPC disengages Combat when player moves out of range
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ensurePatroller = require(ReplicatedStorage.Shared.Tests.Helpers.ensurePatroller)
local restoreToSafeSpawn = require(ReplicatedStorage.Shared.Tests.Helpers.restoreToSafeSpawn)

local NEAR_OFFSET = 25 -- inside engage range
local FAR_OFFSET = 80 -- outside disengage range

return {
	name = "NPC disengages Combat when player leaves range",

	setup = function(ctx)
		local fixture = ensurePatroller.ensure()
		assert(fixture, "Could not obtain a Patroller_1 NPC (no boot spawn and no AIWorldData.Rigs.Patroller template)")
		assert(ctx.player, "No local player")

		local character = ctx.player.Character
		assert(character, "Player has no character")

		ctx.npcFixture = fixture
		local npc = fixture.npc
		ctx.npc = npc
		local npcPos = npc:GetPivot().Position

		character:PivotTo(CFrame.new(npcPos + Vector3.new(0, 0, NEAR_OFFSET), npcPos))
		task.wait(2) -- let NPC detect and enter Combat

		assert(npc:GetAttribute("CurrentState") == "Combat",
			"Precondition failed: NPC should have been in Combat before leaving range")

		-- Now move player far away (same Y as NPC so we don't fall-die mid-suite)
		character:PivotTo(CFrame.new(npcPos + Vector3.new(0, 0, FAR_OFFSET), npcPos))
	end,

	run = function(_ctx)
		task.wait(3) -- give NPC time to notice player is gone + re-patrol
	end,

	verify = function(ctx)
		local state = ctx.npc:GetAttribute("CurrentState")
		-- Disengage means back to Patrol (or Idle if still within detection but not LOS)
		if state == "Patrol" or state == "Idle" then
			return true, string.format("Disengaged to %s", state)
		end
		return false, string.format("Expected Patrol or Idle, got %s", tostring(state))
	end,

	teardown = function(ctx)
		-- This test deliberately teleports the player far from the NPC
		-- (FAR_OFFSET), which can land them over open air / off the arena
		-- platform and into a DeathZone before the next test runs. Put them
		-- back on solid ground so a following test's setup doesn't inherit
		-- a mid-fall or mid-respawn character.
		if ctx.player then
			restoreToSafeSpawn.restoreToSafeSpawn(ctx.player)
		end
		ensurePatroller.teardown(ctx.npcFixture)
	end,
}
