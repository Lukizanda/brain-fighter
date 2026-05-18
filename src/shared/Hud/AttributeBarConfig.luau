----------------------------------------------------------------------
-- AttributeBarConfig
----------------------------------------------------------------------
-- Default styling for an AttributeBar. Per-bar config extends this
-- via table merge so individual bars can override color/size.
----------------------------------------------------------------------

local AttributeBarConfig = {
	-- Geometry (pixels)
	BAR_WIDTH = 220,
	BAR_HEIGHT = 12,
	BAR_SPACING = 6, -- vertical gap between stacked bars
	CORNER_RADIUS = 3,

	-- Background + border
	BACKGROUND_COLOR = Color3.fromRGB(22, 22, 26),
	BACKGROUND_TRANSPARENCY = 0.1,

	-- Delayed "damage" bar that lags behind the live value for a moment
	-- (visual cue: "you just lost X"). Fade controlled by DAMAGE_LAG_SECONDS.
	DAMAGE_BAR_COLOR = Color3.fromRGB(200, 50, 50),
	DAMAGE_LAG_SECONDS = 0.3,

	-- Label (attribute name)
	LABEL_FONT = Enum.Font.GothamBold,
	LABEL_SIZE = 11,
	LABEL_COLOR = Color3.fromRGB(215, 215, 225),
	LABEL_STROKE_TRANSPARENCY = 0.6,

	-- Numeric readout (current/max)
	TEXT_FONT = Enum.Font.RobotoMono,
	TEXT_SIZE = 11,
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	TEXT_STROKE_TRANSPARENCY = 0.4,

	-- Fill tween
	FILL_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- Low-value flash (optional): pulse the fill when value crosses these thresholds
	LOW_THRESHOLD = 0.25, -- fraction below which the color shifts to critical
	MID_THRESHOLD = 0.5, -- fraction below which the color shifts to warning

	-- UI VFX tweens (Section 3.2)
	GAIN_SWEEP_TWEEN     = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	GAIN_SWEEP_FADE      = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	GAIN_SWEEP_DELTA_MIN = 8,
	DRAIN_RIPPLE_TWEEN   = TweenInfo.new(0.30, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
	DRAIN_RIPPLE_COUNT   = 3,
	DRAIN_RIPPLE_STAGGER = 0.08,
	DRAIN_DELTA_MIN      = 10,
	CAP_GLOW_TWEEN       = TweenInfo.new(0.80, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	CAP_STROKE_MIN       = 1,
	CAP_STROKE_MAX       = 3,
}

return AttributeBarConfig
