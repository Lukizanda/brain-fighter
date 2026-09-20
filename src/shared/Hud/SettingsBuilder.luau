--!strict

----------------------------------------------------------------------
-- SettingsBuilder
----------------------------------------------------------------------
-- View-only builder for the settings panel and the gear button that
-- opens it. Knows nothing about where a value is stored or what it does
-- — `SettingsGui` feeds it the current values and wires its signals to
-- `Settings.write`. The one domain fact it borrows is the volume range,
-- so the slider's ends mean the same thing as the stored number.
--
-- Three controls, one per setting:
--   * a slider for SFX volume (drag anywhere on the track; fires the raw
--     0–100 value, the coordinator snaps and echoes it back);
--   * a toggle for Reduced effects;
--   * a two-way choice for the letter palette, with a swatch strip drawn
--     from the chosen palette so the player sees the colours before they
--     land on a block.
--
-- Signals are BindableEvents owned here and destroyed with the panel.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Colors = require(ReplicatedStorage.Shared.Core.Colors)
local Settings = require(ReplicatedStorage.Shared.Settings)
local SettingsConfig = require(script.Parent.SettingsConfig)

export type Panel = {
	gui: Frame,
	closed: RBXScriptSignal,
	sfxVolumeChanged: RBXScriptSignal,
	reducedVfxChanged: RBXScriptSignal,
	paletteChanged: RBXScriptSignal,
	setSfxVolume: (self: Panel, volume: number) -> (),
	setReducedVfx: (self: Panel, enabled: boolean) -> (),
	setPalette: (self: Panel, name: string) -> (),
	setShown: (self: Panel, shown: boolean) -> (),
	isShown: (self: Panel) -> boolean,
	destroy: (self: Panel) -> (),
}

export type Gear = {
	gui: TextButton,
	activated: RBXScriptSignal,
	destroy: (self: Gear) -> (),
}

local SettingsBuilder = {}

-- The swatch strip shows every tile colour, spell colours first.
local SWATCH_COLORS: { string } = { "red", "green", "blue", "wild" }

