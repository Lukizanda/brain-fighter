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

-- Concurrent-stream ceiling. In a six-player fight at the tap cooldown
-- this is ~24 streams a second; past the cap we stop drawing rather than
-- letting Beam count grow without bound. PERF.maxBlockPops already
-- existed as the reserved knob for exactly this.
local activeStreams = 0

local CollectStream = {}

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
	end

	connection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		local alpha = math.min(elapsed / FLIGHT_SEC, 1)

		-- The collector can stop existing mid-flight. Ending quietly is
		-- correct: there is no longer anywhere for the stream to go.
		if not toAttachment.Parent or not toAttachment:IsDescendantOf(workspace) then
			cleanup()
			return
		end

		-- Pull the source end along the ribbon toward the collector, so the
		-- stream is consumed from the block end rather than simply fading
		-- in place. Reads as being drawn in.
		local endPosition = toAttachment.WorldPosition
		anchorPart.Position = origin:Lerp(endPosition, alpha)

		beam.Transparency = NumberSequence.new(
			FADE_START_ALPHA + (1 - FADE_START_ALPHA) * alpha
		)

		if alpha >= 1 then
			cleanup()
		end
	end)

	-- Backstop. If Heartbeat somehow stops reaching this stream, the cap
	-- must not leak a slot and strand the cue for everyone.
	task.delay(FLIGHT_SEC * 4, cleanup)
end

return CollectStream
