--!strict

----------------------------------------------------------------------
-- BarrierCrumbleController
----------------------------------------------------------------------
-- Owns a Stone Wall's visual decline, both halves of it:
--
--   cracks  — fracture lines spread across the slab's faces through the
--             last few seconds of its life, each landing with a snap, so
--             its collapse is something you can see and hear coming and
--             plan around
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
--
-- **The cracks are authored against this same grid**, and that coupling is
-- the point rather than an accident: see the atlas below. Changing these
-- numbers moves the seams the crack patterns are drawn along, so the
-- atlas has to be re-authored to match — the startup validation catches a
-- pattern that no longer *fits* the grid, but it cannot tell that one
-- which fits a smaller grid has stopped spanning the wall.
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
-- only toggles Visible and fires the snap — there is nothing left to
-- interpolate.
local CRACK_PIXELS_PER_STUD = 40

-- How many of the authored patterns below a given face reveals.
local CRACKS_PER_FACE = 6

local CRACK_THICKNESS_PX = 10

-- Cracks taper: a fracture is widest where it started and finest at the
-- tip. Fraction of the base thickness the last segment keeps.
local CRACK_TIP_THICKNESS_FRACTION = 0.45

-- Branches come off an established crack, so they read as secondary.
local CRACK_BRANCH_THICKNESS_FRACTION = 0.6

-- Jaggedness. A crack follows a seam but does not follow it *exactly* —
-- stone fails along a weakness, wandering either side of it. Each seam run
-- is cut into this many sub-segments whose interior joints are shoved
-- perpendicular to the run, which is what stops the pattern reading as a
-- drawn-on grid.
--
-- The endpoints of every run are left untouched, on the lattice node. That
-- is what keeps the wander cosmetic: consecutive runs still meet, branches
-- still land on their trunk, and the crack still arrives at the seam
-- corners the chunks will actually part along.
--
-- Amplitude is in studs, converted at draw time, so the wander is the same
-- physical size on a wall of any proportion. As a fraction of a chunk it
-- has to stay small — a crack that strays a third of the way into a face
-- stops reading as belonging to that seam at all.
local CRACK_JAG_SEGMENTS = 3
local CRACK_JAG_STUDS    = 0.35

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

-- Optional audio on each fracture, and optional in the sense that the
-- telegraph works without it: the cracks are the warning, this only makes
-- them harder to miss for a player facing the other way. Off is a
-- supported state, not a broken one — flip this and the wall still cracks
-- and still crumbles, in silence.
--
-- Worth having a switch at all because it is the piece most likely to want
-- pulling. Six snaps per wall is fine for one wall and could get busy in a
-- fight with several standing at once, and that is a judgement to make in
-- a real match rather than here.
local CRACK_SOUND_ENABLED   = true
local CRACK_SOUND_EFFECT_ID = "wall_crack"

-- Both broad faces. A 2-stud slab's edges aren't worth cracking, and you
-- can't see both faces at once, so each draws its own subset rather than
-- being mirrored through the wall.
local CRACK_FACES: { Enum.NormalId } = { Enum.NormalId.Front, Enum.NormalId.Back }

