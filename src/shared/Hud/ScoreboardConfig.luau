----------------------------------------------------------------------
-- ScoreboardConfig
----------------------------------------------------------------------
-- Tunable constants for the Tab-to-open scoreboard.
----------------------------------------------------------------------

local ScoreboardConfig = {
	TOGGLE_KEY = Enum.KeyCode.Y,
	HEADER_HEIGHT = 32,
	ROW_HEIGHT = 28,
	COLUMN_WIDTHS = { 0.35, 0.15, 0.15, 0.15, 0.20 }, -- Name, Kills, Deaths, Assists, K/D
	HEADERS = { "Player", "Kills", "Deaths", "Assists", "K/D" },

	DIMMER_COLOR = Color3.fromRGB(0, 0, 0),
	DIMMER_TRANSPARENCY = 0.5,

	PANEL_SIZE = UDim2.new(0, 500, 0, 400),
	PANEL_COLOR = Color3.fromRGB(25, 25, 30),
	PANEL_TRANSPARENCY = 0.1,
	PANEL_CORNER_RADIUS = UDim.new(0, 10),

	TITLE_TEXT = "SCOREBOARD",
	TITLE_COLOR = Color3.fromRGB(0, 162, 255),
	TITLE_FONT = Enum.Font.GothamBold,
	TITLE_TEXT_SIZE = 18,

	HEADER_BG_COLOR = Color3.fromRGB(40, 40, 48),
	HEADER_BG_TRANSPARENCY = 0.3,
	HEADER_CORNER_RADIUS = UDim.new(0, 4),
	HEADER_TEXT_COLOR = Color3.fromRGB(180, 180, 190),
	HEADER_TEXT_SIZE = 12,
	HEADER_FONT = Enum.Font.GothamBold,

	ROW_LOCAL_COLOR = Color3.fromRGB(0, 80, 140),
	ROW_LOCAL_TRANSPARENCY = 0.4,
	ROW_OTHER_COLOR = Color3.fromRGB(35, 35, 42),
	ROW_OTHER_TRANSPARENCY = 0.3,
	ROW_CORNER_RADIUS = UDim.new(0, 4),
	ROW_TEXT_SIZE = 13,
	ROW_LOCAL_TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	ROW_OTHER_TEXT_COLOR = Color3.fromRGB(220, 220, 225),
	ROW_NAME_FONT = Enum.Font.GothamBold,
	ROW_VALUE_FONT = Enum.Font.Gotham,
	ROW_NAME_PADDING_LEFT = UDim.new(0, 8),
}

return ScoreboardConfig
