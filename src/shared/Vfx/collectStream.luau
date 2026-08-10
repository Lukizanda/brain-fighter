--!strict

----------------------------------------------------------------------
-- collectStream
----------------------------------------------------------------------
-- Draws a block's mana flowing onto the player who popped it: a colour-
-- tinted ribbon from the block's position onto the collector, plus a
-- small arrival flash when it lands.
--
-- The PvP attribution cue (Phase 5.7 stage 3). The blaster beam used to
-- be the only thing linking a taker to a block for other players; this
-- replaces it and reads better, because it terminates on a person.
-- See wiki/design/tap-to-pop.md § Collect stream.
--
-- Shared rather than living in WorldVfxController because both VMs'
-- clients draw it from the same code: the popper draws it locally on the
-- frame they click (prediction), and every other client draws it from the
-- broadcast payload. Two implementations would drift.
--
-- CLIENT ONLY, for the same reason spawnEffect is — a server-side Beam
-- would replicate as geometry but the burst at the end would not, and the
-- whole thing would be anchored to a Part nobody else can see yet.
----------------------------------------------------------------------

local Debris            = game:GetService("Debris")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Logger    = require(ReplicatedStorage.Shared.Core.Logger)
local VfxConfig = require(ReplicatedStorage.Shared.Vfx.VfxConfig)

local log = Logger.new("collectStream")

----------------------------------------------------------------------
-- Tunables
----------------------------------------------------------------------

-- How long the stream takes to reach the collector.
--
-- Deliberately longer than the 0.25 s tap cooldown, so a fast speller
-- has two streams in the air at once. The first instinct was to fit it
-- *inside* the cooldown to avoid overlap, but overlap is the correct
-- read here — several streams converging says "that player is banking
-- letters fast", which is exactly the tell the cue exists to give. The
-- concurrent-stream cap below is what bounds the cost, not the duration.
--
-- Below ~0.3 s the arc is too brief to track to its destination, which
-- defeats the point of pointing at a person.
local FLIGHT_SEC = 0.4

-- Ribbon width at the block end and at the player end. It narrows as it
-- arrives so the eye is pulled along it toward the person, which is the
-- half of the cue that carries the PvP information.
local WIDTH_AT_BLOCK  = 1.6
local WIDTH_AT_PLAYER = 0.35

-- Sideways bow on the ribbon. A dead-straight line reads as a laser —
-- i.e. as the weapon this replaced. The curve is what makes it read as
-- something being drawn in rather than shot out.
local CURVE_STUDS = 6

-- The ribbon fades rather than vanishing: a Beam that disappears on a
-- frame boundary reads as a glitch, the same reasoning spawnEffect's
-- PointLight fade uses.
local FADE_START_ALPHA = 0.55

local LIGHT_EMISSION = 1
local BEAM_SEGMENTS  = 12

----------------------------------------------------------------------
-- Motes
----------------------------------------------------------------------
-- The sparkle cloud: individual points of light pulled out of the block
-- and into the collector. The ribbon says *there is a connection*; the
-- motes are what make it read as the block's mana being drained rather
-- than a line drawn between two objects.
--
-- Layered on top deliberately. The ribbon is load-bearing (it is the
-- attribution cue and it tracks a moving player for free), so it is the
-- last thing to drop; motes are the first, because losing them costs
-- flavour and losing the ribbon costs information.

local MOTE_COUNT_MAX = 8
local MOTE_COUNT_MIN = 3

local MOTE_SIZE_STUDS = 0.45

-- Radius of the shell motes are born on. Roughly the block's own half
-- extent, so they look like they came off its surface rather than
-- spawning at one point in its middle.
local MOTE_SPAWN_RADIUS = 2.2

-- Per-mote flight, as a fraction shaved off the ribbon's. The stagger is
-- the single thing that most stops N identical parts reading as one rigid
-- object.
--
-- Shortens only, never lengthens: the stream is torn down when the ribbon
-- lands, so a mote given a longer flight would be destroyed in mid-air
-- short of its target. Every mote therefore arrives at or before the
-- ribbon closes, which also puts the events in the right order — sparks
-- land, then the connection winks out.
local MOTE_FLIGHT_JITTER = 0.35

-- Sideways bow on each mote's path, jittered per mote. Straight lines
-- from a shell converge into an obvious cone; curved ones swirl.
local MOTE_CURVE_STUDS = 5

-- Motes shrink as they arrive, so the cloud visually "enters" the
-- collector instead of piling up on their chest and popping out.
local MOTE_END_SCALE = 0.25

-- Beyond this the motes are dropped and the ribbon carries the cue
-- alone. Individual 0.45-stud points are not resolvable at distance
-- anyway, so this is mostly free.
local MOTE_VISIBLE_DISTANCE = 160

-- Concurrent-stream ceiling. In a six-player fight at the tap cooldown
-- this is ~24 streams a second; past the cap we stop drawing rather than
-- letting Beam count grow without bound. PERF.maxBlockPops already
-- existed as the reserved knob for exactly this.
local activeStreams = 0

