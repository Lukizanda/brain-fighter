----------------------------------------------------------------------
-- AttributeBarBuilder
----------------------------------------------------------------------
-- Reusable resource-bar component (Health, Shield, Stamina, Mana, etc.).
-- Purely visual: no data binding, no listeners. An Adapter owns the
-- binding and pushes updates via `:setValue(current, max)`.
--
-- Returned handle:
--   .gui              Frame to register with HudLayoutManager
--   :setValue(cur, m) update fill + numeric readout (tweens to new)
--   :setColor(c3)     override fill color
--   :destroy()        clean up frame + tweens
--
-- Config merge rule: `build(config)` takes per-bar overrides; anything
-- not specified falls back to AttributeBarConfig defaults.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Defaults = require(ReplicatedStorage.Shared.Hud.AttributeBarConfig)

export type Config = {
	name: string,           -- label text ("Health", "Stamina", ...)
	color: Color3,          -- fill color when at full/comfortable value
	warningColor: Color3?,  -- optional: color below MID_THRESHOLD
	criticalColor: Color3?, -- optional: color below LOW_THRESHOLD
	width: number?,
	height: number?,
	showLabel: boolean?,    -- default true
	showNumeric: boolean?,  -- default true
}

export type Handle = {
	gui: Frame,
	setValue: (self: Handle, current: number, max: number) -> (),
	setColor: (self: Handle, c: Color3) -> (),
	playGainSweep: (self: Handle) -> (),
	playDrainRipple: (self: Handle) -> (),
	setCapGlow: (self: Handle, active: boolean) -> (),
	destroy: (self: Handle) -> (),
}

local AttributeBarBuilder = {}

local function resolveFillColor(config: Config, fraction: number): Color3
	if fraction <= Defaults.LOW_THRESHOLD and config.criticalColor then
		return config.criticalColor
	elseif fraction <= Defaults.MID_THRESHOLD and config.warningColor then
		return config.warningColor
	end
	return config.color
end

