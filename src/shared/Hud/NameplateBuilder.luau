--!strict

----------------------------------------------------------------------
-- NameplateBuilder
----------------------------------------------------------------------
-- View-only builder for the plate over a combatant's head: a name line,
-- a health bar with a `current / max` readout, and the damage numbers
-- that pop off it when the health moves.
--
-- One plate serves every combatant a player can look at — another
-- player, or the hub's training dummy. That is the point rather than a
-- convenience: the dummy is the only safe place to learn what a spell
-- does, so it has to teach the *same* display a real opponent will show.
-- If the two ever diverge, the tutorial is lying.
--
-- World-space, so like `PortalPanelBuilder.buildSign` it is not a HUD
-- element and carries no HudGate policy. It lives here rather than under
-- `Vfx/` because it is a readout: it must survive the reduced-effects
-- setting, and the numbers on it are the point.
--
-- Contains no discovery and no Humanoid wiring — `NameplateGui` finds
-- the combatants and pushes values in.
--
-- ## Distance
-- Nothing here tracks the camera. The plate is sized in studs, so the
-- engine shrinks it with its rig and it stays proportionate at any range
-- for free — see `NameplateConfig` for why pixel sizing was wrong and
-- what it costs at duel range.
----------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local NameplateConfig = require(script.Parent.NameplateConfig)

export type Nameplate = {
	gui: BillboardGui,
	setName: (self: Nameplate, name: string) -> (),
	setHealth: (self: Nameplate, current: number, max: number) -> (),
	popDelta: (self: Nameplate, delta: number) -> (),
	setVisible: (self: Nameplate, visible: boolean) -> (),
	destroy: (self: Nameplate) -> (),
}

local NameplateBuilder = {}

local ROW_TOTAL = NameplateConfig.NAME_ROW_WEIGHT + NameplateConfig.BAR_ROW_WEIGHT
local NAME_FRACTION = NameplateConfig.NAME_ROW_WEIGHT / ROW_TOTAL
local BAR_FRACTION = NameplateConfig.BAR_ROW_WEIGHT / ROW_TOTAL

local function fillColorFor(fraction: number): Color3
	if fraction <= NameplateConfig.LOW_THRESHOLD then
		return NameplateConfig.FILL_CRITICAL_COLOR
	elseif fraction <= NameplateConfig.MID_THRESHOLD then
		return NameplateConfig.FILL_WARNING_COLOR
	end
	return NameplateConfig.FILL_COLOR
end

