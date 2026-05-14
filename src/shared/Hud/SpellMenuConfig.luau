----------------------------------------------------------------------
-- SpellMenuConfig
----------------------------------------------------------------------
-- Default styling for the three-color spell cast panel.
----------------------------------------------------------------------

local SpellMenuConfig = {
	BUTTON_WIDTH  = 90,
	BUTTON_HEIGHT = 60,
	BUTTON_GAP    = 6,
	CORNER_RADIUS = 5,

	-- Per-color panel backgrounds
	COLORS = {
		red   = { bg = Color3.fromRGB(180, 55, 55),  label = "RED"   },
		green = { bg = Color3.fromRGB(50, 155, 65),  label = "GREEN" },
		blue  = { bg = Color3.fromRGB(55, 105, 195), label = "BLUE"  },
	},
	ACTIVE_TRANSPARENCY   = 0.1,
	DISABLED_TRANSPARENCY = 0.55,

	-- Text
	LABEL_FONT  = Enum.Font.GothamBold,
	LABEL_SIZE  = 11,
	SPELL_FONT  = Enum.Font.Gotham,
	SPELL_SIZE  = 11,
	COST_FONT   = Enum.Font.RobotoMono,
	COST_SIZE   = 10,
	TEXT_COLOR  = Color3.fromRGB(255, 255, 255),
	DIM_COLOR   = Color3.fromRGB(160, 160, 175),
	TEXT_STROKE = 0.5,

	NO_SPELL_TEXT  = "—",
	COST_FORMAT    = "%d / 160",
}

return SpellMenuConfig
