--!strict

----------------------------------------------------------------------
-- ExposedConstants
----------------------------------------------------------------------
-- Tuning for the Exposed pose layer (stage 11c, wiki/design/boss-movement.md
-- § Vulnerability windows): how far the core opens, how deep the body sinks,
-- how the eyes spin, how bright the core gets, and how fast it all opens and
-- closes. Values are on top of the puppet's own (BrainPuppetConstants).
----------------------------------------------------------------------

return {
	-- Opening: the pose eases in at this rate (weight a second, 0..1), and
	-- eases out over the last CLOSE_SEC of the window so it is shut as the
	-- window ends.
	OPEN_RATE_PER_SEC = 6,
	CLOSE_SEC = 0.35,

	-- Lobes swing wide to bare the core, fluttering a little.
	LOBE_OPEN_RADIANS = math.rad(38),
	LOBE_FLUTTER_RADIANS = math.rad(4),
	LOBE_FLUTTER_HZ = 5,

	-- Stunned: the body sinks and stops its idle motion.
	STUN_SINK_STUDS = 1.6,
	-- Exposed without a stun (the ward-break stagger): a shallower sink and a
	-- side-to-side reel instead of standing still.
	STAGGER_SINK_STUDS = 0.8,
	STAGGER_ROLL_RADIANS = math.rad(9),
	STAGGER_HZ = 1.3,

	-- Dizzy eyes: the gaze circles this far off its target, this fast.
	EYE_SPIN_RADIANS = math.rad(35),
	EYE_SPIN_HZ = 1.6,

	-- The core: extra multiples of its light, throbbing, in a hot white-gold.
	CORE_LIGHT_BOOST = 4,
	CORE_THROB_SHARE = 0.35,
	CORE_THROB_HZ = 3,
	CORE_LIGHT_COLOR = Color3.fromRGB(255, 236, 150),
	-- Above this weight the core light takes the exposed colour.
	CORE_COLOR_FROM_WEIGHT = 0.3,

	-- The synapses blaze, and a gold wash pulses over the body.
	SYNAPSE_GLOW = 1,
	TINT_COLOR = Color3.fromRGB(255, 220, 90),
	TINT_ALPHA_MIN = 0.15,
	TINT_ALPHA_MAX = 0.45,
	TINT_PULSE_HZ = 3,
	-- Below this weight the layer writes nothing.
	MIN_WEIGHT = 0.01,
}
