----------------------------------------------------------------------
-- PortalPanelConfig
----------------------------------------------------------------------
-- Tunable constants for the portal confirm panel and the floating portal
-- sign. Pixel values are authored at HudConstants.REFERENCE_HEIGHT (1080)
-- and scaled by the HUD's UIScale at runtime.
----------------------------------------------------------------------

local PortalPanelConfig = {
	----------------------------------------------------------------------
	-- Panel
	----------------------------------------------------------------------
	SIZE                = UDim2.fromOffset(520, 260),
	-- Sits below centre so it does not cover the thing you walked up to.
	POSITION            = UDim2.fromScale(0.5, 0.66),
	ANCHOR              = Vector2.new(0.5, 0.5),
	CORNER_RADIUS       = UDim.new(0, 18),
	FILL_COLOR          = Color3.fromRGB(22, 24, 30),
	FILL_TRANSPARENCY   = 0.12,
	BORDER_COLOR        = Color3.fromRGB(255, 255, 255),
	BORDER_THICKNESS    = 3,
	BORDER_TRANSPARENCY = 0.62,
	PADDING             = UDim.new(0, 22),

	TITLE_FONT          = Enum.Font.GothamBold,
	TITLE_TEXT_SIZE     = 40,
	TITLE_COLOR         = Color3.fromRGB(255, 255, 255),
	TITLE_HEIGHT        = 48,

	STATUS_FONT         = Enum.Font.Gotham,
	STATUS_TEXT_SIZE    = 26,
	STATUS_COLOR        = Color3.fromRGB(186, 192, 206),
	STATUS_HEIGHT       = 40,

	BUTTON_HEIGHT       = 74,
	BUTTON_GAP          = 14,
	BUTTON_CORNER       = UDim.new(0, 12),
	BUTTON_FONT         = Enum.Font.GothamBold,
	BUTTON_TEXT_SIZE    = 30,

	PRIMARY_COLOR       = Color3.fromRGB(216, 128, 52),
	PRIMARY_TEXT        = Color3.fromRGB(255, 255, 255),
	CANCEL_COLOR        = Color3.fromRGB(52, 56, 66),
	CANCEL_TEXT         = Color3.fromRGB(214, 218, 228),
	CANCEL_LABEL        = "Not now",

	-- Fade in/out when the player steps on and off the pad. Short enough
	-- not to feel like a menu, long enough not to pop.
	TWEEN_SEC           = 0.16,

	----------------------------------------------------------------------
	-- Floating sign
	----------------------------------------------------------------------
	SIGN_SIZE           = UDim2.fromOffset(340, 130),
	SIGN_LABEL_SIZE     = 44,
	SIGN_COUNT_SIZE     = 28,
	SIGN_LABEL_COLOR    = Color3.fromRGB(255, 255, 255),
	SIGN_COUNT_COLOR    = Color3.fromRGB(198, 204, 218),
	-- A sign visible from across the hub but not from the next arena.
	SIGN_MAX_DISTANCE   = 220,
}

return PortalPanelConfig
