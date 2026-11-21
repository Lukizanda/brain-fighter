-- Dress pass: hazards. Art for the three fall pits under the boss island (2026-11-21):
-- the shelf skinned dark with rubble on it, a field of bone fangs, a broken crag wall
-- (the "jaw rim") round the sides and far end, big rocks stepping up to the island's
-- underside on the inner end, and a tapering underside beneath the shelf.
-- Needs greybox/hazards.luau to have run first (it makes Pit_Floor_<Exit>).
-- Run: return require(game.ServerStorage.LevelArtRun:Clone())("dress/hazards.luau")
-- Deterministic: every random draw comes from a seeded Random, in a fixed order.
-- Heights below are studs above the island's floor top. Nothing may rise above
-- HARD_TOP, and no fang above FANG_CAP (the kill volume's top): every part's
-- rotated bounding box is measured and, if over its cap, pushed down.
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())

local PASS = "Dress_Hazards"
local SHELF_PREFIX = "Pit_Floor_"
local V3 = Vector3.new
local TAU = math.pi * 2

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
-- One seed per pit, so editing one pit never reshuffles another.
local SEEDS = { Stones = 7301, Spit = 7302, Overhang = 7303 }
local SEED_FALLBACK = 7399
local SEED_TONE_OFFSET = 500

-- Yield to the engine every this many parts, so one execute_luau call stays responsive.
local PACE_EVERY = 60

