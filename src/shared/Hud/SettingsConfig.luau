----------------------------------------------------------------------
-- SettingsConfig
----------------------------------------------------------------------
-- Tunable constants for the settings panel and the gear button that
-- opens it. Pixel values are authored at HudConstants.REFERENCE_HEIGHT
-- (1080) and scaled by the HUD's UIScale at runtime. Visual family
-- matches PortalPanelConfig — the two panels sit in the same hub.
----------------------------------------------------------------------

local SettingsConfig = {
	----------------------------------------------------------------------
	-- Gear button (lives in the TopRight region stack, hub only)
	----------------------------------------------------------------------
	GEAR_SIZE           = UDim2.fromOffset(56, 56),
	GEAR_CORNER         = UDim.new(0, 12),
	GEAR_FILL_COLOR     = Color3.fromRGB(22, 24, 30),
	GEAR_FILL_TRANSPARENCY = 0.25,
	GEAR_TEXT           = "⚙",
	GEAR_FONT           = Enum.Font.GothamBold,
	GEAR_TEXT_SIZE      = 34,
	GEAR_TEXT_COLOR     = Color3.fromRGB(230, 234, 244),
	-- Ahead of the kill feed (0) and the buff tray (BuffIconConfig.LAYOUT_ORDER)
	-- so it sits at the top of the stack; in the arena it is gated off anyway.
	GEAR_LAYOUT_ORDER   = -1,

	----------------------------------------------------------------------
	-- Panel
	----------------------------------------------------------------------
	SIZE                = UDim2.fromOffset(620, 440),
	POSITION            = UDim2.fromScale(0.5, 0.5),
	ANCHOR              = Vector2.new(0.5, 0.5),
	CORNER_RADIUS       = UDim.new(0, 18),
	FILL_COLOR          = Color3.fromRGB(22, 24, 30),
	FILL_TRANSPARENCY   = 0.08,
	BORDER_COLOR        = Color3.fromRGB(255, 255, 255),
	BORDER_THICKNESS    = 3,
	BORDER_TRANSPARENCY = 0.62,
	PADDING             = UDim.new(0, 24),
	ROW_GAP             = 18,

	TITLE_TEXT          = "Settings",
	TITLE_FONT          = Enum.Font.GothamBold,
	TITLE_TEXT_SIZE     = 40,
	TITLE_COLOR         = Color3.fromRGB(255, 255, 255),
	TITLE_HEIGHT        = 48,

	-- Each row: a label on the left, a control on the right.
	ROW_HEIGHT          = 64,
	LABEL_FONT          = Enum.Font.Gotham,
	LABEL_TEXT_SIZE     = 26,
	LABEL_COLOR         = Color3.fromRGB(214, 218, 228),
	LABEL_WIDTH_SCALE   = 0.42,

	LABELS = {
		SfxVolume  = "Sound effects",
		ReducedVfx = "Reduced effects",
		Palette    = "Letter colours",
	},

	-- Slider (SFX volume)
	SLIDER_TRACK_HEIGHT     = 14,
	SLIDER_TRACK_COLOR      = Color3.fromRGB(52, 56, 66),
	SLIDER_FILL_COLOR       = Color3.fromRGB(216, 128, 52),
	SLIDER_KNOB_SIZE        = 30,
	SLIDER_KNOB_COLOR       = Color3.fromRGB(255, 255, 255),
	SLIDER_VALUE_WIDTH      = 64,
	SLIDER_VALUE_FONT       = Enum.Font.GothamBold,
	SLIDER_VALUE_TEXT_SIZE  = 24,
	SLIDER_VALUE_COLOR      = Color3.fromRGB(255, 255, 255),
	SLIDER_VALUE_FORMAT     = "%d",

	-- Toggle (Reduced effects) and segmented choice (palette) share the
	-- option-button look.
	OPTION_HEIGHT       = 48,
	OPTION_CORNER       = UDim.new(0, 12),
	OPTION_FONT         = Enum.Font.GothamBold,
	OPTION_TEXT_SIZE    = 24,
	OPTION_GAP          = 10,
	OPTION_ON_COLOR     = Color3.fromRGB(216, 128, 52),
	OPTION_ON_TEXT      = Color3.fromRGB(255, 255, 255),
	OPTION_OFF_COLOR    = Color3.fromRGB(52, 56, 66),
	OPTION_OFF_TEXT     = Color3.fromRGB(214, 218, 228),
	TOGGLE_ON_LABEL     = "On",
	TOGGLE_OFF_LABEL    = "Off",
	TOGGLE_WIDTH        = 120,
	-- Palette choices in display order; `id` is a Colors.Palette name.
	PALETTE_OPTIONS = {
		{ id = "default",       label = "Default" },
		{ id = "high_contrast", label = "High contrast" },
	},
	-- Swatch strip under the palette buttons: the three spell colours and
	-- wild, drawn from the palette so the choice is visible before it is
	-- made anywhere else.
	SWATCH_SIZE         = 26,
	SWATCH_GAP          = 8,
	SWATCH_CORNER       = UDim.new(0, 6),

	CLOSE_LABEL         = "Done",
	CLOSE_HEIGHT        = 60,
	CLOSE_COLOR         = Color3.fromRGB(52, 56, 66),
	CLOSE_TEXT          = Color3.fromRGB(214, 218, 228),

	-- Top-to-bottom order inside the panel's UIListLayout.
	ORDER = {
		TITLE      = 1,
		SFX        = 2,
		REDUCED    = 3,
		PALETTE    = 4,
		SWATCHES   = 5,
		CLOSE      = 6,
	},
}

return SettingsConfig
