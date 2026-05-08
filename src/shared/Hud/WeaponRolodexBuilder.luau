----------------------------------------------------------------------
-- WeaponRolodexBuilder
----------------------------------------------------------------------
-- Procedurally constructs a single-card weapon display that cycles
-- through the player's held weapons. No gameplay logic — only rendering.
--
-- Layout (square card, icon fills the card):
-- ┌──────────────┐
-- │[PRI]         │  (slot label overlay, top-left)
-- │              │
-- │     ICON     │  (icon fills card; gradient behind it fades
-- │              │   from solid at the bottom to transparent at
-- │      [30/90] │   the top so the silhouette pops)
-- └──────────────┘
--     ● ○ ○          (dot indicators below)
----------------------------------------------------------------------

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Hud.WeaponRolodexConfig)

local WeaponRolodexBuilder = {}

export type WeaponInfo = {
	tool: Tool,
	displayName: string,
	iconAssetId: string?,
}

export type Handle = {
	gui: Frame,
	showWeapon: (self: Handle, info: WeaponInfo?, direction: number?) -> (),
	setAmmo: (self: Handle, text: string?) -> (),
	setSpecial: (self: Handle, info: WeaponInfo?) -> (),
	setSpecialCooldown: (self: Handle, secondsRemaining: number?) -> (),
	setDots: (self: Handle, total: number, activeIndex: number) -> (),
	getCardFrame: (self: Handle) -> Frame,
	destroy: (self: Handle) -> (),
}

local function createCorner(parent: GuiObject, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function createPaddingXY(parent: GuiObject, x: number, y: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, x)
	p.PaddingRight = UDim.new(0, x)
	p.PaddingTop = UDim.new(0, y)
	p.PaddingBottom = UDim.new(0, y)
	p.Parent = parent
	return p
end

-- Build the 2- or 3-keypoint transparency sequence used for the card's
-- UIGradient. When GRADIENT_FALLOFF_START > 0 we insert a middle keypoint
-- that holds at the transparent end, compressing the fade into the tail
-- of the axis. falloff == 0 reverts to the classic linear ramp.
local function buildGradientSequence(bottomTransparency: number): NumberSequence
	local topT = Config.GRADIENT_TOP_TRANSPARENCY
	local falloff = Config.GRADIENT_FALLOFF_START or 0
	if falloff <= 0 then
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, topT),
			NumberSequenceKeypoint.new(1, bottomTransparency),
		})
	end
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, topT),
		NumberSequenceKeypoint.new(math.min(falloff, 0.999), topT),
		NumberSequenceKeypoint.new(1, bottomTransparency),
	})
end

