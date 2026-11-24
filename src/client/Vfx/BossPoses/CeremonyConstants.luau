--!strict

----------------------------------------------------------------------
-- CeremonyConstants
----------------------------------------------------------------------
-- Tuning for the Ceremony pose layer (client/Vfx/BossPoses/Ceremony):
-- the entrance landing, the ward plates and the death sequence. Pure
-- feel; nothing here changes where the boss is or what it hits.
----------------------------------------------------------------------

local CeremonyConstants = {
	-- ── Entrance ───────────────────────────────────────────────
	-- A boss that was never seen airborne this long after it appeared is
	-- already standing (a late joiner, a streamed-in body): no landing.
	ENTRANCE_GROUND_GRACE_SEC = 0.6,
	-- Airborne = the ground is further below the root than the boss's own
	-- hover height plus this slack (a raycast: a Humanoid's FloorMaterial is
	-- not simulated for a boss another machine owns).
	ENTRANCE_GROUND_TOLERANCE = 2.5,
	ENTRANCE_RAY_LENGTH = 120,
	-- Downward speed (studs a second) that gives a full-strength landing.
	ENTRANCE_FULL_FALL_SPEED = 60,
	ENTRANCE_MIN_STRENGTH = 0.5,
	-- While falling the body holds still, lobes shut, eyes on the ground.
	ENTRANCE_FALL_LOOK_DOWN = Vector3.new(0, -100, 0),
	-- The landing squash: how far the lobes flatten and the brain dips at
	-- full strength, then the spring that settles it.
	LANDING_SQUASH = 0.38,
	LANDING_DIP_STUDS = 2.2,
	LANDING_SPRING_STIFFNESS = 140,
	LANDING_SPRING_DAMPING = 7,
	LANDING_SPRING_SETTLE = 0.01,
	-- The core flares on impact and fades back over this long.
	LANDING_FLARE_SCALE = 2.4,
	LANDING_FLARE_SEC = 0.6,
	-- Eyes after the landing: they hold shut-looking at the ground, snap
	-- up, look left, right, then back on the room.
	EYES_HOLD_SEC = 0.25,
	EYES_LOOK_SEC = 0.35,
	EYES_LOOK_DISTANCE = 40,
	EYES_LOOK_HEIGHT = 4,
	EYES_LOOK_ORDER = { -1, 1 },

	-- ── Ward plates ────────────────────────────────────────────
	-- One plate per quarter of the ward's letters. Each is an ellipsoid
	-- shell in the brain root's frame (the eyes at the front stay clear).
	WARD_PLATES = {
		{ offset = Vector3.new(-5.3, 0, 0), size = Vector3.new(1.6, 9.5, 10.5) },
		{ offset = Vector3.new(5.3, 0, 0), size = Vector3.new(1.6, 9.5, 10.5) },
		{ offset = Vector3.new(0, 4.9, 0), size = Vector3.new(8, 1.6, 10) },
		{ offset = Vector3.new(0, 0.5, 5.6), size = Vector3.new(8, 8, 1.6) },
	},
	WARD_PLATE_COLOR = Color3.fromRGB(90, 220, 255),
	WARD_PLATE_TRANSPARENCY = 0.35,
	-- Plates shimmer: transparency swings this much at this rate.
	WARD_PLATE_SHIMMER = 0.15,
	WARD_PLATE_SHIMMER_HZ = 0.8,
	WARD_CORE_LIGHT_SCALE = 0.4,
	WARD_SYNAPSE_GLOW = 0.7,
	WARD_NEURON_SPEED_SCALE = 1.8,

	-- A plate blown off flies out along its own direction (plus a lift),
	-- spins, fades and is destroyed.
	PLATE_FLIGHT_SEC = 0.9,
	PLATE_FLIGHT_DISTANCE = 16,
	PLATE_FLIGHT_LIFT = 5,
	PLATE_SPIN_RADIANS = math.rad(420),

	-- ── Death ──────────────────────────────────────────────────
	-- The burst has to land before the server destroys the model
	-- (BossService DEATH_LINGER_SEC, set longer than DEATH_BURST_AT_SEC plus
	-- the network delay). The burst's own debris outlives the model.
	DEATH_DEFLATE_SEC = 0.7,
	DEATH_BURST_AT_SEC = 1.3,
	DEATH_DEFLATE_SCALE = Vector3.new(0.5, 0.3, 0.5),
	DEATH_SINK_STUDS = 2.5,
	-- Spin speed, radians a second, ramps from the first to the second.
	DEATH_SPIN_START = math.rad(120),
	DEATH_SPIN_END = math.rad(1300),
	-- The last stretch before the burst: the core swells and glares between
	-- the lobes, the neurons spiral in and the body whitens.
	DEATH_CORE_LIGHT_SCALE = 5,
	DEATH_SYNAPSE_GLOW = 1,
	DEATH_LOBE_OPEN = math.rad(28),
	DEATH_TINT_ALPHA = 0.8,
	DEATH_NEURON_RADIUS_END = 0.3,
	DEATH_NEURON_SPEED_SCALE = 4,

	-- The burst: chunks of the body, a core flash and a ring.
	BURST_CHUNK_COUNT = 14,
	BURST_CHUNK_MIN_SIZE = 0.8,
	BURST_CHUNK_MAX_SIZE = 2.2,
	BURST_CHUNK_SPEED = 38,
	BURST_CHUNK_LIFT = 14,
	BURST_GRAVITY = 55,
	BURST_CHUNK_SEC = 1.2,
	BURST_PARTICLE_COUNT = 60,
	BURST_PARTICLE_SPEED = 30,
	BURST_PARTICLE_LIFETIME = 0.9,
	BURST_PARTICLE_SIZE = 2.5,
	BURST_FLASH_COLOR = Color3.fromRGB(255, 235, 160),
	BURST_FLASH_BRIGHTNESS = 6,
	BURST_FLASH_RANGE = 30,
	BURST_RING_DIAMETER_START = 4,
	BURST_RING_DIAMETER_END = 40,
	BURST_RING_SEC = 0.45,
	BURST_RING_TRANSPARENCY = 0.5,
	-- The effect part holding the particles and light lives this long.
	BURST_FX_LIFETIME_SEC = 2,

	-- Where client-only debris lives.
	FX_FOLDER_NAME = "BossCeremonyFx",
}

return CeremonyConstants
