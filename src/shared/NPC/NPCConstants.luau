--[[
	NPCConstants
	------------
	Tunable values and named tags for the NPC system.
	Phase 0: scaffolding only — values used in later phases.
]]

local NPCConstants = {
	-- ============================================================
	-- CollectionService tags
	-- ============================================================
	TAG_NPC = "NPC",                  -- applied to spawned NPC models
	TAG_NPC_SPAWN = "NPCSpawn",       -- parts that mark where NPCs spawn
	TAG_PATROL_POINT = "PatrolPoint", -- parts that define patrol routes

	-- ============================================================
	-- Movement
	-- ============================================================
	DEFAULT_WALK_SPEED = 12,          -- studs/sec
	PATH_RECOMPUTE_DISTANCE = 4,      -- recompute path if target moved this far
	WAYPOINT_REACHED_DISTANCE = 4,    -- studs from waypoint to consider arrived
	MOVE_TIMEOUT_SECONDS = 8,         -- give up on a single MoveTo after this long

	-- ============================================================
	-- Perception
	-- ============================================================
	DETECTION_RANGE = 50,             -- studs — max distance to notice a player
	IDLE_TRIGGER_DISTANCE = 15,       -- enter Idle when player within this range
	PATROL_RESUME_DISTANCE = 25,      -- resume Patrol when player beyond this range
	-- Hysteresis between IDLE_TRIGGER and PATROL_RESUME prevents flicker

	-- ============================================================
	-- Combat
	-- ============================================================
	COMBAT_ENGAGE_DISTANCE = 40,      -- enter Combat if visible player is within this range
	COMBAT_DISENGAGE_DISTANCE = 55,   -- leave Combat if player beyond this range (hysteresis)
	COMBAT_RATE_OF_FIRE = 120,        -- rounds per minute (0.5s between shots)
	COMBAT_DAMAGE = 8,                -- damage per hit (lower than player weapons — NPCs are beatable)
	COMBAT_SPREAD_DEGREES = 4,        -- accuracy cone half-angle; higher = less accurate
	COMBAT_RANGE = 80,                -- max shot distance
	COMBAT_RAY_RADIUS = 0.25,         -- spherecast radius for more forgiving hitboxes

	-- ============================================================
	-- State names (string constants — avoid magic strings)
	-- ============================================================
	State = {
		Idle = "Idle",
		Patrol = "Patrol",
		Combat = "Combat",
	},

	-- ============================================================
	-- Action results (matches BT leaf semantics for future migration)
	-- ============================================================
	ActionResult = {
		Running = "Running",
		Success = "Success",
		Failure = "Failure",
	},

	-- ============================================================
	-- Logging
	-- ============================================================
	LOG_THROTTLE_INTERVAL = 60,       -- frames between throttled per-NPC logs
}

return NPCConstants
