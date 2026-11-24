--!strict

----------------------------------------------------------------------
-- LetterTowTether
----------------------------------------------------------------------
-- Draws the line between a letter block that is being pulled and the thing
-- pulling it, for as long as the tow lasts. The server (BlockSpawner's tow
-- API; the boss's hunger asks for it) tags the block with
-- `TowConstants.TAG` and publishes the point it is pulled toward as
-- `TowConstants.TARGET_ATTRIBUTE`, refreshed every tick, so the target can
-- move (the boss walks). The server draws nothing: this script owns what a
-- player sees (wiki/design/boss-arena.md § Letter pull, docs/agents/vfx-sfx.md).
--
-- A one-shot VfxBroadcast beam would not do: a tow lasts seconds and both
-- ends move. So: a Beam between an attachment on the block's cube (which
-- LetterBlockAnimator moves, so the line follows the block's bob and its
-- travel) and an attachment on a small invisible client-only part that eases
-- toward the published target. Tinted with the block's own colour, the way
-- the collect stream is. Everything here is client-local and is removed when
-- the tag comes off or the block goes (eaten, popped, torn down).
--
-- A tow with a hold-then-snap schedule (TowConstants BEGAN/SNAP_AT, server
-- time) is also the warning on the letter: the tether tightens (wider, more
-- opaque) toward the snap, a Highlight on the block blinks faster toward it,
-- and a ring on a BillboardGui closes from 2.5x the block to its size exactly
-- at the snap. All of it is a function of server time, full strength from the
-- snap on. Created when the schedule is first readable, removed with the tag.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TowConstants = require(ReplicatedStorage.Shared.BlockSpawner.TowConstants)
local Colors = require(ReplicatedStorage.Shared.Core.Colors)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("LetterTowTether")

local CUBE_CHILD_NAME = "Cube"
local END_PART_SIZE = Vector3.one * 0.2

type Tether = {
	endPart: Part,
	beam: Beam,
	-- Whether the end part has been placed yet; it snaps to the first
	-- published target instead of easing in from the origin.
	placed: boolean,
	-- The warning on a marked letter (a tow with a hold-then-snap schedule),
	-- made on the first frame the schedule is readable: a blinking Highlight
	-- and a closing ring. Nil until then, and for a tow without a schedule.
	highlight: Highlight?,
	ringGui: BillboardGui?,
	ringFrame: Frame?,
	-- Blink phase in radians, advanced by the current rate so the speed-up
	-- toward the snap does not jump.
	blinkPhase: number,
}

local tethers: { [Model]: Tether } = {}

local TAU = math.pi * 2
local HALF = 0.5

local function lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

-- The Highlight (outline plus fill, in the hungry colour, through walls).
local function makeHighlight(block: Model): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = TowConstants.HIGHLIGHT_NAME
	highlight.Adornee = block
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = TowConstants.HIGHLIGHT_FILL_COLOR
	highlight.OutlineColor = TowConstants.HIGHLIGHT_OUTLINE_COLOR
	highlight.OutlineTransparency = TowConstants.HIGHLIGHT_OUTLINE_TRANSPARENCY
	highlight.FillTransparency = TowConstants.HIGHLIGHT_FILL_TRANSPARENCY_MAX
	highlight.Parent = block
	return highlight
end