type Mote = {
	part: BasePart,
	control: Vector3,
	origin: Vector3,
	duration: number,
	baseSize: number,
}

local CollectStream = {}

-- Quadratic Bézier. P2 is passed in per frame rather than baked, because
-- the collector is running — the same reason the payload carries a userId
-- instead of a position. A mote whose endpoint was fixed at spawn would
-- curve gracefully into empty ground.
local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
	local inv = 1 - t
	return (p0 * (inv * inv)) + (p1 * (2 * inv * t)) + (p2 * (t * t))
end

-- How many motes this stream gets.
--
-- Scales down as the arena gets busy rather than cutting out at a
-- threshold: a fight that quietly loses half its sparkles still reads
-- correctly, whereas one where streams randomly have motes or not reads
-- as a bug. The local player is exempt — their own take is the one they
-- are looking at, it is one stream, and it is the feedback for their own
-- input.
local function moteCountFor(isLocalCollector: boolean): number
	if isLocalCollector then
		return MOTE_COUNT_MAX
	end
	local cap = math.max(VfxConfig.PERF.maxBlockPops, 1)
	local load = math.clamp(activeStreams / cap, 0, 1)
	return math.floor(MOTE_COUNT_MAX - (MOTE_COUNT_MAX - MOTE_COUNT_MIN) * load + 0.5)
end

-- A random point on a shell around the block, and a control point that
-- bows the path away from the straight line to the collector.
local function buildMote(origin: Vector3, toward: Vector3, tint: Color3, parent: Instance): Mote
	local dir = Vector3.new(
		math.random() * 2 - 1,
		math.random() * 2 - 1,
		math.random() * 2 - 1
	)
	if dir.Magnitude < 0.01 then
		dir = Vector3.yAxis
	end
	local spawnAt = origin + dir.Unit * (MOTE_SPAWN_RADIUS * (0.4 + math.random() * 0.6))

	local part = Instance.new("Part")
	part.Name         = "CollectMote"
	part.Shape        = Enum.PartType.Ball
	part.Size         = Vector3.one * MOTE_SIZE_STUDS
	part.Anchored     = true
	part.CanCollide   = false
	part.CanQuery     = false -- must never block the next tap's raycast
	part.CanTouch     = false
	part.CastShadow   = false
	part.Material     = Enum.Material.Neon
	part.Color        = tint
	part.Position     = spawnAt
	part.Parent       = parent

	-- Bow perpendicular to travel, in a random roll around that axis, so
	-- the cloud spirals in instead of collapsing along one plane.
	local travel = toward - spawnAt
	local axis = if travel.Magnitude > 0.01 then travel.Unit else Vector3.yAxis
	local perp = axis:Cross(Vector3.yAxis)
	if perp.Magnitude < 0.01 then
		perp = axis:Cross(Vector3.xAxis)
	end
	local roll = CFrame.fromAxisAngle(axis, math.random() * math.pi * 2)
	local bow = (roll * perp.Unit) * (MOTE_CURVE_STUDS * (0.3 + math.random() * 0.7))

	return {
		part     = part,
		origin   = spawnAt,
		control  = spawnAt:Lerp(toward, 0.5) + bow,
		duration = FLIGHT_SEC * (1 - math.random() * MOTE_FLIGHT_JITTER),
		baseSize = MOTE_SIZE_STUDS,
	}
end

