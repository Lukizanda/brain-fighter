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
	TEXT_SIZE                = 14,
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

	-- Tile sparkle (ViewportFrame + ParticleEmitter)
	SPARKLE_VIEWPORT_HEIGHT = 160,
	SPARKLE_CAMERA_DISTANCE = 5,
	SPARKLE_CAMERA_FOV      = 60,
	SPARKLE_PART_SIZE       = Vector3.new(8, 0.1, 0.1),
	SPARKLE_RATE            = 6,
	SPARKLE_SPEED           = NumberRange.new(0.5, 1.5),
	SPARKLE_SPREAD          = Vector2.new(70, 30),
	SPARKLE_LIFETIME        = NumberRange.new(0.8, 1.8),
	SPARKLE_COLOR           = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 180, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 225, 255)),
	}),
	SPARKLE_SIZE            = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.5, 0.08),
		NumberSequenceKeypoint.new(1, 0),
	}),
	SPARKLE_TRANSPARENCY    = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	}),
	SPARKLE_LIGHT_EMISSION  = 0.8,
	SPARKLE_ACCELERATION    = Vector3.new(0, -0.3, 0),
	SPARKLE_ROTATION        = NumberRange.new(-45, 45),
	SPARKLE_ROTATION_SPEED  = NumberRange.new(-60, 60),
	SPARKLE_ZINDEX          = 15,
}

return BufferDisplayConfig
