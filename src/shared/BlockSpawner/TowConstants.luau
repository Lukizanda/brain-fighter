--!strict

----------------------------------------------------------------------
-- TowConstants
----------------------------------------------------------------------
-- The published state of a letter block that is being pulled toward a point
-- (BlockSpawner's tow API; the boss's hunger is the first user). The pool
-- writes it, and two clients read it: LetterBlockAnimator (so the block it
-- animates follows the server's position instead of fighting it) and
-- LetterTowTether (the line drawn from the block to what pulls it). The pool
-- knows nothing about bosses: the target is just a point.
--
-- Shared so the writer and both readers agree on the names without any of
-- them requiring the other.
----------------------------------------------------------------------

local TowConstants = {
	-- On the block for as long as it is in tow. Set after the two attributes
	-- below, so a client that sees the tag finds them.
	TAG = "LetterBlockTowed",
	-- Vector3: where the server has the block now (its animated base
	-- position, without the client's bob and tumble). The server also moves
	-- the model, but the client animator rewrites the model's pivot every
	-- frame, so this is what it follows.
	POSITION_ATTRIBUTE = "Block.TowPosition",
	-- Vector3: the point it is being pulled toward right now.
	TARGET_ATTRIBUTE = "Block.TowTarget",
	-- Vector3: where the block was when the tow began, i.e. where it is held
	-- while a tow has a hold, and where the snap starts from.
	FROM_ATTRIBUTE = "Block.TowFrom",

	-- ============================================================
	-- The hold-then-snap schedule (BlockSpawner.scheduleTow). All numbers are
	-- `workspace:GetServerTimeNow()` seconds, never os.clock(). Absent on a
	-- plain tow, which just follows POSITION_ATTRIBUTE.
	-- ============================================================
	-- When the tow began (the start of the hold).
	BEGAN_AT_ATTRIBUTE = "Block.TowBeganAt",
	-- When the hold ends and the block starts to travel.
	SNAP_AT_ATTRIBUTE = "Block.TowSnapAt",
	-- When the block reaches the target.
	ARRIVE_AT_ATTRIBUTE = "Block.TowArriveAt",
	-- Present while the schedule's clock is stopped (the caller is held, e.g.
	-- the boss is frozen): the server time it stopped at. Clients count time
	-- as min(now, this). Cleared when the caller republishes shifted times.
	PAUSED_AT_ATTRIBUTE = "Block.TowPausedAt",

	-- ============================================================
	-- The snap's curve, read by the server (what moves the block) and the
	-- client (what draws it): see TowCurve. Fraction of the way =
	-- (elapsed / duration) ^ SNAP_POWER.
	-- ============================================================
	SNAP_POWER = 3,

	-- ============================================================
	-- Mark look (LetterBlockAnimator, LetterTowTether), while the block is held.
	-- ============================================================
	-- The held block trembles, from the first amount to the second as the snap
	-- nears (studs of offset on each axis).
	TREMBLE_STUDS_START = 0.05,
	TREMBLE_STUDS_END = 0.45,
	TREMBLE_HZ = 31,
	-- Per-axis frequency multipliers, so the shake is not a straight line.
	TREMBLE_AXIS_RATIOS = Vector3.new(1, 1.31, 0.83),

	-- The tether tightens: width multiplier and transparency from the start
	-- of the hold to the snap (full strength from then on).
	TETHER_WIDTH_SCALE_START = 0.35,
	TETHER_TRANSPARENCY_START = 0.8,
	TETHER_TRANSPARENCY_FULL = 0.1,

	-- Warning highlight on the marked block, in a hungry colour, blinking
	-- faster toward the snap. Drawn through walls.
	HIGHLIGHT_NAME = "TowMark",
	HIGHLIGHT_FILL_COLOR = Color3.fromRGB(255, 40, 90),
	HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 235, 235),
	HIGHLIGHT_OUTLINE_TRANSPARENCY = 0,
	HIGHLIGHT_FILL_TRANSPARENCY_MIN = 0.2,
	HIGHLIGHT_FILL_TRANSPARENCY_MAX = 0.9,
	BLINK_HZ_START = 2,
	BLINK_HZ_END = 14,

	-- Closing ring: a round outline on a BillboardGui over the block that
	-- shrinks from RING_START_SCALE times the block to the block's size at
	-- the snap. Not AlwaysOnTop (that did not draw in this game's client view),
	-- so it is pushed toward the camera by RING_CAMERA_OFFSET_STUDS to clear
	-- the cube.
	RING_NAME = "TowRing",
	RING_START_SCALE = 2.5,
	RING_COLOR = Color3.fromRGB(255, 60, 100),
	RING_STROKE_PIXELS = 3,
	RING_CAMERA_OFFSET_STUDS = 4,
	RING_FALLBACK_BLOCK_STUDS = 4,

	-- ============================================================
	-- Client smoothing. The attributes arrive at the network rate, the
	-- screen redraws faster; each frame the drawn point closes this
	-- fraction-per-second of the gap (exponential, so it is frame-rate
	-- independent).
	-- ============================================================
	FOLLOW_RATE_PER_SEC = 14,

	-- ============================================================
	-- Tether look (LetterTowTether). Tinted with the block's own colour, as
	-- the collect stream is; these are the shape.
	-- ============================================================
	TETHER_WIDTH_AT_BLOCK = 0.9,
	TETHER_WIDTH_AT_TARGET = 2.2,
	TETHER_CURVE_STUDS = 5,
	TETHER_SEGMENTS = 14,
	TETHER_LIGHT_EMISSION = 1,
	TETHER_TRANSPARENCY = 0.35,
	TETHER_END_PART_NAME = "LetterTowTetherEnd",
	TETHER_END_ATTACHMENT_NAME = "TowEnd",
	TETHER_BLOCK_ATTACHMENT_NAME = "TowStart",
	TETHER_BEAM_NAME = "TowTether",
}

return TowConstants
