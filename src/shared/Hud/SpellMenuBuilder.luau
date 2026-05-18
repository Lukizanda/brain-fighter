----------------------------------------------------------------------
-- SpellMenuBuilder
----------------------------------------------------------------------
-- Three-button spell cast panel (red / green / blue). Each button
-- shows the highest affordable spell and current energy. Tap fires
-- `castRequested` with the color; the client script owns the
-- CastAction call so it can supply the live caster reference.
--
-- Returned handle:
--   .gui                 Frame to register with HudLayoutManager
--   .castRequested       RBXScriptSignal<color: string>
--   :setReservoirs(snap) refresh affordability + spell name labels
--   :destroy()           clean up
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Defaults       = require(ReplicatedStorage.Shared.Hud.SpellMenuConfig)
local SpellRegistry  = require(ReplicatedStorage.Shared.SpellRegistry)

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

local SpellMenuBuilder = {}

function SpellMenuBuilder.build(): Handle
	local container = Instance.new("Frame")
	container.Name = "SpellMenu"
	container.Size = UDim2.new(0, 0, 0, Defaults.BUTTON_HEIGHT)
	container.AutomaticSize = Enum.AutomaticSize.X
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, Defaults.BUTTON_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	local castEvent = Instance.new("BindableEvent")
	castEvent.Name = "SpellMenuCast"

	-- Per-color UI references
	local panels: { [string]: Frame }        = {}
	local spellLabels: { [string]: TextLabel } = {}
	local costLabels: { [string]: TextLabel }  = {}

	for i, color in COLOR_ORDER do
		local spec = Defaults.COLORS[color]

		local panel = Instance.new("Frame")
		panel.Name = "Panel_" .. color
		panel.LayoutOrder = i
		panel.Size = UDim2.new(0, Defaults.BUTTON_WIDTH, 0, Defaults.BUTTON_HEIGHT)
		panel.BackgroundColor3 = spec.bg
		panel.BackgroundTransparency = Defaults.DISABLED_TRANSPARENCY
		panel.BorderSizePixel = 0

		local panelCorner = Instance.new("UICorner")
		panelCorner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
		panelCorner.Parent = panel

		-- Invisible TextButton covering the whole panel for tap detection
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 1, 0)
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.Parent = panel

		local capturedColor = color
		btn.MouseButton1Click:Connect(function()
			castEvent:Fire(capturedColor)
		end)

		-- Color label (top)
		local colorLabel = Instance.new("TextLabel")
		colorLabel.Name = "ColorLabel"
		colorLabel.Size = UDim2.new(1, 0, 0, 16)
		colorLabel.Position = UDim2.new(0, 0, 0, 4)
		colorLabel.BackgroundTransparency = 1
		colorLabel.Font = Defaults.LABEL_FONT
		colorLabel.TextSize = Defaults.LABEL_SIZE
		colorLabel.TextColor3 = Defaults.TEXT_COLOR
		colorLabel.TextStrokeTransparency = Defaults.TEXT_STROKE
		colorLabel.Text = spec.label
		colorLabel.TextXAlignment = Enum.TextXAlignment.Center
		colorLabel.Parent = panel

		-- Spell name label (middle)
		local spellLabel = Instance.new("TextLabel")
		spellLabel.Name = "SpellLabel"
		spellLabel.Size = UDim2.new(1, -4, 0, 16)
		spellLabel.Position = UDim2.new(0, 2, 0, 22)
		spellLabel.BackgroundTransparency = 1
		spellLabel.Font = Defaults.SPELL_FONT
		spellLabel.TextSize = Defaults.SPELL_SIZE
		spellLabel.TextColor3 = Defaults.DIM_COLOR
		spellLabel.TextStrokeTransparency = 1
		spellLabel.Text = Defaults.NO_SPELL_TEXT
		spellLabel.TextXAlignment = Enum.TextXAlignment.Center
		spellLabel.TextWrapped = true
		spellLabel.Parent = panel

		-- Cost/energy label (bottom)
		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "CostLabel"
		costLabel.Size = UDim2.new(1, 0, 0, 14)
		costLabel.Position = UDim2.new(0, 0, 1, -16)
		costLabel.BackgroundTransparency = 1
		costLabel.Font = Defaults.COST_FONT
		costLabel.TextSize = Defaults.COST_SIZE
		costLabel.TextColor3 = Defaults.DIM_COLOR
		costLabel.TextStrokeTransparency = 1
		costLabel.Text = "0 / 160"
		costLabel.TextXAlignment = Enum.TextXAlignment.Center
		costLabel.Parent = panel

		panel.Parent = container
		panels[color] = panel
		spellLabels[color] = spellLabel
		costLabels[color] = costLabel
	end

	local handle = {
		gui          = container,
		castRequested = castEvent.Event,
	} :: Handle

	local wasAffordable: { [string]: boolean } = { red = false, green = false, blue = false }
	local vfxTweens: { Tween } = {}

	function handle:setReservoirs(snapshot: Snapshot)
		for _, color in COLOR_ORDER do
			local energy = (snapshot :: any)[color] or 0
			local affordable = SpellRegistry.listAffordableSpells(
				color :: SpellRegistry.Color,
				energy
			)
			local canCast = #affordable > 0
			local topSpell = if canCast then affordable[#affordable] else nil

			if canCast then
				if not wasAffordable[color] then
					handle:playAffordBounce(color)
				else
					panels[color].BackgroundTransparency = Defaults.ACTIVE_TRANSPARENCY
				end
			else
				panels[color].BackgroundTransparency = Defaults.DISABLED_TRANSPARENCY
			end
			wasAffordable[color] = canCast

			spellLabels[color].Text = if topSpell
				then topSpell.name
				else Defaults.NO_SPELL_TEXT
			spellLabels[color].TextColor3 = if canCast
				then Defaults.TEXT_COLOR
				else Defaults.DIM_COLOR

			costLabels[color].Text = string.format("%d", energy)
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
		local t3 = TweenService:Create(panel, Defaults.AFFORD_BOUNCE_TWEEN, {
			BackgroundTransparency = Defaults.ACTIVE_TRANSPARENCY,
		})
		t3:Play()
		table.insert(vfxTweens, t3)
	end

	function handle:playFiredFlash(color: string)
		local panel = panels[color]
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
		local origColor = panel.BackgroundColor3
		local dimTween = TweenService:Create(panel, Defaults.FIRED_DIM_TWEEN, { BackgroundColor3 = Defaults.FIRED_DIM_COLOR })
		dimTween:Play()
		table.insert(vfxTweens, dimTween)
		dimTween.Completed:Connect(function(status: Enum.TweenStatus)
			if status == Enum.TweenStatus.Cancelled then return end
			if not panel.Parent then return end
			local recoverTween = TweenService:Create(panel, Defaults.FIRED_DIM_TWEEN, { BackgroundColor3 = origColor })
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
