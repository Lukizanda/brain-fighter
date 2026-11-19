-- Dress pass: terrain. Floor, rim ridge, exit markers, ledges, the Overhang slab and
-- the island's underside, dressed with the Kit_Terrain assets.
-- Run: return require(game.ServerStorage.LevelArtRun:Clone())("dress/terrain.luau")
-- Deterministic: every random draw comes from a seeded Random, in a fixed order.
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())

local PASS = "Dress_Terrain"
local KIT = "Kit_Terrain"
local V3 = Vector3.new
local TAU = math.pi * 2

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
-- Seeds, one per feature, so editing one feature never reshuffles the others.
local SEED_FLOOR = 7101
local SEED_UNDERSIDE = 7102
local SEED_RETURNS = 7103
local SEED_TONE = 7104

-- Yield to the engine every this many parts, so one execute_luau call stays responsive.
local PACE_EVERY = 60

-- Outline of the floor, found by raycasting down onto the wedges.
local OUTLINE_STEPS = 96 -- angles sampled round the island
local OUTLINE_FROM = 100 -- first radius scanned
local OUTLINE_TO = 180 -- last radius scanned
local OUTLINE_STEP = 1 -- scan step, studs
local OUTLINE_REFINE = 0.25 -- final step back from the first miss
local RAY_UP = 10 -- the ray starts this far above the floor top
local RAY_DOWN = 20

-- Ridge classes (greybox sizes are (thickness, height, length)).
local LIP_MAX_HEIGHT = 6 -- a part this low or lower is a lip, otherwise a mass
local CORE_INSET = Vector3.new(0.8, 0.85, 0.92) -- a mass's hidden core, as a share of its greybox box
local MARKER_MIN_LENGTH = 19 -- a mass long enough to carry an exit marker
local MARKER_MIN_HEIGHT = 16
local MARKER_MIN_GATE_DIST = 14 -- never the piece in the gate's own lane
local VARIETY_SLACK = 0.15 -- how much worse (in log scale) a fit may be to give variety

local LIPS = { "Ridge_Lip_A", "Ridge_Lip_B", "Ridge_Lip_C", "Ridge_Lip_C2", "Ridge_Lip_D", "Ridge_Lip_E" }
local MASSES = {
	"Ridge_Mass_A", "Ridge_Mass_A2", "Ridge_Mass_A3", "Ridge_Mass_B", "Ridge_Mass_B2",
	"Ridge_Mass_C", "Ridge_Mass_C2", "Ridge_Mass_Low", "Ridge_Mass_Small", "Ridge_Mass_Small2",
}
local MARKERS = { Spit = "Gate_Spit", Stones = "Gate_Stones", Overhang = "Gate_Overhang" }

-- Floor inlays (designer ruling: raised at most 0.2, none within 24 studs of the centre).
local INLAY_THICK = 0.2
local SHEET_TOP = 0.04 -- ground sheet over the wedges: hides hairline seams between them
local SHEET_INSET = 1.5 -- sheet radius = the nearest floor edge minus this
local INLAY_TOP_TURF = 0.07
local INLAY_TOP_SOIL = 0.11
local INLAY_TOP_FLAG = { 0.09, 0.15 } -- flagstones sit at slightly different heights: worn, uneven
local MOSS_TOP_STEP = 0.02
local CLEAR_RADIUS = 24 -- nothing but the dais inside this
local RIDGE_MARGIN = 14 -- inlays stop this far inside the floor outline (the ridge stands there)
local LANE_HALF = 11 -- half width kept free of inlays along each lane to a gate or plug
local OBSTACLE_MARGIN = 2.5 -- gap kept around cover, cores, pads and the like
local FLOOR_BASE = "Soil" -- warm earth: separates from the letter green and blue better than turf
local SOIL_LIGHTER = 0.05 -- dusty earth patches, within ART.shade's 0.06
local MOSS_DARKER = -0.06 -- grass renders bright, so moss sits at the bottom of its range
local FLAG_ROLE = "Bedrock" -- Basalt renders darker than Cobblestone; FlagstoneDark read as pale tiles
local FLAG_SHIFT = 0.06 -- Bedrock is value 0.29 and the floor 0.36; at the top of its range paving is only a shade darker
local SOIL_PATCHES = 0 -- dusty earth patches are gone: their 0.2 sides showed as thin black lines at low angles
local TURF_PATCHES = 0 -- moss dropped: the Grass material renders pale mint whatever its colour, so it was never dull olive
local MOSS_PIECES = 3 -- pieces per moss patch
local MOSS_PATCH_RADIUS = 7
local MOSS_SPREAD = 2.5 -- piece centres scatter this far from the patch centre
local FLAG_CLUSTERS = 7
local FLAG_RADIUS = { 11, 15 } -- a paving patch is a loose disc of this radius
local FLAG_ATTEMPTS = 24 -- slabs thrown per patch; overlapping throws are dropped
local FLAG_SIDE = { 2.5, 6 } -- slab sides, varied
local FLAG_FIT = 0.85 -- slab footprint as a circle: fraction of half-diagonal
local FLAG_GAP = { 0.3, 1.4 } -- uneven gaps between slabs
local FLAG_YAW = 18 -- degrees each slab is turned off the patch's own yaw
local FLAG_MISSING = 0.25 -- share of slabs left out
local PLACEMENT_TRIES = 150
local OBSTACLE_PREFIXES = { "Cover", "Core", "Pad", "Overlook", "Cave_", "Ledge_Return", "Gate_", "ArrivalPoint" }

