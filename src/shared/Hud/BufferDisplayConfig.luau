----------------------------------------------------------------------
-- BufferDisplayConfig
----------------------------------------------------------------------
-- Default styling for the BufferDisplay tile row.
----------------------------------------------------------------------

local BufferDisplayConfig = {
	TILE_SIZE = 28,
	TILE_GAP  = 4,
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
}

return BufferDisplayConfig
