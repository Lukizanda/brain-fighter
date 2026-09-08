----------------------------------------------------------------------
-- BuffIconConfig
----------------------------------------------------------------------
-- Default styling for individual buff/debuff icons in the BuffTray.
-- Per-buff overrides (color tint, icon asset) come from each Buff
-- entry when it's added, not from this file.
----------------------------------------------------------------------

local BuffIconConfig = {
	-- Position in the TopRight stack: below the kill feed, which stays at
	-- the default 0. See HudConstants.REGIONS.TopRight.
	LAYOUT_ORDER = 1,

	ICON_SIZE = 36, -- px square
	ICON_SPACING = 4, -- horizontal gap between icons
	CORNER_RADIUS = 4,
	-- The buff art is inset on every side so the background frame reads as
	-- a border around it; the image is ICON_SIZE - 2 * ICON_IMAGE_INSET.
	ICON_IMAGE_INSET = 2,

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

	-- Stack count text, tucked into the bottom-right corner above the
	-- countdown bar.
	STACK_FONT = Enum.Font.GothamBold,
	STACK_TEXT_SIZE = 12,
	STACK_TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	STACK_STROKE_TRANSPARENCY = 0.2,
	STACK_INSET = 2,
	STACK_WIDTH = 16,
	STACK_HEIGHT = 14,
	STACK_MIN_TO_SHOW = 1, -- a lone stack is implied by the icon itself
}

return BuffIconConfig
