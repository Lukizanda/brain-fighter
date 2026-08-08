--!strict

----------------------------------------------------------------------
-- BarrierCrumbleController
----------------------------------------------------------------------
-- Owns a Stone Wall's visual decline, both halves of it:
--
--   cracks  — fracture lines spread across the slab's faces through the
--             last few seconds of its life, so its collapse is something
--             you can see coming and plan around
--   rubble  — the slab breaks into falling chunks when it finally goes,
--             instead of blinking out of existence
--
-- One controller rather than two because both write the same object's
-- appearance on the same frames, and two systems doing that is the fight
-- wiki/concepts/SingleOwnership.md exists to prevent. They are also one
-- effect told in order: the cracks are the crumble's telegraph, and the
-- crumble is the cracks paying off.
--
-- Triggered by the slab's own death. `SkillVisuals.spawnBarrier` tags
-- every barrier with `SkillConstants.BARRIER_TAG`; `Debris` reclaims it
-- on the server when `durationSec` is up, every client's replicated copy
-- dies with it, and `GetInstanceRemovedSignal` hands this controller the
-- Part on the way out. CFrame, Size and Color are still readable on a
-- destroyed Instance, which is the whole trick — the collapse needs no
-- payload because the thing it describes was already replicated.
--
-- So nothing new crosses the wire for a wall expiring, and this follows
-- the same shape as ShieldVfx and FreezeVfx: the server writes state on
-- a replicated object, the client controller renders it. Here the state
-- being written is simply "gone".
--
-- **Cosmetic only.** The rubble is CanCollide = false and never blocks
-- anything. Collision ends exactly when the slab is destroyed, on the
-- frame the duration expires, which is what keeps the gameplay contract
-- (`durationSec` = how long the wall blocks) honest while the collapse
-- plays out afterwards. A player can run straight through the falling
-- chunks, which is correct — they are dust and debris, not a wall.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)
local SkillVisuals   = require(ReplicatedStorage.Shared.Skills.SkillVisuals)

local log = Logger.new("BarrierCrumble")

----------------------------------------------------------------------
-- Tunables
----------------------------------------------------------------------

-- Grid the slab is cut into. 5x4 on the shipped 16x10 wall gives chunks
-- a bit over 3 studs across — big enough to read as masonry, small
-- enough that the wall doesn't come apart like a four-piece jigsaw.
local COLUMNS = 5
local ROWS    = 4

-- Chunks are driven by hand, not by the physics engine. Unanchored parts
-- would need a collision group to stop twenty tumbling boxes shoving
-- players around, and Roblox's 196 studs/s^2 drops them 24 studs inside
-- the first half second — the rubble would be through the floor before
-- you registered the wall breaking. Anchored parts on a gravity we pick
-- cost nothing, disturb nobody, and can be told where the floor is.
local GRAVITY_STUDS_PER_SEC2 = 105

-- Outward shove, scaled by how high up the slab a chunk started: the
-- base barely moves while the top topples clear. This scaling is what
-- makes it read as collapsing rather than as descending in formation.
local TOPPLE_SPEED_STUDS = 7

-- Sideways drift, scaled by distance from the wall's centreline, so the
-- ends fan out and the middle drops.
local SPREAD_SPEED_STUDS = 3

-- Random slop on the above, so no two chunks travel the same path.
local VELOCITY_JITTER_STUDS = 2.5

-- Tumble rate, radians/sec, also scaled by starting height.
local SPIN_RAD_PER_SEC = 4.5

-- Bottom-up release: the base gives way first and the courses above
-- follow. The difference between a wall collapsing and a wall being
-- deleted all at once.
local STAGGER_SEC = 0.16

-- The tallest chunk falls ~8 studs, which at the gravity above puts the
-- last piece down around 0.55 s. The fade is sized so it begins just
-- after that rather than leaving a static pile sitting there: at 1.8/0.7
-- the rubble held motionless for half a second before it started going,
-- and the pause read as the effect having got stuck.
local LIFETIME_SEC = 1.6
local FADE_SEC     = 0.9

-- Chunks stop here rather than falling through the floor — slightly
-- *into* it, so the pile reads as half-buried rubble instead of boxes
-- balanced on an invisible plane. Fraction of a chunk's own height.
local REST_EMBED_FRACTION = 0.35

-- Per-chunk brightness slop. Twenty identically coloured boxes read as
-- one object that was cut up; a little variance reads as broken rock.
local SHADE_JITTER = 0.10

