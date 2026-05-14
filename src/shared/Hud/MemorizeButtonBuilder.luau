----------------------------------------------------------------------
-- MemorizeButtonBuilder
----------------------------------------------------------------------
-- Button that triggers the Memorize action. Enabled when the buffer
-- is non-empty; dims when empty. Flashes green/red on outcome.
--
-- Returned handle:
--   .gui               Frame to register with HudLayoutManager
--   .activated         RBXScriptSignal — fires on button click
--   :setEnabled(b)     show active vs disabled state
--   :flashResult(ok)   green flash (true) or red flash (false)
--   :destroy()         clean up
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Defaults = require(ReplicatedStorage.Shared.Hud.MemorizeButtonConfig)

export type Handle = {
	gui: Frame,
	activated: RBXScriptSignal,
	setEnabled: (self: Handle, enabled: boolean) -> (),
	flashResult: (self: Handle, ok: boolean) -> (),
	destroy: (self: Handle) -> (),
}

local MemorizeButtonBuilder = {}

function MemorizeButtonBuilder.build(): Handle
	local container = Instance.new("Frame")
	container.Name = "MemorizeButton"
	container.Size = UDim2.new(0, Defaults.WIDTH, 0, Defaults.HEIGHT)
	container.BackgroundColor3 = Defaults.DISABLED_COLOR
	container.BackgroundTransparency = Defaults.DISABLED_TRANSPARENCY
	container.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
	corner.Parent = container

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.Size = UDim2.new(1, 0, 1, 0)
	button.BackgroundTransparency = 1
	button.Font = Defaults.FONT
	button.TextSize = Defaults.TEXT_SIZE
	button.TextColor3 = Defaults.DISABLED_TEXT_COLOR
	button.TextStrokeTransparency = Defaults.TEXT_STROKE_TRANSPARENCY
	button.Text = Defaults.LABEL_DEFAULT
	button.AutoButtonColor = false
	button.Parent = container

	local activatedEvent = Instance.new("BindableEvent")
	activatedEvent.Name = "MemorizeActivated"

	local enabled = false
	local flashTween: Tween? = nil

	local function applyEnabledState()
		if enabled then
			container.BackgroundColor3 = Defaults.ACTIVE_COLOR
			container.BackgroundTransparency = Defaults.ACTIVE_TRANSPARENCY
			button.TextColor3 = Defaults.ACTIVE_TEXT_COLOR
		else
			container.BackgroundColor3 = Defaults.DISABLED_COLOR
			container.BackgroundTransparency = Defaults.DISABLED_TRANSPARENCY
			button.TextColor3 = Defaults.DISABLED_TEXT_COLOR
		end
	end

	button.MouseButton1Click:Connect(function()
		if enabled then
			activatedEvent:Fire()
		end
	end)

	local handle = {
		gui       = container,
		activated = activatedEvent.Event,
	} :: Handle

	function handle:setEnabled(e: boolean)
		enabled = e
		applyEnabledState()
	end

	function handle:flashResult(ok: boolean)
		if flashTween then flashTween:Cancel() end
		local flashColor = if ok then Defaults.SUCCESS_COLOR else Defaults.FAILURE_COLOR
		container.BackgroundColor3 = flashColor
		flashTween = TweenService:Create(
			container,
			TweenInfo.new(Defaults.FLASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundColor3 = if enabled then Defaults.ACTIVE_COLOR else Defaults.DISABLED_COLOR }
		)
		flashTween:Play()
	end

	function handle:destroy()
		if flashTween then flashTween:Cancel() end
		activatedEvent:Destroy()
		container:Destroy()
	end

	-- Start disabled
	applyEnabledState()

	return handle
end

return MemorizeButtonBuilder