local PIT_BUDGET = 258 -- parts per pit (the limit is 260)
local HARD_TOP = -12 -- nothing rises above this
local FANG_CAP = -30 -- no fang bounding box above this (the kill volume's top)

-- Shelf rubble: low dark slabs that break up the flat top.
local RUBBLE_COUNT = 6
local RUBBLE_SIDE = { 3.5, 9 }
local RUBBLE_DEPTH = { 3, 7 }
local RUBBLE_HEIGHT = { 0.8, 3.2 }
local RUBBLE_SINK = 0.3
local RUBBLE_TILT = 4 -- degrees
local RUBBLE_EDGE = 5 -- kept this far from the shelf's edges
local RUBBLE_DARK_SHARE = 0.55 -- share in CliffDark, the rest Bedrock
local RUBBLE_TONE = 0.04

-- Fangs: a jittered grid of spikes over the shelf.
local FANG_CELL = 5.5 -- target grid cell, studs; grows if the part budget cannot cover the grid
local FANG_GROW = 1.05
local FANG_AVG_COST = 2.8 -- parts per spike the grid is sized for (mostly points)
local FANG_JITTER = 0.22 -- cell fraction a spike may wander from its cell centre
local FANG_EDGE = 4.5 -- spike centres stay this far from the shelf's edges
local FANG_SINK = 0.4 -- spikes stand this far into the shelf
local FANG_H_MAX = 9.4 -- with FANG_SINK this keeps tips under FANG_CAP
local FANG_H_INNER = { 5, 6.5 } -- height range under the island (inner end)
local FANG_H_OUTER = { 7.5, 9.4 } -- height range in the open part
local FANG_H_LEDGE = { 8.5, 9.4 } -- directly under a ledge
local FANG_TILT = 7 -- degrees, about each horizontal axis
local FANG_DARK_SHARE = 0.35 -- share of spikes in FangDark, the rest Fang
local FANG_TONE = 0.04
local INNER_SPARSE = 25 -- the inner stretch under the island is sparse
local INNER_SKIP = 0.6 -- chance a cell there stays empty
local LEDGE_MARGIN = 2 -- a cell this near a ledge's footprint counts as under it
local LEDGE_PREFIXES = { "Ledge_", "Gate_OverhangSlab" }
-- A point: POINT_ARMS wedges standing round one axis, tall faces meeting at the centre,
-- slopes falling outward. Base diameter POINT_BASE, never more than height / POINT_RATIO.
local POINT_ARMS = 3
local POINT_RATIO = 1.6 -- height is at least this many times the base
local POINT_BASE = { 3.5, 5.8 }
local POINT_TIP = { 1.1, 1.8 } -- width of each arm's ridge: the tip
local POINT_TIP_MAX = 0.45 -- a tip is at most this share of the base
-- A blade: two wedges back to back. Thin: thickness at most length / BLADE_RATIO.
local BLADE_W = { 6, 9 } -- ridge length
local BLADE_BASE = { 2, 3 } -- base thickness of the whole tent (each wedge runs half)
local BLADE_RATIO = 3
local KINDS = { "point", "blade" }
local COST = { point = POINT_ARMS, blade = 2 } -- parts per spike
local WEIGHTS = { -- blades stay at most a quarter of the spikes
	open = { point = 0.8, blade = 0.2 },
	ledge = { point = 0.9, blade = 0.1 },
}

-- Jaw rim: crags along the two sides and the far end.
local RIM_FROM = 14 -- the side walls start this far from the inner end
local RIM_LEN = { 4, 11 } -- crag length along the edge: much varied
local RIM_STEP = 0.85 -- the next crag starts this share of a length on (overlapping)
local RIM_GAP_CHANCE = 0.1
local RIM_GAP = { 1.5, 3.5 } -- a gap of a few studs
local RIM_THICK = { 4, 6.5 }
local RIM_LEAN = { 2, 5 } -- degrees, top leaning into the pit
local RIM_YAW = 8
local RIM_ROLL = 4
local RIM_TOP = { -24, -14 } -- apex of a crag; HARD_TOP is -12
local RIM_CAP_H = { 3, 7 } -- height of the wedge cap that points the crag
local RIM_CAP_EMBED = 0.3 -- the cap sinks this far into its block
local RIM_STUMP_CHANCE = 0.17 -- about one in six: a low stump, no cap
local RIM_STUMP_TOP = { -32, -28 }
local RIM_STAGGER = { -1.5, 2 } -- how far a crag stands out (-) or in (+) of the line
local RIM_BELOW = 8 -- crags start this far under the shelf's top
local RIM_OUT = 0.5 -- a crag's outer face stands this far outside the shelf edge
local RIM_BUDGET = 66
local RIM_DARK_SHARE = 0.45 -- CliffDark below this roll
local RIM_BEDROCK_SHARE = 0.3 -- Bedrock for the next share, the rest Cliff
local RIM_TONE = 0.05

-- Attachment: big rocks stepping up toward the island's underside.
-- t is a fraction of the shelf width from its centre, u studs from the inner end,
-- du the rock's length along the radial, dt its width as a fraction of the shelf.
local ATTACH = {
	{ t = -0.25, u = 16, du = 18, dt = 0.36, top = -13 },
	{ t = 0.22, u = 14, du = 16, dt = 0.4, top = -14.5 },
	{ t = 0, u = 28, du = 14, dt = 0.3, top = -19 },
	{ t = -0.3, u = 33, du = 12, dt = 0.26, top = -25 },
	{ t = 0.3, u = 31, du = 12, dt = 0.28, top = -24 },
	{ t = 0.02, u = 42, du = 10, dt = 0.22, top = -31 },
}
local ATTACH_ROLES = { "CliffDark", "Cliff", "Bedrock" }
local ATTACH_SINK = 3 -- the rock stands this far into the shelf
local ATTACH_YAW = 10
local ATTACH_EDGE = 2 -- kept this far inside the far end
local ATTACH_TONE = 0.04

-- Underside: two blocks under the shelf, then tapering wedges hanging off them.
local UNDER_EMBED = 0.4 -- a hanging piece's top overlaps what it hangs from
local UNDER_B1 = { width = 0.84, depth = 0.72, thick = 6, at = 0.52 } -- fractions of the shelf
local UNDER_B2 = { width = 0.5, depth = 0.42, thick = 9 }
local UNDER_YAW = 3
local UNDER_WEDGES = 5
local UNDER_W = { 9, 15 }
local UNDER_RUN = { 8, 13 }
local UNDER_H = { 14, 26 }
local UNDER_ROLL = 5
local UNDER_MARGIN = 7 -- wedge centres stay this far inside block 1's edge
local UNDER_TONE = 0.04
local UNDER_U = { 0.16, 0.88 } -- block 1's extent, as a fraction of the shelf length

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local pacing = 0
local function pace()
	pacing += 1
	if pacing % PACE_EVERY == 0 then
		task.wait()
	end
end

local center = ART.islandCenter()
local floorTop = center.Y

local function flat(v: Vector3): Vector3
	return V3(v.X, 0, v.Z).Unit
end

local function flatDist(p: Vector3): number
	return V3(p.X - center.X, 0, p.Z - center.Z).Magnitude
end

-- World Y of the top of a part's rotated bounding box.
local function topOf(part: BasePart): number
	local cf, s = part.CFrame, part.Size
	return cf.Position.Y
		+ (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z) / 2
end

type LedgeBox = { x: number, z: number, hx: number, hz: number }
type Cell = { t: number, u: number, ledge: boolean }

----------------------------------------------------------------------
-- One pit
----------------------------------------------------------------------
-- Returns the report line: part count and the highest tops relative to the floor.
local function buildPit(parent: Folder, shelf: BasePart, seed: number, ledges: { LedgeBox }): string
	local exit = shelf.Name:sub(#SHELF_PREFIX + 1)
	local folder = Instance.new("Folder")
	folder.Name = "Pit_" .. exit
	folder.Parent = parent

	local rng = Random.new(seed)
	local toneRng = Random.new(seed + SEED_TONE_OFFSET)
	local function rr(a: number, b: number): number
		return rng:NextNumber(math.min(a, b), math.max(a, b))
	end
	local function tone(role: string, amount: number): Color3
		return ART.shade(role, toneRng:NextNumber(-amount, amount))
	end

	-- The shelf's frame. Its Z axis runs along the radial: the outer end is the
	-- one farther from the island centre.
	local W, L = shelf.Size.X, shelf.Size.Z
	local look = flat(shelf.CFrame.LookVector)
	local endA = shelf.Position + look * (L / 2)
	local endB = shelf.Position - look * (L / 2)
	local radial = if flatDist(endA) > flatDist(endB) then look else -look -- outward
	local tangent = flat(V3(0, 1, 0):Cross(radial))
	local up = V3(0, 1, 0)
	local shelfTopH = shelf.Position.Y + shelf.Size.Y / 2 - floorTop
	local shelfBottomH = shelfTopH - shelf.Size.Y

	-- (t across, u from the inner end, h above the floor top) -> world point
	local function P(t: number, u: number, h: number): Vector3
		return V3(shelf.Position.X, floorTop + h, shelf.Position.Z) + tangent * t + radial * (u - L / 2)
	end
	-- Axes: X = tangent, Y = up, Z = toward the island (against the radial).
	local function frame(pos: Vector3): CFrame
		return CFrame.fromMatrix(pos, tangent, up)
	end

	local count, fangParts = 0, 0
	local highest, highestFang = -math.huge, -math.huge

	-- Count a finished part, push it under its cap if its bounding box pokes above.
	local function track(part: BasePart, cap: number, isFang: boolean?)
		local top = topOf(part) - floorTop
		if top > cap then
			part.CFrame = part.CFrame - V3(0, top - cap, 0)
			top = cap
		end
		count += 1
		highest = math.max(highest, top)
		if isFang then
			fangParts += 1
			highestFang = math.max(highestFang, top)
		end
		pace()
	end

	local function add(role: string, name: string, size: Vector3, cf: CFrame, cap: number, toneAmount: number)
		local part = ART.prim(folder, {
			role = role,
			name = name,
			size = size,
			cf = cf,
			color = tone(role, toneAmount),
		})
		track(part, cap)
	end

	------------------------------------------------------------------
	-- Underside: so the shelf is not a flat box seen from far away
	------------------------------------------------------------------
	local function underside()
		local b1Top = shelfBottomH + UNDER_EMBED
		local b1Bottom = b1Top - UNDER_B1.thick
		local uMid = L * UNDER_B1.at
		add(
			"CliffDark",
			"Under_Block1",
			V3(W * UNDER_B1.width, UNDER_B1.thick, L * UNDER_B1.depth),
			frame(P(0, uMid, (b1Top + b1Bottom) / 2)) * CFrame.Angles(0, math.rad(rr(-UNDER_YAW, UNDER_YAW)), 0),
			HARD_TOP,
			UNDER_TONE
		)
		local b2Top = b1Bottom + UNDER_EMBED
		local b2Bottom = b2Top - UNDER_B2.thick
		add(
			"Bedrock",
			"Under_Block2",
			V3(W * UNDER_B2.width, UNDER_B2.thick, L * UNDER_B2.depth),
			frame(P(0, uMid, (b2Top + b2Bottom) / 2)) * CFrame.Angles(0, math.rad(rr(-UNDER_YAW, UNDER_YAW)), 0),
			HARD_TOP,
			UNDER_TONE
		)
		-- Wedges hang from block 1's underside, thick end up, tapering down.
		local tMax = W * UNDER_B1.width / 2 - UNDER_MARGIN
		for i = 1, UNDER_WEDGES do
			local t = rr(-tMax, tMax)
			local u = rr(L * UNDER_U[1] + UNDER_MARGIN, L * UNDER_U[2] - UNDER_MARGIN)
			local height = rr(UNDER_H[1], UNDER_H[2])
			local angle = rr(0, TAU)
			local role = if i % 3 == 0 then "Bedrock" else "CliffDark"
			local part = ART.wedge(folder, {
				role = role,
				name = "Under_Wedge_" .. i,
				width = rr(UNDER_W[1], UNDER_W[2]),
				height = height,
				run = rr(UNDER_RUN[1], UNDER_RUN[2]),
				center = P(t, u, b1Bottom + UNDER_EMBED - height / 2),
				highToward = V3(math.cos(angle), 0, math.sin(angle)),
				hang = true,
				roll = rr(-UNDER_ROLL, UNDER_ROLL),
				color = tone(role, UNDER_TONE),
			})
			track(part, HARD_TOP)
		end
	end

	------------------------------------------------------------------
	-- Attachment: rocks stepping up toward the island's underside
	------------------------------------------------------------------
	local function attach()
		for i, a in ATTACH do
			local role = ATTACH_ROLES[(i - 1) % #ATTACH_ROLES + 1]
			local depth = a.du
			local uC = math.min(a.u, L - depth / 2 - ATTACH_EDGE)
			local width = a.dt * W
			local botH = shelfTopH - ATTACH_SINK
			local yaw = math.rad(rr(-ATTACH_YAW, ATTACH_YAW))
			add(
				role,
				"Attach_" .. i,
				V3(width, a.top - botH, depth),
				frame(P(a.t * W, uC, (a.top + botH) / 2)) * CFrame.Angles(0, yaw, 0),
				HARD_TOP,
				ATTACH_TONE
			)
		end
	end

	------------------------------------------------------------------
	-- Jaw rim: a broken wall of crags along both sides and the far end
	------------------------------------------------------------------
	local function crag(
		name: string,
		role: string,
		edgeT: number,
		edgeU: number,
		inward: Vector3,
		len: number,
		thick: number,
		topH: number,
		botH: number,
		lean: number,
		extraIn: number,
		stump: boolean
	)
		-- topH is the apex: a block with a wedge cap on it, or just a block for a stump
		local capH = if stump then 0 else rr(RIM_CAP_H[1], RIM_CAP_H[2])
		local blockTop = topH - capH
		local height = blockTop - botH
		-- the outer face stands RIM_OUT outside the edge, counting the lean at the foot
		local inset = thick / 2 + (height / 2) * math.sin(lean) - RIM_OUT + extraIn
		local pos = P(edgeT, edgeU, (blockTop + botH) / 2) + inward * inset
		local along = up:Cross(inward)
		local yaw = math.rad(rr(-RIM_YAW, RIM_YAW))
		local roll = math.rad(rr(-RIM_ROLL, RIM_ROLL))
		-- X runs along the edge, Z points into the pit, so a positive turn about X
		-- tips the top into the pit.
		local upright = CFrame.fromMatrix(pos, along, up)
		local cf = upright * CFrame.Angles(0, yaw, 0) * CFrame.Angles(lean, 0, roll)
		add(role, name, V3(len, height, thick), cf, HARD_TOP, RIM_TONE)
		if not stump then
			-- the cap slants across the crag or along it; built upright, then turned
			-- with the block about the block's centre
			local sign = if rng:NextNumber() < 0.5 then -1 else 1
			local alongSlant = rng:NextNumber() < 0.5
			local cap = ART.wedge(folder, {
				role = role,
				name = name .. "_Cap",
				width = if alongSlant then thick else len,
				height = capH,
				run = if alongSlant then len else thick,
				center = V3(pos.X, floorTop + blockTop + capH / 2 - RIM_CAP_EMBED, pos.Z),
				highToward = if alongSlant then along * sign else inward * sign,
				color = tone(role, RIM_TONE),
			})
			cap.CFrame = cf * upright:Inverse() * cap.CFrame
			track(cap, HARD_TOP)
		end
	end

	local function rim()
		local start = count
		local edges = {
			{ name = "L", tA = -W / 2, uA = RIM_FROM, tB = -W / 2, uB = L, inward = tangent },
			{ name = "R", tA = W / 2, uA = RIM_FROM, tB = W / 2, uB = L, inward = -tangent },
			{ name = "Far", tA = -W / 2, uA = L, tB = W / 2, uB = L, inward = -radial },
		}
		-- Walk each edge, laying crags of varied length that overlap, with the odd gap.
		for _, e in edges do
			local length = math.sqrt((e.tB - e.tA) ^ 2 + (e.uB - e.uA) ^ 2)
			local cursor = 0
			local i = 0
			while cursor < length do
				if rng:NextNumber() < RIM_GAP_CHANCE then
					cursor += rr(RIM_GAP[1], RIM_GAP[2])
				end
				local len = math.min(rr(RIM_LEN[1], RIM_LEN[2]), length)
				-- centred so the crag stays inside the edge's ends
				local mid = math.max(len / 2, math.min(cursor + len / 2, length - len / 2))
				local s = mid / length
				local t = e.tA + (e.tB - e.tA) * s
				local u = e.uA + (e.uB - e.uA) * s
				local thick = rr(RIM_THICK[1], RIM_THICK[2])
				local stump = rng:NextNumber() < RIM_STUMP_CHANCE
				local topH = if stump then rr(RIM_STUMP_TOP[1], RIM_STUMP_TOP[2]) else rr(RIM_TOP[1], RIM_TOP[2])
				local botH = shelfTopH - RIM_BELOW
				local lean = math.rad(rr(RIM_LEAN[1], RIM_LEAN[2]))
				local stagger = rr(RIM_STAGGER[1], RIM_STAGGER[2])
				local roll = rng:NextNumber()
				local role = if roll < RIM_DARK_SHARE
					then "CliffDark"
					elseif roll < RIM_DARK_SHARE + RIM_BEDROCK_SHARE then "Bedrock"
					else "Cliff"
				local used = count - start
				if used + 2 > RIM_BUDGET then
					stump = true -- a cap needs a second part
					topH = rr(RIM_STUMP_TOP[1], RIM_STUMP_TOP[2])
				end
				if used + 1 > RIM_BUDGET then
					break
				end
				i += 1
				crag(string.format("Rim_%s_%d", e.name, i), role, t, u, e.inward, len, thick, topH, botH, lean, stagger, stump)
				cursor += len * RIM_STEP
			end
		end
	end

	------------------------------------------------------------------
	-- Rubble: low dark slabs on the shelf top
	------------------------------------------------------------------
	local function rubble()
		local tMax = W / 2 - RUBBLE_EDGE
		for i = 1, RUBBLE_COUNT do
			local t = rr(-tMax, tMax)
			local u = rr(RUBBLE_EDGE, L - RUBBLE_EDGE)
			local height = rr(RUBBLE_HEIGHT[1], RUBBLE_HEIGHT[2])
			local role = if rng:NextNumber() < RUBBLE_DARK_SHARE then "CliffDark" else "Bedrock"
			local size = V3(rr(RUBBLE_SIDE[1], RUBBLE_SIDE[2]), height, rr(RUBBLE_DEPTH[1], RUBBLE_DEPTH[2]))
			local cf = CFrame.new(P(t, u, shelfTopH + height / 2 - RUBBLE_SINK))
				* CFrame.Angles(0, rr(0, TAU), 0)
				* CFrame.Angles(math.rad(rr(-RUBBLE_TILT, RUBBLE_TILT)), 0, math.rad(rr(-RUBBLE_TILT, RUBBLE_TILT)))
			add(role, "Rubble_" .. i, size, cf, HARD_TOP, RUBBLE_TONE)
		end
	end

	------------------------------------------------------------------
	-- Fangs
	------------------------------------------------------------------
	-- Is (t, u) on the shelf under a ledge's footprint?
	local function overLedge(t: number, u: number): boolean
		local w = P(t, u, 0)
		for _, b in ledges do
			if math.abs(w.X - b.x) < b.hx + LEDGE_MARGIN and math.abs(w.Z - b.z) < b.hz + LEDGE_MARGIN then
				return true
			end
		end
		return false
	end

	-- Is (t, u) inside one of the attachment rocks (which already fill it)?
	local function insideAttach(t: number, u: number): boolean
		for _, a in ATTACH do
			local uC = math.min(a.u, L - a.du / 2 - ATTACH_EDGE)
			if math.abs(t - a.t * W) < a.dt * W / 2 + 1 and math.abs(u - uC) < a.du / 2 + 1 then
				return true
			end
		end
		return false
	end

	local function fangCells(room: number): { Cell }
		local cell = FANG_CELL
		local spanT, spanU = W - 2 * FANG_EDGE, L - 2 * FANG_EDGE
		local cols, rows = 1, 1
		-- The grid is sized so a mostly-points mix fits the parts left; if FANG_CELL
		-- asks for more, the cell grows.
		local innerShare = INNER_SKIP * math.min(1, INNER_SPARSE / L)
		while true do
			cols = math.max(1, math.ceil(spanT / cell))
			rows = math.max(1, math.ceil(spanU / cell))
			if cols * rows * FANG_AVG_COST * (1 - innerShare) <= room then
				break
			end
			cell *= FANG_GROW
		end
		local cellT, cellU = spanT / cols, spanU / rows
		local cells = {}
		-- outer rows first: if the budget runs short, the inner (under-island) cells go
		for row = rows, 1, -1 do
			for col = 1, cols do
				local t = -W / 2 + FANG_EDGE + (col - 0.5 + rr(-FANG_JITTER, FANG_JITTER)) * cellT
				local u = FANG_EDGE + (row - 0.5 + rr(-FANG_JITTER, FANG_JITTER)) * cellU
				local ledge = overLedge(t, u)
				local sparse = rng:NextNumber() < INNER_SKIP and u < INNER_SPARSE and not ledge
				if not sparse and not insideAttach(t, u) then
					table.insert(cells, { t = t, u = u, ledge = ledge })
				end
			end
		end
		return cells
	end

	-- One spike standing at (cx, cz), built upright and then tilted as one. A point is
	-- POINT_ARMS narrow wedges round one axis, tall faces meeting at the centre and
	-- slopes falling outward. A blade is two wedges back to back.
	local function spike(index: number, cx: number, cz: number, kind: string, h: number, role: string, color: Color3)
		local base = V3(cx, floorTop + shelfTopH - FANG_SINK, cz)
		local yaw = rr(0, TAU)
		local lift = V3(0, h / 2, 0)
		local made: { BasePart } = {}
		local function wedge(tag: string, width: number, run: number, at: Vector3, toward: Vector3)
			table.insert(
				made,
				ART.wedge(folder, {
					role = role,
					name = string.format("Fang_%d%s", index, tag),
					width = width,
					height = h,
					run = run,
					center = at,
					highToward = toward,
					color = color,
				})
			)
		end
		if kind == "blade" then
			local d = V3(math.cos(yaw), 0, math.sin(yaw))
			local w = rr(BLADE_W[1], BLADE_W[2])
			local run = math.min(rr(BLADE_BASE[1], BLADE_BASE[2]), w / BLADE_RATIO) / 2
			-- tall faces meet at the base centre: a tent whose peak is a thin ridge
			wedge("a", w, run, base + lift - d * (run / 2), d)
			wedge("b", w, run, base + lift + d * (run / 2), -d)
		else
			local b = math.min(rr(POINT_BASE[1], POINT_BASE[2]), h / POINT_RATIO)
			local run = b / 2
			local w = math.min(rr(POINT_TIP[1], POINT_TIP[2]), b * POINT_TIP_MAX)
			for k = 1, POINT_ARMS do
				local a = yaw + (k - 1) * TAU / POINT_ARMS
				local dir = V3(math.cos(a), 0, math.sin(a))
				-- the arm lies outward from the axis, its tall face toward the axis
				wedge("_" .. k, w, run, base + lift + dir * (run / 2), -dir)
			end
		end
		local tilt = CFrame.new(base)
			* CFrame.Angles(math.rad(rr(-FANG_TILT, FANG_TILT)), 0, math.rad(rr(-FANG_TILT, FANG_TILT)))
			* CFrame.new(-base)
		for _, part in made do
			part.CFrame = tilt * part.CFrame
			track(part, FANG_CAP, true)
		end
	end

	local function fangs()
		local cells = fangCells(math.max(PIT_BUDGET - count, 1))
		for i, cell in cells do
			local f = math.clamp((cell.u - INNER_SPARSE) / (L - INNER_SPARSE), 0, 1)
			local weights = if cell.ledge then WEIGHTS.ledge else WEIGHTS.open
			local roll = rng:NextNumber()
			local kind = "point"
			local acc = 0
			for _, k in KINDS do
				acc += weights[k]
				if roll <= acc then
					kind = k
					break
				end
			end
			-- out of room for a point: a blade; out of room for that: the rest go unbuilt
			if count + COST[kind] > PIT_BUDGET then
				kind = "blade"
			end
			if count + COST[kind] > PIT_BUDGET then
				break
			end
			local lo, hi = FANG_H_LEDGE[1], FANG_H_LEDGE[2]
			if not cell.ledge then
				lo = FANG_H_INNER[1] + (FANG_H_OUTER[1] - FANG_H_INNER[1]) * f
				hi = FANG_H_INNER[2] + (FANG_H_OUTER[2] - FANG_H_INNER[2]) * f
			end
			local h = math.min(rr(lo, hi), FANG_H_MAX)
			local role = if rng:NextNumber() < FANG_DARK_SHARE then "FangDark" else "Fang"
			local w = P(cell.t, cell.u, 0)
			spike(i, w.X, w.Z, kind, h, role, tone(role, FANG_TONE))
		end
	end

	underside()
	attach()
	rim()
	rubble()
	fangs()

	return string.format(
		"%s: %d parts (%d fang), highest top %+.2f vs floor, highest fang top %+.2f (limits -12 / -30)",
		exit,
		count,
		fangParts,
		highest,
		highestFang
	)
end

----------------------------------------------------------------------
-- Run
----------------------------------------------------------------------
local lines = {}
local report = ART.dress(PASS, function(folder)
	local shelves = ART.greybox("Pit_Floor")
	assert(#shelves > 0, "no Pit_Floor parts: run greybox/hazards.luau first")

	-- Footprints of the ledges players stand on, for "directly under a ledge".
	local ledges: { LedgeBox } = {}
	for _, prefix in LEDGE_PREFIXES do
		for _, p in ART.greybox(prefix) do
			local cf, s = p.CFrame, p.Size
			table.insert(ledges, {
				x = p.Position.X,
				z = p.Position.Z,
				hx = (math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z) / 2,
				hz = (math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z) / 2,
			})
		end
	end

	for i, shelf in shelves do
		ART.skin(PASS, shelf, "Bedrock")
		local exit = shelf.Name:sub(#SHELF_PREFIX + 1)
		table.insert(lines, buildPit(folder, shelf, SEEDS[exit] or (SEED_FALLBACK + i), ledges))
	end
end)

return report .. "\n" .. table.concat(lines, "\n")
