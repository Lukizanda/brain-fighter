--!strict

----------------------------------------------------------------------
-- PortalPanelBuilder
----------------------------------------------------------------------
-- View-only builder for the portal confirm panel and the floating portal
-- sign. Contains no game logic and knows nothing about arenas or queues —
-- `PortalGui` feeds it strings and wires its signals.
--
-- Why a panel and not a ProximityPrompt: the panel is where the queue
-- count lives (`0/2 duelling - 1 waiting`), and a prompt has nowhere to
-- put it. See `wiki/design/lobby.md` § Stage 4 detail, decision 4.
----------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local PortalPanelConfig = require(script.Parent.PortalPanelConfig)

export type PortalPanel = {
	gui: Frame,
	confirmed: RBXScriptSignal,
	cancelled: RBXScriptSignal,
	setTitle: (self: PortalPanel, text: string) -> (),
	setStatus: (self: PortalPanel, text: string) -> (),
	setPrimaryText: (self: PortalPanel, text: string) -> (),
	setAccent: (self: PortalPanel, color: Color3) -> (),
	setShown: (self: PortalPanel, shown: boolean) -> (),
	destroy: (self: PortalPanel) -> (),
}

export type PortalSign = {
	gui: BillboardGui,
	setLabel: (self: PortalSign, text: string) -> (),
	setCounts: (self: PortalSign, text: string) -> (),
	destroy: (self: PortalSign) -> (),
}

local PortalPanelBuilder = {}

