----------------------------------------------------------------------
-- DashButtonBuilder
----------------------------------------------------------------------
-- View-only builder for the mobile dash button. Returns a circular
-- ImageButton wrapped in a container Frame sized per DashButtonConfig
-- so the HUD's BottomRight UIListLayout allocates the correct slot.
-- Contains no game logic — DashButtonGui wires `activated` to the
-- shared dash dispatcher.
----------------------------------------------------------------------

local DashButtonConfig = require(script.Parent.DashButtonConfig)

export type DashButton = {
	gui: Frame,
	button: ImageButton,
	activated: RBXScriptSignal,
	destroy: (self: DashButton) -> (),
}

local DashButtonBuilder = {}

function DashButtonBuilder.build(): DashButton
	local container = Instance.new("Frame")
	container.Name = "DashButton"
	container.Size = DashButtonConfig.SIZE
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0

	local button = Instance.new("ImageButton")
	button.Name = "Button"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = DashButtonConfig.FILL_COLOR
	button.BackgroundTransparency = DashButtonConfig.FILL_TRANSPARENCY
	button.BorderSizePixel = 0
	button.Image = ""
	button.AutoButtonColor = true
	button.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = DashButtonConfig.CORNER_RADIUS
	corner.Parent = button

	-- Inset ring: a transparent child Frame smaller than the button by BORDER_INSET
	-- on each side. UIStroke on this inner frame appears inside the button fill,
	-- so the fill overlaps the outer portion of the ring.
	local inset = DashButtonConfig.BORDER_INSET * 2
	local ring = Instance.new("Frame")
	ring.Name = "BorderRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(1, -inset, 1, -inset)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.Parent = button

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = DashButtonConfig.CORNER_RADIUS
	ringCorner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Color = DashButtonConfig.BORDER_COLOR
	stroke.Thickness = DashButtonConfig.BORDER_THICKNESS
	stroke.Transparency = DashButtonConfig.BORDER_TRANSPARENCY
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = DashButtonConfig.LABEL_FONT
	label.TextSize = DashButtonConfig.LABEL_TEXT_SIZE
	label.TextColor3 = DashButtonConfig.LABEL_COLOR
	label.Text = DashButtonConfig.LABEL_TEXT
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = button

	local handle: DashButton = {
		gui = container,
		button = button,
		activated = button.Activated,
		destroy = function(self)
			self.gui:Destroy()
		end,
	}

	return handle
end

return DashButtonBuilder
