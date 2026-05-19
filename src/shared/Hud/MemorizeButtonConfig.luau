----------------------------------------------------------------------
-- MemorizeButtonConfig
----------------------------------------------------------------------
-- Default styling for the Memorize action button.
----------------------------------------------------------------------

local MemorizeButtonConfig = {
	WIDTH  = 310,
	HEIGHT = 100,
	CORNER_RADIUS = 5,

	-- Active (buffer non-empty)
	ACTIVE_COLOR        = Color3.fromRGB(75, 130, 230),
	ACTIVE_TRANSPARENCY = 0.05,
	ACTIVE_TEXT_COLOR   = Color3.fromRGB(255, 255, 255),

	-- Disabled (buffer empty)
	DISABLED_COLOR        = Color3.fromRGB(50, 50, 60),
	DISABLED_TRANSPARENCY = 0.3,
	DISABLED_TEXT_COLOR   = Color3.fromRGB(110, 110, 130),

	-- Flash on success
	SUCCESS_COLOR       = Color3.fromRGB(60, 185, 85),
	FAILURE_COLOR       = Color3.fromRGB(200, 65, 65),
	FLASH_DURATION      = 0.35,

	FONT      = Enum.Font.GothamBold,
	TEXT_SIZE = 32,
	TEXT_STROKE_TRANSPARENCY = 0.5,

	LABEL_DEFAULT = "ABSORB",

	-- Valid-word effects (scale breathe + pulsing stroke)
	VALID_SCALE_MAX          = 1.04,
	VALID_SCALE_TWEEN        = TweenInfo.new(0.80, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	VALID_STROKE_NAME        = "ValidWordStroke",
	VALID_STROKE_COLOR       = Color3.fromRGB(80, 215, 105),
	VALID_STROKE_THICKNESS   = 2,
	VALID_STROKE_PULSE_TWEEN = TweenInfo.new(0.60, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
}

return MemorizeButtonConfig
