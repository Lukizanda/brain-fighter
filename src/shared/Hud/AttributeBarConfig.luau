----------------------------------------------------------------------
-- AttributeBarConfig
----------------------------------------------------------------------
-- Default styling for an AttributeBar. Per-bar config extends this
-- via table merge so individual bars can override color/size.
----------------------------------------------------------------------

local AttributeBarConfig = {
	-- Geometry (pixels)
	BAR_WIDTH = 360,
	BAR_HEIGHT = 36,
	BAR_SPACING = 10, -- vertical gap between stacked bars
	CORNER_RADIUS = 5,

	-- Background + border
	BACKGROUND_COLOR = Color3.fromRGB(22, 22, 26),
	BACKGROUND_TRANSPARENCY = 0.15,

	-- Delayed "damage" bar that lags behind the live value for a moment
	-- (visual cue: "you just lost X"). Fade controlled by DAMAGE_LAG_SECONDS.
	DAMAGE_BAR_COLOR = Color3.fromRGB(200, 50, 50),
	DAMAGE_LAG_SECONDS = 0.3,

	-- Label (attribute name). The strip is the row above the track that the
	-- label sits in; the container is BAR_HEIGHT + TEXT_STRIP_HEIGHT tall
	-- when a label is shown and BAR_HEIGHT tall when it is not.
	LABEL_FONT = Enum.Font.GothamBold,
	LABEL_SIZE = 12,
	LABEL_COLOR = Color3.fromRGB(215, 215, 225),
	LABEL_STROKE_TRANSPARENCY = 0.6,
	TEXT_STRIP_HEIGHT = 16,
	LABEL_INSET = 2, -- left offset, and the gap above the track
	LABEL_WIDTH_FRACTION = 0.5,
	LABEL_HEIGHT = 14,

	-- Numeric readout (current/max)
	TEXT_FONT = Enum.Font.RobotoMono,
	TEXT_SIZE = 11,
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	TEXT_STROKE_TRANSPARENCY = 0.4,
	NUMERIC_RIGHT_INSET = 6,
	NUMERIC_WIDTH_FRACTION = 0.5,
	NUMERIC_FORMAT = "%d",
	NUMERIC_PLACEHOLDER = "0",

	-- Fill tween
	FILL_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- Low-value flash (optional): pulse the fill when value crosses these thresholds
	LOW_THRESHOLD = 0.25, -- fraction below which the color shifts to critical
	MID_THRESHOLD = 0.5, -- fraction below which the color shifts to warning

	-- UI VFX tweens (Section 3.2)
	GAIN_SWEEP_TWEEN     = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	GAIN_SWEEP_FADE      = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	GAIN_SWEEP_DELTA_MIN = 8,
	-- The sweep starts as a thin bright sliver at the left edge of the
	-- track and grows to the bar's current fill fraction.
	GAIN_SWEEP_START_WIDTH   = 2,
	GAIN_SWEEP_COLOR         = Color3.fromRGB(255, 255, 255),
	GAIN_SWEEP_TRANSPARENCY  = 0.5,
	DRAIN_RIPPLE_TWEEN   = TweenInfo.new(0.30, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
	DRAIN_RIPPLE_COUNT   = 3,
	DRAIN_RIPPLE_STAGGER = 0.08,
	DRAIN_DELTA_MIN      = 10,
	-- Each ripple is a dot at the fill edge that expands and fades.
	-- CORNER_SCALE 0.5 is what makes the square frame read as a circle.
	DRAIN_RIPPLE_START_SIZE   = 8,
	DRAIN_RIPPLE_END_SIZE     = 24,
	DRAIN_RIPPLE_COLOR        = Color3.fromRGB(255, 255, 255),
	DRAIN_RIPPLE_TRANSPARENCY = 0.3,
	DRAIN_RIPPLE_CORNER_SCALE = 0.5,
	CAP_GLOW_TWEEN       = TweenInfo.new(0.80, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	CAP_STROKE_MIN       = 1,
	CAP_STROKE_MAX       = 3,
}

return AttributeBarConfig