local RUBBLE_FOLDER_NAME = "SkillBarrierRubble"

----------------------------------------------------------------------
-- Cracks
----------------------------------------------------------------------

-- How long before the slab dies the first fracture shows. The whole
-- point is lead time: a warning that arrives half a second early is a
-- surprise with extra steps, and a player standing behind cover needs
-- long enough to decide to move. 2.5 s of a 6 s wall leaves most of its
-- life looking solid.
local CRACK_LEAD_SEC = 2.5

-- Drawn as SurfaceGui line segments rather than a crack *texture*.
-- Decals would need an asset, and third-party Creator Store images in
-- this universe are a coin flip on whether they load at all
-- (wiki/log.md — a texture that silently never resolves would leave the
-- wall with no telegraph and no error). Frames are owned and guaranteed
-- to render.
--
-- **Each crack snaps in whole; nothing animates its length.** Stone does
-- not tear slowly. A fracture is an instant event — it is either there or
-- it isn't — and drawing one on over a fifth of a second reads as a pen
-- stroke, which is exactly what the first version looked like. What is
-- gradual is the *count*: one crack, then another somewhere else, then
-- another, accelerating as the wall runs out of time. The wall degrades
-- over seconds out of a sequence of instants.
--
-- This is also why the geometry is fixed at build time and stepCracks
-- only toggles Visible — there is nothing left to interpolate.
local CRACK_PIXELS_PER_STUD = 40

-- How many of the authored patterns below a given face reveals.
local CRACKS_PER_FACE = 6

local CRACK_THICKNESS_PX = 10

-- Cracks taper: a fracture is widest where it started and finest at the
-- tip. Fraction of the base thickness the last segment keeps.
local CRACK_TIP_THICKNESS_FRACTION = 0.45

-- Branches come off an established crack, so they read as secondary.
local CRACK_BRANCH_THICKNESS_FRACTION = 0.6

-- When each crack fires, as a fraction of the lead window. Spread across
-- most of it so the fractures arrive as a sequence of separate events
-- rather than in a clump, with the last one landing before the slab goes.
local CRACK_STAGGER_SPAN = 0.85

-- Slop on each crack's moment, so the two faces don't fire in lockstep
-- and the cadence isn't metronomic. Clamped below 1 — a crack jittered
-- past the end of the window would never appear at all.
local CRACK_TIMING_JITTER = 0.06
local CRACK_LATEST_APPEAR = 0.95

-- Mild ease-in on the spread. Linear is a countdown; accelerating reads
-- as failure. Kept mild deliberately — anything steeper backloads the
-- cracks into the last half second and stops being a warning at all.
local CRACK_PROGRESS_EXPONENT = 1.3

local CRACK_COLOR = Color3.fromRGB(24, 22, 20)

-- Both broad faces. A 2-stud slab's edges aren't worth cracking, and you
-- can't see both faces at once, so each draws its own subset rather than
-- being mirrored through the wall.
local CRACK_FACES: { Enum.NormalId } = { Enum.NormalId.Front, Enum.NormalId.Back }

