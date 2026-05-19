----------------------------------------------------------------------
-- MemorizeButtonConfig
----------------------------------------------------------------------
-- Default styling for the Memorize action button.
----------------------------------------------------------------------

local MemorizeButtonConfig = {
	WIDTH  = 140,
	HEIGHT = 34,
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
	TEXT_SIZE = 13,
	TEXT_STROKE_TRANSPARENCY = 0.5,

	LABEL_DEFAULT = "ABSORB",
}

return MemorizeButtonConfig
