----------------------------------------------------------------------
-- TouchControlConfig
----------------------------------------------------------------------
local TouchControlConfig = {
	SHOOT_SIZE = UDim2.fromOffset(120, 120),
	SHOOT_POSITION = UDim2.new(1, -140, 1, -140),
	SHOOT_COLOR = Color3.fromRGB(255, 50, 50),
	SHOOT_TRANSPARENCY = 0.3,
	SHOOT_CORNER_RADIUS = UDim.new(0.5, 0),
	RELOAD_SIZE = UDim2.fromOffset(80, 80),
	RELOAD_POSITION = UDim2.new(1, -240, 1, -100),
	RELOAD_COLOR = Color3.fromRGB(50, 50, 255),
	RELOAD_TRANSPARENCY = 0.3,
	RELOAD_CORNER_RADIUS = UDim.new(0.5, 0),
	RELOAD_LABEL = "R",
	RELOAD_FONT = Enum.Font.GothamBold,
	RELOAD_TEXT_SIZE = 24,
	RELOAD_TEXT_COLOR = Color3.fromRGB(255, 255, 255),
}

return TouchControlConfig
