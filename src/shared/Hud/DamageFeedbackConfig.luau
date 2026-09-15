----------------------------------------------------------------------
-- DamageFeedbackConfig
----------------------------------------------------------------------
-- Tunable constants for the full-screen damage flash.
----------------------------------------------------------------------

local DamageFeedbackConfig = {
	FLASH_IN = TweenInfo.new(0, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
	FLASH_OUT = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	OVERLAY_COLOR = Color3.fromRGB(180, 0, 0),
	-- Intensity (background transparency = 1 - intensity) scales with damage
	-- taken so big hits feel bigger, clamped to a readable range.
	INTENSITY_MIN = 0.2,
	INTENSITY_MAX = 0.6,
	INTENSITY_DAMAGE_DIVISOR = 50,
	-- Hold time at peak intensity before the fade-out tween starts.
	HOLD_SEC = 0.05,
}

return DamageFeedbackConfig