local function makeButton(name: string, fill: Color3, textColor: Color3, text: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(1, 0, 0, PortalPanelConfig.BUTTON_HEIGHT)
	button.BackgroundColor3 = fill
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = PortalPanelConfig.BUTTON_FONT
	button.TextSize = PortalPanelConfig.BUTTON_TEXT_SIZE
	button.TextColor3 = textColor
	button.Text = text
	button.LayoutOrder = order

	local corner = Instance.new("UICorner")
	corner.CornerRadius = PortalPanelConfig.BUTTON_CORNER
	corner.Parent = button

	return button
end

function PortalPanelBuilder.build(): PortalPanel
	local container = Instance.new("Frame")
	container.Name = "PortalPanel"
	container.Size = PortalPanelConfig.SIZE
	container.Position = PortalPanelConfig.POSITION
	container.AnchorPoint = PortalPanelConfig.ANCHOR
	container.BackgroundColor3 = PortalPanelConfig.FILL_COLOR
	container.BackgroundTransparency = PortalPanelConfig.FILL_TRANSPARENCY
	container.BorderSizePixel = 0
	container.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = PortalPanelConfig.CORNER_RADIUS
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = PortalPanelConfig.BORDER_COLOR
	stroke.Thickness = PortalPanelConfig.BORDER_THICKNESS
	stroke.Transparency = PortalPanelConfig.BORDER_TRANSPARENCY
	stroke.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = PortalPanelConfig.PADDING
	padding.PaddingBottom = PortalPanelConfig.PADDING
	padding.PaddingLeft = PortalPanelConfig.PADDING
	padding.PaddingRight = PortalPanelConfig.PADDING
	padding.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, PortalPanelConfig.BUTTON_GAP)
	layout.Parent = container

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, PortalPanelConfig.TITLE_HEIGHT)
	title.BackgroundTransparency = 1
	title.Font = PortalPanelConfig.TITLE_FONT
	title.TextSize = PortalPanelConfig.TITLE_TEXT_SIZE
	title.TextColor3 = PortalPanelConfig.TITLE_COLOR
	title.Text = ""
	title.LayoutOrder = PortalPanelConfig.ORDER.TITLE
	title.Parent = container

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(1, 0, 0, PortalPanelConfig.STATUS_HEIGHT)
	status.BackgroundTransparency = 1
	status.Font = PortalPanelConfig.STATUS_FONT
	status.TextSize = PortalPanelConfig.STATUS_TEXT_SIZE
	status.TextColor3 = PortalPanelConfig.STATUS_COLOR
	status.Text = ""
	status.LayoutOrder = PortalPanelConfig.ORDER.STATUS
	status.Parent = container

	local primary = makeButton("Primary", PortalPanelConfig.PRIMARY_COLOR,
		PortalPanelConfig.PRIMARY_TEXT, PortalPanelConfig.PRIMARY_LABEL, PortalPanelConfig.ORDER.PRIMARY)
	primary.Parent = container

	local cancel = makeButton("Cancel", PortalPanelConfig.CANCEL_COLOR,
		PortalPanelConfig.CANCEL_TEXT, PortalPanelConfig.CANCEL_LABEL, PortalPanelConfig.ORDER.CANCEL)
	cancel.Parent = container

	local panel = {} :: PortalPanel
	local activeTween: Tween? = nil

	panel.gui = container
	panel.confirmed = primary.Activated
	panel.cancelled = cancel.Activated

	function panel:setTitle(text: string)
		title.Text = text
	end

	function panel:setStatus(text: string)
		status.Text = text
	end

	function panel:setPrimaryText(text: string)
		primary.Text = text
	end

	function panel:setAccent(color: Color3)
		primary.BackgroundColor3 = color
	end

	-- Fades rather than snapping, but sets Visible first on the way in so
	-- the fade has something to act on. HudGate owns the *policy* half of
	-- visibility; this is the proximity half, and they compose because the
	-- gate ANDs over the owner's intent.
	function panel:setShown(shown: boolean)
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
		if shown then
			container.Visible = true
		end
		local goal = { BackgroundTransparency = shown and PortalPanelConfig.FILL_TRANSPARENCY or 1 }
		local tween = TweenService:Create(container,
			TweenInfo.new(PortalPanelConfig.TWEEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
		activeTween = tween
		if not shown then
			tween.Completed:Connect(function()
				if not container.Visible then
					return
				end
				if container.BackgroundTransparency >= 1 then
					container.Visible = false
				end
			end)
		end
		tween:Play()
	end

	function panel:destroy()
		if activeTween then
			activeTween:Cancel()
		end
		container:Destroy()
	end

	return panel
end

-- Floating world-space sign above a portal pad. World-space, so it is not
-- a HUD element and carries no HudGate policy — it is culled by distance
-- like any other part of the scene.
function PortalPanelBuilder.buildSign(adornee: BasePart, heightStuds: number): PortalSign
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PortalSign"
	billboard.Adornee = adornee
	billboard.Size = PortalPanelConfig.SIGN_SIZE
	billboard.StudsOffsetWorldSpace = Vector3.new(0, heightStuds, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = PortalPanelConfig.SIGN_MAX_DISTANCE
	billboard.LightInfluence = 0

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, PortalPanelConfig.SIGN_LABEL_HEIGHT_FRACTION, 0)
	label.BackgroundTransparency = 1
	label.Font = PortalPanelConfig.TITLE_FONT
	label.TextScaled = true
	label.TextColor3 = PortalPanelConfig.SIGN_LABEL_COLOR
	label.TextStrokeTransparency = PortalPanelConfig.SIGN_LABEL_STROKE_TRANSPARENCY
	label.Text = ""
	label.LayoutOrder = PortalPanelConfig.SIGN_ORDER.LABEL
	label.Parent = billboard

	local counts = Instance.new("TextLabel")
	counts.Name = "Counts"
	counts.Size = UDim2.new(1, 0, PortalPanelConfig.SIGN_COUNT_HEIGHT_FRACTION, 0)
	counts.BackgroundTransparency = 1
	counts.Font = PortalPanelConfig.STATUS_FONT
	counts.TextScaled = true
	counts.TextColor3 = PortalPanelConfig.SIGN_COUNT_COLOR
	counts.TextStrokeTransparency = PortalPanelConfig.SIGN_COUNT_STROKE_TRANSPARENCY
	counts.Text = ""
	counts.LayoutOrder = PortalPanelConfig.SIGN_ORDER.COUNTS
	counts.Parent = billboard

	local sign = {} :: PortalSign
	sign.gui = billboard

	function sign:setLabel(text: string)
		label.Text = text
	end

	function sign:setCounts(text: string)
		counts.Text = text
	end

	function sign:destroy()
		billboard:Destroy()
	end

	return sign
end

return PortalPanelBuilder
