----------------------------------------------------------------------
-- BufferDisplayConfig
----------------------------------------------------------------------
-- Default styling for the BufferDisplay tile row.
----------------------------------------------------------------------

local BufferDisplayConfig = {
	TILE_WIDTH  = 75,
	TILE_HEIGHT = 75,
	TILE_GAP    = 4,
	CAP       = 12, -- max slots (must match WordBuffer DEFAULT_CAP)
	CORNER_RADIUS = 3,

	-- Active tile colors by WordBuffer color
	TILE_COLORS = {
		red   = Color3.fromRGB(210, 65, 65),
		green = Color3.fromRGB(60, 175, 80),
		blue  = Color3.fromRGB(65, 125, 220),
	},
	TILE_TRANSPARENCY = 0.1,

	-- Empty-slot appearance
	EMPTY_COLOR        = Color3.fromRGB(40, 40, 50),
	EMPTY_TRANSPARENCY = 0.5,

	-- Letter text
	TEXT_FONT                = Enum.Font.GothamBold,
	TEXT_SIZE                = 36,
	TEXT_COLOR               = Color3.fromRGB(255, 255, 255),
	TEXT_STROKE_TRANSPARENCY = 0.4,

	-- Empty-slot dot
	EMPTY_TEXT               = "·",
	EMPTY_TEXT_COLOR         = Color3.fromRGB(120, 120, 140),

	-- UI VFX tweens (Section 3.1)
	POP_TWEEN          = TweenInfo.new(0.10, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	POP_SCALE          = 1.20,
	PULSE_TWEEN        = TweenInfo.new(0.60, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	PULSE_STROKE_COLOR = Color3.fromRGB(255, 215, 0),
	MEMORIZE_FADE      = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	SHAKE_OFFSET_PX    = 4,
	SHAKE_CYCLES       = 3,
	SHAKE_DURATION_SEC = 0.18,
	REJECT_COLOR       = Color3.fromRGB(220, 60, 60),
	REJECT_TWEEN       = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- Valid-word glow (pulsing border stroke on filled tiles only)
	VALID_WORD_STROKE_NAME      = "ValidWordStroke",
	VALID_WORD_STROKE_COLOR     = Color3.fromRGB(255, 215, 0),
	VALID_WORD_STROKE_THICKNESS = 2,
	VALID_WORD_STROKE_PULSE     = TweenInfo.new(0.60, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),

	-- Interaction (Phase 4.7 drag-to-reorder / tap-to-swap)
	DRAG_THRESHOLD_PX         = 8,
	GHOST_TRANSPARENCY        = 0.45,
	GHOST_ZINDEX              = 20,
	SELECTION_STROKE_NAME     = "SelectionStroke",
	SELECTION_STROKE_COLOR    = Color3.fromRGB(255, 215, 0),
	SELECTION_STROKE_THICKNESS = 2,
	SNAP_FLASH_DURATION       = 0.18,
	PULSE_STROKE_NAME         = "MindFullPulseStroke",
	-- VALID_WORD_STROKE_NAME is declared above under "Valid-word glow"

	-- Tile sparkle (TextLabel drift animation, no external assets)
	SPARKLE_CHAR      = "*",
	SPARKLE_COLOR     = Color3.fromRGB(255, 240, 130),
	SPARKLE_TEXT_SIZE = 22,
	SPARKLE_RATE      = 8,    -- labels per second
	SPARKLE_DURATION  = 1.2,  -- seconds to drift + fade
	SPARKLE_DRIFT     = 45,   -- pixels upward
	SPARKLE_WOBBLE    = 20,   -- max horizontal drift pixels
	SPARKLE_ZINDEX    = 15,
}

return BufferDisplayConfig
