--[[
	Patroller archetype
	-------------------
	Phase 0: stub config only. States and transitions filled in Phase 3+.
	The Patroller is the MVP NPC type — walks between PatrolPoint waypoints.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCConstants = require(ReplicatedStorage.Shared.NPC.NPCConstants)

local Patroller = {
	name = "Patroller",
	templateName = "Patroller", -- looks up ServerStorage.AIWorldData.Rigs.Patroller
	walkSpeed = NPCConstants.DEFAULT_WALK_SPEED,
	initialState = NPCConstants.State.Patrol,

	-- Weapon template (optional) — cloned from ReplicatedStorage.Shared.Weapon.Templates
	-- and welded to the NPC's right hand on spawn for visual display only.
	-- NPC damage comes from NPCConstants.COMBAT_*, not the weapon's attributes.
	weaponTemplateName = nil :: string?,

	-- Animation asset IDs (rbxassetid:// strings). nil = skip that animation.
	-- Default R15 walk/idle + Rifle shoot animation from the weapon template.
	animations = {
		walk = "rbxassetid://507777826", -- R15 Walk
		idle = "rbxassetid://507766666", -- R15 Idle 1
		aim = "rbxassetid://17747384020", -- Rifle Idle (held pose for Combat)
		shoot = "rbxassetid://17747381445", -- Rifle Shoot (triggered per shot)
	},

	-- Filled in Phase 3 (states) and Phase 5 (transitions)
	states = {},
	transitions = {},
}

return Patroller
