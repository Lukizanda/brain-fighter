----------------------------------------------------------------------
-- GameStateConfig
----------------------------------------------------------------------
-- Tunable constants for the end-of-round results overlay.
----------------------------------------------------------------------

local GameStateConfig = {
	OVERLAY_COLOR = Color3.fromRGB(0, 0, 0),
	OVERLAY_SHOWN_TRANSPARENCY = 0.5,
	SHOW_HIDE_TWEEN_SEC = 0.3,

	CENTER_SIZE = UDim2.new(0, 450, 0, 350),
	CENTER_COLOR = Color3.fromRGB(20, 20, 25),
	CENTER_TRANSPARENCY = 0.1,
	CENTER_CORNER_RADIUS = UDim.new(0, 12),
	CENTER_PADDING = UDim.new(0, 20),
	CENTER_LIST_PADDING = UDim.new(0, 8),

	ROUND_OVER_TEXT = "ROUND OVER",
	ROUND_OVER_COLOR = Color3.fromRGB(255, 200, 50),
	ROUND_OVER_TEXT_SIZE = 24,

	WINNER_COLOR = Color3.fromRGB(100, 255, 100),
	WINNER_TEXT_SIZE = 20,

	TOP_PLAYERS_HEIGHT = 180,
	TOP_PLAYERS_MAX_SHOWN = 5,
	TOP_PLAYERS_ROW_HEIGHT = 28,
	TOP_PLAYERS_LIST_PADDING = UDim.new(0, 4),
	ROW_LOCAL_COLOR = Color3.fromRGB(0, 80, 140),
	ROW_OTHER_COLOR = Color3.fromRGB(40, 40, 48),
	ROW_TRANSPARENCY = 0.4,
	ROW_CORNER_RADIUS = UDim.new(0, 4),
	RANK_FIRST_COLOR = Color3.fromRGB(255, 215, 0),
	RANK_OTHER_COLOR = Color3.fromRGB(180, 180, 190),
	RANK_TEXT_SIZE = 13,
	NAME_LOCAL_COLOR = Color3.fromRGB(255, 255, 255),
	NAME_OTHER_COLOR = Color3.fromRGB(220, 220, 225),
	NAME_TEXT_SIZE = 13,
	STATS_TEXT_COLOR = Color3.fromRGB(180, 180, 190),
	STATS_TEXT_SIZE = 11,

	NEXT_ROUND_TEXT_COLOR = Color3.fromRGB(180, 180, 190),
	NEXT_ROUND_TEXT_SIZE = 14,

	NO_WINNER_TEXT = "No winner",
}

return GameStateConfig
