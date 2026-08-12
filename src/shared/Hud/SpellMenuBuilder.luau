----------------------------------------------------------------------
-- SpellMenuBuilder
----------------------------------------------------------------------
-- Three circular spell cast panels (red / green / blue). Mana fills each
-- one outward from the centre; the four tier thresholds are concentric
-- rings; a persistent numeral sits in the middle.
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
-- The panels were vertical bars until the circles landed. Two things came
-- with the shape: a bar reads as a *meter* — status you watch — where a
-- disc in a column of round buttons reads as something you press and keep
-- pressing, which is what the gesture actually is; and the disc echoes
-- the charge orb that rises over the caster's head while it climbs.
-- What the shape gives up is honest magnitude: see
-- SpellMenuConfig.FILL_RADIUS_EXPONENT.
--
-- Panel layers (back to front) — every one is a circle:
--   FillBase      — always-visible dim disc (the "empty" container look)
--   FillDisc      — solid colour + top-lit ramp, diameter = energy fraction
--   ChargeReserve — annulus at the fill's outer edge: what release spends
--   Ring_tN       — ring at TIER_COSTS[n] / FILL_MAX
--   ReadyBloom /
--   ReadyGlow     — coloured halo that breathes while the panel can cast
--   CeilingPulse  — rim halo that breathes at the affordability ceiling
--   ColorLabel / Numeral — text overlays
--   TextButton    — press detection (highest ZIndex in the panel)
--
-- No ClipsDescendants anywhere, deliberately: it clips to the *rectangle*
-- and ignores UICorner, so it could not have masked a disc even if the
-- layers needed masking. They do not — each one is sized to its own
-- radius.
--
-- Returned handle:
--   .gui                 Frame to register with HudLayoutManager
--   .chargeStarted       RBXScriptSignal<color>
--   .chargeTierChanged   RBXScriptSignal<color, tier>
--   .chargeProgress      RBXScriptSignal<color, tier, alpha>
--   .castRequested       RBXScriptSignal<color, tier>
--   .chargeCancelled     RBXScriptSignal<color>
--   :setReservoirs(snap)                refresh fill, rings, numeral
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

type TierRing = { frame: Frame, stroke: UIStroke, frac: number }

-- The two strokes of the ready halo, kept together because they are only
-- ever raised and lowered as one thing.
type ReadyGlow = {
	glow: Frame,
	glowStroke: UIStroke,
	bloom: Frame,
	bloomStroke: UIStroke,
}

local COLOR_ORDER = { "red", "green", "blue" }

-- ZIndex ladder, written down because it has to hold under BOTH
-- ZIndexBehavior settings: Sibling (children compare within a parent) and
-- the legacy Global (every number compares against every other). The
-- values are chosen so the intended stacking survives either reading.
local Z_FILL_BASE    = 1
local Z_FILL_DISC    = 2
local Z_RESERVE      = 3
local Z_RING         = 4
local Z_GLOW         = 5
local Z_CEILING      = 6
local Z_TEXT         = 7
local Z_BUTTON       = 10

local function lightenColor(c: Color3, amount: number): Color3
	return Color3.fromRGB(
		math.clamp(math.round(c.R * 255 + amount), 0, 255),
		math.clamp(math.round(c.G * 255 + amount), 0, 255),
		math.clamp(math.round(c.B * 255 + amount), 0, 255)
	)
end

