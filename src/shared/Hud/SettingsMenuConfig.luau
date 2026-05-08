----------------------------------------------------------------------
-- SettingsMenuConfig
----------------------------------------------------------------------
-- All configurable values for the Settings Menu UI.
----------------------------------------------------------------------

local SettingsMenuConfig = {
	-- Panel
	PANEL_WIDTH = 420,
	PANEL_HEIGHT = 460,
	PANEL_BACKGROUND_COLOR = Color3.fromRGB(20, 20, 25),
	PANEL_BACKGROUND_TRANSPARENCY = 0.1,
	PANEL_CORNER_RADIUS = UDim.new(0, 10),
	PANEL_PADDING = UDim.new(0, 16),

	-- Dimmer overlay behind the panel
	DIMMER_COLOR = Color3.fromRGB(0, 0, 0),
	DIMMER_TRANSPARENCY = 0.5,

	-- Title
	TITLE_FONT = Enum.Font.GothamBold,
	TITLE_TEXT_SIZE = 22,
	TITLE_TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	TITLE_TEXT = "SETTINGS",
	TITLE_HEIGHT = 36,

	-- Close button
	CLOSE_BUTTON_SIZE = 28,
	CLOSE_BUTTON_FONT = Enum.Font.GothamBold,
	CLOSE_BUTTON_TEXT_SIZE = 18,
	CLOSE_BUTTON_TEXT_COLOR = Color3.fromRGB(180, 180, 190),
	CLOSE_BUTTON_HOVER_COLOR = Color3.fromRGB(255, 80, 80),
	CLOSE_BUTTON_BACKGROUND_TRANSPARENCY = 1,

	-- Row layout
	ROW_HEIGHT = 44,
	ROW_SPACING = UDim.new(0, 6),
	LABEL_FONT = Enum.Font.GothamBold,
	LABEL_TEXT_SIZE = 14,
	LABEL_TEXT_COLOR = Color3.fromRGB(255, 255, 255),

	-- Slider
	SLIDER_WIDTH = 180,
	SLIDER_HEIGHT = 6,
	SLIDER_TRACK_COLOR = Color3.fromRGB(60, 60, 70),
	SLIDER_FILL_COLOR = Color3.fromRGB(0, 162, 255),
	SLIDER_KNOB_SIZE = 16,
	SLIDER_KNOB_COLOR = Color3.fromRGB(255, 255, 255),
	SLIDER_CORNER_RADIUS = UDim.new(1, 0),

	-- Value text next to sliders
	VALUE_FONT = Enum.Font.RobotoMono,
	VALUE_TEXT_SIZE = 14,
	VALUE_TEXT_COLOR = Color3.fromRGB(180, 180, 190),
	VALUE_WIDTH = 44,

	-- Toggle
	TOGGLE_WIDTH = 44,
	TOGGLE_HEIGHT = 24,
	TOGGLE_ON_COLOR = Color3.fromRGB(0, 162, 255),
	TOGGLE_OFF_COLOR = Color3.fromRGB(60, 60, 70),
	TOGGLE_KNOB_COLOR = Color3.fromRGB(255, 255, 255),
	TOGGLE_KNOB_SIZE = 18,
	TOGGLE_CORNER_RADIUS = UDim.new(1, 0),
	TOGGLE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- Color picker preset buttons
	COLOR_BUTTON_SIZE = 26,
	COLOR_BUTTON_SPACING = UDim.new(0, 6),
	COLOR_BUTTON_CORNER_RADIUS = UDim.new(1, 0),
	COLOR_BUTTON_STROKE_COLOR = Color3.fromRGB(255, 255, 255),
	COLOR_BUTTON_STROKE_THICKNESS = 2,
	COLOR_PRESETS = {
		{ name = "White", color = Color3.fromRGB(255, 255, 255) },
		{ name = "Red", color = Color3.fromRGB(255, 80, 80) },
		{ name = "Green", color = Color3.fromRGB(80, 255, 80) },
		{ name = "Cyan", color = Color3.fromRGB(80, 255, 255) },
		{ name = "Yellow", color = Color3.fromRGB(255, 255, 80) },
	},

	-- ScreenGui
	DISPLAY_ORDER = 35,

	-- Animation
	OPEN_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	CLOSE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),

	-- Setting defaults
	DEFAULT_MOUSE_SENSITIVITY = 0.003,
	MIN_MOUSE_SENSITIVITY = 0.0001,
	MAX_MOUSE_SENSITIVITY = 0.005,
	-- Display as user-friendly 0.1–5.0 range, mapped internally
	SENSITIVITY_DISPLAY_MIN = 0.1,
	SENSITIVITY_DISPLAY_MAX = 5.0,
	SENSITIVITY_DISPLAY_DEFAULT = 1.0,

	DEFAULT_FIELD_OF_VIEW = 70,
	MIN_FIELD_OF_VIEW = 50,
	MAX_FIELD_OF_VIEW = 120,

	DEFAULT_CROSSHAIR_COLOR = Color3.fromRGB(255, 255, 255),
	DEFAULT_AIM_ASSIST = false,

	-- Keybind to toggle the menu
	TOGGLE_KEY = Enum.KeyCode.P, -- P for Preferences (Escape opens Roblox system menu)
}

return SettingsMenuConfig
