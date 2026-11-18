--!strict

----------------------------------------------------------------------
-- BossPuppetConstants
----------------------------------------------------------------------
-- Tuning for the client puppet that animates a boss's body
-- (client/Vfx/BossPuppet, wiki/design/boss-movement.md). Pure feel: none
-- of these change where the boss is or what it hits.
----------------------------------------------------------------------

local BossPuppetConstants = {
	-- Beyond this many studs from the camera the puppet stops animating a
	-- boss (it holds its last pose).
	MAX_ANIMATE_DISTANCE = 400,

	-- How fast a smoothed value chases its goal, per second (higher =
	-- snappier). Used for lean, hover and eye turns.
	SMOOTHING_RATE = 6,

	-- ── Hover ──────────────────────────────────────────────────
	HOVER_LIFT = 0.8,            -- studs above the rest pose
	HOVER_BOB_AMPLITUDE = 0.45,  -- studs
	HOVER_BOB_HZ = 0.45,         -- bobs a second, standing still
	-- Extra bobs a second per stud a second of ground speed, so a boss
	-- on the move bounces faster.
	HOVER_BOB_HZ_PER_SPEED = 0.08,

	-- ── Breathing ──────────────────────────────────────────────
	BREATH_HZ = 0.3,
	BREATH_SCALE = 0.035,        -- fraction of the lobes' size

	-- ── Lean into travel ───────────────────────────────────────
	LEAN_RADIANS_PER_SPEED = math.rad(1.6), -- per stud a second
	LEAN_MAX_RADIANS = math.rad(18),
	-- The stem trails the lean by this multiple, in the other direction.
	STEM_TRAIL = 1.4,
	STEM_SWAY_RADIANS = math.rad(6),
	STEM_SWAY_HZ = 0.6,

	-- ── Eyes ───────────────────────────────────────────────────
	EYE_LOOK_RANGE = 160,        -- studs; the boss's own detection range
	EYE_MAX_RADIANS = math.rad(40),

	-- ── Neurons ────────────────────────────────────────────────
	NEURON_ORBIT_RADIUS = 7.5,
	NEURON_ORBIT_HZ = 0.12,      -- turns a second
	NEURON_BOB_STUDS = 1.6,
	NEURON_BOB_HZ = 0.35,
	NEURON_HEIGHT = 1.5,         -- studs above the core

	-- ── Hit reaction ───────────────────────────────────────────
	-- A damped spring kicked by each hit; the kick grows with the damage
	-- up to WOBBLE_FULL_DAMAGE.
	WOBBLE_STIFFNESS = 180,
	WOBBLE_DAMPING = 9,
	-- Peak wobble at a full kick (1 = the full squash, tilt and flinch below).
	WOBBLE_KICK = 1,
	WOBBLE_FULL_DAMAGE = 60,
	WOBBLE_SQUASH = 0.12,        -- fraction of size at a full kick
	WOBBLE_LOBE_FLINCH_RADIANS = math.rad(10),
	WOBBLE_TILT_RADIANS = math.rad(6),
	HIT_FLASH_COLOR = Color3.fromRGB(255, 255, 255),
	HIT_FLASH_TRANSPARENCY = 0.35, -- fill transparency at the flash's peak
	HIT_FLASH_SEC = 0.18,

	-- ── Core glow ──────────────────────────────────────────────
	CORE_PULSE_HZ = 0.6,
	CORE_LIGHT_MIN = 0.6,
	CORE_LIGHT_MAX = 1.6,
}

return BossPuppetConstants
