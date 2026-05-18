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

	-- UI VFX tweens (Section 3.3)
	AFFORD_BOUNCE_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	AFFORD_BOUNCE_SCALE = 1.08,
	FIRED_FLASH_TWEEN   = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	FIRED_DIM_COLOR     = Color3.fromRGB(80, 80, 90),
	FIRED_DIM_TWEEN     = TweenInfo.new(0.40, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

return SpellMenuConfig
