----------------------------------------------------------------------
-- SpellMenuBuilder
----------------------------------------------------------------------
-- Three spell cast panels (red / green / blue). Each panel contains a
-- layered fill that rises bottom-to-top as mana accumulates, hard notches
-- at the four tier thresholds, and a persistent mana numeral.
--
-- **The gesture is press → hold → release** (Phase 5.8, hold-to-charge;
-- see wiki/systems/ChargeCast.md). Press a panel and the charge starts at
-- T1; keeping it down climbs through the tiers you can afford; release
-- fires whatever you reached. Release off the panel cancels for free.
-- This replaces the tap-fires-highest-affordable button, which gave the
-- player no way to pick a tier at all.
--
-- Nothing is drained while the charge is held — the reserve band and the
-- counting-down numeral are a *promise*, not a debit. CastAction drains
-- exactly one tier cost on release, so cancelling costs nothing and there
-- is no refund path to get wrong.
--
-- Panel layers (back to front):
--   FillBase  — always-visible dim bg (the "empty" container look)
--   FillClip  — clips the fill stack to rounded bounds (ClipsDescendants)
--     FillBar       — solid colour + neutral ramp, height = energy fraction
--     ChargeReserve — the slice of the fill this release will spend
--     Notch_tN      — hard line at TIER_COSTS[n] / FILL_MAX
--   CeilingPulse — overlay that breathes at the affordability ceiling
--   ColorLabel / SpellLabel / Numeral — text overlays
--   TextButton — press detection (highest ZIndex in the panel)
--
-- Returned handle:
--   .gui                 Frame to register with HudLayoutManager
--   .chargeStarted       RBXScriptSignal<color>
--   .chargeTierChanged   RBXScriptSignal<color, tier>
--   .chargeProgress      RBXScriptSignal<color, tier, alpha>
--   .castRequested       RBXScriptSignal<color, tier>
--   .chargeCancelled     RBXScriptSignal<color>
--   :setReservoirs(snap)                refresh fill, notches, numeral
--   :setChargeAffordability(color, max) where the charge ceiling sits
--   :playAffordBounce(color) / :playFiredFlash(color)
--   :destroy()
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local Defaults      = require(ReplicatedStorage.Shared.Hud.SpellMenuConfig)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)

export type Snapshot = { red: number, green: number, blue: number }

export type Handle = {
	gui: Frame,
	chargeStarted: RBXScriptSignal,
	chargeTierChanged: RBXScriptSignal,
	chargeProgress: RBXScriptSignal,
	castRequested: RBXScriptSignal,
	chargeCancelled: RBXScriptSignal,
	setReservoirs: (self: Handle, snapshot: Snapshot) -> (),
	setChargeAffordability: (self: Handle, color: string, maxTier: number) -> (),
	playAffordBounce: (self: Handle, color: string) -> (),
	playFiredFlash: (self: Handle, color: string) -> (),
	destroy: (self: Handle) -> (),
}

local COLOR_ORDER = { "red", "green", "blue" }