-- Underside layers, from the rim down: first stratum is just under the floor outline,
-- each next one steps inward. top / bottom are studs below the floor top.
local UNDER_LAYERS = {
	-- The first stratum's top stays 0.6 under the floor and does not roll: at -0.05
	-- with a 2-degree roll the corners of every block rose through the floor as pale
	-- slabs (art review, 2026-11-19).
	{ n = 48, top = -0.6, bottom = -12, out = 0.2, thick = 14, role = "Cliff", wobble = 1.2, flat = true },
	{ n = 32, top = -10, bottom = -30, out = -7, thick = 26, role = "CliffDark", wobble = 2 },
	{ n = 24, top = -28, bottom = -56, out = -20, thick = 34, role = "CliffDark", wobble = 3 },
	{ n = 16, top = -54, bottom = -84, out = -42, thick = 60, role = "Bedrock", wobble = 4 },
}
local UNDER_OVERLAP = 2.5 -- sectors overlap this much so no crack shows
local UNDER_BOTTOM_DROP = 3 -- each block's bottom hangs a random 0..3 lower
local UNDER_RETRIES = 4 -- first stratum backs off this many times when it meets a ledge
local UNDER_BACKOFF = 3.5
local UNDER_CAP_BOTTOM = -3 -- bottom of a cap block beside a ledge: clear of the slab top (-4) even with the block's roll
local UNDER_CORES = { -- the solid middle: { size, y top, y bottom, yaw }
	{ 110, -4, -26, 20 },
	{ 74, -25, -54, 55 },
	{ 52, -53, -84, 10 },
}
local UNDER_TIP = { width = 30, height = 34, run = 24, top = -83 }
local SPIKES = 16
-- y the spikes hang from: inside the third stratum, whose bottom is -56 less a
-- random 0..3. At -58 a spike under a shallow block hung free (Spike_7, Spike_13).
local SPIKE_FROM = -55
local SPIKE_LENGTH = { 22, 46 }

-- Rim strip: a thin rock facing over each wedge's side face, so the floor's edge reads as rock.
local RIM_STEPS = 96 -- segments round the outline
local RIM_THICK = 1.2 -- radial thickness, outside the outline
local RIM_TOP = 0.1 -- trim, raised at most 0.2
local RIM_BOTTOM = -4 -- the wedges are 4 thick
local RIM_SHADE = -0.06 -- Cliff at the dark end of its range, so the edge is not a bright ring
local RIM_JOIN = 0.8 -- segments overlap this much along the outline

-- Ledge return blocks: tops are jump heights, so the cap may differ from the box top by <= 0.3.
local RETURN_CAP_THICK = 0.5
local RETURN_CAP_DROP = 0.05 -- cap top sits this far under the box top
local RETURN_SKIRT_FLARE = 1.2 -- the base flares this much wider than the box (<= 1 stud a side)

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

local function rel(part: BasePart): Vector3
	return part.Position - center
end

-- Show a role's colour nudged by a seeded amount (ART.shade keeps it within 0.06).
local toneRng = Random.new(SEED_TONE)
local function tone(role: string, amount: number): Color3
	return ART.shade(role, toneRng:NextNumber(-amount, amount))
end

local function refSize(asset: string): Vector3
	local folder = ART.root():FindFirstChild(KIT)
	local model = folder and folder:FindFirstChild(asset)
	assert(model, "run kits/terrain.luau first: missing " .. asset)
	return (model :: Model).PrimaryPart.Size
end

