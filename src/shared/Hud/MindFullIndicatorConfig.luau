----------------------------------------------------------------------
-- MindFullIndicatorConfig
----------------------------------------------------------------------
-- Default styling for the MindFull warning overlay.
----------------------------------------------------------------------

local MindFullIndicatorConfig = {
	WIDTH = 260,
	HEIGHT = 30,
	CORNER_RADIUS = 4,

	BACKGROUND_COLOR = Color3.fromRGB(220, 60, 60),
	BACKGROUND_TRANSPARENCY = 0.15,

	TEXT = "MIND FULL — can't shoot",
	FONT = Enum.Font.GothamBold,
	TEXT_SIZE = 13,
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	TEXT_STROKE_TRANSPARENCY = 0.5,

	TWEEN_IN  = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	TWEEN_OUT = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
}

return MindFullIndicatorConfig
