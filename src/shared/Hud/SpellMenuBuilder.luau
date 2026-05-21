----------------------------------------------------------------------
-- SpellMenuBuilder
----------------------------------------------------------------------
-- Three spell cast buttons (red / green / blue). Each button contains
-- a layered gradient fill that rises bottom-to-top as mana accumulates,
-- replacing the separate ReservoirBars component.
--
-- Panel layers (back to front):
--   FillBase  — always-visible dim bg (the "empty" container look)
--   FillClip  — clips FillBar to rounded bounds (ClipsDescendants)
--     FillBar — solid gradient, height = energy fraction, animated
--   ColorLabel / SpellLabel — text overlays (ZIndex above fill)
--   TextButton — tap detection (fires castEvent + shows energy popup)
--
-- Returned handle:
--   .gui                 Frame to register with HudLayoutManager
--   .castRequested       RBXScriptSignal<color: string>
--   :setReservoirs(snap) refresh fill height + spell name labels
--   :destroy()           clean up
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Defaults      = require(ReplicatedStorage.Shared.Hud.SpellMenuConfig)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)

export type Snapshot = { red: number, green: number, blue: number }

export type Handle = {
	gui: Frame,
	castRequested: RBXScriptSignal,
	setReservoirs: (self: Handle, snapshot: Snapshot) -> (),
	playAffordBounce: (self: Handle, color: string) -> (),
	playFiredFlash: (self: Handle, color: string) -> (),
	destroy: (self: Handle) -> (),
}

local COLOR_ORDER = { "red", "green", "blue" }

local function lightenColor(c: Color3, amount: number): Color3
	return Color3.fromRGB(
		math.clamp(math.round(c.R * 255 + amount), 0, 255),
		math.clamp(math.round(c.G * 255 + amount), 0, 255),
		math.clamp(math.round(c.B * 255 + amount), 0, 255)
	)
end

local SpellMenuBuilder = {}

