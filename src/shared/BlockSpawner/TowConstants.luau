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