----------------------------------------------------------------------
-- The floor outline: how far the walkable floor reaches at each angle.
----------------------------------------------------------------------
local function measureOutline(wedges: { BasePart }): { number }
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = wedges
	local outline = {}
	for i = 0, OUTLINE_STEPS - 1 do
		local theta = i / OUTLINE_STEPS * TAU
		local dir = V3(math.cos(theta), 0, math.sin(theta))
		local reach = OUTLINE_FROM
		local r = OUTLINE_FROM
		while r <= OUTLINE_TO do
			local origin = center + dir * r + V3(0, RAY_UP, 0)
			if workspace:Raycast(origin, V3(0, -RAY_DOWN, 0), params) then
				reach = r
			end
			r += OUTLINE_STEP
		end
		-- refine the last step: the edge lies between reach and reach + OUTLINE_STEP
		local fine = reach + OUTLINE_REFINE
		while fine < reach + OUTLINE_STEP do
			local origin = center + dir * fine + V3(0, RAY_UP, 0)
			if workspace:Raycast(origin, V3(0, -RAY_DOWN, 0), params) then
				reach = fine
			end
			fine += OUTLINE_REFINE
		end
		outline[i] = reach
	end
	return outline
end

local outline: { number } = {}
local function edgeR(theta: number): number
	local f = (theta / TAU * OUTLINE_STEPS) % OUTLINE_STEPS
	local i = math.floor(f)
	local a, b = outline[i], outline[(i + 1) % OUTLINE_STEPS]
	return a + (b - a) * (f - i)
end

----------------------------------------------------------------------
-- Ridge: the lips and masses, and the three exit markers
----------------------------------------------------------------------
local function fitCost(scale: Vector3): (number, boolean)
	local worst = 0
	local ok = true
	for _, f in { scale.X, scale.Y, scale.Z } do
		worst = math.max(worst, math.abs(math.log(f)))
		if f < ART.FIT_MIN or f > ART.FIT_MAX then
			ok = false
		end
	end
	return worst, ok
end

local fitStats = { worstLow = 9, worstHigh = 0, count = 0 }
local usage: { [string]: number } = {}

-- Best-fitting asset for `part`, preferring the least used among nearly-as-good ones.
local function pickAsset(part: BasePart, list: { string }): string
	local best, bestCost = nil, math.huge
	local fits = {}
	for _, name in list do
		local cost, ok = fitCost(part.Size / refSize(name))
		if ok then
			fits[name] = cost
			if cost < bestCost then
				best, bestCost = name, cost
			end
		end
	end
	assert(best, "no ridge asset fits " .. tostring(part.Size))
	local chosen = best
	for _, name in list do
		local cost = fits[name]
		if cost and cost <= bestCost + VARIETY_SLACK and (usage[name] or 0) < (usage[chosen] or 0) then
			chosen = name
		end
	end
	usage[chosen] = (usage[chosen] or 0) + 1
	return chosen
end

local function placeRidge(part: BasePart, asset: string, name: string)
	local toward = ART.towardCenter(part)
	-- the kit's playfield face is local +X; flip the asset when the part's inward face is -X
	local turn = if toward.X < 0 then 180 else 0
	local scale = part.Size / refSize(asset)
	for _, f in { scale.X, scale.Y, scale.Z } do
		fitStats.worstLow = math.min(fitStats.worstLow, f)
		fitStats.worstHigh = math.max(fitStats.worstHigh, f)
	end
	fitStats.count += 1
	local model = ART.place(PASS, KIT, asset, part, { name = name, turn = turn })
	if part.Size.Y > LIP_MAX_HEIGHT then
		-- A dark core inside the mass: the slabs of a stretched asset can leave a
		-- window where the sky shows through the ridge (art review, 2026-11-19,
		-- Ridge_16 at bearing 90). Inset so it never shows where the slabs meet.
		local size = V3(part.Size.X * CORE_INSET.X, part.Size.Y * CORE_INSET.Y, part.Size.Z * CORE_INSET.Z)
		ART.prim(model, {
			role = "CliffDark",
			name = "Core",
			size = size,
			cf = part.CFrame * CFrame.new(0, (size.Y - part.Size.Y) / 2, 0),
			shadow = false,
		})
	end
	pace()
end