-- ZIndex ladder, written down because it has to hold under BOTH
-- ZIndexBehavior settings: Sibling (children compare within a parent) and
-- the legacy Global (every number compares against every other). The
-- values are chosen so the intended stacking survives either reading.
local Z_FILL_BASE    = 1
local Z_FILL_CLIP    = 2
local Z_FILL_BAR     = 2
local Z_RESERVE      = 3
local Z_NOTCH        = 4
local Z_CEILING      = 5
local Z_TEXT         = 6
local Z_BUTTON       = 10

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

	local chargeStartedEvent   = Instance.new("BindableEvent")
	local chargeTierEvent      = Instance.new("BindableEvent")
	local chargeProgressEvent  = Instance.new("BindableEvent")
	local castEvent            = Instance.new("BindableEvent")
	local chargeCancelledEvent = Instance.new("BindableEvent")
	chargeStartedEvent.Name   = "SpellMenuChargeStarted"
	chargeTierEvent.Name      = "SpellMenuChargeTierChanged"
	chargeProgressEvent.Name  = "SpellMenuChargeProgress"
	castEvent.Name            = "SpellMenuCast"
	chargeCancelledEvent.Name = "SpellMenuChargeCancelled"

	local panels: { [string]: Frame }        = {}
	local fillBases: { [string]: Frame }     = {}
	local fillBars: { [string]: Frame }      = {}
	local reserveBands: { [string]: Frame }  = {}
	local ceilingOverlays: { [string]: Frame } = {}
	local notches: { [string]: { Frame } }   = {}
	local spellLabels: { [string]: TextLabel } = {}
	local numerals: { [string]: TextLabel }  = {}
	local litColors: { [string]: Color3 }    = {}

	local currentEnergy: { [string]: number } = { red = 0, green = 0, blue = 0 }
	-- Highest tier this reservoir can pay for right now. 0 = below T1.
	local chargeCeiling: { [string]: number } = { red = 0, green = 0, blue = 0 }

	-- The two halves of "saturate at castable". A panel holding less than a
	-- T1 cast is drained toward grey; the moment T1 becomes affordable it
	-- snaps back to full colour. Both read litColors, which the build loop
	-- below fills in, so these must not be called before it runs.
	local function barColorFor(color: string, canCast: boolean): Color3
		local lit = litColors[color]
		return if canCast then lit else lit:Lerp(Defaults.DESATURATED_GREY, Defaults.DESATURATED_BLEND)
	end

	local function baseColorFor(color: string, canCast: boolean): Color3
		local bg = Defaults.COLORS[color].bg
		return if canCast then bg else bg:Lerp(Defaults.DESATURATED_GREY, Defaults.DESATURATED_BLEND)
	end

	for i, color in COLOR_ORDER do
		local spec = Defaults.COLORS[color]
		local bgColor = spec.bg
		-- BackgroundColor3 carries the whole hue now; the gradient below is
		-- a neutral ramp over it. See SpellMenuConfig.FILL_GRADIENT_* for
		-- why the colour had to come out of the ColorSequence.
		local litColor = lightenColor(bgColor, 55)
		litColors[color] = litColor

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
		-- Built drained, because every reservoir starts empty and the edge
		-- detector in setReservoirs only fires on a *change*. Building
		-- saturated would leave three fully-coloured panels that cannot cast
		-- anything until the first word is memorized.
		fillBase.BackgroundColor3 = bgColor:Lerp(Defaults.DESATURATED_GREY, Defaults.DESATURATED_BLEND)
		fillBase.BackgroundTransparency = Defaults.FILL_BASE_TRANSPARENCY
		fillBase.BorderSizePixel = 0
		fillBase.ZIndex = Z_FILL_BASE
		fillBase.Parent = panel

		local baseCorner = Instance.new("UICorner")
		baseCorner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
		baseCorner.Parent = fillBase

		-- FillClip: clips the fill stack to the rounded panel shape
		local fillClip = Instance.new("Frame")
		fillClip.Name = "FillClip"
		fillClip.Size = UDim2.new(1, 0, 1, 0)
		fillClip.BackgroundTransparency = 1
		fillClip.BorderSizePixel = 0
		fillClip.ClipsDescendants = true
		fillClip.ZIndex = Z_FILL_CLIP
		fillClip.Parent = panel

		local clipCorner = Instance.new("UICorner")
		clipCorner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
		clipCorner.Parent = fillClip

		-- FillBar: solid colour anchored to bottom, height tweens with mana
		local fillBar = Instance.new("Frame")
		fillBar.Name = "FillBar"
		fillBar.AnchorPoint = Vector2.new(0, 1)
		fillBar.Position = UDim2.new(0, 0, 1, 0)
		fillBar.Size = UDim2.new(1, 0, 0, 0)
		fillBar.BackgroundColor3 = litColor:Lerp(Defaults.DESATURATED_GREY, Defaults.DESATURATED_BLEND)
		fillBar.BorderSizePixel = 0
		fillBar.ZIndex = Z_FILL_BAR
		fillBar.Parent = fillClip

		-- Rotation=270: key 0 = bottom (darkened), key 1 = top (untouched).
		-- Neutral tints only — a UIGradient multiplies its parent's
		-- BackgroundColor3, so leaving hue out of it here is what lets the
		-- desaturation below be one tween.
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 270
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Defaults.FILL_GRADIENT_BOTTOM_TINT),
			ColorSequenceKeypoint.new(1, Defaults.FILL_GRADIENT_TOP_TINT),
		})
		gradient.Parent = fillBar

		-- ChargeReserve: the top slice of the fill that this release will
		-- spend. Sibling of FillBar rather than a child of it, so its height
		-- is a fraction of the *panel* and matches the notch scale directly.
		local reserve = Instance.new("Frame")
		reserve.Name = "ChargeReserve"
		reserve.AnchorPoint = Vector2.new(0, 0)
		reserve.Position = UDim2.new(0, 0, 1, 0)
		reserve.Size = UDim2.new(1, 0, 0, 0)
		reserve.BackgroundColor3 = Defaults.CHARGE_RESERVE_COLOR
		reserve.BackgroundTransparency = Defaults.CHARGE_RESERVE_TRANSPARENCY
		reserve.BorderSizePixel = 0
		reserve.Visible = false
		reserve.ZIndex = Z_RESERVE
		reserve.Parent = fillClip

		-- Tier notches. Red is the only school with a T4, so the count comes
		-- from the registry rather than from NUM_TIERS — a fourth line on
		-- green would mark a spell that does not exist.
		local colorNotches: { Frame } = {}
		for tier = 1, SpellRegistry.tierCount(color :: SpellRegistry.Color) do
			local frac = SpellRegistry.TIER_COSTS[tier] / Defaults.FILL_MAX
			local notch = Instance.new("Frame")
			notch.Name = string.format("Notch_t%d", tier)
			notch.AnchorPoint = Vector2.new(0, 0.5)
			notch.Position = UDim2.new(0, 0, 1 - frac, 0)
			notch.Size = UDim2.new(1, 0, 0, Defaults.NOTCH_THICKNESS)
			notch.BackgroundColor3 = Defaults.NOTCH_COLOR
			notch.BackgroundTransparency = Defaults.NOTCH_TRANSPARENCY
			notch.BorderSizePixel = 0
			notch.ZIndex = Z_NOTCH
			notch.Parent = fillClip
			colorNotches[tier] = notch
		end
		notches[color] = colorNotches

		-- CeilingPulse: breathes when a held charge has topped out.
		local ceiling = Instance.new("Frame")
		ceiling.Name = "CeilingPulse"
		ceiling.Size = UDim2.new(1, 0, 1, 0)
		ceiling.BackgroundColor3 = Defaults.CHARGE_CEILING_PULSE_COLOR
		ceiling.BackgroundTransparency = 1
		ceiling.BorderSizePixel = 0
		ceiling.Visible = false
		ceiling.ZIndex = Z_CEILING
		ceiling.Parent = panel

		local ceilingCorner = Instance.new("UICorner")
		ceilingCorner.CornerRadius = UDim.new(0, Defaults.CORNER_RADIUS)
		ceilingCorner.Parent = ceiling

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
		colorLabel.ZIndex = Z_TEXT
		colorLabel.Parent = panel

		-- Persistent mana numeral, top-right. Replaces the tap-triggered
		-- EnergyPopup: a hold has to show what it is about to spend *while*
		-- the player decides, not after they have committed.
		local numeral = Instance.new("TextLabel")
		numeral.Name = "Numeral"
		numeral.AnchorPoint = Vector2.new(1, 0)
		numeral.Position = UDim2.new(1, -Defaults.NUMERAL_INSET, 0, Defaults.NUMERAL_INSET)
		numeral.Size = UDim2.new(1, -Defaults.NUMERAL_INSET * 2, 0, Defaults.NUMERAL_HEIGHT)
		numeral.BackgroundTransparency = 1
		numeral.Font = Defaults.NUMERAL_FONT
		numeral.TextSize = Defaults.NUMERAL_SIZE
		numeral.TextColor3 = Defaults.NUMERAL_DIM_COLOR
		numeral.TextStrokeTransparency = Defaults.NUMERAL_STROKE
		numeral.TextXAlignment = Enum.TextXAlignment.Right
		numeral.Text = string.format("0/%d", Defaults.FILL_MAX)
		numeral.ZIndex = Z_TEXT
		numeral.Parent = panel

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
		spellLabel.ZIndex = Z_TEXT
		spellLabel.Parent = panel

		-- TextButton: full-size press target (highest ZIndex in panel)
		local btn = Instance.new("TextButton")
		btn.Name = "PressTarget"
		btn.Size = UDim2.new(1, 0, 1, 0)
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.ZIndex = Z_BUTTON
		btn.Parent = panel

		panel.Parent = container
		panels[color]       = panel
		fillBases[color]    = fillBase
		fillBars[color]     = fillBar
		reserveBands[color] = reserve
		ceilingOverlays[color] = ceiling
		spellLabels[color]  = spellLabel
		numerals[color]     = numeral
	end

	local handle = {
		gui               = container,
		chargeStarted     = chargeStartedEvent.Event,
		chargeTierChanged = chargeTierEvent.Event,
		chargeProgress    = chargeProgressEvent.Event,
		castRequested     = castEvent.Event,
		chargeCancelled   = chargeCancelledEvent.Event,
	} :: Handle

	local wasAffordable: { [string]: boolean } = { red = false, green = false, blue = false }
	local vfxTweens: { Tween } = {}
	local connections: { RBXScriptConnection } = {}
	local ceilingTweens: { [string]: Tween } = {}

	------------------------------------------------------------------
	-- Charge visuals
	------------------------------------------------------------------

	local function pendingCostFor(tier: number): number
		return if tier >= 1 then SpellRegistry.TIER_COSTS[tier] else 0
	end

	local function refreshNumeral(color: string, pendingCost: number)
		local energy = currentEnergy[color] or 0
		local remaining = math.max(energy - pendingCost, 0)
		local numeral = numerals[color]
		numeral.Text = string.format("%d/%d", remaining, Defaults.FILL_MAX)
		numeral.TextColor3 = if pendingCost > 0
			then Defaults.NUMERAL_RESERVED_COLOR
			elseif wasAffordable[color] then Defaults.NUMERAL_COLOR
			else Defaults.NUMERAL_DIM_COLOR
	end

	local function refreshReserve(color: string, pendingCost: number, tweenInfo: TweenInfo)
		local band = reserveBands[color]
		local energy = currentEnergy[color] or 0
		local energyFrac = math.clamp(energy / Defaults.FILL_MAX, 0, 1)
		local reserveFrac = math.clamp(pendingCost / Defaults.FILL_MAX, 0, energyFrac)

		if reserveFrac <= 0 then
			-- Snap the position too: a band tweening to zero height from the
			-- wrong Y reads as the mana sliding sideways out of the bar.
			band.Position = UDim2.new(0, 0, 1 - energyFrac, 0)
			local t = TweenService:Create(band, tweenInfo, { Size = UDim2.new(1, 0, 0, 0) })
			t:Play()
			table.insert(vfxTweens, t)
			band.Visible = false
			return
		end

		band.Visible = true
		band.Position = UDim2.new(0, 0, 1 - energyFrac, 0)
		local t = TweenService:Create(band, tweenInfo, { Size = UDim2.new(1, 0, reserveFrac, 0) })
		t:Play()
		table.insert(vfxTweens, t)
	end

	local function refreshNotches(color: string, activeTier: number)
		for tier, notch in notches[color] do
			local isActive = tier == activeTier
			local t = TweenService:Create(notch, Defaults.NOTCH_TWEEN, {
				BackgroundTransparency = if isActive
					then Defaults.NOTCH_ACTIVE_TRANSPARENCY
					else Defaults.NOTCH_TRANSPARENCY,
				Size = UDim2.new(1, 0, 0, if isActive
					then Defaults.NOTCH_THICKNESS_ACTIVE
					else Defaults.NOTCH_THICKNESS),
			})
			t:Play()
			table.insert(vfxTweens, t)
		end
	end

	local function stopCeilingPulse(color: string)
		local existing = ceilingTweens[color]
		if existing then
			existing:Cancel()
			ceilingTweens[color] = nil
		end
		local overlay = ceilingOverlays[color]
		overlay.BackgroundTransparency = 1
		overlay.Visible = false
	end

	local function startCeilingPulse(color: string)
		if ceilingTweens[color] then return end
		local overlay = ceilingOverlays[color]
		overlay.Visible = true
		overlay.BackgroundTransparency = Defaults.CHARGE_CEILING_PULSE_MIN
		local t = TweenService:Create(overlay, Defaults.CHARGE_CEILING_PULSE_TWEEN, {
			BackgroundTransparency = Defaults.CHARGE_CEILING_PULSE_MAX,
		})
		t:Play()
		ceilingTweens[color] = t
	end

	------------------------------------------------------------------
	-- Charge state machine
	------------------------------------------------------------------
	-- One press at a time by construction: a second colour cannot be
	-- charged while the first is held, which keeps "release fires what I
	-- was charging" true even on a multi-touch screen.

	type Press = {
		color: string,
		startClock: number,
		tier: number,
		-- False while the panel could not afford even T1 at press time. The
		-- press is still tracked so the release can fizzle, but no charge
		-- has started and no orb should be raised.
		started: boolean,
	}

	local press: Press? = nil
	local heartbeatConn: RBXScriptConnection? = nil

	local function applyChargeVisual(color: string, tier: number)
		local pendingCost = pendingCostFor(tier)
		refreshReserve(color, pendingCost, Defaults.CHARGE_RESERVE_TWEEN)
		refreshNumeral(color, pendingCost)
		refreshNotches(color, tier)
		if tier >= 1 and tier >= chargeCeiling[color] then
			startCeilingPulse(color)
		else
			stopCeilingPulse(color)
		end
	end

	local function clearChargeVisual(color: string)
		refreshReserve(color, 0, Defaults.CHARGE_RELEASE_TWEEN)
		refreshNumeral(color, 0)
		refreshNotches(color, 0)
		stopCeilingPulse(color)
	end

	-- Highest tier reachable right now, and how far along the climb to the
	-- next one we are. Mirrors CastAction.resolveSpecAtCharge — the builder
	-- cannot require CastAction (it would drag EnergyReservoirs and
	-- SpellExecutor into the HUD), so both read the same two registry
	-- functions rather than one reimplementing the other's arithmetic.
	local function tierAtHold(color: string, heldSec: number): (number, number)
		local ceiling = chargeCeiling[color] or 0
		local tier = 0
		for t = 1, ceiling do
			if SpellRegistry.chargeTimeFor(t) <= heldSec then
				tier = t
			else
				break
			end
		end
		if tier >= ceiling then
			return tier, 1
		end
		local from = SpellRegistry.chargeTimeFor(math.max(tier, 1))
		local to = SpellRegistry.chargeTimeFor(tier + 1)
		local span = to - from
		local alpha = if span > 0 then math.clamp((heldSec - from) / span, 0, 1) else 1
		return tier, alpha
	end

	local function evaluateCharge()
		local p = press
		if not p then return end

		local heldSec = os.clock() - p.startClock
		local tier, alpha = tierAtHold(p.color, heldSec)

		-- A charge can begin late: memorizing a word mid-press can lift a
		-- dead panel over T1, and the natural reading of that is that the
		-- charge starts then rather than that the press was wasted.
		if not p.started and tier >= 1 then
			p.started = true
			chargeStartedEvent:Fire(p.color)
		end

		if tier ~= p.tier then
			p.tier = tier
			applyChargeVisual(p.color, tier)
			chargeTierEvent:Fire(p.color, tier)
		end

		if p.started then
			chargeProgressEvent:Fire(p.color, tier, alpha)
		end
	end

	local function stopHeartbeat()
		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
	end

	local function beginPress(color: string)
		if press then return end
		press = { color = color, startClock = os.clock(), tier = 0, started = false }
		stopHeartbeat()
		heartbeatConn = RunService.Heartbeat:Connect(evaluateCharge)
		-- Evaluate on the press frame, not on the next Heartbeat: T1's charge
		-- time is zero, so a tap has to resolve immediately or a fast click
		-- would release before the first tick and fizzle.
		evaluateCharge()
	end

	local function isOverPanel(color: string, screenPos: Vector2): boolean
		local panel = panels[color]
		if not panel or not panel.Parent then return false end
		local ap = panel.AbsolutePosition
		local as = panel.AbsoluteSize
		return screenPos.X >= ap.X
			and screenPos.X <= ap.X + as.X
			and screenPos.Y >= ap.Y
			and screenPos.Y <= ap.Y + as.Y
	end

	local function endPress(screenPos: Vector2)
		local p = press
		if not p then return end
		press = nil
		stopHeartbeat()

		local color = p.color
		clearChargeVisual(color)

		if p.tier >= 1 and isOverPanel(color, screenPos) then
			castEvent:Fire(color, p.tier)
		else
			-- Both cancel paths land here: dragged off the panel, and never
			-- reached T1 at all. The HUD fizzles either way, and nothing was
			-- drained, so there is nothing to give back.
			chargeCancelledEvent:Fire(color)
		end
	end

	for _, color in COLOR_ORDER do
		local capturedColor = color
		local btn = panels[color]:FindFirstChild("PressTarget") :: TextButton
		table.insert(connections, btn.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			beginPress(capturedColor)
		end))
	end

	-- Release is global rather than per-button, because the whole point of
	-- release-outside-to-cancel is that the pointer has left the button by
	-- then and its own InputEnded would never fire.
	--
	-- Safe against BlockTapController: that script pops a block on
	-- InputBegan, not on release, and the *press* that starts a charge lands
	-- on a TextButton and so arrives there with gameProcessedEvent = true.
	-- A cancelled charge therefore cannot pop the block behind the HUD.
	table.insert(connections, UserInputService.InputEnded:Connect(function(input: InputObject)
		if press == nil then return end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		endPress(Vector2.new(input.Position.X, input.Position.Y))
	end))

	------------------------------------------------------------------
	-- Public API
	------------------------------------------------------------------

	function handle:setChargeAffordability(color: string, maxTier: number)
		chargeCeiling[color] = math.clamp(maxTier, 0, SpellRegistry.tierCount(color :: SpellRegistry.Color))
	end

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

			handle:setChargeAffordability(color, if topSpell then topSpell.tier else 0)

			if canCast ~= wasAffordable[color] then
				-- One edge flag drives both the bounce and the grey→saturated
				-- flip, deliberately: a second detector for the colour change
				-- would be one more thing to get out of step with the bounce.
				wasAffordable[color] = canCast
				if canCast then
					handle:playAffordBounce(color)
				end
				local barTween = TweenService:Create(fillBars[color], Defaults.DESATURATED_TWEEN, {
					BackgroundColor3 = barColorFor(color, canCast),
				})
				local baseTween = TweenService:Create(fillBases[color], Defaults.DESATURATED_TWEEN, {
					BackgroundColor3 = baseColorFor(color, canCast),
				})
				barTween:Play()
				baseTween:Play()
				table.insert(vfxTweens, barTween)
				table.insert(vfxTweens, baseTween)
			end

			spellLabels[color].Text = if topSpell then topSpell.name else Defaults.NO_SPELL_TEXT
			spellLabels[color].TextColor3 = if canCast then Defaults.TEXT_COLOR else Defaults.DIM_COLOR

			-- Keep the numeral and the reserve band honest against the new
			-- energy, including for a colour being held right now.
			local pendingCost = if press and press.color == color then pendingCostFor(press.tier) else 0
			refreshNumeral(color, pendingCost)
			refreshReserve(color, pendingCost, Defaults.FILL_TWEEN)
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
		-- TweenService's Completed fires with Enum.PlaybackState, not the
		-- legacy Enum.TweenStatus (which is for :TweenSize/:TweenPosition
		-- and spells its member "Canceled", one L). Indexing the missing
		-- TweenStatus.Cancelled threw inside the handler, so everything
		-- below it — including the tween back to the resting state — never
		-- ran, and the panel stayed stuck at its bounced/dimmed scale.
		t1.Completed:Connect(function(status: Enum.PlaybackState)
			if status == Enum.PlaybackState.Cancelled then return end
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
		overlay.ZIndex = Z_BUTTON - 1
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

		-- Dim the FillBase briefly then recover
		local origTransp = base.BackgroundTransparency
		local dimTween = TweenService:Create(base, Defaults.FIRED_DIM_TWEEN, { BackgroundTransparency = 0.05 })
		dimTween:Play()
		table.insert(vfxTweens, dimTween)
		-- Same Enum.PlaybackState note as playAffordBounce above.
		dimTween.Completed:Connect(function(status: Enum.PlaybackState)
			if status == Enum.PlaybackState.Cancelled then return end
			if not base.Parent then return end
			local recoverTween = TweenService:Create(base, Defaults.FIRED_DIM_TWEEN, { BackgroundTransparency = origTransp })
			recoverTween:Play()
			table.insert(vfxTweens, recoverTween)
		end)
	end

	function handle:destroy()
		stopHeartbeat()
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)
		for _, t in ceilingTweens do
			t:Cancel()
		end
		table.clear(ceilingTweens)
		for _, t in vfxTweens do
			t:Cancel()
		end
		table.clear(vfxTweens)
		chargeStartedEvent:Destroy()
		chargeTierEvent:Destroy()
		chargeProgressEvent:Destroy()
		castEvent:Destroy()
		chargeCancelledEvent:Destroy()
		container:Destroy()
	end

	return handle
end

return SpellMenuBuilder
