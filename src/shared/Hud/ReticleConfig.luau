----------------------------------------------------------------------
-- ReticleConfig
----------------------------------------------------------------------
local ReticleConfig = {
	CONTAINER_SIZE = 50,
	LINE_LENGTH = 15,
	LINE_THICKNESS = 2,
	LINE_COLOR = Color3.fromRGB(255, 255, 255),
	LINE_STROKE_COLOR = Color3.fromRGB(0, 0, 0),
	LINE_STROKE_THICKNESS = 1,
	LINE_CORNER_RADIUS = UDim.new(1, 0),
	HITMARKER_SIZE = 50,
	HITMARKER_ROTATION = 45,
	HITMARKER_COLOR = Color3.fromRGB(255, 62, 65),
	HITMARKER_PADDING = UDim.new(0, 1),
	HITMARKER_INITIAL_SCALE = 2,
	HITMARKER_FINAL_SCALE = 1,
	HITMARKER_SCALE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	HITMARKER_FADE_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	-- Spread / shot-expansion
	SPREAD_MIN_GAP = 6,   -- px from center to line edge at rest
	SPREAD_MAX_GAP = 24,  -- px from center to line edge at max spread
	SPREAD_TWEEN_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	SPREAD_DECAY_RATE = 3.0, -- normalized units per second the spread falls
	SPREAD_PER_SHOT = 0.4,   -- normalized bump added to spread on each shot fired
}

return ReticleConfig
