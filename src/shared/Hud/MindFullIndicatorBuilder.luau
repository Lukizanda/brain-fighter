----------------------------------------------------------------------
-- MindFullIndicatorBuilder
----------------------------------------------------------------------
-- Warning banner shown when the WordBuffer is full (player can't shoot).
-- Purely visual — the client script drives :setActive(bool).
--
-- Returned handle:
--   .gui            Frame to register with HudLayoutManager
--   :setActive(b)   show (true) / hide (false) with a tween
--   :destroy()      clean up
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Defaults = require(ReplicatedStorage.Shared.Hud.MindFullIndicatorConfig)

export type Handle = {
	gui: Frame,
	setActive: (self: Handle, active: boolean) -> (),
	destroy: (self: Handle) -> (),
}

local MindFullIndicatorBuilder = {}

function MindFullIndicatorBuilder.build(): Handle
	local container = Instance.new("Frame")
	container.Name = "MindFullIndicator"
	container.Size = UDim2.new(0, Defaults.WIDTH, 0, Defaults.HEIGHT)
	container.BackgroundColor3 = Defaults.BACKGROUND_COLOR
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
	corner.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Defaults.FONT
	label.TextSize = Defaults.TEXT_SIZE
	label.TextColor3 = Defaults.TEXT_COLOR
	label.TextStrokeTransparency = Defaults.TEXT_STROKE_TRANSPARENCY
	label.Text = Defaults.TEXT
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = container

	local activeTween: Tween? = nil
	local isActive = false

	local handle = { gui = container } :: Handle

	function handle:setActive(active: boolean)
		if active == isActive then return end
		isActive = active

		if activeTween then
			activeTween:Cancel()
		end

		local targetTransparency = if active
			then Defaults.BACKGROUND_TRANSPARENCY
			else 1

		activeTween = TweenService:Create(
			container,
			if active then Defaults.TWEEN_IN else Defaults.TWEEN_OUT,
			{ BackgroundTransparency = targetTransparency }
		)
		activeTween:Play()

		-- Fade the label in sync
		TweenService:Create(
			label,
			if active then Defaults.TWEEN_IN else Defaults.TWEEN_OUT,
			{ TextTransparency = if active then 0 else 1,
			  TextStrokeTransparency = if active then Defaults.TEXT_STROKE_TRANSPARENCY else 1 }
		):Play()
	end

	function handle:destroy()
		if activeTween then activeTween:Cancel() end
		container:Destroy()
	end

	-- Start hidden
	container.BackgroundTransparency = 1
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1

	return handle
end

return MindFullIndicatorBuilder
