----------------------------------------------------------------------
-- Test: NPC enters Combat when player approaches within engage range
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ensurePatroller = require(ReplicatedStorage.Shared.Tests.Helpers.ensurePatroller)

local COMBAT_ENGAGE_DISTANCE = 40 -- matches NPCConstants.COMBAT_ENGAGE_DISTANCE
local OFFSET_FROM_NPC = 25 -- teleport the player this close to the NPC (well inside engage range)

return {
	name = "NPC enters Combat when player is within engage range",

	setup = function(ctx)
		local fixture = ensurePatroller.ensure(ctx.player)
		assert(fixture, "Could not build the Patroller fixture (no AIWorldData.Rigs.Patroller template)")
		assert(ctx.player, "No local player")

		local character = ctx.player.Character
		assert(character, "Player has no character")
		local hrp = character:FindFirstChild("HumanoidRootPart")
		assert(hrp, "Player character has no HRP")

		ctx.npcFixture = fixture
		ctx.npc = fixture.npc
		ctx.originalHealth = ctx.player.Character:FindFirstChildOfClass("Humanoid").MaxHealth

		-- Teleport player to within engage range of the NPC
		local npcPos = fixture.npc:GetPivot().Position
		local targetPos = npcPos + Vector3.new(0, 0, OFFSET_FROM_NPC)
		character:PivotTo(CFrame.new(targetPos, npcPos))
		fixture:engage()
	end,

	run = function(_ctx)
		-- NPC perception + state machine runs on Heartbeat — wait a couple seconds
		task.wait(2)
	end,

	verify = function(ctx)
		local state = ctx.npc:GetAttribute("CurrentState")
		if state == "Combat" then
			return true, nil
		end
		return false, string.format("Expected Combat, got %s", tostring(state))
	end,

	teardown = function(ctx)
		ensurePatroller.teardown(ctx.npcFixture)
	end,
}