local function dressRidge()
	local segments = ART.greybox("Ridge_Segment")
	-- exit markers: the nearest long, tall mass beside each gate, never the gate's lane
	local markerFor: { [BasePart]: string } = {}
	for exit, gateName in MARKERS do
		local gate = ART.greybox(gateName)[1]
		local best, bestDist = nil, math.huge
		for _, s in segments do
			local flat = V3(s.Position.X - gate.Position.X, 0, s.Position.Z - gate.Position.Z).Magnitude
			if
				s.Size.Z >= MARKER_MIN_LENGTH
				and s.Size.Y >= MARKER_MIN_HEIGHT
				and flat >= MARKER_MIN_GATE_DIST
				and flat < bestDist
				and not markerFor[s]
			then
				best, bestDist = s, flat
			end
		end
		assert(best, "no ridge mass beside " .. gateName)
		markerFor[best] = "Ridge_Marker_" .. exit
	end
	for i, s in segments do
		local name = string.format("Ridge_%02d", i)
		local marker = markerFor[s]
		if marker then
			placeRidge(s, marker, name .. "_" .. marker)
		else
			local list = if s.Size.Y <= LIP_MAX_HEIGHT then LIPS else MASSES
			local asset = pickAsset(s, list)
			placeRidge(s, asset, name .. "_" .. asset)
		end
	end
end

----------------------------------------------------------------------
-- Floor: skin the wedges, then inlays on top
----------------------------------------------------------------------
local function inlay(folder: Folder, role: string, w: number, d: number, top: number, x: number, z: number, yaw: number, name: string, shift: number?)
	ART.prim(folder, {
		role = role,
		name = name,
		size = V3(w, INLAY_THICK, d),
		shadow = false, -- a 0.1 stud slab casts only a hard black line at low sun angles
		cf = CFrame.new(center.X + x, floorTop + top - INLAY_THICK / 2, center.Z + z) * CFrame.Angles(0, math.rad(yaw), 0),
		color = ART.shade(role, (shift or 0) + toneRng:NextNumber(-0.025, 0.025)),
	})
	pace()
end

