----------------------------------------------------------------------
-- DeathScreenConfig
----------------------------------------------------------------------
-- Tunable constants for the death overlay + respawn countdown.
----------------------------------------------------------------------

local DeathScreenConfig = {
	OVERLAY_COLOR = Color3.fromRGB(0, 0, 0),
	OVERLAY_TRANSPARENCY = 0.4,
	COUNTDOWN_SIZE = UDim2.new(0, 300, 0, 50),
	COUNTDOWN_POSITION = UDim2.new(0.5, -150, 0.4, 0),
	COUNTDOWN_TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	COUNTDOWN_FONT = Enum.Font.GothamBold,
	COUNTDOWN_TEXT_SIZE = 24,
	ELIMINATED_TEXT = "Eliminated",
	-- Countdown re-render cadence. Coarser than a frame since the label
	-- only shows whole seconds.
	TICK_SEC = 0.1,
}

return DeathScreenConfig