function WeaponRolodexBuilder.build(): Handle
	-- Layout (bottom-to-top):
	--   [ dots ]                row below the main card
	--   [ main card  ]          cycles Normal weapons, slides on Tab
	--   [special card]          Special indicator, right-aligned, smaller
	-- Container is anchored bottom-right so the dots stay flush with the
	-- corner and the special card stacks upward from there.

	local specialSize = math.floor(Config.CARD_SIZE * Config.SPECIAL_CARD_SCALE)
	local mainCardY = specialSize + Config.SPECIAL_CARD_SPACING
	local dotRowY = mainCardY + Config.CARD_SIZE + Config.DOT_ROW_OFFSET_Y

	local container = Instance.new("Frame")
	container.Name = "WeaponRolodex"
	container.Size = UDim2.new(0, Config.CARD_SIZE, 0, dotRowY + Config.DOT_SIZE)
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(1, 1)
	container.Position = UDim2.new(1, 0, 1, 0)

	-- Uniform scale — cheap way to dial overall size without touching every
	-- individual dimension / font size / margin in the config.
	local containerScale = Instance.new("UIScale")
	containerScale.Scale = Config.UI_SCALE
	containerScale.Parent = container

	-- Main card — cycles Normal weapons. Background color + UIGradient
	-- produce the fade behind the icon. Corner radius comes from config
	-- as a UDim so a circle (scale 0.5) is as valid as rounded-square.
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.new(0, Config.CARD_SIZE, 0, Config.CARD_SIZE)
	card.Position = UDim2.new(0, 0, 0, mainCardY)
	card.BackgroundColor3 = Config.GRADIENT_COLOR
	card.BackgroundTransparency = 0
	-- ClipsDescendants off so pills anchored at bounding-box corners stay
	-- visible when the card is circular. Icon overflow is harmless — the
	-- weapon render is padded and the corner pixels are transparent anyway.
	card.ClipsDescendants = false
	card.Active = true -- required for touch InputBegan/InputEnded to fire
	card.Parent = container
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = Config.CARD_CORNER_RADIUS
	cardCorner.Parent = card

	local cardGradient = Instance.new("UIGradient")
	cardGradient.Rotation = Config.GRADIENT_ROTATION
	cardGradient.Transparency = buildGradientSequence(Config.GRADIENT_BOTTOM_TRANSPARENCY)
	cardGradient.Parent = card

	-- Icon fills the card
	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "Icon"
	iconImage.Size = UDim2.new(1, 0, 1, 0)
	iconImage.BackgroundTransparency = 1
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.Image = ""
	iconImage.Parent = card
	createCorner(iconImage, Config.ICON_CORNER_RADIUS)

	-- Fallback text (shown when no icon is set) — fills the card
	local iconFallbackName = Instance.new("TextLabel")
	iconFallbackName.Name = "FallbackName"
	iconFallbackName.Size = UDim2.new(1, -12, 1, -12)
	iconFallbackName.Position = UDim2.new(0, 6, 0, 6)
	iconFallbackName.BackgroundTransparency = 1
	iconFallbackName.TextColor3 = Config.AMMO_TEXT_COLOR
	iconFallbackName.Font = Config.AMMO_FONT
	iconFallbackName.TextSize = 14
	iconFallbackName.TextWrapped = true
	iconFallbackName.TextTruncate = Enum.TextTruncate.AtEnd
	iconFallbackName.Text = ""
	iconFallbackName.Visible = false
	iconFallbackName.Parent = card

	-- Slot label pill (top-left overlay)
	local slotPill = Instance.new("Frame")
	slotPill.Name = "SlotPill"
	slotPill.AutomaticSize = Enum.AutomaticSize.XY
	slotPill.Size = UDim2.new(0, 0, 0, 0)
	slotPill.AnchorPoint = Vector2.new(0, 0)
	slotPill.Position = UDim2.new(0, Config.SLOT_LABEL_PILL_MARGIN, 0, Config.SLOT_LABEL_PILL_MARGIN)
	slotPill.BackgroundColor3 = Config.SLOT_LABEL_PILL_BG_COLOR
	slotPill.BackgroundTransparency = Config.SLOT_LABEL_PILL_BG_TRANSPARENCY
	slotPill.BorderSizePixel = 0
	slotPill.Visible = Config.SHOW_SLOT_LABEL
	slotPill.Parent = card
	createCorner(slotPill, Config.SLOT_LABEL_PILL_CORNER_RADIUS)
	createPaddingXY(slotPill, Config.SLOT_LABEL_PILL_PADDING_X, Config.SLOT_LABEL_PILL_PADDING_Y)

	local slotLabel = Instance.new("TextLabel")
	slotLabel.Name = "SlotLabel"
	slotLabel.AutomaticSize = Enum.AutomaticSize.XY
	slotLabel.Size = UDim2.new(0, 0, 0, 0)
	slotLabel.BackgroundTransparency = 1
	slotLabel.TextColor3 = Config.SLOT_LABEL_TEXT_COLOR
	slotLabel.Font = Config.SLOT_LABEL_FONT
	slotLabel.TextSize = Config.SLOT_LABEL_TEXT_SIZE
	slotLabel.Text = ""
	slotLabel.Parent = slotPill

	-- Ammo pill (bottom-right overlay)
	local ammoPill = Instance.new("Frame")
	ammoPill.Name = "AmmoPill"
	ammoPill.AutomaticSize = Enum.AutomaticSize.XY
	ammoPill.Size = UDim2.new(0, 0, 0, 0)
	ammoPill.AnchorPoint = Vector2.new(1, 1)
	ammoPill.Position = UDim2.new(1, -Config.AMMO_PILL_MARGIN_X, 1, -Config.AMMO_PILL_MARGIN_Y)
	ammoPill.BackgroundColor3 = Config.AMMO_PILL_BG_COLOR
	ammoPill.BackgroundTransparency = Config.AMMO_PILL_BG_TRANSPARENCY
	ammoPill.BorderSizePixel = 0
	ammoPill.Visible = false
	ammoPill.Parent = card
	createCorner(ammoPill, Config.AMMO_PILL_CORNER_RADIUS)
	createPaddingXY(ammoPill, Config.AMMO_PILL_PADDING_X, Config.AMMO_PILL_PADDING_Y)

	local ammoLabel = Instance.new("TextLabel")
	ammoLabel.Name = "Ammo"
	ammoLabel.AutomaticSize = Enum.AutomaticSize.XY
	ammoLabel.Size = UDim2.new(0, 0, 0, 0)
	ammoLabel.BackgroundTransparency = 1
	ammoLabel.TextColor3 = Config.AMMO_TEXT_COLOR
	ammoLabel.Font = Config.AMMO_FONT
	ammoLabel.TextSize = Config.AMMO_TEXT_SIZE
	ammoLabel.TextStrokeColor3 = Config.TEXT_STROKE_COLOR
	ammoLabel.TextStrokeTransparency = Config.TEXT_STROKE_TRANSPARENCY
	ammoLabel.Text = ""
	ammoLabel.Parent = ammoPill

	-- Special card — smaller, right-aligned, stacked above the main card.
	-- Mirrors the main card's gradient + icon + fallback layout so the two
	-- read as the same visual language, but doesn't cycle (there's only
	-- ever one Special held) and has no ammo pill (Phase 4B will add a
	-- cooldown overlay in its place).
	local specialCard = Instance.new("Frame")
	specialCard.Name = "SpecialCard"
	specialCard.Size = UDim2.new(0, specialSize, 0, specialSize)
	specialCard.AnchorPoint = Vector2.new(1, 0)
	specialCard.Position = UDim2.new(1, 0, 0, 0)
	specialCard.BackgroundColor3 = Config.GRADIENT_COLOR
	specialCard.BackgroundTransparency = 0
	specialCard.ClipsDescendants = false
	specialCard.Parent = container
	local specialCardCorner = Instance.new("UICorner")
	specialCardCorner.CornerRadius = Config.CARD_CORNER_RADIUS
	specialCardCorner.Parent = specialCard

	local specialGradient = Instance.new("UIGradient")
	specialGradient.Rotation = Config.GRADIENT_ROTATION
	specialGradient.Transparency = buildGradientSequence(Config.SPECIAL_EMPTY_GRADIENT_BOTTOM_TRANSPARENCY)
	specialGradient.Parent = specialCard

	local specialIcon = Instance.new("ImageLabel")
	specialIcon.Name = "Icon"
	specialIcon.Size = UDim2.new(1, 0, 1, 0)
	specialIcon.BackgroundTransparency = 1
	specialIcon.ScaleType = Enum.ScaleType.Fit
	specialIcon.Image = ""
	specialIcon.Visible = false
	specialIcon.Parent = specialCard
	createCorner(specialIcon, Config.ICON_CORNER_RADIUS)

	local specialFallback = Instance.new("TextLabel")
	specialFallback.Name = "FallbackName"
	specialFallback.Size = UDim2.new(1, -12, 1, -12)
	specialFallback.Position = UDim2.new(0, 6, 0, 6)
	specialFallback.BackgroundTransparency = 1
	specialFallback.TextColor3 = Config.EMPTY_TEXT_COLOR
	specialFallback.Font = Config.AMMO_FONT
	specialFallback.TextSize = 12
	specialFallback.TextWrapped = true
	specialFallback.TextTruncate = Enum.TextTruncate.AtEnd
	specialFallback.Text = Config.SPECIAL_EMPTY_TEXT
	specialFallback.Parent = specialCard

	-- Cooldown overlay — dark tint + centered countdown text. Parented last
	-- so it renders on top of the icon. Hidden by default; setSpecialCooldown
	-- flips it on with a remaining-seconds number.
	local cooldownOverlay = Instance.new("Frame")
	cooldownOverlay.Name = "CooldownOverlay"
	cooldownOverlay.Size = UDim2.new(1, 0, 1, 0)
	cooldownOverlay.BackgroundColor3 = Config.COOLDOWN_OVERLAY_COLOR
	cooldownOverlay.BackgroundTransparency = Config.COOLDOWN_OVERLAY_TRANSPARENCY
	cooldownOverlay.BorderSizePixel = 0
	cooldownOverlay.Visible = false
	cooldownOverlay.Parent = specialCard
	local cooldownOverlayCorner = Instance.new("UICorner")
	cooldownOverlayCorner.CornerRadius = Config.CARD_CORNER_RADIUS
	cooldownOverlayCorner.Parent = cooldownOverlay

	local cooldownText = Instance.new("TextLabel")
	cooldownText.Name = "CooldownText"
	cooldownText.Size = UDim2.new(1, 0, 1, 0)
	cooldownText.BackgroundTransparency = 1
	cooldownText.Font = Config.COOLDOWN_TEXT_FONT
	cooldownText.TextColor3 = Config.COOLDOWN_TEXT_COLOR
	cooldownText.TextSize = Config.COOLDOWN_TEXT_SIZE
	cooldownText.TextStrokeColor3 = Config.TEXT_STROKE_COLOR
	cooldownText.TextStrokeTransparency = Config.TEXT_STROKE_TRANSPARENCY
	cooldownText.Text = ""
	cooldownText.Parent = cooldownOverlay

	-- Dot indicator row (below main card)
	local dotRow = Instance.new("Frame")
	dotRow.Name = "DotRow"
	dotRow.Size = UDim2.new(1, 0, 0, Config.DOT_SIZE)
	dotRow.Position = UDim2.new(0, 0, 0, dotRowY)
	dotRow.BackgroundTransparency = 1
	dotRow.Parent = container

	local dotLayout = Instance.new("UIListLayout")
	dotLayout.FillDirection = Enum.FillDirection.Horizontal
	dotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotLayout.Padding = UDim.new(0, Config.DOT_SPACING)
	dotLayout.Parent = dotRow

	-- State for animation
	local currentTween: Tween? = nil

	-- ================================================================
	-- Handle methods
	-- ================================================================
	local handle: Handle = {} :: Handle
	handle.gui = container

	local function applyGradientForActive()
		cardGradient.Transparency = buildGradientSequence(Config.GRADIENT_BOTTOM_TRANSPARENCY)
	end

	local function applyGradientForEmpty()
		cardGradient.Transparency = buildGradientSequence(Config.EMPTY_GRADIENT_BOTTOM_TRANSPARENCY)
	end

	function handle:showWeapon(info: WeaponInfo?, direction: number?)
		if not info then
			-- Empty state: cancel any in-flight slide and reset to rest position
			if currentTween then
				currentTween:Cancel()
				currentTween = nil
			end
			card.Position = UDim2.new(0, 0, 0, 0)
			slotLabel.Text = Config.EMPTY_TEXT
			slotLabel.TextColor3 = Config.EMPTY_TEXT_COLOR
			ammoPill.Visible = false
			iconImage.Image = ""
			iconImage.Visible = false
			iconFallbackName.Visible = false
			applyGradientForEmpty()
			return
		end

		-- Slide animation. Only cancel + replace the tween when a fresh
		-- direction is passed — content-only refreshes (dir == nil) must
		-- not interrupt an in-flight slide, otherwise downstream signals
		-- like tool.Equipped cancel the slide mid-flight and leave the
		-- card frozen off-center.
		local dir = direction or 0
		if dir ~= 0 then
			if currentTween then
				currentTween:Cancel()
				currentTween = nil
			end
			local offsetX = Config.SLIDE_OFFSET_X * dir
			card.Position = UDim2.new(0, offsetX, 0, 0)
			local tween = TweenService:Create(card, TweenInfo.new(
				Config.SLIDE_TWEEN_TIME,
				Config.SLIDE_TWEEN_STYLE,
				Config.SLIDE_TWEEN_DIRECTION
			), { Position = UDim2.new(0, 0, 0, 0) })
			currentTween = tween
			tween:Play()
		end

		-- Slot name (Primary / Secondary / Melee) retired with the loadout-system
		-- migration. Fall back to displayName so if SHOW_SLOT_LABEL is ever
		-- flipped back on, the pill shows something useful.
		slotLabel.Text = string.upper(info.displayName)
		slotLabel.TextColor3 = Config.SLOT_LABEL_TEXT_COLOR
		applyGradientForActive()

		-- Icon or fallback text
		if info.iconAssetId and info.iconAssetId ~= "" then
			iconImage.Image = info.iconAssetId
			iconImage.Visible = true
			iconFallbackName.Visible = false
		else
			iconImage.Image = ""
			iconImage.Visible = false
			iconFallbackName.Text = info.displayName
			iconFallbackName.Visible = true
		end
	end

	function handle:setAmmo(text: string?)
		if typeof(text) == "string" and text ~= "" then
			ammoLabel.Text = text
			ammoPill.Visible = true
		else
			ammoLabel.Text = ""
			ammoPill.Visible = false
		end
	end

	-- Update the Special indicator card. `info == nil` → empty-slot state
	-- (faded gradient + "No Special" placeholder text). Otherwise: show the
	-- special's icon, brighten the gradient to match the main card.
	function handle:setSpecial(info: WeaponInfo?)
		if not info then
			specialIcon.Image = ""
			specialIcon.Visible = false
			specialFallback.Text = Config.SPECIAL_EMPTY_TEXT
			specialFallback.TextColor3 = Config.EMPTY_TEXT_COLOR
			specialFallback.Visible = true
			specialGradient.Transparency = buildGradientSequence(Config.SPECIAL_EMPTY_GRADIENT_BOTTOM_TRANSPARENCY)
			return
		end
		specialGradient.Transparency = buildGradientSequence(Config.GRADIENT_BOTTOM_TRANSPARENCY)
		if info.iconAssetId and info.iconAssetId ~= "" then
			specialIcon.Image = info.iconAssetId
			specialIcon.Visible = true
			specialFallback.Visible = false
		else
			specialIcon.Image = ""
			specialIcon.Visible = false
			specialFallback.Text = info.displayName
			specialFallback.TextColor3 = Config.SLOT_LABEL_TEXT_COLOR
			specialFallback.Visible = true
		end
	end

	-- Drive the Special card's cooldown overlay. Pass seconds remaining to
	-- show the dim + countdown state, or nil to hide. Formatting: "3.2s"
	-- above 1s, "0.8s" below — no integer clamping so the last second still
	-- reads as moving. Values <= 0 hide the overlay.
	function handle:setSpecialCooldown(secondsRemaining: number?)
		if not secondsRemaining or secondsRemaining <= 0 then
			cooldownOverlay.Visible = false
			cooldownText.Text = ""
			return
		end
		cooldownText.Text = string.format("%.1fs", secondsRemaining)
		cooldownOverlay.Visible = true
	end

	function handle:setDots(total: number, activeIndex: number)
		for _, child in dotRow:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		if total <= 1 then
			return
		end

		for i = 1, total do
			local dot = Instance.new("Frame")
			dot.Name = "Dot_" .. i
			dot.Size = UDim2.new(0, Config.DOT_SIZE, 0, Config.DOT_SIZE)
			dot.BackgroundColor3 = if i == activeIndex then Config.DOT_ACTIVE_COLOR else Config.DOT_INACTIVE_COLOR
			dot.BorderSizePixel = 0
			dot.Parent = dotRow
			createCorner(dot, Config.DOT_SIZE / 2)
		end
	end

	function handle:getCardFrame(): Frame
		return card
	end

	function handle:destroy()
		if currentTween then
			currentTween:Cancel()
		end
		container:Destroy()
	end

	return handle
end

return WeaponRolodexBuilder