local function dressFloor(folder: Folder, wedges: { BasePart })
	for _, w in wedges do
		ART.skin(PASS, w, FLOOR_BASE)
	end
	-- One flat disc in the floor's own colour over the wedges. The wedges meet in hairline
	-- seams that show as thin black lines at low angles; the sheet is 0.04 up and covers them.
	local nearest = math.huge
	for i = 0, OUTLINE_STEPS - 1 do
		nearest = math.min(nearest, outline[i])
	end
	local sheetD = (nearest - SHEET_INSET) * 2
	ART.prim(folder, {
		role = FLOOR_BASE,
		name = "GroundSheet",
		shadow = false,
		shape = "Cylinder",
		size = V3(INLAY_THICK, sheetD, sheetD),
		cf = CFrame.new(center.X, floorTop + SHEET_TOP - INLAY_THICK / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
	})

	-- where inlays may not go
	local lanes = {} -- unit direction in the floor plane, from the centre to a gate or the plug
	for _, n in { "Gate_Spit", "Gate_Stones", "Gate_Overhang", "Gate_CaveRidge" } do
		local g = rel(ART.greybox(n)[1])
		table.insert(lanes, V3(g.X, 0, g.Z).Unit)
	end
	local obstacles = {}
	for _, prefix in OBSTACLE_PREFIXES do
		for _, p in ART.greybox(prefix) do
			table.insert(obstacles, p)
		end
	end
	local function blocked(x: number, z: number, extent: number): boolean
		local r = math.sqrt(x * x + z * z)
		if r - extent < CLEAR_RADIUS or r + extent > edgeR(math.atan2(z, x) % TAU) - RIDGE_MARGIN then
			return true
		end
		for _, dir in lanes do
			local along = x * dir.X + z * dir.Z
			local lateral = math.abs(x * dir.Z - z * dir.X)
			if along > -extent and lateral < LANE_HALF + extent then
				return true
			end
		end
		local point = center + V3(x, 0, z)
		for _, p in obstacles do
			local l = p.CFrame:PointToObjectSpace(V3(point.X, p.Position.Y, point.Z))
			local m = OBSTACLE_MARGIN + extent
			if math.abs(l.X) < p.Size.X / 2 + m and math.abs(l.Z) < p.Size.Z / 2 + m then
				return true
			end
		end
		return false
	end

	local rng = Random.new(SEED_FLOOR)
	local placed = {} -- { x, z, radius } of every patch so none overlap
	local function free(x: number, z: number, radius: number): boolean
		for _, q in placed do
			local dx, dz = x - q[1], z - q[2]
			if math.sqrt(dx * dx + dz * dz) < radius + q[3] + 0.5 then
				return false
			end
		end
		return true
	end
	local function findSpot(radius: number): (number?, number?)
		for _ = 1, PLACEMENT_TRIES do
			local theta = rng:NextNumber(0, TAU)
			local r = rng:NextNumber(CLEAR_RADIUS + radius, edgeR(theta) - RIDGE_MARGIN - radius)
			local x, z = math.cos(theta) * r, math.sin(theta) * r
			if not blocked(x, z, radius) and free(x, z, radius) then
				table.insert(placed, { x, z, radius })
				return x, z
			end
		end
		return nil, nil
	end

	for i = 1, SOIL_PATCHES do
		local w, d = rng:NextNumber(6, 13), rng:NextNumber(5, 10)
		local x, z = findSpot(math.max(w, d) / 2 + 1)
		if x then
			inlay(folder, "Soil", w, d, INLAY_TOP_SOIL, x, z, rng:NextNumber(0, 180), "Soil_" .. i, SOIL_LIGHTER)
		end
	end
	-- moss: each patch is a few small pieces, turned differently and overlapping, so no
	-- straight edge runs more than a few studs. Each piece has its own top (0.02 apart).
	for i = 1, TURF_PATCHES do
		local radius = MOSS_PATCH_RADIUS
		local x, z = findSpot(radius)
		if x then
			for k = 1, MOSS_PIECES do
				local px = x + rng:NextNumber(-MOSS_SPREAD, MOSS_SPREAD)
				local pz = z + rng:NextNumber(-MOSS_SPREAD, MOSS_SPREAD)
				inlay(folder, "Turf", rng:NextNumber(4, 7), rng:NextNumber(3, 5.5), INLAY_TOP_TURF + (k - 1) * MOSS_TOP_STEP, px, pz, rng:NextNumber(0, 180), "Moss_" .. i .. "_" .. k, MOSS_DARKER)
			end
		end
	end
	-- worn paving sunk in the ground: dark flagstones of varied size, thrown loosely in a
	-- disc with uneven gaps, some missing; no grid, no rows.
	for i = 1, FLAG_CLUSTERS do
		local radius = rng:NextNumber(FLAG_RADIUS[1], FLAG_RADIUS[2])
		local x, z = findSpot(radius)
		if x then
			local baseYaw = rng:NextNumber(0, 180)
			local slabs = {} -- { x, z, radius } inside this cluster
			for k = 1, FLAG_ATTEMPTS do
				local w, d = rng:NextNumber(FLAG_SIDE[1], FLAG_SIDE[2]), rng:NextNumber(FLAG_SIDE[1], FLAG_SIDE[2])
				local reach = 0.5 * math.sqrt(w * w + d * d) * FLAG_FIT
				local a = rng:NextNumber(0, TAU)
				local rr = math.sqrt(rng:NextNumber()) * math.max(radius - reach, 0)
				local sx, sz = x + math.cos(a) * rr, z + math.sin(a) * rr
				local gap = rng:NextNumber(FLAG_GAP[1], FLAG_GAP[2])
				local clear = true
				for _, q in slabs do
					local dx, dz = sx - q[1], sz - q[2]
					if math.sqrt(dx * dx + dz * dz) < reach + q[3] + gap then
						clear = false
						break
					end
				end
				-- the draws above always happen, so a kept/missing slab never reshuffles the rest
				local top = rng:NextNumber(INLAY_TOP_FLAG[1], INLAY_TOP_FLAG[2])
				local yaw = baseYaw + rng:NextNumber(-FLAG_YAW, FLAG_YAW)
				local present = rng:NextNumber() > FLAG_MISSING
				if clear then
					table.insert(slabs, { sx, sz, reach })
					if present then
						inlay(folder, FLAG_ROLE, w, d, top, sx, sz, yaw, "Flag_" .. i .. "_" .. k, FLAG_SHIFT)
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Rim strip
----------------------------------------------------------------------
local function dressRim(folder: Folder)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	local solids = {}
	for _, prefix in { "Ledge_Spit", "Ledge_Stone" } do
		for _, p in ART.greybox(prefix) do
			table.insert(solids, p)
		end
	end
	overlap.FilterDescendantsInstances = solids
	local function at(i: number): Vector3
		local theta = (i % RIM_STEPS) / RIM_STEPS * TAU
		return center + V3(math.cos(theta), 0, math.sin(theta)) * outline[i % OUTLINE_STEPS]
	end
	for i = 0, RIM_STEPS - 1 do
		local a, b = at(i), at(i + 1)
		local along = b - a
		local len = along.Magnitude + RIM_JOIN
		local tangent = along.Unit
		local outward = tangent:Cross(V3(0, 1, 0)) -- right-hand normal of the walk direction
		local mid = (a + b) / 2
		if outward:Dot(mid - center) < 0 then
			outward = -outward
		end
		local pos = V3(mid.X, floorTop + (RIM_TOP + RIM_BOTTOM) / 2, mid.Z) + outward * (RIM_THICK / 2)
		local cf = CFrame.fromMatrix(pos, tangent, V3(0, 1, 0), tangent:Cross(V3(0, 1, 0)))
		local size = V3(len, RIM_TOP - RIM_BOTTOM, RIM_THICK)
		-- a ramp or stone meets the floor edge here: leave the opening clear
		if #workspace:GetPartBoundsInBox(cf, size, overlap) == 0 then
			ART.prim(folder, {
				role = "Cliff",
				name = "Rim_" .. i,
				size = size,
				cf = cf,
				color = ART.shade("Cliff", RIM_SHADE + toneRng:NextNumber(-0.02, 0.02)),
			})
			pace()
		end
	end
end

----------------------------------------------------------------------
-- Ledges
----------------------------------------------------------------------
local function dressStones()
	-- cylinders lie on their side (size 4, d, d); the asset stands upright on the same spot
	local assets = { [14] = "Ledge_Stone_14", [11] = "Ledge_Stone_11", [16] = "Ledge_Stone_16" }
	for _, p in ART.greybox("Ledge_Stone_") do
		local d = p.Size.Y
		local asset = assets[d]
		assert(asset, "no stone asset for diameter " .. d)
		ART.place(PASS, KIT, asset, p, {
			name = "Ledge_Stone_d" .. d,
			at = CFrame.new(p.Position),
			size = V3(d, p.Size.X, d),
		})
	end
end

-- Each spit piece is dressed on its own greybox part, following its CFrame (the ramp is
-- tilted 12 degrees), so every visible walkable top matches the box it stands on.
local function dressSpit()
	for _, n in { "Ramp", "Mid", "Tip" } do
		local part = ART.greybox("Ledge_Spit_" .. n)[1]
		ART.place(PASS, KIT, "Ledge_Spit_" .. n, part, { name = "Ledge_Spit_" .. n })
	end
end

-- Stepped natural rock over a return block: the cap keeps the greybox top (within 0.3),
-- lumps step down the sides and flare at the base, so it reads as a way up.
local function dressReturns(folder: Folder)
	local rng = Random.new(SEED_RETURNS)
	for i, part in ART.greybox("Ledge_Return_") do
		local s, cf = part.Size, part.CFrame
		local top = s.Y / 2
		local function put(role: string, size: Vector3, off: Vector3, yaw: number, name: string)
			ART.prim(folder, {
				role = role,
				name = name .. "_" .. i,
				size = size,
				cf = cf * CFrame.new(off) * CFrame.Angles(0, math.rad(yaw), 0),
				color = tone(role, 0.03),
			})
			pace()
		end
		local capGap = RETURN_CAP_DROP + RETURN_CAP_THICK
		put("Cliff", V3(s.X - 0.5, s.Y - capGap, s.Z - 0.5), V3(0, -capGap / 2, 0), rng:NextNumber(-3, 3), "Body")
		put("CliffLight", V3(s.X - 0.9, RETURN_CAP_THICK, s.Z - 0.9), V3(0, top - RETURN_CAP_DROP - RETURN_CAP_THICK / 2, 0), rng:NextNumber(-4, 4), "Cap")
		put("CliffDark", V3(s.X + RETURN_SKIRT_FLARE, s.Y * 0.34, s.Z + RETURN_SKIRT_FLARE), V3(0, -top + s.Y * 0.17, 0), rng:NextNumber(-4, 4), "Skirt")
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		put("Cliff", V3(s.X + 0.8, s.Y * 0.6, s.Z * 0.5), V3(0, -top + s.Y * 0.3, side * s.Z * 0.28), rng:NextNumber(-4, 4), "Step")
		put("CliffDark", V3(s.X * 0.55, s.Y * 0.3, s.Z * 0.4), V3(-side * s.X * 0.1, top - s.Y * 0.18, -side * s.Z * 0.3), rng:NextNumber(-8, 8), "Chunk")
		ART.hide(PASS, part)
	end
end

----------------------------------------------------------------------
-- Underside
----------------------------------------------------------------------
local function dressUnderside(folder: Folder)
	local rng = Random.new(SEED_UNDERSIDE)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	local solids = {}
	for _, prefix in { "Ledge_Spit", "Ledge_Stone", "Gate_OverhangSlab" } do
		for _, p in ART.greybox(prefix) do
			table.insert(solids, p)
		end
	end
	overlap.FilterDescendantsInstances = solids

	for li, layer in UNDER_LAYERS do
		local step = TAU / layer.n
		for i = 1, layer.n do
			local theta = (i - 0.5 + rng:NextNumber(-0.15, 0.15)) * step
			local reach = math.min(edgeR(theta - step / 2), edgeR(theta), edgeR(theta + step / 2))
			local rOut = reach + layer.out + rng:NextNumber(-layer.wobble, layer.wobble)
			local bottom = layer.bottom - rng:NextNumber(0, UNDER_BOTTOM_DROP)
			local radial = V3(math.cos(theta), 0, math.sin(theta))
			local roll = math.rad(rng:NextNumber(-2, 2)) -- drawn even when flat, so the seed's later draws stay put
			if layer.flat then
				roll = 0
			end
			local function frame(out: number): (CFrame, Vector3)
				local width = 2 * out * math.tan(step / 2) + UNDER_OVERLAP
				local size = V3(width, layer.top - bottom, layer.thick)
				local pos = center + radial * (out - layer.thick / 2) + V3(0, (layer.top + bottom) / 2, 0)
				return CFrame.lookAt(pos, pos + radial) * CFrame.Angles(0, 0, roll), size
			end
			local cf, size = frame(rOut)
			if li == 1 and #workspace:GetPartBoundsInBox(cf, size, overlap) > 0 then
				-- a ledge or the slab hangs here: keep only a cap that covers the floor's
				-- side face above it, then back off if that still meets the ledge
				bottom = UNDER_CAP_BOTTOM
				cf, size = frame(rOut)
				local tries = 0
				while tries < UNDER_RETRIES and #workspace:GetPartBoundsInBox(cf, size, overlap) > 0 do
					rOut -= UNDER_BACKOFF
					cf, size = frame(rOut)
					tries += 1
				end
			end
			ART.prim(folder, {
				role = layer.role,
				name = string.format("Under_%d_%d", li, i),
				size = size,
				cf = cf,
				color = tone(layer.role, 0.05),
			})
			pace()
		end
	end

	-- the solid middle
	for i, c in UNDER_CORES do
		ART.prim(folder, {
			role = if i == 1 then "CliffDark" else "Bedrock",
			name = "Under_Core_" .. i,
			size = V3(c[1], c[2] - c[3], c[1]),
			cf = CFrame.new(center.X, floorTop + (c[2] + c[3]) / 2, center.Z) * CFrame.Angles(0, math.rad(c[4]), 0),
		})
	end
	ART.wedge(folder, {
		role = "Bedrock",
		name = "Under_Tip",
		width = UNDER_TIP.width,
		height = UNDER_TIP.height,
		run = UNDER_TIP.run,
		center = V3(center.X, floorTop + UNDER_TIP.top - UNDER_TIP.height / 2 + 0.3, center.Z),
		highToward = V3(1, 0, 0),
		hang = true,
	})

	-- hanging spikes break the layered silhouette
	for i = 1, SPIKES do
		local theta = rng:NextNumber(0, TAU)
		local r = edgeR(theta) - rng:NextNumber(26, 40)
		local radial = V3(math.cos(theta), 0, math.sin(theta))
		local h = rng:NextNumber(SPIKE_LENGTH[1], SPIKE_LENGTH[2])
		local y = SPIKE_FROM - h / 2 + 0.3
		local pos = center + radial * r
		ART.wedge(folder, {
			role = if i % 3 == 0 then "Bedrock" else "CliffDark",
			name = "Spike_" .. i,
			width = rng:NextNumber(9, 16),
			height = h,
			run = rng:NextNumber(7, 12),
			center = V3(pos.X, floorTop + y, pos.Z),
			highToward = -radial,
			hang = true,
			roll = rng:NextNumber(-6, 6),
			color = tone("CliffDark", 0.04),
		})
		pace()
	end
end

----------------------------------------------------------------------
-- Measurements (reported by the run; nothing is built from them)
----------------------------------------------------------------------
local MEASURE_TOP_BAND = 0.6 -- art corners this close to the box top belong to its visible top
local COVER_SAMPLES = 5 -- the collision-top sample grid is COVER_SAMPLES x COVER_SAMPLES
local COVER_EDGE = 0.45 -- the outermost samples sit at this fraction of the box size from the centre
local COVER_DEPTH = 0.6 -- a sample is covered when art holds the point this far under the top

-- How far the art's visible top reaches past, or falls short of, its greybox box, measured in
-- the box's own frame (so a tilted ramp is measured along its slope).
local function topMatch(model: Model): string
	local ref = model.PrimaryPart :: BasePart
	local half = ref.Size / 2
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local topHi, topLo = -math.huge, math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= ref then
			local h = d.Size / 2
			local pts = {}
			local partTop = -math.huge
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local c = ref.CFrame:PointToObjectSpace(d.CFrame:PointToWorldSpace(V3(sx * h.X, sy * h.Y, sz * h.Z)))
						partTop = math.max(partTop, c.Y)
						table.insert(pts, c)
					end
				end
			end
			if partTop > half.Y - MEASURE_TOP_BAND then
				topHi = math.max(topHi, partTop - half.Y)
				topLo = math.min(topLo, partTop - half.Y)
				for _, c in pts do
					if c.Y > half.Y - MEASURE_TOP_BAND then
						minX, maxX = math.min(minX, c.X), math.max(maxX, c.X)
						minZ, maxZ = math.min(minZ, c.Z), math.max(maxZ, c.Z)
					end
				end
			end
		end
	end
	return string.format(
		"%s box(%.1f x %.1f): top reaches x %+.2f..%+.2f (box +-%.2f), z %+.2f..%+.2f (box +-%.2f), height %+.2f..%+.2f vs box top",
		model.Name, ref.Size.X, ref.Size.Z, minX, maxX, half.X, minZ, maxZ, half.Z, topLo, topHi
	)
end

-- How many of a 5 x 5 grid of points on the collision top have art under them.
local function topCover(model: Model): number
	local ref = model.PrimaryPart :: BasePart
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= ref then
			table.insert(parts, d)
		end
	end
	local covered = 0
	for i = 0, COVER_SAMPLES - 1 do
		for j = 0, COVER_SAMPLES - 1 do
			local fx = (i / (COVER_SAMPLES - 1) * 2 - 1) * COVER_EDGE
			local fz = (j / (COVER_SAMPLES - 1) * 2 - 1) * COVER_EDGE
			local world = ref.CFrame:PointToWorldSpace(V3(fx * ref.Size.X, ref.Size.Y / 2 - COVER_DEPTH, fz * ref.Size.Z))
			for _, d in parts do
				local l = d.CFrame:PointToObjectSpace(world)
				if math.abs(l.X) <= d.Size.X / 2 and math.abs(l.Y) <= d.Size.Y / 2 and math.abs(l.Z) <= d.Size.Z / 2 then
					covered += 1
					break
				end
			end
		end
	end
	return covered
end

local function measure(): { string }
	local lines = {}
	local folder = workspace[ART.DRESS_ROOT_NAME][PASS]
	local coverMin, coverSum, lips, lipTop = COVER_SAMPLES * COVER_SAMPLES, 0, 0, -math.huge
	for _, m in folder:GetChildren() do
		if m:IsA("Model") then
			local ref = m.PrimaryPart :: BasePart
			if m:GetAttribute("ArtFor") == "Ridge_Segment" and ref.Size.Y <= LIP_MAX_HEIGHT then
				local n = topCover(m)
				coverMin, coverSum, lips = math.min(coverMin, n), coverSum + n, lips + 1
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") and d ~= ref then
						local h = d.Size / 2
						local up = math.abs(d.CFrame.RightVector.Y) * h.X + math.abs(d.CFrame.UpVector.Y) * h.Y + math.abs(d.CFrame.LookVector.Y) * h.Z
						lipTop = math.max(lipTop, d.Position.Y + up - floorTop)
					end
				end
			elseif m.Name:match("^Ledge_Spit_") then
				table.insert(lines, topMatch(m))
			end
		end
	end
	table.insert(lines, string.format("lips: %d, top covered at %d..%.1f of %d sample points (min..mean), highest art top +%.2f", lips, coverMin, coverSum / math.max(lips, 1), COVER_SAMPLES * COVER_SAMPLES, lipTop))
	return lines
end

----------------------------------------------------------------------
-- Run
----------------------------------------------------------------------
local extras = {}
local report = ART.dress(PASS, function(folder)
	local wedges = ART.greybox("Floor_Wedge")
	outline = measureOutline(wedges)
	dressFloor(folder, wedges)
	dressRidge()
	dressStones()
	dressSpit()
	dressReturns(folder)
	ART.adopt(PASS, KIT, "Overhang_Slab", ART.greybox("Gate_OverhangSlab")[1])
	dressUnderside(folder)
	dressRim(folder)
	local total = 0
	for _, d in workspace[ART.DRESS_ROOT_NAME][PASS]:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "GreyboxRef" then
			total += 1
		end
	end
	table.insert(extras, string.format("art parts excluding GreyboxRef: %d", total))
end)

local usedText = {}
for name, n in usage do
	table.insert(usedText, name .. "=" .. n)
end
table.sort(usedText)
table.insert(extras, string.format("ridge fits: %d, stretch %.2f..%.2f", fitStats.count, fitStats.worstLow, fitStats.worstHigh))
for _, line in measure() do
	table.insert(extras, line)
end
table.insert(extras, "assets: " .. table.concat(usedText, " "))
return report .. "\n" .. table.concat(extras, "\n") .. "\nstill grey:\n" .. ART.undressed()
