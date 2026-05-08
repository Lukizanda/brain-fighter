----------------------------------------------------------------------
-- MeleeConstants
----------------------------------------------------------------------
-- Shared constants for melee weapons. Per-weapon values (damage, reach,
-- durations) come from the archetype; these are engine-wide defaults.
----------------------------------------------------------------------

local MeleeConstants = {
	-- Swing phase names (used by both client and server state machines)
	State = {
		Unequipped = "Unequipped",
		Idle = "Idle",
		Windup = "Windup", -- animation anticipation, no damage yet
		Active = "Active", -- damage window, hit detection runs
		Recovery = "Recovery", -- follow-through, cannot swing again
	},

	HitMode = {
		Single = "Single", -- first target hit ends the sweep
		Cleave = "Cleave", -- all targets in the box take damage
	},

	-- Attribute names (server + client share these via Tool attributes)
	DAMAGE_ATTRIBUTE = "meleeDamage",
	REACH_ATTRIBUTE = "meleeReach", -- studs forward from handle
	HITBOX_WIDTH_ATTRIBUTE = "meleeHitboxWidth",
	HITBOX_HEIGHT_ATTRIBUTE = "meleeHitboxHeight",
	WINDUP_SECONDS_ATTRIBUTE = "meleeWindupSeconds",
	ACTIVE_SECONDS_ATTRIBUTE = "meleeActiveSeconds",
	RECOVERY_SECONDS_ATTRIBUTE = "meleeRecoverySeconds",
	COOLDOWN_SECONDS_ATTRIBUTE = "meleeCooldownSeconds",
	HIT_MODE_ATTRIBUTE = "meleeHitMode",

	-- RemoteEvent name under Weapon/Remotes
	SWING_REQUEST_REMOTE = "MeleeSwingRequest",

	-- Server validation: how much clock skew to tolerate on cooldown checks
	COOLDOWN_SKEW_TOLERANCE = 0.05,

	-- Hit detection: how many sub-steps to take across the active window
	-- (more steps = catches fast-moving targets, costs more raycasts)
	HIT_DETECTION_SUBSTEPS = 4,

	-- Hybrid hit-detection (client-claims, server-validates) tuning.
	-- The client runs the actual hit sweep with blade-accurate geometry
	-- and sends claimed humanoids; the server sanity-checks each claim.
	SERVER_SANITY_REACH_MULTIPLIER = 1.5, -- accept claims within reach * this
	MAX_CLAIMS_PER_SWING = 16,            -- DoS guard: reject oversized claim lists
	STALE_CLAIM_THRESHOLD = 2.0,          -- reject if os.clock() - clientTime exceeds this
	LOS_SANITY_ENABLED = true,            -- raycast HRP->target; reject if blocked
}

return MeleeConstants