----------------------------------------------------------------------
-- The crack atlas
----------------------------------------------------------------------
-- Authored fracture patterns in NORMALISED face coordinates: x runs 0 at
-- the left edge to 1 at the right, y runs 0 at the top to 1 at the base
-- (matching the GUI canvas, whose origin is top-left). Each pattern is a
-- list of strokes; each stroke is a polyline. Stroke 1 is the trunk and
-- any others are branches, authored to start on a point of the trunk so
-- they join it.
--
-- **Authored rather than generated, and that is a bug fix.** The first
-- version walked each crack from a random base point with random
-- headings and random segment lengths, and nothing stopped that walk
-- leaving the face — a crack starting near an edge and turning outward
-- rendered as lines hanging in the air off the side of the wall.
-- Clamping a random walk means either steering it (which straightens
-- cracks against the edge, where they most want to look natural) or
-- rejecting and retrying (unbounded work on a frame). Fixed points sized
-- to the slab cannot leave it in the first place, need no per-wall
-- generation, and can actually be looked at and tuned.
--
-- Cracks climb from the base, which is where a wall under its own weight
-- fails. Variety across the set is deliberate: different heights reached,
-- different amounts of lateral travel, some branched and some not.
--
-- **Every point must lie within [0, 1] on both axes** — that invariant is
-- what keeps the pattern on the slab. It is checked once at startup
-- rather than trusted; see the validation below.
local CRACK_PATTERNS: { { { Vector2 } } } = {
	-- Tall trunk, low branch.
	{
		{ Vector2.new(0.13, 1.00), Vector2.new(0.17, 0.79), Vector2.new(0.10, 0.61), Vector2.new(0.16, 0.38) },
		{ Vector2.new(0.17, 0.79), Vector2.new(0.28, 0.68) },
	},
	-- Long, steep, unbranched.
	{
		{ Vector2.new(0.31, 1.00), Vector2.new(0.35, 0.81), Vector2.new(0.29, 0.60), Vector2.new(0.37, 0.42), Vector2.new(0.32, 0.23) },
	},
	-- Short and stubby.
	{
		{ Vector2.new(0.50, 1.00), Vector2.new(0.45, 0.86), Vector2.new(0.52, 0.72) },
	},
	-- Wide fork near the top.
	{
		{ Vector2.new(0.67, 1.00), Vector2.new(0.71, 0.83), Vector2.new(0.65, 0.65), Vector2.new(0.70, 0.49) },
		{ Vector2.new(0.65, 0.65), Vector2.new(0.78, 0.57) },
	},
	-- Leans hard to one side as it climbs.
	{
		{ Vector2.new(0.87, 1.00), Vector2.new(0.81, 0.82), Vector2.new(0.88, 0.63), Vector2.new(0.79, 0.44) },
	},
	-- Tight zigzag, mid height.
	{
		{ Vector2.new(0.23, 1.00), Vector2.new(0.29, 0.87), Vector2.new(0.22, 0.73), Vector2.new(0.30, 0.57) },
	},
	-- Low and forked, both arms short.
	{
		{ Vector2.new(0.43, 1.00), Vector2.new(0.39, 0.85), Vector2.new(0.45, 0.71) },
		{ Vector2.new(0.45, 0.71), Vector2.new(0.36, 0.60) },
	},
	-- The tallest in the set; reaches most of the way up the slab.
	{
		{ Vector2.new(0.60, 1.00), Vector2.new(0.64, 0.85), Vector2.new(0.57, 0.69), Vector2.new(0.63, 0.50), Vector2.new(0.57, 0.29) },
	},
	-- Gentle, nearly vertical.
	{
		{ Vector2.new(0.77, 1.00), Vector2.new(0.74, 0.85), Vector2.new(0.79, 0.69), Vector2.new(0.75, 0.53) },
	},
	-- Hugs the left edge — the case that used to run off the face.
	{
		{ Vector2.new(0.06, 1.00), Vector2.new(0.10, 0.83), Vector2.new(0.05, 0.67), Vector2.new(0.11, 0.51) },
	},
}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

type Chunk = {
	part: BasePart,
	origin: CFrame,
	velocity: Vector3,
	spin: Vector3,
	releaseAt: number,
	restY: number,
	-- Time (relative to release) at which this chunk hit the rest plane.
	-- Set once, then position and rotation both freeze by evaluating at
	-- it instead of at the live clock.
	restAt: number?,
}

type Crumble = {
	elapsed: number,
	folder: Folder,
	chunks: { Chunk },
}

-- One fracture line segment, fully placed at build time. `appearAt` is
-- the point in the lead window at which its crack snaps into existence —
-- shared by every segment of that crack, so the whole fracture lands on
-- one frame.
type CrackSegment = {
	frame: Frame,
	appearAt: number,
}

local active: { Crumble } = {}
local cracking: { [BasePart]: { CrackSegment } } = {}

local function jitter(magnitude: number): number
	return (math.random() * 2 - 1) * magnitude
end

----------------------------------------------------------------------
-- Cracks
----------------------------------------------------------------------

-- Startup check on the invariant the atlas rests on. A pattern edited
-- out of range is exactly the bug the atlas replaced, so it fails loudly
-- here rather than by drawing lines off the side of a wall in a match.
for patternIndex, pattern in ipairs(CRACK_PATTERNS) do
	for strokeIndex, stroke in ipairs(pattern) do
		for pointIndex, point in ipairs(stroke) do
			if point.X < 0 or point.X > 1 or point.Y < 0 or point.Y > 1 then
				log:warn(string.format(
					"crack pattern %d stroke %d point %d is outside the face (%.2f, %.2f)"
						.. " — it will be clipped at the slab edge",
					patternIndex, strokeIndex, pointIndex, point.X, point.Y
				))
			end
		end
	end
end