----------------------------------------------------------------------
-- The crack atlas
----------------------------------------------------------------------
-- Authored fracture patterns in SEAM-LATTICE coordinates. A node is
-- `Vector2.new(column, row)` on the grid the slab is cut into: column runs
-- 0 at the left edge to COLUMNS at the right, row runs 0 at the base to
-- ROWS at the top. Both are integers, and consecutive nodes in a stroke
-- must be neighbours — every run therefore lies along a line the crumble
-- actually breaks on. Each pattern is a list of strokes; stroke 1 is the
-- trunk and any others are branches, authored to start on a node of the
-- trunk so they join it.
--
-- **On the lattice, and that is a bug fix.** The previous atlas was drawn
-- freehand in normalised face coordinates, and looked fine on a still
-- wall — but the slab breaks into a grid of boxes, so every crack was
-- promising a fracture line the collapse then ignored, and the collapse
-- opened straight seams the cracks had said nothing about. The telegraph
-- has to be a telegraph *of this collapse*: a crack is where the wall is
-- about to come apart, so it belongs on the seam it comes apart along.
--
-- Rooting the geometry in the lattice also subsumes the bug the freehand
-- atlas was itself written to fix. The version before that walked each
-- crack from a random point with random headings, and nothing stopped the
-- walk leaving the face — cracks rendered as lines hanging in the air off
-- the side of the wall. A node is in bounds by construction, so there is
-- nothing left to steer or reject; only the jag between nodes needs
-- clamping, and it is bounded before it is applied.
--
-- Two rules shape the set, and both were learned by drawing it.
--
-- **No two patterns use the same run.** Six of the ten are drawn on a
-- face, and two cracks laid along one seam don't read as two cracks — the
-- second to appear lands on the first and mostly thickens it, so a
-- fracture that should have been its own event is spent for nothing.
-- Disjointness is a property of the set, checked at startup, which is what
-- lets any six be revealed without the reveal having to think about it
-- (`chooseCracks` still does, because mirroring can reintroduce a clash
-- the authored set doesn't have).
--
-- **Nothing runs along the outer edges** — no vertical on column 0 or
-- COLUMNS, no horizontal on row 0 or ROWS. Those seams are the slab's own
-- silhouette, so a crack drawn on one doesn't read as a crack at all; it
-- reads as an outline. The first disjoint set had four patterns on the
-- outer columns, and because they were disjoint they stacked end to end
-- into unbroken lines up both sides, framing the wall like a picture. The
-- rule costs the interesting half of nothing: the base still offers four
-- runs to climb out of, and horizontals may still *reach* an edge, they
-- just may not travel along one.
--
-- What is left after both rules: four cracks climbing from the base (which
-- is where a wall under its own weight fails), two low bed joints running
-- across them, and four rooted higher up on a joint or reaching in from an
-- edge. Different heights, different lateral travel, some branched, some a
-- plain vertical — and spread over the whole face rather than one busy
-- corner, since a pattern's place in the set is now also its place on the
-- wall.
--
-- **Every node must be an integer within the grid, and every step must be
-- to a neighbour.** Those two invariants are what keep a pattern on the
-- slab and on the seams. They are checked once at startup rather than
-- trusted; see the validation below.
local CRACK_PATTERNS: { { { Vector2 } } } = {
	-- Base column 1. Climbs two courses, then turns out to the left edge.
	{
		{ Vector2.new(1, 0), Vector2.new(1, 1), Vector2.new(1, 2), Vector2.new(0, 2) },
	},
	-- Base column 2. Three courses dead straight — the plain vertical of
	-- the set — with a short branch peeling off partway up.
	{
		{ Vector2.new(2, 0), Vector2.new(2, 1), Vector2.new(2, 2), Vector2.new(2, 3) },
		{ Vector2.new(2, 2), Vector2.new(1, 2) },
	},
	-- Base column 3. Climbs two, then steps out to mid-face.
	{
		{ Vector2.new(3, 0), Vector2.new(3, 1), Vector2.new(3, 2), Vector2.new(4, 2) },
	},
	-- Base column 4. Climbs two, then runs out to the right edge.
	{
		{ Vector2.new(4, 0), Vector2.new(4, 1), Vector2.new(4, 2), Vector2.new(5, 2) },
	},
	-- Low bed joint crossing the left half. Cuts across whatever is
	-- climbing out of the base under it.
	{
		{ Vector2.new(0, 1), Vector2.new(1, 1), Vector2.new(2, 1) },
	},
	-- The same failure on the right half.
	{
		{ Vector2.new(3, 1), Vector2.new(4, 1), Vector2.new(5, 1) },
	},
	-- Upper left, climbing off a joint to the top edge.
	{
		{ Vector2.new(1, 2), Vector2.new(1, 3), Vector2.new(1, 4) },
	},
	-- Bed joint high on the left. The quietest in the set.
	{
		{ Vector2.new(0, 3), Vector2.new(1, 3), Vector2.new(2, 3) },
	},
	-- Upper middle, climbing to the top with a fork near the crown.
	{
		{ Vector2.new(3, 2), Vector2.new(3, 3), Vector2.new(3, 4) },
		{ Vector2.new(3, 3), Vector2.new(4, 3) },
	},
	-- Reaches in from the right edge high up, then turns for the crown.
	{
		{ Vector2.new(5, 3), Vector2.new(4, 3), Vector2.new(4, 4) },
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

-- Everything one cracking slab needs per frame.
--
-- `moments` is one entry per stagger slot, not per crack, and that is the
-- point of it: both faces draw their own fracture for the same moment, so
-- keying the sound on the crack would hit twice for every one the player
-- perceives. Ascending, and consumed in order by `played`.
type CrackState = {
	segments: { CrackSegment },
	moments: { number },
	played: number,
}

local active: { Crumble } = {}
local cracking: { [BasePart]: CrackState } = {}

local function jitter(magnitude: number): number
	return (math.random() * 2 - 1) * magnitude
end

----------------------------------------------------------------------
-- Cracks
----------------------------------------------------------------------

-- Startup check on the two invariants the atlas rests on: nodes are on
-- the grid, and each step goes to a neighbour. A pattern edited off the
-- lattice is exactly the bug the lattice was adopted to fix — a crack
-- promising a break the collapse won't make, or one drifting off the face
-- entirely — so it fails loudly here rather than in a match.
for patternIndex, pattern in ipairs(CRACK_PATTERNS) do
	for strokeIndex, stroke in ipairs(pattern) do
		for nodeIndex, node in ipairs(stroke) do
			if node.X % 1 ~= 0 or node.Y % 1 ~= 0
				or node.X < 0 or node.X > COLUMNS
				or node.Y < 0 or node.Y > ROWS
			then
				log:warn(string.format(
					"crack pattern %d stroke %d node %d is not a grid corner (%.2f, %.2f)"
						.. " — expected whole numbers within %dx%d",
					patternIndex, strokeIndex, nodeIndex, node.X, node.Y, COLUMNS, ROWS
				))
			end

			if nodeIndex > 1 then
				local previous = stroke[nodeIndex - 1]

				-- Manhattan distance of exactly 1: one column or one row,
				-- never both and never a jump. A diagonal step cuts across
				-- the middle of a chunk, which is the whole thing the
				-- lattice rules out.
				local step = math.abs(node.X - previous.X) + math.abs(node.Y - previous.Y)
				if step ~= 1 then
					log:warn(string.format(
						"crack pattern %d stroke %d node %d does not follow a seam from the"
							.. " node before it (step of %.2f) — the run will cut across a chunk",
						patternIndex, strokeIndex, nodeIndex, step
					))
				end

				-- Runs along the slab's own outline read as a border rather
				-- than a fracture; reaching an edge is fine, travelling
				-- along one is not. Cheap to check and easy to reintroduce
				-- by accident, since such a run looks unremarkable written
				-- down and only shows itself once two patterns stack into a
				-- full-height line up the side of the wall.
				local onOuterColumn = node.X == previous.X
					and (node.X == 0 or node.X == COLUMNS)
				local onOuterRow = node.Y == previous.Y
					and (node.Y == 0 or node.Y == ROWS)
				if onOuterColumn or onOuterRow then
					log:warn(string.format(
						"crack pattern %d stroke %d node %d runs along the slab's outer edge"
							.. " — it will read as an outline, not a crack",
						patternIndex, strokeIndex, nodeIndex
					))
				end
			end
		end
	end
end

-- Mirroring doubles the apparent variety of the atlas for one
-- subtraction, and lands on a seam either way: the columns are evenly
-- spaced, so the mirror of column c is column COLUMNS - c.
local function mirrorNode(node: Vector2, mirrored: boolean): Vector2
	return if mirrored then Vector2.new(COLUMNS - node.X, node.Y) else node
end

-- A grid corner in canvas pixels.
--
-- The row flip is the load-bearing line: the lattice counts rows up from
-- the base, matching the chunks, while the GUI canvas counts pixels down
-- from the top. Without it the whole atlas renders upside down — cracks
-- hanging from the ceiling, still perfectly on the seams, which is a
-- failure that would look deliberate.
local function nodeToPixels(node: Vector2, canvasPx: Vector2, mirrored: boolean): Vector2
	local placed = mirrorNode(node, mirrored)
	return Vector2.new(
		placed.X / COLUMNS * canvasPx.X,
		(1 - placed.Y / ROWS) * canvasPx.Y
	)
end

-- Expands a stroke's lattice nodes into the pixel polyline actually drawn:
-- every node, plus the jag joints wandering either side of the seam
-- between them.
local function strokePoints(stroke: { Vector2 }, canvasPx: Vector2, mirrored: boolean): { Vector2 }
	local points: { Vector2 } = {}
	local previous = nodeToPixels(stroke[1], canvasPx, mirrored)
	table.insert(points, previous)

	for nodeIndex = 2, #stroke do
		local target = nodeToPixels(stroke[nodeIndex], canvasPx, mirrored)
		local delta  = target - previous
		local runPx  = delta.Magnitude

		if runPx > 0 then
			local normal = Vector2.new(-delta.Y, delta.X) / runPx
			for step = 1, CRACK_JAG_SEGMENTS - 1 do
				local along  = previous + delta * (step / CRACK_JAG_SEGMENTS)
				local offset = normal * jitter(CRACK_JAG_STUDS * CRACK_PIXELS_PER_STUD)
				local joint  = along + offset
				-- Only the jag can leave the face, and only along a run on
				-- the outer edge, where the wander has nothing on one side
				-- to stray into. Clamped rather than left to the container's
				-- ClipsDescendants, so the crack stays a connected line
				-- instead of losing a joint and gapping.
				table.insert(points, Vector2.new(
					math.clamp(joint.X, 0, canvasPx.X),
					math.clamp(joint.Y, 0, canvasPx.Y)
				))
			end
		end

		table.insert(points, target)
		previous = target
	end

	return points
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
		local baseThickness = if strokeIndex == 1
			then CRACK_THICKNESS_PX
			else CRACK_THICKNESS_PX * CRACK_BRANCH_THICKNESS_FRACTION

		local points = strokePoints(stroke, canvasPx, mirrored)
		local runs   = #points - 1

		for index = 1, runs do
			local fromPx = points[index]
			local toPx   = points[index + 1]
			local delta  = toPx - fromPx
			local lengthPx = delta.Magnitude
			if lengthPx <= 0 then continue end

			local taper = 1 - (1 - CRACK_TIP_THICKNESS_FRACTION)
				* ((index - 1) / math.max(runs - 1, 1))
			local thickness = baseThickness * taper
			local centre = fromPx + delta / 2

			local frame = Instance.new("Frame")
			frame.Name        = "CrackSegment"
			-- Centre-anchored and placed at the midpoint of the run it
			-- covers. Rotation pivots about the element's centre, so
			-- anchoring there makes pivot and anchor the same point and
			-- the segment lands exactly on the line between the two
			-- points. With a left-edge AnchorPoint the frame swings off its
			-- start and the crack renders as disconnected dashes.
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position    = UDim2.fromOffset(centre.X, centre.Y)
			-- Overlong by its own thickness, half at each end. Two rotated
			-- rectangles meeting at an angle leave a wedge of daylight on
			-- the outside of the turn; the overlap fills it. The jag puts a
			-- turn at every joint, so without this the crack reads as a
			-- dotted line the moment it stops being straight.
			frame.Size             = UDim2.fromOffset(lengthPx + thickness, thickness)
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

-- Names one seam run, independent of which way it was walked, so a run
-- shared by two patterns produces the same key from both.
local function edgeKey(a: Vector2, b: Vector2): string
	local ax, ay, bx, by = a.X, a.Y, b.X, b.Y
	if bx < ax or (bx == ax and by < ay) then
		ax, ay, bx, by = bx, by, ax, ay
	end
	return string.format("%d,%d/%d,%d", ax, ay, bx, by)
end

-- Every seam run a pattern occupies in the orientation it would be drawn.
local function patternEdges(pattern: { { Vector2 } }, mirrored: boolean): { string }
	local edges: { string } = {}
	for _, stroke in ipairs(pattern) do
		for index = 1, #stroke - 1 do
			table.insert(edges, edgeKey(
				mirrorNode(stroke[index], mirrored),
				mirrorNode(stroke[index + 1], mirrored)
			))
		end
	end
	return edges
end

-- The set-level invariant, and the reason any six patterns can be revealed
-- without checking: no two of them use the same run, so no crack can land
-- on another. Authored that way and verified here rather than trusted,
-- because a duplicate is invisible in the source — two patterns sharing a
-- seam look fine written down and only show up as a fracture that appears
-- and changes nothing. Checked unmirrored, which is the orientation
-- `chooseCracks` can always fall back to.
do
	local owner: { [string]: number } = {}
	for patternIndex, pattern in ipairs(CRACK_PATTERNS) do
		for _, key in ipairs(patternEdges(pattern, false)) do
			if owner[key] then
				log:warn(string.format(
					"crack patterns %d and %d both run along seam %s — whichever appears"
						.. " second will land on the first",
					owner[key], patternIndex, key
				))
			else
				owner[key] = patternIndex
			end
		end
	end
end

type Reveal = {
	pattern: { { Vector2 } },
	mirrored: boolean,
}

-- Picks the patterns a face reveals, preferring ones that don't retrace a
-- seam an already-picked crack is using.
--
-- The problem it solves is specific to the lattice: on a 5x4 grid there
-- are only six runs out of the base, so a plain shuffle of ten base-rooted
-- patterns will often deal two that start on the same one. Two cracks laid
-- along the same seam don't read as two cracks — the second one appearing
-- lands on top of the first and mostly just thickens it, so a fracture
-- that should have been its own event is spent for nothing. Spreading them
-- is what makes six reveals look like six.
--
-- Greedy rather than an exact cover, and it takes the *first* candidate
-- that collides with nothing rather than the best of all of them, which
-- keeps the pick random when the lattice has room and only starts
-- compromising once it doesn't. Both orientations of each pattern are
-- considered, so mirroring becomes a way out of a clash instead of another
-- source of them: a pattern rooted at column 1 mirrors to column 4.
--
-- Bounded work — patterns x orientations x runs, a few hundred string
-- comparisons once per face when a wall spawns, and it short-circuits the
-- moment it finds a clean fit.
local function chooseCracks(count: number): { Reveal }
	local order = shuffledPatternIndices()
	local taken: { [number]: boolean } = {}
	local claimed: { [string]: boolean } = {}
	local chosen: { Reveal } = {}

	for _ = 1, count do
		local bestIndex: number? = nil
		local bestMirrored = false
		local bestOverlap = math.huge

		for _, index in ipairs(order) do
			if not taken[index] then
				-- Orientations tried in random order, so a pattern that fits
				-- either way doesn't always come out the same way up.
				local firstMirrored = math.random() < 0.5
				for _, mirrored in ipairs({ firstMirrored, not firstMirrored }) do
					local overlap = 0
					for _, key in ipairs(patternEdges(CRACK_PATTERNS[index], mirrored)) do
						if claimed[key] then
							overlap += 1
						end
					end
					if overlap < bestOverlap then
						bestIndex, bestMirrored, bestOverlap = index, mirrored, overlap
					end
				end
			end
			if bestOverlap == 0 then break end
		end

		-- Only when the atlas runs out, which CRACKS_PER_FACE prevents.
		if not bestIndex then break end

		taken[bestIndex] = true
		local pattern = CRACK_PATTERNS[bestIndex]
		for _, key in ipairs(patternEdges(pattern, bestMirrored)) do
			claimed[key] = true
		end
		table.insert(chosen, { pattern = pattern, mirrored = bestMirrored })
	end

	return chosen
end

local function buildCracks(barrier: BasePart)
	local segments: { CrackSegment } = {}
	local moments: { number } = {}
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

		-- Chosen per face rather than per wall: the two sides fracture
		-- independently, so each gets its own spread across the lattice.
		for slot, reveal in ipairs(chooseCracks(revealed)) do
			local appearAt = math.min(
				(slot - 1) / revealed * CRACK_STAGGER_SPAN + jitter(CRACK_TIMING_JITTER),
				CRACK_LATEST_APPEAR
			)
			addCrack(
				container,
				canvasPx,
				reveal.pattern,
				reveal.mirrored,
				segments,
				appearAt
			)

			-- The earlier of the two faces' cracks for this slot is the
			-- moment the wall audibly fails. Whichever face the player
			-- happens to be looking at, a crack is on screen when it sounds.
			moments[slot] = math.min(moments[slot] or math.huge, appearAt)
		end
	end

	-- The jitter can reorder neighbouring slots, and the clamp at
	-- CRACK_LATEST_APPEAR can tie the last two. `played` walks this in
	-- order, so it has to actually be in order.
	table.sort(moments)

	cracking[barrier] = { segments = segments, moments = moments, played = 0 }
end

local function stepCracks(barrier: BasePart, state: CrackState)
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
	for _, segment in ipairs(state.segments) do
		segment.frame.Visible = progress >= segment.appearAt
	end

	-- How many fractures this frame accounted for. Normally one, or none.
	local landed = 0
	while state.played < #state.moments and progress >= state.moments[state.played + 1] do
		state.played += 1
		landed += 1
	end

	-- One sound however many landed, which matters for exactly one case: a
	-- client joining a wall already partway through its lead window draws
	-- every crack due by then on its first frame, and playing a snap for
	-- each would announce as a burst of noise what is, to that player, a
	-- wall that simply already looks cracked.
	if landed > 0 and CRACK_SOUND_ENABLED then
		SkillVisuals.spawnEffectAtPoint(barrier.Position, CRACK_SOUND_EFFECT_ID)
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
	for barrier, state in pairs(cracking) do
		-- A barrier removed some way other than Destroy (a round reset
		-- reparenting it, say) would otherwise be walked forever.
		if barrier.Parent then
			stepCracks(barrier, state)
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
