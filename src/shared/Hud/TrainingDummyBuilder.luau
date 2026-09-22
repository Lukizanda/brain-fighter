--!strict

----------------------------------------------------------------------
-- TrainingDummyBuilder
----------------------------------------------------------------------
-- View-only builder for the health readout over a training dummy: a bar
-- with a `current / max` line, plus the damage numbers that pop off it.
--
-- World-space, so like `PortalPanelBuilder.buildSign` it is not a HUD
-- element and carries no HudGate policy — it is culled by distance like
-- any other part of the scene. It lives here rather than under `Vfx/`
-- because it is a readout, not an effect: it must survive the reduced
-- effects setting, and the numbers on it are the point.
--
-- Contains no discovery and no Humanoid wiring — `TrainingDummyGui`
-- finds the rigs and pushes values in.
----------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local TrainingDummyConfig = require(script.Parent.TrainingDummyConfig)

export type TrainingDummyReadout = {
	gui: BillboardGui,
	setHealth: (self: TrainingDummyReadout, current: number, max: number) -> (),
	popDelta: (self: TrainingDummyReadout, delta: number) -> (),
	setVisible: (self: TrainingDummyReadout, visible: boolean) -> (),
	destroy: (self: TrainingDummyReadout) -> (),
}

local TrainingDummyBuilder = {}

local function fillColorFor(fraction: number): Color3
	if fraction <= TrainingDummyConfig.LOW_THRESHOLD then
		return TrainingDummyConfig.FILL_CRITICAL_COLOR
	elseif fraction <= TrainingDummyConfig.MID_THRESHOLD then
		return TrainingDummyConfig.FILL_WARNING_COLOR
	end
	return TrainingDummyConfig.FILL_COLOR
end

function TrainingDummyBuilder.build(anchor: BasePart): TrainingDummyReadout
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TrainingDummyReadout"
	billboard.Adornee = anchor
	billboard.Size = TrainingDummyConfig.BAR_SIZE
	billboard.StudsOffsetWorldSpace = Vector3.new(0, TrainingDummyConfig.HEIGHT_STUDS, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = TrainingDummyConfig.MAX_DISTANCE
	billboard.LightInfluence = 0

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromScale(1, 1)
	track.BackgroundColor3 = TrainingDummyConfig.TRACK_COLOR
	track.BackgroundTransparency = TrainingDummyConfig.TRACK_TRANSPARENCY
	track.BorderSizePixel = 0
	track.Parent = billboard

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = TrainingDummyConfig.CORNER_RADIUS
	trackCorner.Parent = track

	local stroke = Instance.new("UIStroke")
	stroke.Color = TrainingDummyConfig.BORDER_COLOR
	stroke.Thickness = TrainingDummyConfig.BORDER_THICKNESS
	stroke.Transparency = TrainingDummyConfig.BORDER_TRANSPARENCY
	stroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = TrainingDummyConfig.FILL_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = TrainingDummyConfig.CORNER_RADIUS
	fillCorner.Parent = fill

	-- Sits over the fill so the numbers stay legible at any fraction.
	local readout = Instance.new("TextLabel")
	readout.Name = "Readout"
	readout.Size = UDim2.fromScale(1, 1)
	readout.BackgroundTransparency = 1
	readout.Font = TrainingDummyConfig.TEXT_FONT
	readout.TextScaled = true
	readout.TextColor3 = TrainingDummyConfig.TEXT_COLOR
	readout.TextStrokeTransparency = TrainingDummyConfig.TEXT_STROKE_TRANSPARENCY
	readout.Text = ""
	readout.Parent = track

	local textPadding = Instance.new("UIPadding")
	textPadding.PaddingLeft = TrainingDummyConfig.TEXT_INSET
	textPadding.PaddingRight = TrainingDummyConfig.TEXT_INSET
	textPadding.Parent = readout

	local activeFillTween: Tween? = nil
	local popups: { [BillboardGui]: true } = {}

	local handle = {} :: TrainingDummyReadout
	handle.gui = billboard

	function handle:setHealth(current: number, max: number)
		local safeMax = math.max(max, 1)
		local fraction = math.clamp(current / safeMax, 0, 1)

		if activeFillTween then
			activeFillTween:Cancel()
		end
		activeFillTween = TweenService:Create(fill, TrainingDummyConfig.FILL_TWEEN, {
			Size = UDim2.fromScale(fraction, 1),
			BackgroundColor3 = fillColorFor(fraction),
		})
		;(activeFillTween :: Tween):Play()

		readout.Text = string.format(TrainingDummyConfig.TEXT_FORMAT, math.round(current), math.round(safeMax))
	end

	-- A positive delta is damage, a negative one a heal. Both are drawn,
	-- because a bar that moves without a number is the thing this readout
	-- exists to avoid.
	function handle:popDelta(delta: number)
		local magnitude = math.round(math.abs(delta))
		if magnitude <= 0 then
			return
		end

		local isDamage = delta > 0
		local popup = Instance.new("BillboardGui")
		popup.Name = "DamageNumber"
		popup.Adornee = anchor
		popup.Size = TrainingDummyConfig.DAMAGE_SIZE
		popup.AlwaysOnTop = false
		popup.MaxDistance = TrainingDummyConfig.MAX_DISTANCE
		popup.LightInfluence = 0

		local jitter = (math.random() * 2 - 1) * TrainingDummyConfig.DAMAGE_JITTER_STUDS
		local startHeight = TrainingDummyConfig.HEIGHT_STUDS + TrainingDummyConfig.DAMAGE_START_OFFSET
		popup.StudsOffsetWorldSpace = Vector3.new(jitter, startHeight, 0)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = TrainingDummyConfig.DAMAGE_FONT
		label.TextScaled = true
		label.TextColor3 = if isDamage
			then TrainingDummyConfig.DAMAGE_COLOR
			else TrainingDummyConfig.HEAL_COLOR
		label.TextStrokeTransparency = TrainingDummyConfig.DAMAGE_STROKE_TRANSPARENCY
		label.Text = string.format(
			if isDamage then TrainingDummyConfig.DAMAGE_FORMAT else TrainingDummyConfig.HEAL_FORMAT,
			magnitude
		)
		label.Parent = popup

		popup.Parent = anchor
		popups[popup] = true

		local rise = TweenService:Create(popup, TrainingDummyConfig.DAMAGE_TWEEN, {
			StudsOffsetWorldSpace = Vector3.new(
				jitter,
				startHeight + TrainingDummyConfig.DAMAGE_RISE_STUDS,
				0
			),
		})
		rise:Play()

		local fade = TweenService:Create(label, TrainingDummyConfig.DAMAGE_FADE_TWEEN, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})

		task.delay(TrainingDummyConfig.DAMAGE_FADE_DELAY, function()
			if popups[popup] then
				fade:Play()
			end
		end)

		rise.Completed:Connect(function()
			popups[popup] = nil
			popup:Destroy()
		end)
	end

	-- Hidden rather than destroyed while the rig is dead: the model is
	-- about to be replaced by a fresh clone, and the readout for that one
	-- is built from scratch.
	function handle:setVisible(visible: boolean)
		billboard.Enabled = visible
	end

	function handle:destroy()
		if activeFillTween then
			activeFillTween:Cancel()
			activeFillTween = nil
		end
		for popup in popups do
			popup:Destroy()
		end
		table.clear(popups)
		billboard:Destroy()
	end

	return handle
end

return TrainingDummyBuilder