function NameplateBuilder.build(anchor: BasePart): Nameplate
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Adornee = anchor
	billboard.Size = NameplateConfig.PLATE_SIZE
	billboard.StudsOffsetWorldSpace = Vector3.new(0, NameplateConfig.HEIGHT_STUDS, 0)
	billboard.AlwaysOnTop = NameplateConfig.ALWAYS_ON_TOP
	billboard.MaxDistance = NameplateConfig.MAX_DISTANCE
	billboard.LightInfluence = 0

	-- Rows are sized as fractions of the plate, so the two row weights in
	-- the config are the only place the split is stated.
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.Size = UDim2.fromScale(1, NAME_FRACTION)
	nameLabel.Position = UDim2.fromScale(0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = NameplateConfig.NAME_FONT
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = NameplateConfig.NAME_COLOR
	nameLabel.TextStrokeColor3 = NameplateConfig.NAME_STROKE_COLOR
	nameLabel.TextStrokeTransparency = NameplateConfig.NAME_STROKE_TRANSPARENCY
	nameLabel.Text = ""
	nameLabel.Parent = billboard

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromScale(1, BAR_FRACTION)
	track.Position = UDim2.fromScale(0, NAME_FRACTION)
	track.BackgroundColor3 = NameplateConfig.TRACK_COLOR
	track.BackgroundTransparency = NameplateConfig.TRACK_TRANSPARENCY
	track.BorderSizePixel = 0
	track.Parent = billboard

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = NameplateConfig.CORNER_RADIUS
	trackCorner.Parent = track

	local stroke = Instance.new("UIStroke")
	stroke.Color = NameplateConfig.BORDER_COLOR
	stroke.Thickness = NameplateConfig.BORDER_THICKNESS
	stroke.Transparency = NameplateConfig.BORDER_TRANSPARENCY
	stroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = NameplateConfig.FILL_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = NameplateConfig.CORNER_RADIUS
	fillCorner.Parent = fill

	-- Sits over the fill so the numbers stay legible at any fraction.
	local readout = Instance.new("TextLabel")
	readout.Name = "Readout"
	readout.Size = UDim2.fromScale(1, 1)
	readout.BackgroundTransparency = 1
	readout.Font = NameplateConfig.TEXT_FONT
	readout.TextScaled = true
	readout.TextColor3 = NameplateConfig.TEXT_COLOR
	readout.TextStrokeTransparency = NameplateConfig.TEXT_STROKE_TRANSPARENCY
	readout.Text = ""
	readout.Parent = track

	local textPadding = Instance.new("UIPadding")
	textPadding.PaddingLeft = NameplateConfig.TEXT_INSET
	textPadding.PaddingRight = NameplateConfig.TEXT_INSET
	textPadding.Parent = readout

	local activeFillTween: Tween? = nil
	local popups: { [BillboardGui]: true } = {}

	local handle = {} :: Nameplate
	handle.gui = billboard

	function handle:setName(name: string)
		nameLabel.Text = name
	end

	function handle:setHealth(current: number, max: number)
		local safeMax = math.max(max, 1)
		local fraction = math.clamp(current / safeMax, 0, 1)

		if activeFillTween then
			activeFillTween:Cancel()
		end
		activeFillTween = TweenService:Create(fill, NameplateConfig.FILL_TWEEN, {
			Size = UDim2.fromScale(fraction, 1),
			BackgroundColor3 = fillColorFor(fraction),
		})
		;(activeFillTween :: Tween):Play()

		readout.Text = string.format(NameplateConfig.TEXT_FORMAT, math.round(current), math.round(safeMax))
	end

	-- A positive delta is damage, a negative one a heal. Both are drawn,
	-- because a bar that moves without a number is the thing this plate
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
		popup.Size = NameplateConfig.DAMAGE_SIZE
		popup.AlwaysOnTop = NameplateConfig.ALWAYS_ON_TOP
		popup.MaxDistance = NameplateConfig.MAX_DISTANCE
		popup.LightInfluence = 0

		local jitter = (math.random() * 2 - 1) * NameplateConfig.DAMAGE_JITTER_STUDS
		local startHeight = NameplateConfig.HEIGHT_STUDS + NameplateConfig.DAMAGE_START_OFFSET
		popup.StudsOffsetWorldSpace = Vector3.new(jitter, startHeight, 0)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = NameplateConfig.DAMAGE_FONT
		label.TextScaled = true
		label.TextColor3 = if isDamage
			then NameplateConfig.DAMAGE_COLOR
			else NameplateConfig.HEAL_COLOR
		label.TextStrokeTransparency = NameplateConfig.DAMAGE_STROKE_TRANSPARENCY
		label.Text = string.format(
			if isDamage then NameplateConfig.DAMAGE_FORMAT else NameplateConfig.HEAL_FORMAT,
			magnitude
		)
		label.Parent = popup

		popup.Parent = anchor
		popups[popup] = true

		local rise = TweenService:Create(popup, NameplateConfig.DAMAGE_TWEEN, {
			StudsOffsetWorldSpace = Vector3.new(
				jitter,
				startHeight + NameplateConfig.DAMAGE_RISE_STUDS,
				0
			),
		})
		rise:Play()

		local fade = TweenService:Create(label, NameplateConfig.DAMAGE_FADE_TWEEN, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})

		task.delay(NameplateConfig.DAMAGE_FADE_DELAY, function()
			if popups[popup] then
				fade:Play()
			end
		end)

		rise.Completed:Connect(function()
			popups[popup] = nil
			popup:Destroy()
		end)
	end

	-- Hidden rather than destroyed while the combatant is down: the rig is
	-- about to be replaced (a respawning dummy, a respawning player) and
	-- the plate for that one is built from scratch.
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

return NameplateBuilder
