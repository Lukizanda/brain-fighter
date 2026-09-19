----------------------------------------------------------------------
-- RoundTimerConfig
----------------------------------------------------------------------
-- Tunable constants for the round state / timer strip at the top of the
-- screen. Pixel values are authored at HudConstants.REFERENCE_HEIGHT
-- (1080) and scaled by the HUD's UIScale at runtime.
----------------------------------------------------------------------

local RoundTimerConfig = {
	CONTAINER_SIZE = UDim2.new(0, 300, 0, 50),
	CONTAINER_POSITION = UDim2.new(0.5, 0, 0, 8),
	CONTAINER_ANCHOR = Vector2.new(0.5, 0),
	CONTAINER_COLOR = Color3.fromRGB(20, 20, 25),
	CONTAINER_TRANSPARENCY = 0.3,
	CONTAINER_CORNER_RADIUS = UDim.new(0, 8),

	TIMER_SIZE = UDim2.new(1, 0, 0, 30),
	TIMER_POSITION = UDim2.new(0, 0, 0, 4),
	TIMER_FONT = Enum.Font.GothamBold,
	TIMER_TEXT_SIZE = 20,

	SUB_SIZE = UDim2.new(1, 0, 0, 16),
	SUB_POSITION = UDim2.new(0, 0, 0, 32),
	SUB_FONT = Enum.Font.Gotham,
	SUB_TEXT_SIZE = 12,
	SUB_COLOR = Color3.fromRGB(180, 180, 190),

	WAITING_TEXT = "Waiting for players...",
	WAITING_COLOR = Color3.fromRGB(200, 200, 100),

	COUNTDOWN_FORMAT = "Starting in %d...",
	COUNTDOWN_SUB_TEXT = "Get ready!",
	COUNTDOWN_COLOR = Color3.fromRGB(255, 200, 50),

	-- Active: white until the clock is short, amber, then red.
	ACTIVE_COLOR = Color3.fromRGB(255, 255, 255),
	WARN_AT_SEC = 60,
	WARN_COLOR = Color3.fromRGB(255, 200, 50),
	DANGER_AT_SEC = 30,
	DANGER_COLOR = Color3.fromRGB(255, 80, 80),

	POST_ROUND_COLOR = Color3.fromRGB(100, 255, 100),
	NEXT_ROUND_FORMAT = "Next round in %d...",
}

return RoundTimerConfig
