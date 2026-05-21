----------------------------------------------------------------------
-- HudConstants
----------------------------------------------------------------------
-- Central configuration for the entire HUD layout system.
-- All screen regions, sizes, and responsive scaling are defined here.
----------------------------------------------------------------------

local HudConstants = {
	REGIONS = {
		BottomLeft = {
			Position = UDim2.new(0, 20, 1, -20),
			AnchorPoint = Vector2.new(0, 1),
			Size = UDim2.new(0, 300, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 1,
		},
		BottomRight = {
			Position = UDim2.new(1, -20, 1, 0),  -- Y = 0; DASH bottom margin (DashButtonConfig.BOTTOM_MARGIN) owns the screen gap
			AnchorPoint = Vector2.new(1, 1),
			Size = UDim2.new(0, 640, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 1,
			stackVertical = true,
			stackPadding = 0,  -- gap between SpellMenu and DASH is owned by DashButtonConfig.SPELL_GAP
		},
		BottomCenter = {
			Position = UDim2.new(0.5, 0, 1, -20),
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.new(0, 400, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 1,
			stackVertical = true,
			stackHorizontalAlign = Enum.HorizontalAlignment.Center,
		},
		TopCenter = {
			Position = UDim2.new(0.5, 0, 0, 8),
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.new(0.4, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 1,
		},
		TopRight = {
			Position = UDim2.new(1, -20, 0, 20),
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.new(0, 400, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 1,
		},
		Center = {
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(1, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None,
			ZIndex = 2,
		},
	},
	-- UIScale reference height: all pixel values in HUD configs are authored at this height.
	-- _updateScale() in HudLayoutManager derives Scale = viewportY / REFERENCE_HEIGHT.
	REFERENCE_HEIGHT = 1080,
	MIN_SCALE = 0.35,
	HUD_DISPLAY_ORDER = 10,
	OVERLAY_DISPLAY_ORDER = 20,
	HEALTH_REGION = "BottomLeft",
	WEAPON_PANEL_REGION = "BottomRight",
	RETICLE_REGION = "Center",
	TOUCH_CONTROLS_REGION = "BottomRight",
	WEAPON_PANEL_TOUCH_REGION = "BottomCenter",
}

return HudConstants