local function makeOptionButton(name: string, text: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(0, SettingsConfig.TOGGLE_WIDTH, 0, SettingsConfig.OPTION_HEIGHT)
	button.BackgroundColor3 = SettingsConfig.OPTION_OFF_COLOR
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = SettingsConfig.OPTION_FONT
	button.TextSize = SettingsConfig.OPTION_TEXT_SIZE
	button.TextColor3 = SettingsConfig.OPTION_OFF_TEXT
	button.Text = text
	button.LayoutOrder = order

	local corner = Instance.new("UICorner")
	corner.CornerRadius = SettingsConfig.OPTION_CORNER
	corner.Parent = button

	return button
end

local function paintOption(button: TextButton, on: boolean)
	button.BackgroundColor3 = if on then SettingsConfig.OPTION_ON_COLOR else SettingsConfig.OPTION_OFF_COLOR
	button.TextColor3 = if on then SettingsConfig.OPTION_ON_TEXT else SettingsConfig.OPTION_OFF_TEXT
end

-- A row: label on the left, a control area on the right that the caller
-- fills. Returns the control area.
local function makeRow(parent: Frame, name: string, labelText: string, order: number): Frame
	local row = Instance.new("Frame")
	row.Name = name
	row.Size = UDim2.new(1, 0, 0, SettingsConfig.ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(SettingsConfig.LABEL_WIDTH_SCALE, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = SettingsConfig.LABEL_FONT
	label.TextSize = SettingsConfig.LABEL_TEXT_SIZE
	label.TextColor3 = SettingsConfig.LABEL_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = labelText
	label.Parent = row

	local control = Instance.new("Frame")
	control.Name = "Control"
	control.Position = UDim2.new(SettingsConfig.LABEL_WIDTH_SCALE, 0, 0, 0)
	control.Size = UDim2.new(1 - SettingsConfig.LABEL_WIDTH_SCALE, 0, 1, 0)
	control.BackgroundTransparency = 1
	control.Parent = row

	return control
end

function SettingsBuilder.buildGear(): Gear
	local button = Instance.new("TextButton")
	button.Name = "SettingsGear"
	button.Size = SettingsConfig.GEAR_SIZE
	button.BackgroundColor3 = SettingsConfig.GEAR_FILL_COLOR
	button.BackgroundTransparency = SettingsConfig.GEAR_FILL_TRANSPARENCY
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = SettingsConfig.GEAR_FONT
	button.TextSize = SettingsConfig.GEAR_TEXT_SIZE
	button.TextColor3 = SettingsConfig.GEAR_TEXT_COLOR
	button.Text = SettingsConfig.GEAR_TEXT
	button.LayoutOrder = SettingsConfig.GEAR_LAYOUT_ORDER

	local corner = Instance.new("UICorner")
	corner.CornerRadius = SettingsConfig.GEAR_CORNER
	corner.Parent = button

	local gear = {} :: Gear
	gear.gui = button
	gear.activated = button.Activated

	function gear:destroy()
		button:Destroy()
	end

	return gear
end

function SettingsBuilder.build(): Panel
	local container = Instance.new("Frame")
	container.Name = "SettingsPanel"
	container.Size = SettingsConfig.SIZE
	container.Position = SettingsConfig.POSITION
	container.AnchorPoint = SettingsConfig.ANCHOR
	container.BackgroundColor3 = SettingsConfig.FILL_COLOR
	container.BackgroundTransparency = SettingsConfig.FILL_TRANSPARENCY
	container.BorderSizePixel = 0
	container.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = SettingsConfig.CORNER_RADIUS
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = SettingsConfig.BORDER_COLOR
	stroke.Thickness = SettingsConfig.BORDER_THICKNESS
	stroke.Transparency = SettingsConfig.BORDER_TRANSPARENCY
	stroke.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = SettingsConfig.PADDING
	padding.PaddingBottom = SettingsConfig.PADDING
	padding.PaddingLeft = SettingsConfig.PADDING
	padding.PaddingRight = SettingsConfig.PADDING
	padding.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, SettingsConfig.ROW_GAP)
	layout.Parent = container

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, SettingsConfig.TITLE_HEIGHT)
	title.BackgroundTransparency = 1
	title.Font = SettingsConfig.TITLE_FONT
	title.TextSize = SettingsConfig.TITLE_TEXT_SIZE
	title.TextColor3 = SettingsConfig.TITLE_COLOR
	title.Text = SettingsConfig.TITLE_TEXT
	title.LayoutOrder = SettingsConfig.ORDER.TITLE
	title.Parent = container

	local closedEvent = Instance.new("BindableEvent")
	local sfxEvent = Instance.new("BindableEvent")
	local reducedEvent = Instance.new("BindableEvent")
	local paletteEvent = Instance.new("BindableEvent")
	local connections: { RBXScriptConnection } = {}

	----------------------------------------------------------------
	-- SFX volume slider
	----------------------------------------------------------------
	local sfxControl = makeRow(container, "SfxRow", SettingsConfig.LABELS.SfxVolume, SettingsConfig.ORDER.SFX)

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.AnchorPoint = Vector2.new(1, 0.5)
	valueLabel.Position = UDim2.new(1, 0, 0.5, 0)
	valueLabel.Size = UDim2.new(0, SettingsConfig.SLIDER_VALUE_WIDTH, 1, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = SettingsConfig.SLIDER_VALUE_FONT
	valueLabel.TextSize = SettingsConfig.SLIDER_VALUE_TEXT_SIZE
	valueLabel.TextColor3 = SettingsConfig.SLIDER_VALUE_COLOR
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = sfxControl

	-- A TextButton so it takes mouse and touch input on every platform.
	local track = Instance.new("TextButton")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 0, 0.5, 0)
	track.Size = UDim2.new(1, -(SettingsConfig.SLIDER_VALUE_WIDTH + SettingsConfig.OPTION_GAP), 0, SettingsConfig.SLIDER_TRACK_HEIGHT)
	track.BackgroundColor3 = SettingsConfig.SLIDER_TRACK_COLOR
	track.BorderSizePixel = 0
	track.AutoButtonColor = false
	track.Text = ""
	track.Parent = sfxControl

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0.5, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = SettingsConfig.SLIDER_FILL_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.Size = UDim2.fromOffset(SettingsConfig.SLIDER_KNOB_SIZE, SettingsConfig.SLIDER_KNOB_SIZE)
	knob.BackgroundColor3 = SettingsConfig.SLIDER_KNOB_COLOR
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(0.5, 0)
	knobCorner.Parent = knob

	local volumeRange = Settings.SFX_VOLUME_MAX - Settings.SFX_VOLUME_MIN

	local function paintVolume(volume: number)
		local fraction = (volume - Settings.SFX_VOLUME_MIN) / volumeRange
		fill.Size = UDim2.fromScale(fraction, 1)
		knob.Position = UDim2.fromScale(fraction, 0.5)
		valueLabel.Text = string.format(SettingsConfig.SLIDER_VALUE_FORMAT, volume)
	end

	local function volumeAtX(x: number): number
		local width = math.max(track.AbsoluteSize.X, 1)
		local fraction = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		return Settings.SFX_VOLUME_MIN + fraction * volumeRange
	end

	local dragging = false

	local function isPointer(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	table.insert(connections, track.InputBegan:Connect(function(input: InputObject)
		if not isPointer(input) then
			return
		end
		dragging = true
		sfxEvent:Fire(volumeAtX(input.Position.X))
	end))

	table.insert(connections, UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			sfxEvent:Fire(volumeAtX(input.Position.X))
		end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input: InputObject)
		if dragging and isPointer(input) then
			dragging = false
		end
	end))

	----------------------------------------------------------------
	-- Reduced effects toggle
	----------------------------------------------------------------
	local reducedControl = makeRow(container, "ReducedRow", SettingsConfig.LABELS.ReducedVfx, SettingsConfig.ORDER.REDUCED)

	local toggle = makeOptionButton("Toggle", SettingsConfig.TOGGLE_OFF_LABEL, 1)
	toggle.AnchorPoint = Vector2.new(0, 0.5)
	toggle.Position = UDim2.new(0, 0, 0.5, 0)
	toggle.Parent = reducedControl

	local reducedOn = false

	local function paintReduced(enabled: boolean)
		reducedOn = enabled
		toggle.Text = if enabled then SettingsConfig.TOGGLE_ON_LABEL else SettingsConfig.TOGGLE_OFF_LABEL
		paintOption(toggle, enabled)
	end

	table.insert(connections, toggle.Activated:Connect(function()
		reducedEvent:Fire(not reducedOn)
	end))

	----------------------------------------------------------------
	-- Palette choice + swatches
	----------------------------------------------------------------
	local paletteControl = makeRow(container, "PaletteRow", SettingsConfig.LABELS.Palette, SettingsConfig.ORDER.PALETTE)

	local paletteLayout = Instance.new("UIListLayout")
	paletteLayout.FillDirection = Enum.FillDirection.Horizontal
	paletteLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	paletteLayout.SortOrder = Enum.SortOrder.LayoutOrder
	paletteLayout.Padding = UDim.new(0, SettingsConfig.OPTION_GAP)
	paletteLayout.Parent = paletteControl

	local paletteButtons: { [string]: TextButton } = {}
	for i, option in SettingsConfig.PALETTE_OPTIONS do
		local button = makeOptionButton("Palette_" .. option.id, option.label, i)
		button.Size = UDim2.new(0, 0, 0, SettingsConfig.OPTION_HEIGHT)
		button.AutomaticSize = Enum.AutomaticSize.X
		local buttonPadding = Instance.new("UIPadding")
		buttonPadding.PaddingLeft = UDim.new(0, SettingsConfig.OPTION_GAP * 2)
		buttonPadding.PaddingRight = UDim.new(0, SettingsConfig.OPTION_GAP * 2)
		buttonPadding.Parent = button
		button.Parent = paletteControl
		paletteButtons[option.id] = button
		table.insert(connections, button.Activated:Connect(function()
			paletteEvent:Fire(option.id)
		end))
	end

	local swatchRow = Instance.new("Frame")
	swatchRow.Name = "Swatches"
	swatchRow.Size = UDim2.new(1, 0, 0, SettingsConfig.SWATCH_SIZE)
	swatchRow.BackgroundTransparency = 1
	swatchRow.LayoutOrder = SettingsConfig.ORDER.SWATCHES
	swatchRow.Parent = container

	local swatchLayout = Instance.new("UIListLayout")
	swatchLayout.FillDirection = Enum.FillDirection.Horizontal
	swatchLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	swatchLayout.SortOrder = Enum.SortOrder.LayoutOrder
	swatchLayout.Padding = UDim.new(0, SettingsConfig.SWATCH_GAP)
	swatchLayout.Parent = swatchRow

	local swatches: { [string]: Frame } = {}
	for i, color in SWATCH_COLORS do
		local swatch = Instance.new("Frame")
		swatch.Name = "Swatch_" .. color
		swatch.Size = UDim2.fromOffset(SettingsConfig.SWATCH_SIZE, SettingsConfig.SWATCH_SIZE)
		swatch.BorderSizePixel = 0
		swatch.LayoutOrder = i
		local swatchCorner = Instance.new("UICorner")
		swatchCorner.CornerRadius = SettingsConfig.SWATCH_CORNER
		swatchCorner.Parent = swatch
		swatch.Parent = swatchRow
		swatches[color] = swatch
	end

	local function paintPalette(name: string)
		for id, button in paletteButtons do
			paintOption(button, id == name)
		end
		local palette = Colors.PALETTES[name] or Colors.PALETTES[Colors.Palette.Default]
		for color, swatch in swatches do
			swatch.BackgroundColor3 = palette[color]
		end
	end

	----------------------------------------------------------------
	-- Close
	----------------------------------------------------------------
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.new(1, 0, 0, SettingsConfig.CLOSE_HEIGHT)
	close.BackgroundColor3 = SettingsConfig.CLOSE_COLOR
	close.BorderSizePixel = 0
	close.AutoButtonColor = true
	close.Font = SettingsConfig.OPTION_FONT
	close.TextSize = SettingsConfig.OPTION_TEXT_SIZE
	close.TextColor3 = SettingsConfig.CLOSE_TEXT
	close.Text = SettingsConfig.CLOSE_LABEL
	close.LayoutOrder = SettingsConfig.ORDER.CLOSE
	close.Parent = container

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = SettingsConfig.OPTION_CORNER
	closeCorner.Parent = close

	table.insert(connections, close.Activated:Connect(function()
		closedEvent:Fire()
	end))

	----------------------------------------------------------------
	-- Handle
	----------------------------------------------------------------
	local panel = {} :: Panel
	panel.gui = container
	panel.closed = closedEvent.Event
	panel.sfxVolumeChanged = sfxEvent.Event
	panel.reducedVfxChanged = reducedEvent.Event
	panel.paletteChanged = paletteEvent.Event

	function panel:setSfxVolume(volume: number)
		paintVolume(volume)
	end

	function panel:setReducedVfx(enabled: boolean)
		paintReduced(enabled)
	end

	function panel:setPalette(name: string)
		paintPalette(name)
	end

	function panel:setShown(shown: boolean)
		container.Visible = shown
	end

	function panel:isShown(): boolean
		return container.Visible
	end

	function panel:destroy()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		closedEvent:Destroy()
		sfxEvent:Destroy()
		reducedEvent:Destroy()
		paletteEvent:Destroy()
		container:Destroy()
	end

	paintVolume(Settings.SFX_VOLUME_MIN)
	paintReduced(false)
	paintPalette(Colors.Palette.Default)

	return panel
end

return SettingsBuilder
