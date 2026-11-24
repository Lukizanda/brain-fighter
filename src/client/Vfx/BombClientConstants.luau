--!strict

----------------------------------------------------------------------
-- BombClientConstants
----------------------------------------------------------------------
-- The client-only look and tap-feel numbers of the scramble puzzle and its
-- seekers. The contract names (attributes, tag, remote, part names) are
-- BombConstants and are not repeated here. Read by BombVisuals (draws the
-- puzzle row, the timer, the seekers and the progress strip), BombTapController
-- (taps them) and BombClientState (the predictions they share).
----------------------------------------------------------------------

local BombClientConstants = {
	-- ============================================================
	-- Client-only instances
	-- ============================================================
	-- A Folder in workspace made by BombVisuals; one Folder per puzzle inside it
	-- holds everything the client draws for that puzzle, and one Folder per
	-- letter inside that. Never replicated.
	CLIENT_FOLDER_NAME = "ScrambleBombClient",
	-- The enlarged tap target made for each letter (client-only: in the camera
	-- row while the puzzle rests, following the seeker part once it hatches).
	-- Carries BombConstants.TILE_INDEX_ATTRIBUTE and a child ObjectValue naming
	-- the puzzle.
	PROXY_NAME = "TapProxy",
	PROXY_BOMB_VALUE_NAME = "Bomb",
	-- A cube, so a phone finger has some slack. Narrower than ROW_SPACING_STUDS,
	-- so neighbouring proxies never overlap.
	PROXY_SIZE_STUDS = 4.4,
	-- The proxy of a hatched seeker eases toward the (20 Hz-ish) replicated part
	-- position at this rate (1/s); a gap wider than SNAP_DISTANCE_STUDS jumps.
	FOLLOW_RATE_PER_SEC = 30,
	SNAP_DISTANCE_STUDS = 12,

	-- ============================================================
	-- Resting row (camera-facing, so letters never overlap or hide each other)
	-- ============================================================
	-- Distance between two neighbouring letters along the camera's flattened
	-- right vector. Wider than a glyph (GLYPH_STUDS, pulsed) and a proxy.
	ROW_SPACING_STUDS = 5.2,
	-- The row hangs this far above BombCentre.
	ROW_LIFT_STUDS = 4,
	-- A flattened camera right vector shorter than this (looking straight down)
	-- falls back to the world X axis.
	ROW_MIN_RIGHT_STUDS = 0.05,

	-- ============================================================
	-- Tap
	-- ============================================================
	-- How long a predicted tap waits before it is taken back when the server
	-- has not confirmed it (BombAccepted for a lock, the part gone for a pop). A
	-- failure reply travels one round trip; this is far longer, so a slow link
	-- does not flicker a good tap.
	PREDICTION_TIMEOUT_SEC = 1.5,
	-- How long a refused letter's glyph shakes.
	SHAKE_SEC = 0.35,
	SHAKE_STUDS = 0.35,
	SHAKE_HZ = 22,

	-- ============================================================
	-- Letter glyph (a BillboardGui on the proxy, sized in studs)
	-- ============================================================
	-- Large enough to read on a phone from 20 to 45 studs.
	GLYPH_STUDS = 4.6,
	GLYPH_CORNER_SCALE = 0.18,
	GLYPH_BORDER_PX = 5,
	GLYPH_BG_TRANSPARENCY = 0.05,
	GLYPH_TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	GLYPH_TEXT_OUTLINE = Color3.fromRGB(0, 0, 0),
	GLYPH_BORDER_COLOR = Color3.fromRGB(0, 0, 0),
	-- Out of reach: grey, still readable.
	FAR_BG_COLOR = Color3.fromRGB(105, 105, 110),
	FAR_TEXT_COLOR = Color3.fromRGB(215, 215, 220),
	-- A locked letter (resting): greyed, with its order badge.
	LOCKED_BG_COLOR = Color3.fromRGB(70, 75, 85),
	LOCKED_TEXT_COLOR = Color3.fromRGB(175, 175, 182),
	-- A refused letter's border.
	REFUSED_BORDER_COLOR = Color3.fromRGB(255, 40, 40),

	-- The round badge on a glyph's top-right corner: the order number of a locked
	-- letter, or the "!" of a hatched seeker. A fraction of the glyph's size.
	BADGE_SIZE_SCALE = 0.42,
	BADGE_X_SCALE = 0.9,
	BADGE_Y_SCALE = 0.1,
	BADGE_CORNER_SCALE = 0.5,
	BADGE_BG_COLOR = Color3.fromRGB(255, 255, 255),
	BADGE_TEXT_COLOR = Color3.fromRGB(0, 0, 0),

	-- ============================================================
	-- Hint (a small label under the glyph)
	-- ============================================================
	HINT_COLOR = Color3.fromRGB(255, 225, 40),
	HINT_TEXT = "POP",
	TAG_TEXT_COLOR = Color3.fromRGB(0, 0, 0),
	HINT_BORDER_PX = 8,
	TAG_HEIGHT_SCALE = 0.34,
	TAG_WIDTH_SCALE = 0.9,
	-- Where the tag's top edge sits, as a fraction of the glyph's height.
	TAG_TOP_SCALE = 1.05,
	-- The hinted glyph pulses between 1 and 1 + HINT_PULSE_SCALE, once per
	-- HINT_PULSE_PERIOD_SEC. Reduced effects holds it still. Small enough that a
	-- pulsed glyph still fits inside ROW_SPACING_STUDS.
	HINT_PULSE_SCALE = 0.1,
	HINT_PULSE_PERIOD_SEC = 0.7,

	-- ============================================================
	-- Hatched seeker: a fireball (user, 2026-11-25: the letter and its "!" go;
	-- what chases you should look like what the boss throws). The WARN_ values
	-- below still mark a letter waiting its turn to hatch.
	-- ============================================================
	FIREBALL_NAME = "SeekerFireball",
	FIREBALL_SIZE_STUDS = 3.2,
	FIREBALL_CORE_COLOR = Color3.fromRGB(255, 152, 48),
	-- It swells from this share of its size to full over IGNITE_SEC as it hatches.
	FIREBALL_IGNITE_SCALE = 0.35,
	FIREBALL_IGNITE_SEC = 0.6,
	-- On its final approach (straight, no tracking) it burns white-hot and
	-- bigger: the cue to step aside.
	FIREBALL_COMMITTED_COLOR = Color3.fromRGB(255, 246, 200),
	FIREBALL_COMMITTED_SCALE = 1.35,
	FIREBALL_FLAME_RATE = 28,
	FIREBALL_FLAME_LIFETIME_MIN_SEC = 0.2,
	FIREBALL_FLAME_LIFETIME_MAX_SEC = 0.4,
	FIREBALL_FLAME_SIZE_START = 3.4,
	FIREBALL_FLAME_SIZE_END = 0.5,
	FIREBALL_FLAME_SPEED_MAX = 2,
	FIREBALL_FLAME_SPREAD_DEG = 180,
	FIREBALL_FLAME_FADE_START = 0.2,
	FIREBALL_TRAIL_HALF_WIDTH_STUDS = 1.1,
	FIREBALL_TRAIL_LIFETIME_SEC = 0.35,
	FIREBALL_LIGHT_RANGE = 14,
	FIREBALL_LIGHT_BRIGHTNESS = 2,
	WARN_COLOR = Color3.fromRGB(255, 90, 30),
	WARN_BORDER_PX = 9,
	WARN_BADGE_TEXT = "!",
	WARN_PULSE_SCALE = 0.1,
	WARN_PULSE_PERIOD_SEC = 0.35,

	-- ============================================================
	-- Burst ring on the ground under each hatched seeker
	-- ============================================================
	-- Ring colours come from SporeConstants (the spore's burst ring) so both
	-- "this goes off here" markers look alike. The ring part sits this far over
	-- the probed ground.
	RING_LIFT_STUDS = 0.15,
	-- With no ground found under a seeker the ring hangs this far below it.
	RING_FALLBACK_DROP_STUDS = 3,

	-- ============================================================
	-- Timer: ground ring (fills as the timer runs out) and countdown number
	-- ============================================================
	-- About the row's half-width (four letters: 1.5 * 5.2 + 2.3 = 10 studs).
	TIMER_RING_RADIUS_STUDS = 10,
	TIMER_RING_COLOR = Color3.fromRGB(255, 170, 40),
	TIMER_RING_STROKE_STUDS = 0.5,
	TIMER_RING_OUTLINE_TRANSPARENCY = 0.1,
	TIMER_RING_FILL_TRANSPARENCY = 0.7,
	-- The countdown is a PIXEL-sized BillboardGui (a stud-sized one covered most
	-- of the screen), this far above the row's centre line.
	COUNTDOWN_ABOVE_ROW_STUDS = 3.6,
	COUNTDOWN_WIDTH_PX = 150,
	COUNTDOWN_TIME_HEIGHT_PX = 44,
	COUNTDOWN_NOTE_HEIGHT_PX = 24,
	COUNTDOWN_FORMAT = "%d",
	COUNTDOWN_COLOR = Color3.fromRGB(255, 255, 255),
	-- The last seconds turn red.
	COUNTDOWN_URGENT_SEC = 3,
	COUNTDOWN_URGENT_COLOR = Color3.fromRGB(255, 70, 60),
	-- BombHatchAt jumping earlier (a refused tap): the number flashes and a note
	-- shows the lost time.
	HATCH_JUMP_EPSILON_SEC = 0.05,
	PENALTY_FLASH_SEC = 0.8,
	PENALTY_FLASH_SCALE = 0.45,
	PENALTY_NOTE_FORMAT = "-%.1fs",
	PENALTY_COLOR = Color3.fromRGB(255, 70, 60),
	-- Resting and too far from the centre.
	GET_CLOSER_TEXT = "Get closer!",
	GET_CLOSER_COLOR = Color3.fromRGB(255, 225, 40),

	-- ============================================================
	-- Progress strip (a small ScreenGui at the top centre of the screen)
	-- ============================================================
	HUD_GUI_NAME = "BombProgressHud",
	HUD_TOP_PX = 76,
	HUD_WIDTH_PX = 260,
	HUD_SLOTS_HEIGHT_PX = 40,
	HUD_NOTE_HEIGHT_PX = 20,
	HUD_BG_COLOR = Color3.fromRGB(15, 15, 20),
	HUD_BG_TRANSPARENCY = 0.35,
	HUD_CORNER_PX = 10,
	SLOT_EMPTY = "_",
	SLOT_SEPARATOR = " ",
	SLOT_TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	-- The strip once the puzzle has hatched: the word is lost, grey, struck through.
	BROKEN_TEXT_COLOR = Color3.fromRGB(150, 150, 155),
	BROKEN_SLOTS_FORMAT = "<s>%s</s>",
	BROKEN_NOTE_TEXT = "Pop them or hide!",
	BROKEN_NOTE_COLOR = Color3.fromRGB(255, 190, 60),
	-- Higher than the round timer so a puzzle's strip is never hidden by it.
	HUD_DISPLAY_ORDER_BOOST = 1,

	LABEL_FONT = Enum.Font.GothamBlack,
	NOTE_FONT = Enum.Font.GothamBold,
}

return BombClientConstants