-- Where the stream should terminate, resolved fresh on the frame it is
-- asked for. Nil once the collector has no character — a respawn or a
-- disconnect mid-flight ends the stream instead of erroring.
local function resolveCollector(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	if not player then return nil end
	local character = player.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root :: BasePart else nil
end

-- Draw one collect stream.
--
-- `origin` is a world position (the block is already being destroyed, so
-- there is no Instance left to hang it off). `collectorUserId` is
-- re-resolved every frame — see VfxBroadcast.collect for why this is not
-- a baked Vector3.
function CollectStream.play(origin: Vector3, collectorUserId: number, color: Color3?)
	if RunService:IsServer() then
		log:warnThrottled("server_call", 5, string.format(
			"refused on the server — the arrival burst would render for nobody. " ..
			"Use VfxBroadcast.collect instead.\n%s", debug.traceback()))
		return
	end

	local target = resolveCollector(collectorUserId)
	if not target then return end

	if activeStreams >= VfxConfig.PERF.maxBlockPops then
		log:infoThrottled("stream_cap", 5, string.format(
			"at the %d-stream cap — dropping this one", VfxConfig.PERF.maxBlockPops))
		return
	end
	activeStreams += 1

	local tint = color or VfxConfig.COLORS.red.primary

	-- An anchored, non-collidable, invisible Part is the only thing that
	-- can carry an Attachment at a fixed world point. CanQuery = false
	-- keeps it out of the block raycast — without it, the stream from one
	-- pop would silently block the next tap aimed through the same space.
	local anchorPart = Instance.new("Part")
	anchorPart.Name         = "CollectStreamAnchor"
	anchorPart.Anchored     = true
	anchorPart.CanCollide   = false
	anchorPart.CanQuery     = false
	anchorPart.CanTouch     = false
	anchorPart.Transparency = 1
	anchorPart.Size         = Vector3.one
	anchorPart.Position     = origin
	anchorPart.Parent       = workspace

	local fromAttachment = Instance.new("Attachment")
	fromAttachment.Parent = anchorPart

	-- Parented to the collector's own HumanoidRootPart, which is what makes
	-- the Beam track them: a Beam between two live Attachments follows both
	-- ends with no per-frame code at all. This is why the ribbon is the
	-- load-bearing layer of the cue and the last thing to drop under load.
	local toAttachment = Instance.new("Attachment")
	toAttachment.Name   = "CollectStreamEnd"
	toAttachment.Parent = target

	-- Motes, if this stream has earned any. Built before the loop so the
	-- driver below only ever advances them.
	--
	-- Skipped entirely when the block is too far to resolve individual
	-- 0.45-stud points, and thinned out as the arena gets busy. Both are
	-- degradations of flavour, never of the cue: the ribbon is unaffected.
	local motes: { Mote } = {}
	local isLocalCollector = collectorUserId == Players.LocalPlayer.UserId
	local camera = workspace.CurrentCamera
	local nearEnough = isLocalCollector
		or not camera
		or (camera.CFrame.Position - origin).Magnitude <= MOTE_VISIBLE_DISTANCE

	if nearEnough then
		local count = moteCountFor(isLocalCollector)
		local toward = target.Position
		for _ = 1, count do
			table.insert(motes, buildMote(origin, toward, tint, workspace))
		end
	end

	local beam = Instance.new("Beam")
	beam.Attachment0    = fromAttachment
	beam.Attachment1    = toAttachment
	beam.Color          = ColorSequence.new(tint)
	beam.LightEmission  = LIGHT_EMISSION
	beam.LightInfluence = 0
	beam.FaceCamera     = true
	beam.Segments       = BEAM_SEGMENTS
	beam.Width0         = WIDTH_AT_BLOCK
	beam.Width1         = WIDTH_AT_PLAYER
	beam.CurveSize0     = CURVE_STUDS
	beam.CurveSize1     = -CURVE_STUDS
	beam.Transparency   = NumberSequence.new(FADE_START_ALPHA)
	beam.Parent         = anchorPart

	local elapsed = 0
	local connection: RBXScriptConnection
	local finished = false

	local function cleanup()
		if finished then return end
		finished = true
		activeStreams -= 1
		if connection.Connected then connection:Disconnect() end
		if toAttachment.Parent then toAttachment:Destroy() end
		Debris:AddItem(anchorPart, 0)
		for _, mote in motes do
			Debris:AddItem(mote.part, 0)
		end
		table.clear(motes)
	end

	-- ONE connection drives the ribbon and every mote.
	--
	-- Not N tweens and not a connection per mote: at eight motes across a
	-- dozen concurrent streams that would be ~100 independent schedules
	-- for a 0.4 s effect. This is the same single-driver shape
	-- LetterBlockAnimator uses to bob the whole block field.
	connection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		local alpha = math.min(elapsed / FLIGHT_SEC, 1)

		-- The collector can stop existing mid-flight. Ending quietly is
		-- correct: there is no longer anywhere for the stream to go.
		if not toAttachment.Parent or not toAttachment:IsDescendantOf(workspace) then
			cleanup()
			return
		end

		-- Read once per frame and share it: every mote curves toward the
		-- same live point, and the collector is moving.
		local endPosition = toAttachment.WorldPosition

		-- Pull the source end along the ribbon toward the collector, so the
		-- stream is consumed from the block end rather than simply fading
		-- in place. Reads as being drawn in.
		anchorPart.Position = origin:Lerp(endPosition, alpha)

		beam.Transparency = NumberSequence.new(
			FADE_START_ALPHA + (1 - FADE_START_ALPHA) * alpha
		)

		for _, mote in motes do
			local part = mote.part
			if part.Parent then
				-- Per-mote clock, so the cloud lands staggered rather than
				-- snapping out of existence together.
				local mAlpha = math.min(elapsed / mote.duration, 1)
				part.Position = bezier(mote.origin, mote.control, endPosition, mAlpha)
				local scale = mote.baseSize * (1 - (1 - MOTE_END_SCALE) * mAlpha)
				part.Size = Vector3.one * scale
				if mAlpha >= 1 then
					-- Arrived. Destroy on landing rather than at stream end,
					-- so an early mote does not hang on the collector's chest
					-- waiting for the ribbon to catch up.
					part:Destroy()
				end
			end
		end

		if alpha >= 1 then
			cleanup()
		end
	end)

	-- Backstop. If Heartbeat somehow stops reaching this stream, the cap
	-- must not leak a slot and strand the cue for everyone.
	task.delay(FLIGHT_SEC * 4, cleanup)
end

return CollectStream