-- The closing ring: a round outline on a BillboardGui over the block. The
-- gui is RING_START_SCALE times the block wide and the ring is a Frame that
-- starts filling it and shrinks to the block's own size. Not AlwaysOnTop (that
-- did not draw in this game's client view); pushed toward the camera instead
-- so the cube does not hide it.
local function makeRing(cube: BasePart): (BillboardGui, Frame)
	local side = if cube.Size.X > 0 then cube.Size.X else TowConstants.RING_FALLBACK_BLOCK_STUDS
	local gui = Instance.new("BillboardGui")
	gui.Name = TowConstants.RING_NAME
	gui.Adornee = cube
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Size = UDim2.fromScale(side * TowConstants.RING_START_SCALE, side * TowConstants.RING_START_SCALE)
	gui.StudsOffset = Vector3.new(0, 0, TowConstants.RING_CAMERA_OFFSET_STUDS)

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(HALF, HALF)
	frame.Position = UDim2.fromScale(HALF, HALF)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(HALF, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = TowConstants.RING_COLOR
	stroke.Thickness = TowConstants.RING_STROKE_PIXELS
	stroke.Parent = frame

	gui.Parent = cube
	return gui, frame
end

local function removeTether(block: Model)
	local tether = tethers[block]
	if tether == nil then
		return
	end
	tethers[block] = nil
	tether.endPart:Destroy()
	if tether.highlight ~= nil then
		tether.highlight:Destroy()
	end
	if tether.ringGui ~= nil then
		tether.ringGui:Destroy()
	end
	local cube = block:FindFirstChild(CUBE_CHILD_NAME)
	local attachment = cube and cube:FindFirstChild(TowConstants.TETHER_BLOCK_ATTACHMENT_NAME)
	if attachment then
		attachment:Destroy()
	end
end

local function addTether(instance: Instance)
	if not instance:IsA("Model") or tethers[instance] ~= nil then
		return
	end
	local block: Model = instance
	local cube = block:FindFirstChild(CUBE_CHILD_NAME)
	if cube == nil or not cube:IsA("BasePart") then
		return
	end

	local tint = Colors.tint(tostring(block:GetAttribute(LetterBlocks.COLOR_ATTRIBUTE)))

	local startAttachment = Instance.new("Attachment")
	startAttachment.Name = TowConstants.TETHER_BLOCK_ATTACHMENT_NAME
	startAttachment.Parent = cube

	local endPart = Instance.new("Part")
	endPart.Name = TowConstants.TETHER_END_PART_NAME
	endPart.Anchored = true
	endPart.CanCollide = false
	endPart.CanQuery = false
	endPart.CanTouch = false
	endPart.CastShadow = false
	endPart.Transparency = 1
	endPart.Size = END_PART_SIZE
	local endAttachment = Instance.new("Attachment")
	endAttachment.Name = TowConstants.TETHER_END_ATTACHMENT_NAME
	endAttachment.Parent = endPart

	local beam = Instance.new("Beam")
	beam.Name = TowConstants.TETHER_BEAM_NAME
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endAttachment
	beam.Color = ColorSequence.new(tint)
	beam.LightEmission = TowConstants.TETHER_LIGHT_EMISSION
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = TowConstants.TETHER_SEGMENTS
	beam.Width0 = TowConstants.TETHER_WIDTH_AT_BLOCK
	beam.Width1 = TowConstants.TETHER_WIDTH_AT_TARGET
	beam.CurveSize0 = TowConstants.TETHER_CURVE_STUDS
	beam.CurveSize1 = -TowConstants.TETHER_CURVE_STUDS
	beam.Transparency = NumberSequence.new(TowConstants.TETHER_TRANSPARENCY)
	beam.Parent = endPart

	-- Parked at the block until the first target arrives (the tag and the
	-- attributes replicate independently), so nothing flashes at the origin.
	endPart.Position = cube.Position
	endPart.Parent = workspace

	tethers[block] = {
		endPart = endPart,
		beam = beam,
		placed = false,
		highlight = nil,
		ringGui = nil,
		ringFrame = nil,
		blinkPhase = 0,
	}
end

for _, block in ipairs(CollectionService:GetTagged(TowConstants.TAG)) do
	addTether(block)
end
CollectionService:GetInstanceAddedSignal(TowConstants.TAG):Connect(addTether)
CollectionService:GetInstanceRemovedSignal(TowConstants.TAG):Connect(function(instance)
	if instance:IsA("Model") then
		removeTether(instance)
	end
end)

-- How far through the hold the schedule is (0 at the start, 1 from the snap
-- on), or nil when the tow has no schedule (yet).
local function markProgress(block: Model): number?
	local beganAt = block:GetAttribute(TowConstants.BEGAN_AT_ATTRIBUTE)
	local snapAt = block:GetAttribute(TowConstants.SNAP_AT_ATTRIBUTE)
	if type(beganAt) ~= "number" or type(snapAt) ~= "number" or snapAt <= beganAt then
		return nil
	end
	local now = workspace:GetServerTimeNow()
	local pausedAt = block:GetAttribute(TowConstants.PAUSED_AT_ATTRIBUTE)
	if type(pausedAt) == "number" then
		now = math.min(now, pausedAt)
	end
	return math.clamp((now - beganAt) / (snapAt - beganAt), 0, 1)
end

-- The tether tightens, the highlight blinks faster and the ring closes as the
-- snap nears; from the snap on all three are at full strength.
local function drawMark(block: Model, tether: Tether, progress: number, dt: number)
	local widthScale = lerp(TowConstants.TETHER_WIDTH_SCALE_START, 1, progress)
	tether.beam.Width0 = TowConstants.TETHER_WIDTH_AT_BLOCK * widthScale
	tether.beam.Width1 = TowConstants.TETHER_WIDTH_AT_TARGET * widthScale
	tether.beam.Transparency = NumberSequence.new(
		lerp(TowConstants.TETHER_TRANSPARENCY_START, TowConstants.TETHER_TRANSPARENCY_FULL, progress)
	)

	local highlight = tether.highlight
	if highlight == nil then
		highlight = makeHighlight(block)
		tether.highlight = highlight
	end
	local rate = lerp(TowConstants.BLINK_HZ_START, TowConstants.BLINK_HZ_END, progress)
	tether.blinkPhase = (tether.blinkPhase + rate * TAU * dt) % TAU
	local wave = (math.sin(tether.blinkPhase) + 1) * HALF
	highlight.FillTransparency = TowConstants.HIGHLIGHT_FILL_TRANSPARENCY_MAX
		- (TowConstants.HIGHLIGHT_FILL_TRANSPARENCY_MAX - TowConstants.HIGHLIGHT_FILL_TRANSPARENCY_MIN) * wave

	if tether.ringFrame == nil then
		local cube = block:FindFirstChild(CUBE_CHILD_NAME)
		if cube ~= nil and cube:IsA("BasePart") then
			tether.ringGui, tether.ringFrame = makeRing(cube)
		end
	end
	local ringFrame = tether.ringFrame
	if ringFrame ~= nil then
		-- From RING_START_SCALE times the block (the gui's full size) down to
		-- the block's size, which is 1 / RING_START_SCALE of the gui.
		local fraction = lerp(1, 1 / TowConstants.RING_START_SCALE, progress)
		ringFrame.Size = UDim2.fromScale(fraction, fraction)
	end
end

RunService.Heartbeat:Connect(function(dt)
	for block, tether in pairs(tethers) do
		if block.Parent == nil then
			removeTether(block)
			continue
		end
		local progress = markProgress(block)
		if progress ~= nil then
			drawMark(block, tether, progress, dt)
		end
		local target = block:GetAttribute(TowConstants.TARGET_ATTRIBUTE)
		if typeof(target) ~= "Vector3" then
			continue
		end
		if not tether.placed then
			tether.placed = true
			tether.endPart.Position = target
		else
			tether.endPart.Position = tether.endPart.Position:Lerp(
				target,
				1 - math.exp(-TowConstants.FOLLOW_RATE_PER_SEC * dt)
			)
		end
	end
end)

log:info("LetterTowTether started")