-- Every layer is a square Frame turned into a circle by the same corner
-- radius, anchored at its own centre so it grows symmetrically.
local function makeCircle(name: string, zIndex: number, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Defaults.PANEL_CORNER_RADIUS
	corner.Parent = frame

	frame.Parent = parent
	return frame
end

-- A ring is a circle with no fill and a UIStroke — the stroke traces the
-- corner radius, which is the cheapest true annulus the engine offers.
local function makeRing(
	name: string,
	color: Color3,
	thickness: number,
	transparency: number,
	zIndex: number,
	parent: Instance
): (Frame, UIStroke)
	local frame = makeCircle(name, zIndex, parent)
	frame.BackgroundTransparency = 1

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	return frame, stroke
end

-- A UIStroke grows *outward* from its frame's bounds, so a ring meant to
-- sit centred on a radius has to be inset by its own thickness.
local function ringSize(frac: number, thickness: number): UDim2
	return UDim2.new(frac, -thickness, frac, -thickness)
end

local SpellMenuBuilder = {}

function SpellMenuBuilder.build(): Handle
	local container = Instance.new("Frame")
	container.Name = "SpellMenu"
	container.Size = UDim2.new(0, Defaults.PANEL_DIAMETER, 0, 0)
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

	local panels: { [string]: Frame }             = {}
	local fillBases: { [string]: Frame }          = {}
	local fillDiscs: { [string]: Frame }          = {}
	local reserveBands: { [string]: Frame }       = {}
	local reserveStrokes: { [string]: UIStroke }  = {}
	local ceilingRings: { [string]: Frame }       = {}
	local ceilingStrokes: { [string]: UIStroke }  = {}
	local readyGlows: { [string]: ReadyGlow }     = {}
	local rings: { [string]: { TierRing } }       = {}
	local numerals: { [string]: TextLabel }       = {}
	local litColors: { [string]: Color3 }         = {}
	local glowColors: { [string]: Color3 }        = {}

	local currentEnergy: { [string]: number } = { red = 0, green = 0, blue = 0 }
	-- Highest tier this reservoir can pay for right now. 0 = below T1.
	local chargeCeiling: { [string]: number } = { red = 0, green = 0, blue = 0 }

	-- Mana → the fill disc's diameter as a fraction of the panel. Every
	-- layer that has to line up with the fill edge — both tier rings and
	-- both edges of the reserve band — goes through here, so
	-- FILL_RADIUS_EXPONENT stays one lever instead of four call sites that
	-- have to agree with each other.
	local function radiusFractionFor(mana: number): number
		local frac = math.clamp(mana / Defaults.FILL_MAX, 0, 1)
		return frac ^ Defaults.FILL_RADIUS_EXPONENT
	end

	-- The two halves of "saturate at castable". A panel holding less than a
	-- T1 cast is drained toward grey; the moment T1 becomes affordable it
	-- snaps back to full colour. Both read litColors, which the build loop
	-- below fills in, so these must not be called before it runs.
	local function discColorFor(color: string, canCast: boolean): Color3
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

		-- Outer panel — transparent square container; the circles inside it
		-- are all centred on it.
		local panel = Instance.new("Frame")
		panel.Name = "Panel_" .. color
		panel.LayoutOrder = i
		panel.Size = UDim2.fromOffset(Defaults.PANEL_DIAMETER, Defaults.PANEL_DIAMETER)
		panel.BackgroundTransparency = 1
		panel.BorderSizePixel = 0

		-- FillBase: always-visible dim disc — conveys the "empty" shape
		local fillBase = makeCircle("FillBase", Z_FILL_BASE, panel)
		fillBase.Size = UDim2.fromScale(1, 1)
		-- Built drained, because every reservoir starts empty and the edge
		-- detector in setReservoirs only fires on a *change*. Building
		-- saturated would leave three fully-coloured panels that cannot cast
		-- anything until the first word is memorized.
		fillBase.BackgroundColor3 = bgColor:Lerp(Defaults.DESATURATED_GREY, Defaults.DESATURATED_BLEND)
		fillBase.BackgroundTransparency = Defaults.FILL_BASE_TRANSPARENCY

		-- FillDisc: grows out of the centre as mana accumulates.
		local fillDisc = makeCircle("FillDisc", Z_FILL_DISC, panel)
		fillDisc.Size = UDim2.fromScale(0, 0)
		fillDisc.BackgroundColor3 = litColor:Lerp(Defaults.DESATURATED_GREY, Defaults.DESATURATED_BLEND)

		-- Rotation=270: key 0 = bottom (darkened), key 1 = top (untouched).
		-- Neutral tints only — a UIGradient multiplies its parent's
		-- BackgroundColor3, so leaving hue out of it here is what lets the
		-- desaturation below be one tween. On a disc the top-lit ramp is
		-- also what stops it reading as a flat coin.
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 270
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Defaults.FILL_GRADIENT_BOTTOM_TINT),
			ColorSequenceKeypoint.new(1, Defaults.FILL_GRADIENT_TOP_TINT),
		})
		gradient.Parent = fillDisc

		-- ChargeReserve: the outer annulus of the fill that this release
		-- will spend. Sized to the post-spend radius with a stroke thick
		-- enough to reach the pre-spend radius, so it always hugs the fill
		-- edge and eats inward.
		local reserve, reserveStroke = makeRing(
			"ChargeReserve",
			Defaults.CHARGE_RESERVE_COLOR,
			0,
			Defaults.CHARGE_RESERVE_TRANSPARENCY,
			Z_RESERVE,
			panel
		)
		reserve.Size = UDim2.fromScale(Defaults.CHARGE_RESERVE_MIN_INNER_SCALE, Defaults.CHARGE_RESERVE_MIN_INNER_SCALE)

		-- Tier rings. Red is the only school with a T4, so the count comes
		-- from the registry rather than from NUM_TIERS — a fourth ring on
		-- green would mark a spell that does not exist.
		local colorRings: { TierRing } = {}
		for tier = 1, SpellRegistry.tierCount(color :: SpellRegistry.Color) do
			local frac = radiusFractionFor(SpellRegistry.TIER_COSTS[tier])
			local ringFrame, ringStroke = makeRing(
				string.format("Ring_t%d", tier),
				Defaults.NOTCH_COLOR,
				Defaults.NOTCH_THICKNESS,
				Defaults.NOTCH_TRANSPARENCY,
				Z_RING,
				panel
			)
			ringFrame.Size = ringSize(frac, Defaults.NOTCH_THICKNESS)
			colorRings[tier] = { frame = ringFrame, stroke = ringStroke, frac = frac }
		end
		rings[color] = colorRings

		-- ReadyBloom / ReadyGlow: the "this one is loaded" halo. Built as two
		-- strokes so the edge reads as light rather than as a border — the
		-- bloom is a wide faint wash inset inside the rim, the glow a crisp
		-- line sitting on it. Only the glow bleeds outward, and only by its
		-- own thickness, which is what keeps two lit neighbours out of each
		-- other's BUTTON_GAP.
		local glowColor = lightenColor(bgColor, Defaults.READY_GLOW_LIGHTEN)
		glowColors[color] = glowColor

		local bloomRing, bloomStroke = makeRing(
			"ReadyBloom",
			glowColor,
			Defaults.READY_BLOOM_THICKNESS,
			1,
			Z_GLOW,
			panel
		)
		local bloomInset = Defaults.READY_BLOOM_THICKNESS * 2
		bloomRing.Size = UDim2.new(1, -bloomInset, 1, -bloomInset)
		bloomRing.Visible = false

		local glowRing, glowStroke = makeRing(
			"ReadyGlow",
			glowColor,
			Defaults.READY_GLOW_THICKNESS,
			1,
			Z_GLOW,
			panel
		)
		glowRing.Size = UDim2.fromScale(1, 1)
		glowRing.Visible = false

		readyGlows[color] = {
			glow = glowRing,
			glowStroke = glowStroke,
			bloom = bloomRing,
			bloomStroke = bloomStroke,
		}

		-- CeilingPulse: rim halo that breathes when a held charge has topped
		-- out. Inset by twice its thickness so the stroke's outer edge lands
		-- exactly on the panel rim instead of bleeding into the gap.
		local ceilingRing, ceilingStroke = makeRing(
			"CeilingPulse",
			Defaults.CHARGE_CEILING_PULSE_COLOR,
			Defaults.CHARGE_CEILING_RING_THICKNESS,
			1,
			Z_CEILING,
			panel
		)
		local ceilingInset = Defaults.CHARGE_CEILING_RING_THICKNESS * 2
		ceilingRing.Size = UDim2.new(1, -ceilingInset, 1, -ceilingInset)
		ceilingRing.Visible = false

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

		-- Persistent mana numeral, centred. A hold has to show what it is
		-- about to spend *while* the player decides, not after they have
		-- committed.
		local numeral = Instance.new("TextLabel")
		numeral.Name = "Numeral"
		numeral.AnchorPoint = Vector2.new(0.5, 0.5)
		numeral.Position = UDim2.fromScale(0.5, 0.5)
		numeral.Size = UDim2.new(1, 0, 0, Defaults.NUMERAL_HEIGHT)
		numeral.BackgroundTransparency = 1
		numeral.Font = Defaults.NUMERAL_FONT
		numeral.TextSize = Defaults.NUMERAL_SIZE
		numeral.TextColor3 = Defaults.NUMERAL_DIM_COLOR
		numeral.TextStrokeTransparency = Defaults.NUMERAL_STROKE
		numeral.TextXAlignment = Enum.TextXAlignment.Center
		numeral.Text = string.format("0/%d", Defaults.FILL_MAX)
		numeral.ZIndex = Z_TEXT
		numeral.Parent = panel

		-- TextButton: full-square press target (highest ZIndex in panel).
		-- Square rather than circular on purpose — see isOverPanel.
		local btn = Instance.new("TextButton")
		btn.Name = "PressTarget"
		btn.Size = UDim2.fromScale(1, 1)
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.ZIndex = Z_BUTTON
		btn.Parent = panel

		panel.Parent = container
		panels[color]         = panel
		fillBases[color]      = fillBase
		fillDiscs[color]      = fillDisc
		reserveBands[color]   = reserve
		reserveStrokes[color] = reserveStroke
		ceilingRings[color]   = ceilingRing
		ceilingStrokes[color] = ceilingStroke
		numerals[color]       = numeral
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
	-- Both strokes of one panel's halo. Started on the same frame with the
	-- same TweenInfo, so they stay in phase without being driven together.
	local readyTweens: { [string]: { Tween } } = {}

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

	-- No branch for "nothing reserved": a pendingCost of 0 collapses the
	-- band's two edges onto each other, which is a zero-thickness stroke,
	-- which draws nothing. The clear path and the grow path are the same
	-- arithmetic.
	local function refreshReserve(color: string, pendingCost: number, tweenInfo: TweenInfo)
		local energy = currentEnergy[color] or 0
		local outerFrac = radiusFractionFor(energy)
		local innerFrac = math.max(
			radiusFractionFor(math.max(energy - pendingCost, 0)),
			Defaults.CHARGE_RESERVE_MIN_INNER_SCALE
		)
		-- Diameter difference halved, because the stroke grows outward on
		-- both sides of the frame it hangs off.
		local thickness = math.max((outerFrac - innerFrac) * Defaults.PANEL_DIAMETER / 2, 0)

		local sizeTween = TweenService:Create(reserveBands[color], tweenInfo, {
			Size = UDim2.fromScale(innerFrac, innerFrac),
		})
		local strokeTween = TweenService:Create(reserveStrokes[color], tweenInfo, {
			Thickness = thickness,
		})
		sizeTween:Play()
		strokeTween:Play()
		table.insert(vfxTweens, sizeTween)
		table.insert(vfxTweens, strokeTween)
	end

	local function refreshNotches(color: string, activeTier: number)
		for tier, ring in rings[color] do
			local isActive = tier == activeTier
			local thickness = if isActive
				then Defaults.NOTCH_THICKNESS_ACTIVE
				else Defaults.NOTCH_THICKNESS
			local frameTween = TweenService:Create(ring.frame, Defaults.NOTCH_TWEEN, {
				Size = ringSize(ring.frac, thickness),
			})
			local strokeTween = TweenService:Create(ring.stroke, Defaults.NOTCH_TWEEN, {
				Thickness = thickness,
				Color = if isActive then Defaults.NOTCH_ACTIVE_COLOR else Defaults.NOTCH_COLOR,
				Transparency = if isActive
					then Defaults.NOTCH_ACTIVE_TRANSPARENCY
					else Defaults.NOTCH_TRANSPARENCY,
			})
			frameTween:Play()
			strokeTween:Play()
			table.insert(vfxTweens, frameTween)
			table.insert(vfxTweens, strokeTween)
		end
	end

	local function stopReadyGlow(color: string)
		local existing = readyTweens[color]
		if not existing then return end
		for _, t in existing do
			t:Cancel()
		end
		readyTweens[color] = nil

		local parts = readyGlows[color]
		parts.glowStroke.Transparency = 1
		parts.bloomStroke.Transparency = 1
		parts.glow.Visible = false
		parts.bloom.Visible = false
	end

	local function startReadyGlow(color: string)
		if readyTweens[color] then return end
		local parts = readyGlows[color]
		parts.glow.Visible = true
		parts.bloom.Visible = true
		parts.glowStroke.Transparency = Defaults.READY_GLOW_DIM
		parts.bloomStroke.Transparency = Defaults.READY_BLOOM_DIM

		local glowTween = TweenService:Create(parts.glowStroke, Defaults.READY_GLOW_TWEEN, {
			Transparency = Defaults.READY_GLOW_BRIGHT,
		})
		local bloomTween = TweenService:Create(parts.bloomStroke, Defaults.READY_GLOW_TWEEN, {
			Transparency = Defaults.READY_BLOOM_BRIGHT,
		})
		glowTween:Play()
		bloomTween:Play()
		readyTweens[color] = { glowTween, bloomTween }
	end

	local function stopCeilingPulse(color: string)
		local existing = ceilingTweens[color]
		if existing then
			existing:Cancel()
			ceilingTweens[color] = nil
		end
		local stroke = ceilingStrokes[color]
		stroke.Transparency = 1
		ceilingRings[color].Visible = false
	end

	local function startCeilingPulse(color: string)
		if ceilingTweens[color] then return end
		local stroke = ceilingStrokes[color]
		ceilingRings[color].Visible = true
		stroke.Transparency = Defaults.CHARGE_CEILING_PULSE_MIN
		local t = TweenService:Create(stroke, Defaults.CHARGE_CEILING_PULSE_TWEEN, {
			Transparency = Defaults.CHARGE_CEILING_PULSE_MAX,
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

	-- One predicate rather than start/stop calls scattered through the
	-- press handlers: the halo means "you could press this", which stops
	-- being information the instant you do press it, and while a charge is
	-- held the rim belongs to the ceiling pulse. Both start and stop are
	-- idempotent, so every state change can just call this and let it
	-- settle.
	local function refreshReadyGlow(color: string)
		local held = press ~= nil and press.color == color
		if wasAffordable[color] and not held then
			startReadyGlow(color)
		else
			stopReadyGlow(color)
		end
	end

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
		refreshReadyGlow(color)
		stopHeartbeat()
		heartbeatConn = RunService.Heartbeat:Connect(evaluateCharge)
		-- Evaluate on the press frame, not on the next Heartbeat: T1's charge
		-- time is zero, so a tap has to resolve immediately or a fast click
		-- would release before the first tick and fizzle.
		evaluateCharge()
	end

	-- Deliberately a *rectangle* test against the panel's bounding box,
	-- even though the panel draws as a circle. The corners are live but
	-- invisible, which makes drag-off-to-cancel slightly harder to trigger
	-- by accident — and an accidental cancel costs the player a whole
	-- charge, where an accidental cast costs them mana they were about to
	-- spend anyway. The error should fall on the forgiving side.
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
		-- `press` is already nil above, so this re-raises the halo if the
		-- panel is still castable. If the release spent the reservoir dry it
		-- comes straight back down on the next setReservoirs.
		refreshReadyGlow(color)

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

			local fraction = radiusFractionFor(energy)
			local fillTween = TweenService:Create(fillDiscs[color], Defaults.FILL_TWEEN, {
				Size = UDim2.fromScale(fraction, fraction),
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
				local discTween = TweenService:Create(fillDiscs[color], Defaults.DESATURATED_TWEEN, {
					BackgroundColor3 = discColorFor(color, canCast),
				})
				local baseTween = TweenService:Create(fillBases[color], Defaults.DESATURATED_TWEEN, {
					BackgroundColor3 = baseColorFor(color, canCast),
				})
				discTween:Play()
				baseTween:Play()
				table.insert(vfxTweens, discTween)
				table.insert(vfxTweens, baseTween)
			end

			refreshReadyGlow(color)

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

		-- White flash disc
		local overlay = makeCircle("FiredFlash", Z_BUTTON - 1, panel)
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		overlay.BackgroundTransparency = 0
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
		for _, pair in readyTweens do
			for _, t in pair do
				t:Cancel()
			end
		end
		table.clear(readyTweens)
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
