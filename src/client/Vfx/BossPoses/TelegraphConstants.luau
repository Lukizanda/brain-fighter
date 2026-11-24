--!strict

----------------------------------------------------------------------
-- TelegraphConstants
----------------------------------------------------------------------
-- Tuning for the Telegraph pose layer (stage 11b of
-- wiki/design/boss-movement.md): the body tell for each attack and for
-- eating. Pure feel; none of these change where the boss is or what it hits.
--
-- Every tell is timed to the boss's `WindupEndsAt`: it builds in the last
-- N seconds before it, peaks on it and releases after it. Lengths that the
-- server also knows (a shot's stagger, the slam's total warning) are read
-- from BossConfig by the layer; the FALLBACK_* values below are used only
-- if the config is missing them.
--
-- Axes are the boss's own frame: -Z is forward, +Y is up. Rotating about X by
-- a positive angle tips the top of the brain toward +Z (back).
----------------------------------------------------------------------

local TelegraphConstants = {
	-- ── Shared ─────────────────────────────────────────────────
	-- How long a tell takes to fade out after its attack's last beat.
	RELEASE_SEC = 0.4,

	-- ── Fireball volley: draw back and up, glow, recoil per shot ──
	-- The draw builds over this many seconds before WindupEndsAt.
	VOLLEY_DRAW_SEC = 0.7,
	VOLLEY_RISE_STUDS = 1.6,
	VOLLEY_BACK_STUDS = 2.4,
	VOLLEY_TILT_RADIANS = math.rad(14),
	-- A kick on every shot (decays over one shot interval).
	VOLLEY_RECOIL_STUDS = 1.1,
	VOLLEY_RECOIL_TILT_RADIANS = math.rad(5),
	-- Fraction of the full draw held while the shots fly.
	VOLLEY_HOLD = 0.85,
	VOLLEY_GLOW_COLOR = Color3.fromRGB(255, 70, 30),
	VOLLEY_TINT_ALPHA = 0.4,
	VOLLEY_CORE_LIGHT_BOOST = 2.2,  -- extra multiples of the core light at full draw
	VOLLEY_IDLE_MOTION_LEFT = 0.25, -- idle bob left while drawing (1 = all of it)
	VOLLEY_NEURON_SPEED_BOOST = 3,  -- extra multiples of the neuron orbit speed
	VOLLEY_NEURON_RADIUS_SCALE = 0.65, -- neurons pull in tight at full draw
	FALLBACK_VOLLEY_SHOT_COUNT = 20,
	FALLBACK_VOLLEY_SHOT_INTERVAL_SEC = 0.15,

	-- ── Ground slam: rise, hang, drop with squash and stretch ───
	-- The attack's name in the config (BossConstants has none for it).
	SLAM_ATTACK = "GroundSlam",
	-- The warning starts at the server's total (prep + the slam's own
	-- windup); the body rises over SLAM_RISE_SEC, hangs, then drops in the
	-- last SLAM_DROP_SEC to land on WindupEndsAt.
	SLAM_RISE_SEC = 0.65,
	SLAM_DROP_SEC = 0.18,
	SLAM_LIFT_STUDS = 8,
	-- The hang trembles.
	SLAM_QUIVER_STUDS = 0.18,
	SLAM_QUIVER_HZ = 22,
	-- Stretched while rising and dropping; squashed on landing.
	SLAM_RISE_SCALE = Vector3.new(0.96, 1.08, 0.96),
	SLAM_DROP_SCALE = Vector3.new(0.88, 1.22, 0.88),
	SLAM_LAND_SCALE = Vector3.new(1.24, 0.66, 1.24),
	SLAM_LAND_SINK_STUDS = 1.4,
	SLAM_LAND_RECOVER_SEC = 0.45,
	SLAM_TINT = Color3.fromRGB(255, 150, 40),
	SLAM_TINT_ALPHA = 0.3,
	SLAM_GLOW = 0.7,
	SLAM_NEURON_RADIUS_SCALE = 0.7,
	-- Neurons burst outward on the landing, then settle.
	SLAM_LAND_NEURON_RADIUS_SCALE = 1.5,
	FALLBACK_SLAM_TOTAL_WARNING_SEC = 1.8,
	FALLBACK_SLAM_RADIUS_STUDS = 22,

	-- The client-only shadow on the ground under the slam.
	SHADOW_NAME = "BossSlamShadow",
	SHADOW_COLOR = Color3.fromRGB(0, 0, 0),
	SHADOW_HEIGHT_STUDS = 0.2,
	SHADOW_START_DIAMETER = 6,
	-- Share of the slam's full radius the shadow reaches at the landing.
	SHADOW_FULL_RADIUS_FRACTION = 0.9,
	SHADOW_MAX_TRANSPARENCY = 0.85,
	SHADOW_MIN_TRANSPARENCY = 0.4,
	SHADOW_FADE_SEC = 0.35,
	SHADOW_RAY_DISTANCE = 60,
	-- Studs above the boss's root the ground ray starts from (clears the floor).
	SHADOW_RAY_START_STUDS = 1,
	-- Lift above the hit point so the disc does not z-fight the floor.
	SHADOW_GROUND_CLEARANCE_STUDS = 0.08,

	-- ── Spore lob: swell, gulp, spit ───────────────────────────
	-- Violet, so it never reads as the volley's red.
	SPORE_TINT = Color3.fromRGB(170, 90, 230),
	SPORE_TINT_ALPHA = 0.35,
	SPORE_GULP_SEC = 0.9,
	SPORE_GULP_COUNT = 2,
	-- Body inflates by this fraction as it swells; each gulp adds a pulse.
	SPORE_SWELL_FRACTION = 0.1,
	SPORE_GULP_PULSE_FRACTION = 0.07,
	SPORE_SINK_STUDS = 0.9,
	SPORE_HUNCH_BACK_STUDS = 0.8,
	SPORE_HUNCH_TILT_RADIANS = math.rad(8),
	-- The stem throbs down and out with each gulp (the pose has no stem
	-- scale, so it moves the stem instead).
	SPORE_STEM_THROB_STUDS = 0.8,
	SPORE_STEM_THROB_TILT_RADIANS = math.rad(20),
	SPORE_GLOW = 0.55,
	-- The spit: lurches forward and flattens, then recovers.
	SPORE_SPIT_SEC = 0.5,
	SPORE_SPIT_FORWARD_STUDS = 3,
	SPORE_SPIT_TILT_RADIANS = math.rad(-16),
	SPORE_SPIT_SCALE = Vector3.new(1.14, 0.8, 1.14),
	SPORE_SPIT_CORE_LIGHT_BOOST = 2.5,

	-- ── Eating: lean toward the letter, stem reaches out ───────
	-- How fast the lean fades in and out, per second.
	EAT_BLEND_RATE = 5,
	EAT_LEAN_RADIANS = math.rad(15),
	EAT_LEAN_FORWARD_STUDS = 1.4,
	EAT_STEM_REACH_RADIANS = math.rad(50),
	-- The reach flicks in and out like a tongue.
	EAT_REACH_HZ = 2.2,
	EAT_REACH_FLICK_FRACTION = 0.3,
	-- Eyes lock on the letter once the lean is this far in.
	EAT_EYE_LOCK_WEIGHT = 0.5,
	-- Below this blend the lean is not worth applying.
	EAT_MIN_WEIGHT = 0.001,
	-- Ignore a letter this close to straight up/down the boss's axis.
	EAT_MIN_FLAT_DISTANCE_STUDS = 0.5,
	-- The yank: the stem whips back past its rest (radians beyond straight
	-- down, away from the letter) as the letter is hauled in.
	EAT_WHIP_BACK_RADIANS = math.rad(35),
	-- The gulp as the letter lands: a quick swell and a settle.
	EAT_GULP_SEC = 0.3,
	-- Share of EAT_GULP_SEC spent swelling; the rest is the settle.
	EAT_GULP_ATTACK_FRACTION = 0.25,
	EAT_GULP_SWELL_FRACTION = 0.08,
	EAT_GULP_SINK_STUDS = 0.4,
	EAT_GULP_GLOW = 0.4,
}

return TelegraphConstants
