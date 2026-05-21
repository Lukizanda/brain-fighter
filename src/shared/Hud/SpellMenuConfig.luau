----------------------------------------------------------------------
-- SpellMenuConfig
----------------------------------------------------------------------
-- Default styling for the three-color spell cast panel.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)

local SpellMenuConfig = {
	BUTTON_WIDTH  = 200,
	BUTTON_HEIGHT = 200,
	BUTTON_GAP    = 12,
	CORNER_RADIUS = 10,

	-- Per-color panel backgrounds
	COLORS = {
		red   = { bg = Color3.fromRGB(180, 55, 55),  label = "RED"   },
		green = { bg = Color3.fromRGB(50, 155, 65),  label = "GREEN" },
		blue  = { bg = Color3.fromRGB(55, 105, 195), label = "BLUE"  },
	},

	-- Fill: dim base layer (always-visible "empty" bg) and animated fill bar
	FILL_BASE_TRANSPARENCY = 0.72,
	FILL_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	FILL_MAX   = EnergyReservoirs.CAP_PER_COLOR,

	-- Text
	LABEL_FONT  = Enum.Font.GothamBold,
	LABEL_SIZE  = 26,
	SPELL_FONT  = Enum.Font.Gotham,
	SPELL_SIZE  = 24,
	TEXT_COLOR  = Color3.fromRGB(255, 255, 255),
	DIM_COLOR   = Color3.fromRGB(160, 160, 175),
	TEXT_STROKE = 0.5,

	NO_SPELL_TEXT = "—",

	-- Numeric popup on tap ("128 / 160")
	POPUP_DURATION  = 1.8,
	POPUP_FADE_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	POPUP_FONT = Enum.Font.GothamBold,
	POPUP_SIZE = 26,

	-- UI VFX tweens
	AFFORD_BOUNCE_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	AFFORD_BOUNCE_SCALE = 1.08,
	FIRED_FLASH_TWEEN   = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	FIRED_DIM_TWEEN     = TweenInfo.new(0.40, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

return SpellMenuConfig
