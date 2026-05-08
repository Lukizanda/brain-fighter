----------------------------------------------------------------------
-- ReticleBuilder
----------------------------------------------------------------------
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReticleConfig = require(script.Parent.ReticleConfig)

local ReticleBuilder = {}

local function createLine(
	parent: Frame,
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2,
	color: Color3,
	strokeColor: Color3?,
	strokeThickness: number?
)
	local line = Instance.new("Frame")
	line.Size = size
	line.Position = position
	line.AnchorPoint = anchorPoint
	line.BackgroundColor3 = color
	line.BackgroundTransparency = 0
	line.BorderSizePixel = 0
	line.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = ReticleConfig.LINE_CORNER_RADIUS
	corner.Parent = line

	if strokeColor and strokeThickness and strokeThickness > 0 then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = strokeThickness
		stroke.Color = strokeColor
		stroke.Parent = line
	end

	return line
end

-- Returns { top, bottom, left, right } so callers can animate positions.
local function createCrosshairLines(parent: Frame, config: typeof(ReticleConfig))
	local len = config.LINE_LENGTH
	local thick = config.LINE_THICKNESS
	local color = config.LINE_COLOR
	local strokeColor = config.LINE_STROKE_COLOR
	local strokeThick = config.LINE_STROKE_THICKNESS

	local top    = createLine(parent, UDim2.fromOffset(thick, len), UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 0), color, strokeColor, strokeThick)
	local bottom = createLine(parent, UDim2.fromOffset(thick, len), UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 1), color, strokeColor, strokeThick)
	local left   = createLine(parent, UDim2.fromOffset(len, thick), UDim2.new(0, 0, 0.5, 0), Vector2.new(0, 0.5), color, strokeColor, strokeThick)
	local right  = createLine(parent, UDim2.fromOffset(len, thick), UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5), color, strokeColor, strokeThick)

	return top, bottom, left, right
end

