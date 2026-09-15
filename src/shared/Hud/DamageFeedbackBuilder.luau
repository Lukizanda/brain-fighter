----------------------------------------------------------------------
-- DamageFeedbackBuilder
----------------------------------------------------------------------
-- View-only builder for the full-screen damage flash. Returns a ScreenGui
-- (own top-level, per wiki/concepts/HudGate.md's own-ScreenGui adapter)
-- plus a `flash` method that plays the tween. Contains no remote wiring —
-- DamageFeedbackGui listens to the DamageFeedback remote and calls `flash`.
----------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local DamageFeedbackConfig = require(script.Parent.DamageFeedbackConfig)

export type DamageFeedback = {
	screenGui: ScreenGui,
	flash: (self: DamageFeedback, finalDamage: number) -> (),
	destroy: (self: DamageFeedback) -> (),
}

local DamageFeedbackBuilder = {}

function DamageFeedbackBuilder.build(): DamageFeedback
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DamageFeedbackGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = DamageFeedbackConfig.OVERLAY_COLOR
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Active = false
	overlay.Parent = screenGui

	local handle: DamageFeedback = {
		screenGui = screenGui,
		flash = function(_self, finalDamage: number)
			local intensity = math.clamp(
				finalDamage / DamageFeedbackConfig.INTENSITY_DAMAGE_DIVISOR,
				DamageFeedbackConfig.INTENSITY_MIN,
				DamageFeedbackConfig.INTENSITY_MAX
			)
			TweenService:Create(overlay, DamageFeedbackConfig.FLASH_IN, { BackgroundTransparency = 1 - intensity }):Play()
			task.wait(DamageFeedbackConfig.HOLD_SEC)
			TweenService:Create(overlay, DamageFeedbackConfig.FLASH_OUT, { BackgroundTransparency = 1 }):Play()
		end,
		destroy = function(self)
			self.screenGui:Destroy()
		end,
	}

	return handle
end

return DamageFeedbackBuilder