-- Draws one authored pattern onto a face, scaled to the slab. Every
-- segment of the pattern shares `appearAt`, so the fracture arrives
-- complete rather than unzipping.
local function addCrack(
	container: Frame,
	canvasPx: Vector2,
	pattern: { { Vector2 } },
	mirrored: boolean,
	segments: { CrackSegment },
	appearAt: number
)
	for strokeIndex, stroke in ipairs(pattern) do
		local trunkThickness = if strokeIndex == 1
			then CRACK_THICKNESS_PX
			else CRACK_THICKNESS_PX * CRACK_BRANCH_THICKNESS_FRACTION

		for pointIndex = 1, #stroke - 1 do
			local fromNorm = stroke[pointIndex]
			local toNorm   = stroke[pointIndex + 1]
			-- Mirroring doubles the apparent variety of the atlas for one
			-- subtraction, and cannot push a point out of bounds because
			-- 1 - x is in [0, 1] whenever x is.
			if mirrored then
				fromNorm = Vector2.new(1 - fromNorm.X, fromNorm.Y)
				toNorm   = Vector2.new(1 - toNorm.X, toNorm.Y)
			end

			local fromPx = fromNorm * canvasPx
			local toPx   = toNorm * canvasPx
			local delta  = toPx - fromPx
			local lengthPx = delta.Magnitude
			if lengthPx <= 0 then continue end

			local taper = 1 - (1 - CRACK_TIP_THICKNESS_FRACTION)
				* ((pointIndex - 1) / math.max(#stroke - 1, 1))
			local centre = fromPx + delta / 2

			local frame = Instance.new("Frame")
			frame.Name        = "CrackSegment"
			-- Centre-anchored and placed at the midpoint of the run it
			-- covers. Rotation pivots about the element's centre, so
			-- anchoring there makes pivot and anchor the same point and
			-- the segment lands exactly on the line between the two
			-- authored points. With a left-edge AnchorPoint the frame
			-- swings off its start and the crack renders as disconnected
			-- dashes.
			frame.AnchorPoint      = Vector2.new(0.5, 0.5)
			frame.Position         = UDim2.fromOffset(centre.X, centre.Y)
			frame.Size             = UDim2.fromOffset(lengthPx, trunkThickness * taper)
			frame.Rotation         = math.deg(math.atan2(delta.Y, delta.X))
			frame.BackgroundColor3 = CRACK_COLOR
			frame.BorderSizePixel  = 0
			-- Fully formed and hidden. The only thing that ever changes is
			-- this flag, on the frame its crack fires.
			frame.Visible          = false
			frame.Parent           = container

			table.insert(segments, { frame = frame, appearAt = appearAt })
		end
	end
end

-- Indices 1..#CRACK_PATTERNS in random order. Each face reveals a subset,
-- so two walls standing side by side don't fracture identically.
local function shuffledPatternIndices(): { number }
	local order = {}
	for index = 1, #CRACK_PATTERNS do
		order[index] = index
	end
	for index = #order, 2, -1 do
		local swap = math.random(index)
		order[index], order[swap] = order[swap], order[index]
	end
	return order
end

local function buildCracks(barrier: BasePart)
	local segments: { CrackSegment } = {}
	local canvasPx = Vector2.new(
		barrier.Size.X * CRACK_PIXELS_PER_STUD,
		barrier.Size.Y * CRACK_PIXELS_PER_STUD
	)
	local revealed = math.min(CRACKS_PER_FACE, #CRACK_PATTERNS)

	for _, face in ipairs(CRACK_FACES) do
		local gui = Instance.new("SurfaceGui")
		gui.Name          = "BarrierCracks"
		gui.Face          = face
		gui.SizingMode    = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = CRACK_PIXELS_PER_STUD
		-- Shaded like the surface it sits on. At the default 0 the cracks
		-- are fullbright and glow out of a shadowed wall.
		gui.LightInfluence = 1
		-- Parented to the slab, so they replicate nowhere and are cleaned
		-- up by the same Destroy that triggers the crumble.
		gui.Parent = barrier

		-- Belt and braces on staying inside the wall. The atlas is
		-- authored in range and validated at startup, but a segment has
		-- *thickness*, so one lying along an edge would otherwise put half
		-- its width past it — and clipping turns "we author carefully"
		-- into something the engine enforces. A crack cut off at the slab
		-- edge is also just what a crack reaching the edge looks like.
		local container = Instance.new("Frame")
		container.Name                   = "CrackCanvas"
		container.Size                   = UDim2.fromScale(1, 1)
		container.BackgroundTransparency = 1
		container.ClipsDescendants       = true
		container.Parent                 = gui

		local order = shuffledPatternIndices()
		for slot = 1, revealed do
			local appearAt = math.min(
				(slot - 1) / revealed * CRACK_STAGGER_SPAN + jitter(CRACK_TIMING_JITTER),
				CRACK_LATEST_APPEAR
			)
			addCrack(
				container,
				canvasPx,
				CRACK_PATTERNS[order[slot]],
				math.random() < 0.5,
				segments,
				appearAt
			)
		end
	end

	cracking[barrier] = segments
end

local function stepCracks(barrier: BasePart, segments: { CrackSegment })
	-- Read every frame rather than caching at spawn: the attribute
	-- replicates with the Instance, but the tag it is discovered by
	-- replicates on its own schedule, and this sidesteps the ordering
	-- question entirely.
	local expiresAt = barrier:GetAttribute(SkillConstants.BARRIER_EXPIRES_AT)
	if typeof(expiresAt) ~= "number" then return end

	local remaining = expiresAt - workspace:GetServerTimeNow()
	if remaining > CRACK_LEAD_SEC then return end

	local progress = math.clamp(1 - remaining / CRACK_LEAD_SEC, 0, 1) ^ CRACK_PROGRESS_EXPONENT

	-- On or off, nothing in between. The wall's decay is gradual because
	-- these moments are spread out, not because any one of them is.
	for _, segment in ipairs(segments) do
		segment.frame.Visible = progress >= segment.appearAt
	end
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function buildChunk(
	folder: Folder,
	slabCFrame: CFrame,
	slabSize: Vector3,
	color: Color3,
	column: number,
	row: number
): Chunk
	local cellSize = Vector3.new(slabSize.X / COLUMNS, slabSize.Y / ROWS, slabSize.Z)

	-- Cell centres in slab-local space, so the chunks tile the slab
	-- exactly. Seamless at t=0 is the point: every gap you see afterwards
	-- was opened by the collapse rather than being there from the start.
	local acrossFrac = (column + 0.5) / COLUMNS - 0.5
	local heightFrac = (row + 0.5) / ROWS
	local origin = slabCFrame * CFrame.new(
		acrossFrac * slabSize.X,
		(heightFrac - 0.5) * slabSize.Y,
		0
	)

	local shade = 1 + jitter(SHADE_JITTER)
	local part = Instance.new("Part")
	part.Name        = "RubbleChunk"
	part.Size        = cellSize
	part.CFrame      = origin
	part.Anchored    = true
	part.CanCollide  = false
	part.CanQuery    = false
	part.CanTouch    = false
	part.CastShadow  = false
	part.Material    = Enum.Material.Slate
	part.Color       = Color3.new(
		math.clamp(color.R * shade, 0, 1),
		math.clamp(color.G * shade, 0, 1),
		math.clamp(color.B * shade, 0, 1)
	)
	part.Parent = folder

	-- Topple direction is chosen per chunk rather than per wall, so the
	-- slab falls apart to both sides. A wall that tips entirely one way
	-- reads as being pushed over by something.
	local toppleSign = if math.random() < 0.5 then -1 else 1
	local velocity = slabCFrame.LookVector * (TOPPLE_SPEED_STUDS * heightFrac * toppleSign)
		+ slabCFrame.RightVector * (SPREAD_SPEED_STUDS * acrossFrac * 2)
		+ Vector3.new(jitter(VELOCITY_JITTER_STUDS), 0, jitter(VELOCITY_JITTER_STUDS))

	local footY = slabCFrame.Position.Y - slabSize.Y / 2

	return {
		part      = part,
		origin    = origin,
		velocity  = velocity,
		spin      = Vector3.new(
			jitter(SPIN_RAD_PER_SEC) * heightFrac,
			jitter(SPIN_RAD_PER_SEC) * heightFrac,
			jitter(SPIN_RAD_PER_SEC) * heightFrac
		),
		releaseAt = heightFrac * STAGGER_SEC + jitter(STAGGER_SEC * 0.25),
		restY     = footY + cellSize.Y * 0.5 * (1 - REST_EMBED_FRACTION),
		restAt    = nil,
	}
end

local function startCrumble(slabCFrame: CFrame, slabSize: Vector3, color: Color3)
	local folder = Instance.new("Folder")
	folder.Name   = RUBBLE_FOLDER_NAME
	folder.Parent = workspace

	local chunks: { Chunk } = {}
	for column = 0, COLUMNS - 1 do
		for row = 0, ROWS - 1 do
			table.insert(chunks, buildChunk(folder, slabCFrame, slabSize, color, column, row))
		end
	end

	table.insert(active, { elapsed = 0, folder = folder, chunks = chunks })

	-- The same three-point plume the wall rose out of, drawn locally.
	-- Same stone, same spot — what distinguishes arriving from collapsing
	-- is which way the slab is going, not what the ground does about it.
	local footCFrame = slabCFrame * CFrame.new(0, -slabSize.Y / 2, 0)
	SkillVisuals.barrierGroundDust(footCFrame, slabSize)
end

----------------------------------------------------------------------
-- Per-frame
----------------------------------------------------------------------

local function stepChunk(chunk: Chunk, elapsed: number)
	local t = elapsed - chunk.releaseAt
	-- Still standing: this course hasn't given way yet.
	if t <= 0 then return end

	-- Down and resting: skipped entirely from here on, which is what
	-- stops a landed chunk spinning in the pile.
	if chunk.restAt then return end

	local fall = 0.5 * GRAVITY_STUDS_PER_SEC2 * t * t
	local position = chunk.origin.Position + chunk.velocity * t - Vector3.new(0, fall, 0)
	if position.Y <= chunk.restY then
		chunk.restAt = t
		position = Vector3.new(position.X, chunk.restY, position.Z)
	end

	chunk.part.CFrame = CFrame.new(position)
		* chunk.origin.Rotation
		* CFrame.Angles(chunk.spin.X * t, chunk.spin.Y * t, chunk.spin.Z * t)
end

local function stepCrumble(crumble: Crumble, dt: number): boolean
	crumble.elapsed += dt

	local fadeAlpha = math.clamp(
		(crumble.elapsed - (LIFETIME_SEC - FADE_SEC)) / FADE_SEC,
		0, 1
	)

	for _, chunk in ipairs(crumble.chunks) do
		stepChunk(chunk, crumble.elapsed)
		-- fadeAlpha and Transparency both run 0 (solid) to 1 (gone).
		if fadeAlpha > 0 then
			chunk.part.Transparency = fadeAlpha
		end
	end

	if crumble.elapsed >= LIFETIME_SEC then
		crumble.folder:Destroy()
		return true
	end
	return false
end

RunService.Heartbeat:Connect(function(dt: number)
	for barrier, segments in pairs(cracking) do
		-- A barrier removed some way other than Destroy (a round reset
		-- reparenting it, say) would otherwise be walked forever.
		if barrier.Parent then
			stepCracks(barrier, segments)
		else
			cracking[barrier] = nil
		end
	end

	-- Reverse so removals don't shift the indices still to be visited.
	for i = #active, 1, -1 do
		if stepCrumble(active[i], dt) then
			table.remove(active, i)
		end
	end
end)

----------------------------------------------------------------------
-- Trigger
----------------------------------------------------------------------

local function isUsableSlab(instance: Instance): BasePart?
	if not instance:IsA("BasePart") then return nil end
	local slab = instance :: BasePart
	-- A degenerate slab would give a zero-pixel crack canvas and a grid of
	-- zero-size chunks. Cheaper to refuse than to litter the workspace
	-- with invisible rubble.
	local size = slab.Size
	if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then return nil end
	return slab
end

for _, tagged in ipairs(CollectionService:GetTagged(SkillConstants.BARRIER_TAG)) do
	local slab = isUsableSlab(tagged)
	-- Walls already standing when this client joined. The deadline is
	-- absolute, so a late joiner picks up mid-life cracking correctly.
	if slab then buildCracks(slab) end
end

CollectionService:GetInstanceAddedSignal(SkillConstants.BARRIER_TAG):Connect(function(instance: Instance)
	local slab = isUsableSlab(instance)
	if not slab then
		log:warnThrottled("bad_size_add", 5, "barrier tagged with a degenerate Size — no cracks")
		return
	end
	buildCracks(slab)
end)

CollectionService:GetInstanceRemovedSignal(SkillConstants.BARRIER_TAG):Connect(function(instance: Instance)
	local slab = isUsableSlab(instance)
	if not slab then
		log:warnThrottled("bad_size", 5, "barrier removed with a degenerate Size — no crumble")
		return
	end

	cracking[slab] = nil
	startCrumble(slab.CFrame, slab.Size, slab.Color)
end)

log:info("ready")