function AttributeBarBuilder.build(config: Config): Handle
	local width = config.width or Defaults.BAR_WIDTH
	local height = config.height or Defaults.BAR_HEIGHT
	local showLabel = if config.showLabel == nil then true else config.showLabel
	local showNumeric = if config.showNumeric == nil then true else config.showNumeric

	-- Container: bar + overlaid label/numeric. We size the container to include
	-- a small strip above the bar for text, so the bar stays `height` tall.
	local textStripHeight = if showLabel then 16 else 0
	local container = Instance.new("Frame")
	container.Name = "AttributeBar_" .. config.name
	container.Size = UDim2.new(0, width, 0, height + textStripHeight)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0

	-- Background track
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, 0, 1, 0)
	track.Size = UDim2.new(1, 0, 0, height)
	track.BackgroundColor3 = Defaults.BACKGROUND_COLOR
	track.BackgroundTransparency = Defaults.BACKGROUND_TRANSPARENCY
	track.BorderSizePixel = 0
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
	trackCorner.Parent = track

	-- Delayed damage indicator (behind fill, fades to match new value)
	local damageFill = Instance.new("Frame")
	damageFill.Name = "DamageFill"
	damageFill.Size = UDim2.new(1, 0, 1, 0)
	damageFill.BackgroundColor3 = Defaults.DAMAGE_BAR_COLOR
	damageFill.BorderSizePixel = 0
	damageFill.Parent = track

	local damageCorner = Instance.new("UICorner")
	damageCorner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
	damageCorner.Parent = damageFill

	-- Live fill (primary color)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = config.color
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
	fillCorner.Parent = fill

	-- Label (top-left) and numeric (top-right) share the row above the bar
	local labelText: TextLabel?
	local numericText: TextLabel?

	if showLabel then
		labelText = Instance.new("TextLabel")
		labelText.Name = "Label"
		labelText.AnchorPoint = Vector2.new(0, 1)
		labelText.Position = UDim2.new(0, 2, 1, -height - 2)
		labelText.Size = UDim2.new(0.5, 0, 0, 14)
		labelText.BackgroundTransparency = 1
		labelText.Font = Defaults.LABEL_FONT
		labelText.TextSize = Defaults.LABEL_SIZE
		labelText.TextColor3 = Defaults.LABEL_COLOR
		labelText.TextStrokeTransparency = Defaults.LABEL_STROKE_TRANSPARENCY
		labelText.TextXAlignment = Enum.TextXAlignment.Left
		labelText.TextYAlignment = Enum.TextYAlignment.Bottom
		labelText.Text = string.upper(config.name)
		labelText.Parent = container
	end

	if showNumeric then
		numericText = Instance.new("TextLabel")
		numericText.Name = "Numeric"
		numericText.AnchorPoint = Vector2.new(1, 0.5)
		numericText.Position = UDim2.new(1, -6, 0.5, 0)
		numericText.Size = UDim2.new(0.5, 0, 1, 0)
		numericText.BackgroundTransparency = 1
		numericText.Font = Defaults.TEXT_FONT
		numericText.TextSize = Defaults.TEXT_SIZE
		numericText.TextColor3 = Defaults.TEXT_COLOR
		numericText.TextStrokeTransparency = Defaults.TEXT_STROKE_TRANSPARENCY
		numericText.TextXAlignment = Enum.TextXAlignment.Right
		numericText.TextYAlignment = Enum.TextYAlignment.Center
		numericText.ZIndex = fill.ZIndex + 1
		numericText.Text = "0"
		numericText.Parent = track
	end

	-- Mutable handle state
	local lastTweens: { Tween } = {}
	local lastFraction = 0
	local capGlowTween: Tween? = nil
	local CAP_GLOW_STROKE_NAME = "CapGlowStroke"

	local function cancelTweens()
		for _, t in lastTweens do
			t:Cancel()
		end
		table.clear(lastTweens)
	end

	local handle = {
		gui = container,
	} :: Handle

	function handle:setValue(current: number, max: number)
		local safeMax = math.max(max, 1)
		local fraction = math.clamp(current / safeMax, 0, 1)
		lastFraction = fraction

		local fillTween = TweenService:Create(fill, Defaults.FILL_TWEEN,
			{ Size = UDim2.new(fraction, 0, 1, 0) })
		fillTween:Play()
		table.insert(lastTweens, fillTween)

		fill.BackgroundColor3 = resolveFillColor(config, fraction)

		task.delay(Defaults.DAMAGE_LAG_SECONDS, function()
			-- damageFill may have been destroyed during the lag
			if not damageFill.Parent then return end
			local t = TweenService:Create(damageFill, Defaults.FILL_TWEEN,
				{ Size = UDim2.new(fraction, 0, 1, 0) })
			t:Play()
			table.insert(lastTweens, t)
		end)

		if numericText then
			numericText.Text = string.format("%d", math.ceil(current))
		end
	end

	function handle:setColor(c: Color3)
		config.color = c
		fill.BackgroundColor3 = c
	end

	function handle:playGainSweep()
		local overlay = Instance.new("Frame")
		overlay.Name = "GainSweepOverlay"
		overlay.Size = UDim2.new(0, 2, 1, 0)
		overlay.Position = UDim2.new(0, 0, 0, 0)
		overlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		overlay.BackgroundTransparency = 0.5
		overlay.BorderSizePixel = 0
		overlay.ZIndex = fill.ZIndex + 1
		overlay.Parent = track
		local sweepTween = TweenService:Create(overlay, Defaults.GAIN_SWEEP_TWEEN, {
			Size = UDim2.new(lastFraction, 0, 1, 0),
		})
		sweepTween:Play()
		sweepTween.Completed:Connect(function(status: Enum.TweenStatus)
			if status == Enum.TweenStatus.Cancelled then return end
			if not overlay.Parent then return end
			local fadeTween = TweenService:Create(overlay, Defaults.GAIN_SWEEP_FADE, { BackgroundTransparency = 1 })
			fadeTween:Play()
			fadeTween.Completed:Connect(function()
				if overlay.Parent then overlay:Destroy() end
			end)
		end)
	end

	function handle:playDrainRipple()
		for i = 0, Defaults.DRAIN_RIPPLE_COUNT - 1 do
			task.delay(i * Defaults.DRAIN_RIPPLE_STAGGER, function()
				if not fill.Parent then return end
				local ring = Instance.new("Frame")
				ring.Name = "DrainRipple"
				ring.Size = UDim2.new(0, 8, 0, 8)
				ring.AnchorPoint = Vector2.new(0.5, 0.5)
				ring.Position = UDim2.new(lastFraction, 0, 0.5, 0)
				ring.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				ring.BackgroundTransparency = 0.3
				ring.BorderSizePixel = 0
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = ring
				ring.Parent = track
				local rippleTween = TweenService:Create(ring, Defaults.DRAIN_RIPPLE_TWEEN, {
					Size = UDim2.new(0, 24, 0, 24),
					BackgroundTransparency = 1,
				})
				rippleTween:Play()
				rippleTween.Completed:Connect(function()
					if ring.Parent then ring:Destroy() end
				end)
			end)
		end
	end

	function handle:setCapGlow(active: boolean)
		if capGlowTween then
			capGlowTween:Cancel()
			capGlowTween = nil
		end
		local stroke = track:FindFirstChild(CAP_GLOW_STROKE_NAME)
		if active then
			if not stroke then
				local newStroke = Instance.new("UIStroke")
				newStroke.Name = CAP_GLOW_STROKE_NAME
				newStroke.Color = config.color
				newStroke.Thickness = Defaults.CAP_STROKE_MIN
				newStroke.Parent = track
				stroke = newStroke
			end
			capGlowTween = TweenService:Create(stroke :: UIStroke, Defaults.CAP_GLOW_TWEEN, {
				Thickness = Defaults.CAP_STROKE_MAX,
			})
			capGlowTween:Play()
		elseif stroke then
			stroke:Destroy()
		end
	end

	function handle:destroy()
		cancelTweens()
		if capGlowTween then
			capGlowTween:Cancel()
			capGlowTween = nil
		end
		container:Destroy()
	end

	return handle
end

return AttributeBarBuilder
