----------------------------------------------------------------------
-- BuffIconConfig
----------------------------------------------------------------------
-- Default styling for individual buff/debuff icons in the BuffTray.
-- Per-buff overrides (color tint, icon asset) come from each Buff
-- entry when it's added, not from this file.
----------------------------------------------------------------------

local BuffIconConfig = {
	ICON_SIZE = 36, -- px square
	ICON_SPACING = 4, -- horizontal gap between icons
	CORNER_RADIUS = 4,

	-- Background frame behind each icon (shows through when icon is
	-- semi-transparent, gives the tray a cohesive look)
	BACKGROUND_COLOR = Color3.fromRGB(22, 22, 26),
	BACKGROUND_TRANSPARENCY = 0.1,

	-- Border stroke color by buff polarity
	BUFF_BORDER_COLOR = Color3.fromRGB(100, 200, 100), -- positive
	DEBUFF_BORDER_COLOR = Color3.fromRGB(220, 80, 80), -- negative
	NEUTRAL_BORDER_COLOR = Color3.fromRGB(180, 180, 180),
	BORDER_THICKNESS = 1.5,

	-- Countdown arc (drawn with UIGradient + rotation, or as a simple
	-- "remaining fraction" width bar for now)
	COUNTDOWN_BAR_HEIGHT = 3,
	COUNTDOWN_BAR_COLOR = Color3.fromRGB(255, 255, 255),
	COUNTDOWN_BAR_TRANSPARENCY = 0.2,

	-- Stack count text
	STACK_FONT = Enum.Font.GothamBold,
	STACK_TEXT_SIZE = 12,
	STACK_TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	STACK_STROKE_TRANSPARENCY = 0.2,
}

return BuffIconConfig
