----------------------------------------------------------------------
-- SettingsMenuBuilder
----------------------------------------------------------------------
-- Builds the Settings Menu UI. Returns a handle with open/close/destroy
-- methods and callbacks for when settings change.
----------------------------------------------------------------------
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local log = Logger.new("SettingsMenuBuilder")

local SettingsMenuConfig = require(script.Parent.SettingsMenuConfig)

local SettingsMenuBuilder = {}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function mergeConfig(overrides: { [string]: any }?): typeof(SettingsMenuConfig)
	if not overrides then
		return SettingsMenuConfig
	end
	local config = table.clone(SettingsMenuConfig)
	for k, v in overrides do
		config[k] = v
	end
	return config
end

local function roundTo(value: number, decimals: number): number
	local mult = 10 ^ decimals
	return math.round(value * mult) / mult
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------

function SettingsMenuBuilder.build(configOverrides: { [string]: any }?)
	local config = mergeConfig(configOverrides)
	local connections: { RBXScriptConnection } = {}
	local tweens: { Tween } = {}

	-- Current settings state
	local state = {
		sensitivity = config.SENSITIVITY_DISPLAY_DEFAULT,
		fieldOfView = config.DEFAULT_FIELD_OF_VIEW,
		crosshairColor = config.DEFAULT_CROSSHAIR_COLOR,
		aimAssist = config.DEFAULT_AIM_ASSIST,
	}

	-- Callbacks table — callers can assign functions to these keys
	local callbacks = {
		onSensitivityChanged = nil :: ((displayValue: number, rawValue: number) -> ())?,
		onFieldOfViewChanged = nil :: ((fov: number) -> ())?,
		onCrosshairColorChanged = nil :: ((color: Color3) -> ())?,
		onAimAssistChanged = nil :: ((enabled: boolean) -> ())?,
	}

	-- ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SettingsMenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = config.DISPLAY_ORDER
	screenGui.IgnoreGuiInset = true
	screenGui.Enabled = false
	-- Caller mounts handle.gui to PlayerGui (keeps this module client-global-free).

	-- Dimmer overlay
	local dimmer = Instance.new("Frame")
	dimmer.Name = "Dimmer"
	dimmer.Size = UDim2.new(1, 0, 1, 0)
	dimmer.BackgroundColor3 = config.DIMMER_COLOR
	dimmer.BackgroundTransparency = config.DIMMER_TRANSPARENCY
	dimmer.BorderSizePixel = 0
	dimmer.ZIndex = 1
	dimmer.Parent = screenGui

	-- Panel
	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.Size = UDim2.fromOffset(config.PANEL_WIDTH, config.PANEL_HEIGHT)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = config.PANEL_BACKGROUND_COLOR
	panel.BackgroundTransparency = config.PANEL_BACKGROUND_TRANSPARENCY
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = screenGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = config.PANEL_CORNER_RADIUS
	panelCorner.Parent = panel

	local panelPadding = Instance.new("UIPadding")
	panelPadding.PaddingTop = config.PANEL_PADDING
	panelPadding.PaddingBottom = config.PANEL_PADDING
	panelPadding.PaddingLeft = config.PANEL_PADDING
	panelPadding.PaddingRight = config.PANEL_PADDING
	panelPadding.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, config.TITLE_HEIGHT)
	title.Position = UDim2.fromOffset(0, 0)
	title.BackgroundTransparency = 1
	title.Font = config.TITLE_FONT
	title.TextSize = config.TITLE_TEXT_SIZE
	title.TextColor3 = config.TITLE_TEXT_COLOR
	title.Text = config.TITLE_TEXT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	title.Parent = panel

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.fromOffset(config.CLOSE_BUTTON_SIZE, config.CLOSE_BUTTON_SIZE)
	closeBtn.Position = UDim2.new(1, 0, 0, 0)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundTransparency = config.CLOSE_BUTTON_BACKGROUND_TRANSPARENCY
	closeBtn.Font = config.CLOSE_BUTTON_FONT
	closeBtn.TextSize = config.CLOSE_BUTTON_TEXT_SIZE
	closeBtn.TextColor3 = config.CLOSE_BUTTON_TEXT_COLOR
	closeBtn.Text = "X"
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 3
	closeBtn.Parent = panel

	table.insert(connections, closeBtn.MouseEnter:Connect(function()
		closeBtn.TextColor3 = config.CLOSE_BUTTON_HOVER_COLOR
	end))
	table.insert(connections, closeBtn.MouseLeave:Connect(function()
		closeBtn.TextColor3 = config.CLOSE_BUTTON_TEXT_COLOR
	end))

	-- Content container (scrollable rows below title)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 1, -(config.TITLE_HEIGHT + 8))
	content.Position = UDim2.fromOffset(0, config.TITLE_HEIGHT + 8)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ZIndex = 3
	content.Parent = panel

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.FillDirection = Enum.FillDirection.Vertical
	contentLayout.Padding = config.ROW_SPACING
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = content

	----------------------------------------------------------------------
	-- Row factory helpers
	----------------------------------------------------------------------

	local layoutOrder = 0
	local function nextOrder(): number
		layoutOrder += 1
		return layoutOrder
	end

	local function createRow(labelText: string): Frame
		local row = Instance.new("Frame")
		row.Name = labelText:gsub("%s", "")
		row.Size = UDim2.new(1, 0, 0, config.ROW_HEIGHT)
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.LayoutOrder = nextOrder()
		row.ZIndex = 3
		row.Parent = content

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(0.45, 0, 1, 0)
		label.Position = UDim2.fromOffset(0, 0)
		label.BackgroundTransparency = 1
		label.Font = config.LABEL_FONT
		label.TextSize = config.LABEL_TEXT_SIZE
		label.TextColor3 = config.LABEL_TEXT_COLOR
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Text = labelText
		label.ZIndex = 3
		label.Parent = row

		return row
	end

	----------------------------------------------------------------------
	-- Slider widget
	----------------------------------------------------------------------

	local function createSlider(
		row: Frame,
		min: number,
		max: number,
		default: number,
		decimals: number,
		onChange: (value: number) -> ()
	)
		local controlFrame = Instance.new("Frame")
		controlFrame.Name = "Control"
		controlFrame.Size = UDim2.new(0.55, 0, 1, 0)
		controlFrame.Position = UDim2.fromScale(0.45, 0)
		controlFrame.BackgroundTransparency = 1
		controlFrame.ZIndex = 3
		controlFrame.Parent = row

		local controlLayout = Instance.new("UIListLayout")
		controlLayout.FillDirection = Enum.FillDirection.Horizontal
		controlLayout.Padding = UDim.new(0, 8)
		controlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		controlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		controlLayout.SortOrder = Enum.SortOrder.LayoutOrder
		controlLayout.Parent = controlFrame

		-- Track
		local track = Instance.new("Frame")
		track.Name = "Track"
		track.Size = UDim2.fromOffset(config.SLIDER_WIDTH, config.SLIDER_HEIGHT)
		track.BackgroundColor3 = config.SLIDER_TRACK_COLOR
		track.BorderSizePixel = 0
		track.LayoutOrder = 1
		track.ZIndex = 4
		track.Parent = controlFrame

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = config.SLIDER_CORNER_RADIUS
		trackCorner.Parent = track

		-- Fill
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = config.SLIDER_FILL_COLOR
		fill.BorderSizePixel = 0
		fill.ZIndex = 5
		fill.Parent = track

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = config.SLIDER_CORNER_RADIUS
		fillCorner.Parent = fill

		-- Knob
		local knob = Instance.new("Frame")
		knob.Name = "Knob"
		knob.Size = UDim2.fromOffset(config.SLIDER_KNOB_SIZE, config.SLIDER_KNOB_SIZE)
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Position = UDim2.new(0, 0, 0.5, 0)
		knob.BackgroundColor3 = config.SLIDER_KNOB_COLOR
		knob.BorderSizePixel = 0
		knob.ZIndex = 6
		knob.Parent = track

		local knobCorner = Instance.new("UICorner")
		knobCorner.CornerRadius = config.SLIDER_CORNER_RADIUS
		knobCorner.Parent = knob

		-- Value label
		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = "ValueLabel"
		valueLabel.Size = UDim2.fromOffset(config.VALUE_WIDTH, config.ROW_HEIGHT)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Font = config.VALUE_FONT
		valueLabel.TextSize = config.VALUE_TEXT_SIZE
		valueLabel.TextColor3 = config.VALUE_TEXT_COLOR
		valueLabel.TextXAlignment = Enum.TextXAlignment.Left
		valueLabel.LayoutOrder = 2
		valueLabel.ZIndex = 4
		valueLabel.Parent = controlFrame

		-- Slider logic
		local dragging = false

		local function setSliderValue(alpha: number)
			alpha = math.clamp(alpha, 0, 1)
			local value = min + (max - min) * alpha
			value = roundTo(value, decimals)
			fill.Size = UDim2.fromScale(alpha, 1)
			knob.Position = UDim2.new(alpha, 0, 0.5, 0)
			valueLabel.Text = string.format("%." .. tostring(decimals) .. "f", value)
			onChange(value)
		end

		local function onInput(input: InputObject)
			local trackAbsPos = track.AbsolutePosition.X
			local trackAbsSize = track.AbsoluteSize.X
			if trackAbsSize <= 0 then
				return
			end
			local relativeX = input.Position.X - trackAbsPos
			local alpha = relativeX / trackAbsSize
			setSliderValue(alpha)
		end

		table.insert(connections, track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				onInput(input)
			end
		end))

		table.insert(connections, knob.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				onInput(input)
			end
		end))

		table.insert(connections, game:GetService("UserInputService").InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch) then
				onInput(input)
			end
		end))

		table.insert(connections, game:GetService("UserInputService").InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end))

		-- Set initial value
		local initAlpha = (default - min) / (max - min)
		setSliderValue(initAlpha)

		return {
			setValue = function(value: number)
				local alpha = (value - min) / (max - min)
				setSliderValue(alpha)
			end,
		}
	end

	----------------------------------------------------------------------
	-- Toggle widget
	----------------------------------------------------------------------

	local function createToggle(row: Frame, default: boolean, onChange: (enabled: boolean) -> ())
		local controlFrame = Instance.new("Frame")
		controlFrame.Name = "Control"
		controlFrame.Size = UDim2.new(0.55, 0, 1, 0)
		controlFrame.Position = UDim2.fromScale(0.45, 0)
		controlFrame.BackgroundTransparency = 1
		controlFrame.ZIndex = 3
		controlFrame.Parent = row

		local toggleBg = Instance.new("Frame")
		toggleBg.Name = "ToggleBg"
		toggleBg.Size = UDim2.fromOffset(config.TOGGLE_WIDTH, config.TOGGLE_HEIGHT)
		toggleBg.Position = UDim2.new(0, 0, 0.5, 0)
		toggleBg.AnchorPoint = Vector2.new(0, 0.5)
		toggleBg.BackgroundColor3 = if default then config.TOGGLE_ON_COLOR else config.TOGGLE_OFF_COLOR
		toggleBg.BorderSizePixel = 0
		toggleBg.ZIndex = 4
		toggleBg.Parent = controlFrame

		local toggleCorner = Instance.new("UICorner")
		toggleCorner.CornerRadius = config.TOGGLE_CORNER_RADIUS
		toggleCorner.Parent = toggleBg

		local toggleKnob = Instance.new("Frame")
		toggleKnob.Name = "Knob"
		toggleKnob.Size = UDim2.fromOffset(config.TOGGLE_KNOB_SIZE, config.TOGGLE_KNOB_SIZE)
		toggleKnob.AnchorPoint = Vector2.new(0, 0.5)
		local knobPad = (config.TOGGLE_HEIGHT - config.TOGGLE_KNOB_SIZE) / 2
		local offX = knobPad
		local onX = config.TOGGLE_WIDTH - config.TOGGLE_KNOB_SIZE - knobPad
		toggleKnob.Position = UDim2.new(0, if default then onX else offX, 0.5, 0)
		toggleKnob.BackgroundColor3 = config.TOGGLE_KNOB_COLOR
		toggleKnob.BorderSizePixel = 0
		toggleKnob.ZIndex = 5
		toggleKnob.Parent = toggleBg

		local knobCorner = Instance.new("UICorner")
		knobCorner.CornerRadius = config.TOGGLE_CORNER_RADIUS
		knobCorner.Parent = toggleKnob

		local enabled = default

		-- Clickable overlay
		local clickArea = Instance.new("TextButton")
		clickArea.Name = "ClickArea"
		clickArea.Size = UDim2.new(1, 0, 1, 0)
		clickArea.BackgroundTransparency = 1
		clickArea.Text = ""
		clickArea.ZIndex = 6
		clickArea.Parent = toggleBg

		table.insert(connections, clickArea.MouseButton1Click:Connect(function()
			enabled = not enabled
			local targetBgColor = if enabled then config.TOGGLE_ON_COLOR else config.TOGGLE_OFF_COLOR
			local targetKnobX = if enabled then onX else offX

			local bgTween = TweenService:Create(toggleBg, config.TOGGLE_TWEEN, { BackgroundColor3 = targetBgColor })
			bgTween:Play()
			table.insert(tweens, bgTween)

			local knobTween = TweenService:Create(
				toggleKnob,
				config.TOGGLE_TWEEN,
				{ Position = UDim2.new(0, targetKnobX, 0.5, 0) }
			)
			knobTween:Play()
			table.insert(tweens, knobTween)

			onChange(enabled)
		end))

		return {
			setValue = function(value: boolean)
				enabled = value
				toggleBg.BackgroundColor3 = if enabled then config.TOGGLE_ON_COLOR else config.TOGGLE_OFF_COLOR
				toggleKnob.Position = UDim2.new(0, if enabled then onX else offX, 0.5, 0)
			end,
		}
	end

	----------------------------------------------------------------------
	-- Color preset picker widget
	----------------------------------------------------------------------

	local function createColorPicker(row: Frame, default: Color3, onChange: (color: Color3) -> ())
		local controlFrame = Instance.new("Frame")
		controlFrame.Name = "Control"
		controlFrame.Size = UDim2.new(0.55, 0, 1, 0)
		controlFrame.Position = UDim2.fromScale(0.45, 0)
		controlFrame.BackgroundTransparency = 1
		controlFrame.ZIndex = 3
		controlFrame.Parent = row

		local colorLayout = Instance.new("UIListLayout")
		colorLayout.FillDirection = Enum.FillDirection.Horizontal
		colorLayout.Padding = config.COLOR_BUTTON_SPACING
		colorLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		colorLayout.SortOrder = Enum.SortOrder.LayoutOrder
		colorLayout.Parent = controlFrame

		local strokes: { UIStroke } = {}
		local currentColor = default

		for i, preset in config.COLOR_PRESETS do
			local btn = Instance.new("TextButton")
			btn.Name = preset.name
			btn.Size = UDim2.fromOffset(config.COLOR_BUTTON_SIZE, config.COLOR_BUTTON_SIZE)
			btn.BackgroundColor3 = preset.color
			btn.BorderSizePixel = 0
			btn.Text = ""
			btn.LayoutOrder = i
			btn.ZIndex = 4
			btn.Parent = controlFrame

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = config.COLOR_BUTTON_CORNER_RADIUS
			btnCorner.Parent = btn

			local stroke = Instance.new("UIStroke")
			stroke.Color = config.COLOR_BUTTON_STROKE_COLOR
			stroke.Thickness = if preset.color == default then config.COLOR_BUTTON_STROKE_THICKNESS else 0
			stroke.Parent = btn
			table.insert(strokes, stroke)

			table.insert(connections, btn.MouseButton1Click:Connect(function()
				currentColor = preset.color
				-- Update strokes — only selected has visible stroke
				for _, s in strokes do
					s.Thickness = 0
				end
				stroke.Thickness = config.COLOR_BUTTON_STROKE_THICKNESS
				onChange(preset.color)
			end))
		end

		return {
			setValue = function(color: Color3)
				currentColor = color
				for idx, preset in config.COLOR_PRESETS do
					strokes[idx].Thickness = if preset.color == color then config.COLOR_BUTTON_STROKE_THICKNESS else 0
				end
			end,
		}
	end

	----------------------------------------------------------------------
	-- Separator
	----------------------------------------------------------------------

	local function createSeparator()
		local sep = Instance.new("Frame")
		sep.Name = "Separator"
		sep.Size = UDim2.new(1, 0, 0, 1)
		sep.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
		sep.BackgroundTransparency = 0.5
		sep.BorderSizePixel = 0
		sep.LayoutOrder = nextOrder()
		sep.ZIndex = 3
		sep.Parent = content
	end

	----------------------------------------------------------------------
	-- Build setting rows
	----------------------------------------------------------------------

	-- Mouse Sensitivity
	local sensitivityRow = createRow("Mouse Sensitivity")
	local sensitivitySlider = createSlider(
		sensitivityRow,
		config.SENSITIVITY_DISPLAY_MIN,
		config.SENSITIVITY_DISPLAY_MAX,
		config.SENSITIVITY_DISPLAY_DEFAULT,
		1,
		function(value)
			state.sensitivity = value
			-- Map display range to raw range
			local alpha = (value - config.SENSITIVITY_DISPLAY_MIN) / (config.SENSITIVITY_DISPLAY_MAX - config.SENSITIVITY_DISPLAY_MIN)
			local rawValue = config.MIN_MOUSE_SENSITIVITY + (config.MAX_MOUSE_SENSITIVITY - config.MIN_MOUSE_SENSITIVITY) * alpha
			if callbacks.onSensitivityChanged then
				callbacks.onSensitivityChanged(value, rawValue)
			end
		end
	)

	createSeparator()

	-- Field of View
	local fovRow = createRow("Field of View")
	local fovSlider = createSlider(
		fovRow,
		config.MIN_FIELD_OF_VIEW,
		config.MAX_FIELD_OF_VIEW,
		config.DEFAULT_FIELD_OF_VIEW,
		0,
		function(value)
			state.fieldOfView = value
			if callbacks.onFieldOfViewChanged then
				callbacks.onFieldOfViewChanged(value)
			end
		end
	)

	createSeparator()

	-- Crosshair Color
	local crosshairRow = createRow("Crosshair Color")
	local crosshairPicker = createColorPicker(
		crosshairRow,
		config.DEFAULT_CROSSHAIR_COLOR,
		function(color)
			state.crosshairColor = color
			if callbacks.onCrosshairColorChanged then
				callbacks.onCrosshairColorChanged(color)
			end
		end
	)

	createSeparator()

	-- Aim Assist
	local aimAssistRow = createRow("Aim Assist")
	local aimAssistToggle = createToggle(
		aimAssistRow,
		config.DEFAULT_AIM_ASSIST,
		function(enabled)
			state.aimAssist = enabled
			if callbacks.onAimAssistChanged then
				callbacks.onAimAssistChanged(enabled)
			end
		end
	)

	----------------------------------------------------------------------
	-- Handle
	----------------------------------------------------------------------

	local isOpen = false

	local handle = {
		gui = screenGui,
		callbacks = callbacks,
	}

	function handle:isVisible(): boolean
		return isOpen
	end

	function handle:open()
		if isOpen then
			return
		end
		isOpen = true
		screenGui.Enabled = true
		panel.Size = UDim2.fromOffset(config.PANEL_WIDTH, config.PANEL_HEIGHT)

		-- Animate in
		panel.BackgroundTransparency = 1
		dimmer.BackgroundTransparency = 1
		local panelTween = TweenService:Create(panel, config.OPEN_TWEEN, {
			BackgroundTransparency = config.PANEL_BACKGROUND_TRANSPARENCY,
		})
		panelTween:Play()
		table.insert(tweens, panelTween)

		local dimmerTween = TweenService:Create(dimmer, config.OPEN_TWEEN, {
			BackgroundTransparency = config.DIMMER_TRANSPARENCY,
		})
		dimmerTween:Play()
		table.insert(tweens, dimmerTween)

		log:info("Menu opened")
	end

	function handle:close()
		if not isOpen then
			return
		end
		isOpen = false

		local panelTween = TweenService:Create(panel, config.CLOSE_TWEEN, {
			BackgroundTransparency = 1,
		})
		panelTween:Play()
		table.insert(tweens, panelTween)

		local dimmerTween = TweenService:Create(dimmer, config.CLOSE_TWEEN, {
			BackgroundTransparency = 1,
		})
		dimmerTween:Play()
		table.insert(tweens, dimmerTween)

		task.delay(config.CLOSE_TWEEN.Time, function()
			if not isOpen then
				screenGui.Enabled = false
			end
		end)

		log:info("Menu closed")
	end

	function handle:toggle()
		if isOpen then
			self:close()
		else
			self:open()
		end
	end

	function handle:getState()
		return table.clone(state)
	end

	function handle:destroy()
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)

		for _, tween in tweens do
			tween:Cancel()
		end
		table.clear(tweens)

		screenGui:Destroy()
		log:info("Destroyed")
	end

	-- Close button wiring
	table.insert(connections, closeBtn.MouseButton1Click:Connect(function()
		handle:close()
	end))

	-- Block clicks on dimmer from falling through
	table.insert(connections, dimmer.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			handle:close()
		end
	end))

	log:info("Built settings menu")
	return handle
end

return SettingsMenuBuilder
