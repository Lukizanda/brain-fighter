----------------------------------------------------------------------
-- BossHudConfig
----------------------------------------------------------------------
-- Tunable constants for the boss health bar + phase indicator.
----------------------------------------------------------------------

local BossHudConfig = {
	PHASE_LABELS = { "I", "II", "III", "IV", "V" },
	BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	CONTAINER_SIZE = UDim2.new(0.4, 0, 0, 68),
	CONTAINER_POSITION = UDim2.new(0.5, 0, 0, 8),
	CONTAINER_COLOR = Color3.fromRGB(20, 0, 0),
	CONTAINER_TRANSPARENCY = 0.35,
	CORNER_RADIUS = UDim.new(0, 6),

	TOP_ROW_SIZE = UDim2.new(1, -16, 0, 26),
	TOP_ROW_POSITION = UDim2.new(0, 8, 0, 6),

	NAME_TEXT = "BOSS",
	NAME_COLOR = Color3.fromRGB(255, 220, 220),
	NAME_FONT = Enum.Font.GothamBold,

	PHASE_SIZE = UDim2.new(0, 55, 1, 0),
	PHASE_POSITION = UDim2.new(1, -55, 0, 0),
	PHASE_COLOR = Color3.fromRGB(255, 180, 60),
	PHASE_FONT = Enum.Font.GothamBold,
	PHASE_TEXT_DEFAULT = "Phase I",

	BAR_BG_SIZE = UDim2.new(1, -16, 0, 18),
	BAR_BG_POSITION = UDim2.new(0, 8, 0, 38),
	BAR_BG_COLOR = Color3.fromRGB(60, 10, 10),
	BAR_CORNER_RADIUS = UDim.new(0, 4),
	BAR_FILL_COLOR = Color3.fromRGB(210, 30, 30),

	-- Debug-only phase label toggle, off by default (see DevDebugHotkeys).
	PHASE_DEBUG_KEY = Enum.KeyCode.Semicolon,
}

return BossHudConfig
