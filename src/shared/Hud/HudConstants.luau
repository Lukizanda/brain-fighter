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
			-- Mobile vertical column (SpellMenu top, DASH below, above native jump).
			-- The -260 Y offset lifts the column off the screen edge to clear the
			-- native Roblox jump button; stackPadding is the SpellMenu↔DASH gap.
			-- Both are authored at REFERENCE_HEIGHT and scaled by the HUD UIScale.
			Position = UDim2.new(1, -20, 1, -260),
			AnchorPoint = Vector2.new(1, 1),
			Size = UDim2.new(0, 640, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 1,
			stackVertical = true,
			stackPadding = 36,
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
			-- Two occupants with different lifetimes: the kill feed (grows
			-- downward as entries arrive) and the buff tray. Without a stack
			-- they both sat at the region's top-right corner and drew on top
			-- of each other. KillFeedGui leaves LayoutOrder at 0 so the feed
			-- keeps the position it has always had; the tray declares
			-- BuffIconConfig.LAYOUT_ORDER and sits underneath it.
			Position = UDim2.new(1, -20, 0, 20),
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.new(0, 400, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 1,
			stackVertical = true,
			stackPadding = 8,
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
}

return HudConstants