function SpellMenuBuilder.build(): Handle
	local container = Instance.new("Frame")
	container.Name = "SpellMenu"
	container.Size = UDim2.new(0, Defaults.BUTTON_WIDTH, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, Defaults.BUTTON_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	local castEvent = Instance.new("BindableEvent")
	castEvent.Name = "SpellMenuCast"

	local panels: { [string]: Frame }    = {}
	local fillBases: { [string]: Frame } = {}
	local fillBars: { [string]: Frame }  = {}
	local spellLabels: { [string]: TextLabel } = {}
	local currentEnergy: { [string]: number }  = { red = 0, green = 0, blue = 0 }

	for i, color in COLOR_ORDER do
		local spec = Defaults.COLORS[color]
		local bgColor = spec.bg
		local lightColor = lightenColor(bgColor, 55)

		-- Outer panel — transparent container so fill layers compose cleanly
		local panel = Instance.new("Frame")
		panel.Name = "Panel_" .. color
		panel.LayoutOrder = i
		panel.Size = UDim2.new(0, Defaults.BUTTON_WIDTH, 0, Defaults.BUTTON_HEIGHT)
		panel.BackgroundTransparency = 1
		panel.BorderSizePixel = 0

		-- FillBase: always-visible dim layer — conveys the "empty" shape
		local fillBase = Instance.new("Frame")
		fillBase.Name = "FillBase"
		fillBase.Size = UDim2.new(1, 0, 1, 0)
		fillBase.BackgroundColor3 = bgColor
		fillBase.BackgroundTransparency = Defaults.FILL_BASE_TRANSPARENCY
		fillBase.BorderSizePixel = 0
		fillBase.ZIndex = 1
		fillBase.Parent = panel

		local baseCorner = Instance.new("UICorner")
		baseCorner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
		baseCorner.Parent = fillBase

		-- FillClip: clips FillBar to the rounded panel shape
		local fillClip = Instance.new("Frame")
		fillClip.Name = "FillClip"
		fillClip.Size = UDim2.new(1, 0, 1, 0)
		fillClip.BackgroundTransparency = 1
		fillClip.BorderSizePixel = 0
		fillClip.ClipsDescendants = true
		fillClip.ZIndex = 2
		fillClip.Parent = panel

		local clipCorner = Instance.new("UICorner")
		clipCorner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
		clipCorner.Parent = fillClip

		-- FillBar: solid gradient anchored to bottom, height tweens with mana
		local fillBar = Instance.new("Frame")
		fillBar.Name = "FillBar"
		fillBar.AnchorPoint = Vector2.new(0, 1)
		fillBar.Position = UDim2.new(0, 0, 1, 0)
		fillBar.Size = UDim2.new(1, 0, 0, 0)
		fillBar.BackgroundColor3 = bgColor
		fillBar.BorderSizePixel = 0
		fillBar.ZIndex = 2
		fillBar.Parent = fillClip

		-- Rotation=270: key 0 = bottom (solid), key 1 = top (lighter)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 270
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, bgColor),
			ColorSequenceKeypoint.new(1, lightColor),
		})
		gradient.Parent = fillBar

		-- Color label: "RED" / "GREEN" / "BLUE"
		local colorLabel = Instance.new("TextLabel")
		colorLabel.Name = "ColorLabel"
		colorLabel.Size = UDim2.new(1, 0, 0, 18)
		colorLabel.Position = UDim2.new(0, 0, 0, 6)
		colorLabel.BackgroundTransparency = 1
		colorLabel.Font = Defaults.LABEL_FONT
		colorLabel.TextSize = Defaults.LABEL_SIZE
		colorLabel.TextColor3 = Defaults.TEXT_COLOR
		colorLabel.TextStrokeTransparency = Defaults.TEXT_STROKE
		colorLabel.Text = spec.label
		colorLabel.TextXAlignment = Enum.TextXAlignment.Center
		colorLabel.ZIndex = 4
		colorLabel.Parent = panel

		-- Spell name label (vertically centered)
		local spellLabel = Instance.new("TextLabel")
		spellLabel.Name = "SpellLabel"
		spellLabel.Size = UDim2.new(1, -4, 0, 18)
		spellLabel.Position = UDim2.new(0, 2, 0.5, -9)
		spellLabel.BackgroundTransparency = 1
		spellLabel.Font = Defaults.SPELL_FONT
		spellLabel.TextSize = Defaults.SPELL_SIZE
		spellLabel.TextColor3 = Defaults.DIM_COLOR
		spellLabel.TextStrokeTransparency = 1
		spellLabel.Text = Defaults.NO_SPELL_TEXT
		spellLabel.TextXAlignment = Enum.TextXAlignment.Center
		spellLabel.TextWrapped = true
		spellLabel.ZIndex = 4
		spellLabel.Parent = panel

		-- TextButton: full-size tap target (highest ZIndex in panel)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 1, 0)
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.ZIndex = 10
		btn.Parent = panel

		local capturedColor = color
		btn.MouseButton1Click:Connect(function()
			local energy = currentEnergy[capturedColor] or 0

			-- Energy popup floats above the button
			local popup = Instance.new("Frame")
			popup.Name = "EnergyPopup"
			popup.AnchorPoint = Vector2.new(0.5, 1)
			popup.Position = UDim2.new(0.5, 0, 0, -4)
			popup.Size = UDim2.new(0, 72, 0, 22)
			popup.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
			popup.BackgroundTransparency = 0.15
			popup.BorderSizePixel = 0
			popup.ZIndex = 20
			popup.Parent = panel

			local popupCorner = Instance.new("UICorner")
			popupCorner.CornerRadius = UDim.new(0, 4)
			popupCorner.Parent = popup

			local popupLabel = Instance.new("TextLabel")
			popupLabel.Size = UDim2.new(1, 0, 1, 0)
			popupLabel.BackgroundTransparency = 1
			popupLabel.Font = Defaults.POPUP_FONT
			popupLabel.TextSize = Defaults.POPUP_SIZE
			popupLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			popupLabel.Text = string.format("%d / %d", energy, Defaults.FILL_MAX)
			popupLabel.TextXAlignment = Enum.TextXAlignment.Center
			popupLabel.ZIndex = 21
			popupLabel.Parent = popup

			task.delay(Defaults.POPUP_DURATION, function()
				if not popup.Parent then return end
				local fadeFrame = TweenService:Create(popup, Defaults.POPUP_FADE_TWEEN, { BackgroundTransparency = 1 })
				local fadeText = TweenService:Create(popupLabel, Defaults.POPUP_FADE_TWEEN, { TextTransparency = 1 })
				fadeFrame:Play()
				fadeText:Play()
				fadeFrame.Completed:Connect(function()
					if popup.Parent then popup:Destroy() end
				end)
			end)

			castEvent:Fire(capturedColor)
		end)

		panel.Parent = container
		panels[color]     = panel
		fillBases[color]  = fillBase
		fillBars[color]   = fillBar
		spellLabels[color] = spellLabel
	end

	local handle = {
		gui           = container,
		castRequested = castEvent.Event,
	} :: Handle

	local wasAffordable: { [string]: boolean } = { red = false, green = false, blue = false }
	local vfxTweens: { Tween } = {}

	function handle:setReservoirs(snapshot: Snapshot)
		for _, color in COLOR_ORDER do
			local energy = (snapshot :: any)[color] or 0
			currentEnergy[color] = energy

			local fraction = math.clamp(energy / Defaults.FILL_MAX, 0, 1)
			local fillTween = TweenService:Create(fillBars[color], Defaults.FILL_TWEEN, {
				Size = UDim2.new(1, 0, fraction, 0),
			})
			fillTween:Play()
			table.insert(vfxTweens, fillTween)

			local affordable = SpellRegistry.listAffordableSpells(
				color :: SpellRegistry.Color,
				energy
			)
			local canCast = #affordable > 0
			local topSpell = if canCast then affordable[#affordable] else nil

			if canCast and not wasAffordable[color] then
				handle:playAffordBounce(color)
			end
			wasAffordable[color] = canCast

			spellLabels[color].Text = if topSpell then topSpell.name else Defaults.NO_SPELL_TEXT
			spellLabels[color].TextColor3 = if canCast then Defaults.TEXT_COLOR else Defaults.DIM_COLOR
		end
	end

	function handle:playAffordBounce(color: string)
		local panel = panels[color]
		local scaleInst = panel:FindFirstChildOfClass("UIScale")
		if not scaleInst then
			scaleInst = Instance.new("UIScale")
			scaleInst.Parent = panel
		end
		scaleInst.Scale = 1
		local t1 = TweenService:Create(scaleInst, Defaults.AFFORD_BOUNCE_TWEEN, { Scale = Defaults.AFFORD_BOUNCE_SCALE })
		t1:Play()
		table.insert(vfxTweens, t1)
		t1.Completed:Connect(function(status: Enum.TweenStatus)
			if status == Enum.TweenStatus.Cancelled then return end
			if not scaleInst.Parent then return end
			local t2 = TweenService:Create(scaleInst, Defaults.AFFORD_BOUNCE_TWEEN, { Scale = 1 })
			t2:Play()
			table.insert(vfxTweens, t2)
		end)
	end

	function handle:playFiredFlash(color: string)
		local panel = panels[color]
		local base = fillBases[color]

		-- White flash overlay
		local overlay = Instance.new("Frame")
		overlay.Name = "FiredFlash"
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		overlay.BackgroundTransparency = 0
		overlay.BorderSizePixel = 0
		overlay.ZIndex = panel.ZIndex + 5
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
		corner.Parent = overlay
		overlay.Parent = panel
		local flashTween = TweenService:Create(overlay, Defaults.FIRED_FLASH_TWEEN, { BackgroundTransparency = 1 })
		flashTween:Play()
		table.insert(vfxTweens, flashTween)
		flashTween.Completed:Connect(function()
			if overlay.Parent then overlay:Destroy() end
		end)

		-- Dim the FillBase briefly then recover (replaces old BackgroundColor3 tween)
		local origTransp = base.BackgroundTransparency
		local dimTween = TweenService:Create(base, Defaults.FIRED_DIM_TWEEN, { BackgroundTransparency = 0.05 })
		dimTween:Play()
		table.insert(vfxTweens, dimTween)
		dimTween.Completed:Connect(function(status: Enum.TweenStatus)
			if status == Enum.TweenStatus.Cancelled then return end
			if not base.Parent then return end
			local recoverTween = TweenService:Create(base, Defaults.FIRED_DIM_TWEEN, { BackgroundTransparency = origTransp })
			recoverTween:Play()
			table.insert(vfxTweens, recoverTween)
		end)
	end

	function handle:destroy()
		for _, t in vfxTweens do
			t:Cancel()
		end
		table.clear(vfxTweens)
		castEvent:Destroy()
		container:Destroy()
	end

	return handle
end

return SpellMenuBuilder
