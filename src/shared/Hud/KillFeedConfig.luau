----------------------------------------------------------------------
-- KillFeedConfig
----------------------------------------------------------------------
-- Tunable constants for the top-right kill feed strip.
----------------------------------------------------------------------

local KillFeedConfig = {
	MAX_VISIBLE_ENTRIES = 5,
	ENTRY_LIFETIME = 5, -- seconds before the entry begins fading
	FADE_DURATION = 0.4,
	ENTRY_HEIGHT = 26,
	ENTRY_PADDING = 4,

	NAME_FONT = Enum.Font.GothamBold,
	WEAPON_FONT = Enum.Font.GothamSemibold,
	NAME_TEXT_SIZE = 14,
	WEAPON_TEXT_SIZE = 13,

	NEUTRAL_NAME_COLOR = Color3.fromRGB(220, 220, 220),
	LOCAL_PLAYER_OUTLINE = Color3.fromRGB(255, 255, 255),
	WEAPON_TEXT_COLOR = Color3.fromRGB(200, 200, 210),
	ENVIRONMENT_LABEL = "Environment",

	ENTRY_BG_COLOR = Color3.fromRGB(15, 15, 20),
	ENTRY_BG_TRANSPARENCY = 0.3,
	ENTRY_CORNER_RADIUS = UDim.new(0, 6),
}

return KillFeedConfig