function ReticleBuilder.build(configOverrides: { [string]: any }?)
	local config = ReticleConfig
	if configOverrides then
		config = table.clone(ReticleConfig)
		for k, v in configOverrides do
			config[k] = v
		end
	end

	local root = Instance.new("Frame")
	root.Name = "Reticle"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	local crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.Size = UDim2.fromOffset(config.CONTAINER_SIZE, config.CONTAINER_SIZE)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.BackgroundTransparency = 1
	crosshair.BorderSizePixel = 0
	crosshair.Parent = root

	local crosshairTop, crosshairBottom, crosshairLeft, crosshairRight = createCrosshairLines(crosshair, config)

	-- CanvasGroup with Rotation has a Roblox quirk where GroupTransparency=1
	-- does not fully suppress descendant rendering. We set Visible=false as
	-- the hard on/off and use GroupTransparency only for the fade animation.
	local hitmarker = Instance.new("CanvasGroup")
	hitmarker.Name = "Hitmarker"
	hitmarker.Size = UDim2.fromOffset(config.HITMARKER_SIZE, config.HITMARKER_SIZE)
	hitmarker.Position = UDim2.fromScale(0.5, 0.5)
	hitmarker.AnchorPoint = Vector2.new(0.5, 0.5)
	hitmarker.Rotation = config.HITMARKER_ROTATION
	hitmarker.BackgroundTransparency = 1
	hitmarker.BorderSizePixel = 0
	hitmarker.GroupTransparency = 1
	hitmarker.Visible = false
	hitmarker.ZIndex = 2
	hitmarker.Parent = root

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = config.HITMARKER_PADDING
	padding.PaddingBottom = config.HITMARKER_PADDING
	padding.PaddingLeft = config.HITMARKER_PADDING
	padding.PaddingRight = config.HITMARKER_PADDING
	padding.Parent = hitmarker

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = config.HITMARKER_FINAL_SCALE
	uiScale.Parent = hitmarker

	local hitConfig = table.clone(config)
	hitConfig.LINE_COLOR = config.HITMARKER_COLOR
	hitConfig.LINE_STROKE_THICKNESS = 0
	createCrosshairLines(hitmarker, hitConfig)

	local scaleTween = TweenService:Create(uiScale, config.HITMARKER_SCALE_TWEEN, {
		Scale = config.HITMARKER_FINAL_SCALE,
	})
	local fadeTween = TweenService:Create(hitmarker, config.HITMARKER_FADE_TWEEN, {
		GroupTransparency = 1,
	})

	local handle = {}

	-- ---- Spread state -------------------------------------------------------
	local currentSpread: number = 0
	local spreadTween: Tween? = nil

	-- "gap" = px distance from container CENTER to the NEAR edge of each line.
	-- The container is CONTAINER_SIZE × CONTAINER_SIZE; center is at half of that.
	-- Lines are anchored to the container edges at Scale 0 or 1, so:
	--   Top/Left  near-edge offset = (CONTAINER_SIZE/2 - LINE_LENGTH) - gap
	--                               = half - len - gap
	--   Bottom/Right near-edge offset = gap - (CONTAINER_SIZE/2 - LINE_LENGTH)
	--                                 = gap - half + len
	-- Verified: at gap = CONTAINER_SIZE/2 - LINE_LENGTH (= 25-15 = 10), offsets = 0
	-- matching the original resting positions exactly.
	local half = config.CONTAINER_SIZE / 2
	local len  = config.LINE_LENGTH

	local function gapToOffset(gap: number): (number, number)
		-- Returns (inwardOffset, outwardOffset) for top/left vs bottom/right lines.
		local inner = half - len - gap  -- top / left pixel offset
		local outer = gap - half + len  -- bottom / right pixel offset  (= -inner)
		return inner, outer
	end

	local function applyGapImmediate(gap: number)
		local inner, outer = gapToOffset(gap)
		crosshairTop.Position    = UDim2.new(0.5, 0, 0,  inner)
		crosshairBottom.Position = UDim2.new(0.5, 0, 1,  outer)
		crosshairLeft.Position   = UDim2.new(0,  inner, 0.5, 0)
		crosshairRight.Position  = UDim2.new(1,  outer, 0.5, 0)
	end

	-- Set resting gap immediately so first frame looks correct.
	applyGapImmediate(config.SPREAD_MIN_GAP)

	function handle:setSpread(normalized: number)
		normalized = math.clamp(normalized, 0, 1)
		currentSpread = normalized
		local gap = config.SPREAD_MIN_GAP + (config.SPREAD_MAX_GAP - config.SPREAD_MIN_GAP) * normalized
		local inner, outer = gapToOffset(gap)

		if spreadTween then
			spreadTween:Cancel()
			spreadTween = nil
		end

		-- Tween all four lines simultaneously.
		local ti = config.SPREAD_TWEEN_INFO
		local tweenTop    = TweenService:Create(crosshairTop,    ti, { Position = UDim2.new(0.5, 0, 0,  inner) })
		local tweenBottom = TweenService:Create(crosshairBottom, ti, { Position = UDim2.new(0.5, 0, 1,  outer) })
		local tweenLeft   = TweenService:Create(crosshairLeft,   ti, { Position = UDim2.new(0,  inner, 0.5, 0) })
		local tweenRight  = TweenService:Create(crosshairRight,  ti, { Position = UDim2.new(1,  outer, 0.5, 0) })

		tweenTop:Play()
		tweenBottom:Play()
		tweenLeft:Play()
		tweenRight:Play()

		-- Track the primary tween only for cancellation bookkeeping.
		spreadTween = tweenTop
	end

	-- Heartbeat-driven decay: continuously reduces spread toward 0 when at rest.
	local heartbeatConn: RBXScriptConnection = RunService.Heartbeat:Connect(function(dt: number)
		if currentSpread <= 0 then
			return
		end
		local next = math.max(0, currentSpread - config.SPREAD_DECAY_RATE * dt)
		handle:setSpread(next)
	end)

	-- ---- Hitmarker ----------------------------------------------------------
	local hideOnFadeConn: RBXScriptConnection? = nil

	function handle:showHitmarker()
		if scaleTween.PlaybackState == Enum.PlaybackState.Playing then
			scaleTween:Cancel()
		end
		if fadeTween.PlaybackState == Enum.PlaybackState.Playing then
			fadeTween:Cancel()
		end
		if hideOnFadeConn then
			hideOnFadeConn:Disconnect()
			hideOnFadeConn = nil
		end

		hitmarker.Visible = true
		hitmarker.GroupTransparency = 0
		uiScale.Scale = config.HITMARKER_INITIAL_SCALE

		scaleTween:Play()
		fadeTween:Play()

		-- Once the fade completes, hard-hide so the rotated-CanvasGroup quirk
		-- doesn't leave descendants faintly rendering at GroupTransparency=1.
		hideOnFadeConn = fadeTween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed then
				hitmarker.Visible = false
			end
			if hideOnFadeConn then
				hideOnFadeConn:Disconnect()
				hideOnFadeConn = nil
			end
		end)
	end

	function handle:destroy()
		heartbeatConn:Disconnect()
		if spreadTween then
			spreadTween:Cancel()
			spreadTween = nil
		end
		if hideOnFadeConn then
			hideOnFadeConn:Disconnect()
			hideOnFadeConn = nil
		end
		scaleTween:Cancel()
		fadeTween:Cancel()
		root:Destroy()
	end

	handle.gui = root
	return handle
end

return ReticleBuilder
