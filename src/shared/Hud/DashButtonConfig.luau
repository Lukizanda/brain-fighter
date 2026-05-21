----------------------------------------------------------------------
-- DashButtonConfig
----------------------------------------------------------------------
-- Tunable constants for the mobile dash button. All pixel values are
-- authored at HudConstants.REFERENCE_HEIGHT (1080) and scaled by the
-- HUD's UIScale at runtime.
----------------------------------------------------------------------

local DashButtonConfig = {
	SIZE                = UDim2.fromOffset(180, 180),
	CORNER_RADIUS       = UDim.new(0.5, 0),
	FILL_COLOR          = Color3.fromRGB(30, 30, 35),
	FILL_TRANSPARENCY   = 0.3,
	BORDER_COLOR        = Color3.fromRGB(255, 255, 255),
	BORDER_THICKNESS    = 7,
	BORDER_TRANSPARENCY = 0.7,
	-- How far the ring sits inside the button edge (px). The fill covers the
	-- gap between the ring and the button edge, giving the inset overlap look.
	BORDER_INSET        = 12,
	LABEL_TEXT          = "DASH",
	LABEL_COLOR         = Color3.fromRGB(255, 255, 255),
	LABEL_FONT          = Enum.Font.GothamBold,
	LABEL_TEXT_SIZE     = 24,
	-- BottomRight column slot. SpellMenu = 1 (top), DASH = 2 (below it, above native jump).
	LAYOUT_ORDER        = 2,
	-- Gap between the bottom of the SpellMenu and the top of the DASH button.
	SPELL_GAP           = 36,
	-- Gap between the bottom of the DASH button and the screen edge.
	BOTTOM_MARGIN       = 260,
}

return DashButtonConfig
