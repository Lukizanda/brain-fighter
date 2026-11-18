-- Terrain kit: island floor, rim ridge, exit markers, ledges, underside.
-- Run: return require(game.ServerStorage.LevelArtRun)("kits/terrain.luau")
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())
local KIT = "Kit_Terrain"
local row = ART.ROWS.Terrain
local FLOOR_Y = ART.FLOOR_Y

local GAP = 12 -- air between assets
local FRONT_Z = row.z - 10 -- floor, ledges, markers
local BACK_Z = row.z + 40 -- ridge lips and masses
local UNDERSIDE_Z = row.z + 45 -- local +10 is the strip's +Z edge (z = 1305)
local RAISE_STONES = 20 -- mounts: ledge tops sit below the stage floor, so lift them
local RAISE_SLAB = 10
local STONE_TAPER_LAYERS = { 0.82, 0.6, 0.4, 0.2 }
local STONE_TAPER_ROLES = { "CliffDark", "CliffDark", "Bedrock", "Bedrock" }

local V3 = Vector3.new

-- One art part in the asset's local space. rot is degrees (x, y, z).
-- axisUp turns a Cylinder so its round faces point up and down.
local function put(parent, origin, role, size, pos, rot, opts)
	opts = opts or {}
	local r = rot or V3(0, 0, 0)
	local cf = origin * CFrame.new(pos) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
	if opts.axisUp then
		cf = cf * CFrame.Angles(0, 0, math.rad(90))
	end
	return ART.prim(parent, {
		role = role,
		size = size,
		cf = cf,
		shape = opts.shape,
		name = opts.name,
		color = opts.color,
	})
end

-- A wedge in the asset's local space. dir = local direction of the tall vertical
-- face; the slope falls away from it. hang = upside down (thick end on top).
local function wedge(parent, origin, role, width, height, run, pos, dir, opts)
	opts = opts or {}
	return ART.wedge(parent, {
		role = role,
		width = width,
		height = height,
		run = run,
		center = origin:PointToWorldSpace(pos),
		highToward = origin:VectorToWorldSpace(dir),
		hang = opts.hang,
		roll = opts.roll,
		name = opts.name,
		color = opts.color,
	})
end

-- A wedge lying flat (triangle in the floor plane). up = local horizontal direction
-- of the height leg (from the base edge to the apex), tall = local direction of the
-- tall face. thick is the vertical thickness.
local function flatWedge(parent, origin, role, thick, leg, run, pos, up, tall, name)
	local lx = up:Cross(tall)
	local cf = origin * CFrame.fromMatrix(pos, lx, up, tall)
	return ART.prim(parent, { role = role, shape = "Wedge", size = V3(thick, leg, run), cf = cf, name = name })
end

local function tone(rng: Random, role: string, amount: number): Color3
	return ART.shade(role, rng:NextNumber(-amount, amount))
end

----------------------------------------------------------------------
-- 1. Floor swatch
----------------------------------------------------------------------
local function buildFloor(model: Model, origin: CFrame)
	local rng = Random.new(1101)
	local TURF_TOP = 0.08
	put(model, origin, "Turf", V3(60, 4, 60), V3(0, TURF_TOP - 2, 0), nil, { name = "Ground" })

	-- inlays: nearest point at least 24 studs from the centre, tops all different (0.11 .. 0.19)
	local inlays = {
		{ "Soil", -24, -22, 9, 7, 20 },
		{ "Soil", 22, -25, 8, 6, -15 },
		{ "Soil", -26, 14, 7, 9, 10 },
		{ "Soil", 22, 20, 10, 6, 30 },
		{ "Flagstone", -10, -27, 6, 4, 8 },
		{ "Flagstone", 12, -26, 5, 5, -12 },
		{ "Flagstone", -27.5, -3, 4, 6, 0 },
		{ "FlagstoneDark", 27.5, 2, 4, 7, 0 },
		{ "Flagstone", 3, 27, 7, 4, 0 },
	}
	for i, d in inlays do
		local top = 0.10 + 0.01 * i
		local thick = 0.3
		put(model, origin, d[1], V3(d[4], thick, d[5]), V3(d[2], top - thick / 2, d[3]), V3(0, d[6], 0), {
			name = "Inlay_" .. i,
		})
	end

	-- tufts (wedge blades) and pebbles, in the outer ring only
	local function ringPoint(): (number, number)
		while true do
			local x, z = rng:NextNumber(-28, 28), rng:NextNumber(-28, 28)
			if math.sqrt(x * x + z * z) >= 26 then
				return x, z
			end
		end
	end
	for i = 1, 12 do
		local x, z = ringPoint()
		local h = rng:NextNumber(0.7, 1.4)
		put(model, origin, "TurfLight", V3(0.5, h, 0.6), V3(x, TURF_TOP + h / 2 - 0.05, z), V3(0, rng:NextNumber(0, 360), 0), {
			shape = "Wedge",
			name = "Tuft_" .. i,
		})
	end
	for i = 1, 8 do
		local x, z = ringPoint()
		local d = rng:NextNumber(0.6, 1.2)
		put(model, origin, if i % 2 == 0 then "Flagstone" else "FlagstoneDark", V3(d, d * 0.7, d), V3(x, TURF_TOP + d * 0.2, z), nil, {
			shape = "Ball",
			name = "Pebble_" .. i,
		})
	end

	-- test letters
	local function at(x: number, y: number, z: number): Vector3
		return (origin * CFrame.new(x, y, z)).Position
	end
	local tiles = { "red", "green", "blue", "wild" }
	local glyph = { red = "R", green = "G", blue = "B", wild = "W" }
	for i, tile in tiles do
		local x = -9 + (i - 1) * 6
		ART.letterBlock(model, at(x, 22, -8), glyph[tile], tile, "default")
		ART.letterBlock(model, at(x, 22, 8), glyph[tile], tile, "high_contrast")
	end
	for i = 1, 3 do
		ART.letterBlock(model, at(-8 + (i - 1) * 8, 2.1, -12), glyph[tiles[i]], tiles[i], "default")
	end
end

----------------------------------------------------------------------
-- 2. Ridge lips (local +X = playfield face, local Z = length; build with yaw = 90)
----------------------------------------------------------------------
local function buildLip(model: Model, origin: CFrame, p)
	local rng = Random.new(p.seed)
	local T = p.T
	put(model, origin, "CliffDark", V3(T + 0.6, 1.6, p.L - 1), V3(0, 0.7, 0), V3(0, rng:NextNumber(-1.5, 1.5), 0), { name = "Base" })
	local face = T / 2 - 0.2
	for i, s in p.segs do
		local w = T - 1.2 + rng:NextNumber(0, 0.8)
		local h = s.top - 1.0
		put(model, origin, "Cliff", V3(w, h, s.len), V3(face - w / 2, 1.0 + h / 2, s.zc), V3(rng:NextNumber(-2, 2), rng:NextNumber(-4, 4), rng:NextNumber(1, 3)), {
			name = "Body_" .. i,
			color = tone(rng, "Cliff", 0.03),
		})
		put(model, origin, "CliffLight", V3(w * 0.85, 0.9, s.len - 1.4), V3(face - w * 0.5, s.top - 0.2, s.zc), V3(0, rng:NextNumber(-6, 6), rng:NextNumber(-4, 4)), {
			name = "Cap_" .. i,
		})
		put(model, origin, "Turf", V3(w * 0.5, 0.2, s.len * 0.55), V3(face - w * 0.5 - 0.3, s.top + 0.35, s.zc + rng:NextNumber(-1, 1)), V3(0, rng:NextNumber(-8, 8), 0), {
			name = "Moss_" .. i,
		})
		-- outward side rolls off: tall face against the body, slope falling away to -X
		local run = 3.2 + rng:NextNumber(0, 1.6)
		wedge(model, origin, "Cliff", s.len * rng:NextNumber(0.7, 0.9), s.top * 0.85, run, V3(face - w - run / 2 + 0.4, s.top * 0.425 + 0.3, s.zc), V3(1, 0, 0), {
			name = "Roll_" .. i,
			roll = rng:NextNumber(-4, 4),
			color = tone(rng, "Cliff", 0.04),
		})
	end
	for i, c in p.chips do
		put(model, origin, "CliffDark", V3(T * 0.5, c.h, 2.6), V3(face - T * 0.3, 0.7 + c.h / 2, c.z), V3(rng:NextNumber(-8, 8), rng:NextNumber(-20, 20), rng:NextNumber(-10, 10)), {
			name = "Chip_" .. i,
		})
	end
	-- scree skirt on the playfield side, kept within the 1 stud envelope
	put(model, origin, "CliffDark", V3(1.8, 1.4, p.L * 0.4), V3(T / 2 - 0.4, 0.6, p.scree), V3(0, 0, -25), { name = "Scree" })
end

----------------------------------------------------------------------
-- 3. Ridge masses
----------------------------------------------------------------------
local function buildMass(model: Model, origin: CFrame, p)
	local rng = Random.new(p.seed)
	local T, H = p.T, p.H
	local baseH = 0.28 * H
	put(model, origin, "CliffDark", V3(T + 1.0, baseH + 0.5, p.L - 0.8), V3(0, (baseH + 0.5) / 2 - 0.3, 0), V3(0, rng:NextNumber(-1.5, 1.5), 0), {
		name = "Base",
	})
	local face = T / 2 - 0.35 -- playfield face stays pinned here
	local strata = if H >= 17 then 3 else 2
	for ci, c in p.cols do
		local top = H + c.off
		local capH = 1.4
		local y0 = baseH - 1.2
		local bodyTop = top - capH + 0.4
		local w = T
		local lo = y0
		for s = 1, strata do
			local hi = if s == strata then bodyTop + 0.2 else lo + (bodyTop - y0) / strata * rng:NextNumber(0.7, 1.3)
			w = T - 0.2 + (s - 1) * 0.5 + rng:NextNumber(0, 0.5)
			local len = c.len - (s - 1) * rng:NextNumber(0.2, 1.8)
			local faceShift = rng:NextNumber(-0.4, 0.25) -- strata steps in and out, never a 1 stud ledge
			put(model, origin, if s % 2 == 0 then "CliffDark" else "Cliff", V3(w, hi - lo + 0.4, len), V3(face + faceShift - w / 2, (lo + hi) / 2, c.zc + rng:NextNumber(-1.2, 1.2)), V3(rng:NextNumber(-2.5, 2.5), rng:NextNumber(-4, 4), p.lean * rng:NextNumber(0.6, 1.3)), {
				name = "Stratum_" .. ci .. "_" .. s,
				color = tone(rng, if s % 2 == 0 then "CliffDark" else "Cliff", 0.06),
			})
			lo = hi - 0.2
		end
		put(model, origin, "CliffLight", V3(w - 0.5, capH, c.len - 1.0), V3(face - (w - 0.5) / 2 - 0.1, top - capH / 2, c.zc), V3(0, rng:NextNumber(-4, 4), p.lean + 1), {
			name = "Cap_" .. ci,
		})
		if ci % 2 == 1 and not p.noMoss then
			put(model, origin, "Turf", V3(w * 0.45, 0.18, c.len * 0.4), V3(face - w * 0.5, top + 0.1, c.zc), V3(0, rng:NextNumber(-10, 10), 0), {
				name = "Moss_" .. ci,
			})
		end
		-- buttress on the outward side, leaning onto the mass
		-- skyline wedges: different heights and directions, playfield side within +-2 of the box top
		local nWedges = p.capWedges or 2
		for k = 1, nWedges do
			local dirSign = if (ci + k) % 2 == 0 then 1 else -1
			local hMax = H + 2 - (top - 0.8)
			local wh = math.min(rng:NextNumber(1.6, 2.8), hMax)
			local wlen = c.len * rng:NextNumber(0.28, 0.4)
			local zoff = if p.capWedges then (if c.zc < 0 then -1 else 1) * c.len * 0.22 else (k == 1 and -1 or 1) * c.len * 0.2
			wedge(model, origin, "CliffLight", (w - 0.8) * rng:NextNumber(0.6, 0.85), wh, wlen, V3(face - (w - 0.8) / 2 - 0.2, top - 0.8 + wh / 2, c.zc + zoff), V3(0, 0, dirSign), {
				name = "Skyline_" .. ci .. "_" .. k,
				color = tone(rng, "CliffLight", 0.04),
			})
		end
		-- big buttress wedge on the outward side, sloping down and away
		if ci <= 2 then
			local run = 4.5 + rng:NextNumber(0, 1.5)
			local bh = (0.55 + rng:NextNumber(0, 0.15)) * H
			wedge(model, origin, "CliffDark", c.len * 0.5, bh, run, V3(-T / 2 - run / 2 + 0.6, bh / 2 - 0.2, c.zc), V3(1, 0, 0), {
				name = "Buttress_" .. ci,
				roll = rng:NextNumber(-3, 3),
			})
		end
	end
	if not p.noShard then
		local c = p.cols[#p.cols > 1 and 2 or 1]
		put(model, origin, "Cliff", V3(2.2, 7, math.min(5, c.len * 0.5)), V3(-T / 2 - 0.1, H + 2.5 - 3.5, c.zc + 2), V3(0, 10, 9), { name = "Shard" })
		put(model, origin, "CliffDark", V3(2.2, 3, 4), V3(-T / 2 - 1.2, 0.65 * H, c.zc - 3), V3(0, 12, 20), { name = "Hanging" })
	end
end

----------------------------------------------------------------------
-- 4. Exit marker silhouettes (on top of a 10 x 18 x 26 mass)
----------------------------------------------------------------------
local MARKER_TOP = 17

-- a stack of blocks that lean together about local X (so the lean shows from the playfield)
local function leaningStack(model: Model, origin: CFrame, base: Vector3, thetaDeg: number, parts)
	local th = math.rad(thetaDeg)
	local dir = V3(0, math.cos(th), math.sin(th))
	local used = 0
	for i, p in parts do
		local centre = base + dir * (used + p.size.Y / 2 - 0.3)
		put(model, origin, p.role, p.size, centre, V3(thetaDeg, 0, p.roll or 0), { name = p.name or ("Blade_" .. i) })
		used += p.size.Y - 0.6
	end
end

local function markerSpit(model: Model, origin: CFrame)
	leaningStack(model, origin, V3(-1.2, MARKER_TOP - 1.0, -2), 16, {
		{ role = "CliffLight", size = V3(3.6, 4.5, 8.4), roll = 2 },
		{ role = "CliffLight", size = V3(2.8, 4.5, 5.6), roll = 3 },
		{ role = "CliffLight", size = V3(2, 3.6, 3), roll = 4 },
		{ role = "CliffLight", size = V3(1.2, 2.4, 1.4), roll = 5 },
	})
end

local function markerStones(model: Model, origin: CFrame)
	local rng = Random.new(4402)
	local stones = {
		{ d = 9, t = 4, role = "CliffLight" },
		{ d = 6.6, t = 3.4, role = "Cliff" },
		{ d = 4.6, t = 3, role = "CliffLight" },
	}
	local y = MARKER_TOP - 0.6
	for i, s in stones do
		put(model, origin, s.role, V3(s.t, s.d, s.d), V3(-1.2 + rng:NextNumber(-0.5, 0.5), y + s.t / 2, rng:NextNumber(-0.7, 0.7)), V3(rng:NextNumber(-7, 7), rng:NextNumber(0, 90), rng:NextNumber(-3, 3)), {
			shape = "Cylinder",
			axisUp = true,
			name = "Stone_" .. i,
		})
		y += s.t - 0.15
	end
end

local function markerOverhang(model: Model, origin: CFrame)
	for i, side in { -1, 1 } do
		local zc = side * 4.6
		put(model, origin, "CliffLight", V3(7.4, 9, 6.4), V3(-1.2, MARKER_TOP + 3.6, zc), V3(side * 11, side * 8, 2), { name = "Half_" .. i })
		put(model, origin, "Cliff", V3(6.2, 1.4, 5.4), V3(-1.2, MARKER_TOP + 8.3, zc + side * 0.8), V3(side * 11, side * 8, 2), { name = "HalfCap_" .. i })
	end
end

----------------------------------------------------------------------
-- 5. Ledge stones
----------------------------------------------------------------------
local function stoneDisc(model: Model, origin: CFrame, cx: number, diam: number, top: number, seed: number, idx: number)
	local rng = Random.new(seed)
	put(model, origin, "Turf", V3(0.6, diam, diam), V3(cx, top - 0.3, 0), nil, { shape = "Cylinder", axisUp = true, name = "Top_" .. idx })
	put(model, origin, "Cliff", V3(3.5, diam - 0.5, diam - 0.5), V3(cx, top - 2.25, 0), nil, {
		shape = "Cylinder",
		axisUp = true,
		name = "Rock_" .. idx,
		color = tone(rng, "Cliff", 0.03),
	})
	local y = top - 4
	for k, f in STONE_TAPER_LAYERS do
		local d = diam * f
		put(model, origin, STONE_TAPER_ROLES[k], V3(2.8, d, d), V3(cx + rng:NextNumber(-0.6, 0.6), y - 1.2, rng:NextNumber(-0.6, 0.6)), V3(rng:NextNumber(-4, 4), 0, 0), {
			shape = "Cylinder",
			axisUp = true,
			name = "Taper_" .. idx .. "_" .. k,
		})
		y -= 2.5
	end
	-- one hanging wedge off the rim breaks the symmetric cone
	local a = rng:NextNumber(0, math.pi * 2)
	local inward = V3(-math.cos(a), 0, -math.sin(a))
	wedge(model, origin, "CliffDark", diam * 0.35, 4.5, diam * 0.28, V3(cx + math.cos(a) * diam * 0.3, top - 4 - 2.2 + 0.3, math.sin(a) * diam * 0.3), inward, {
		hang = true,
		name = "HangWedge_" .. idx,
	})
end

local function buildStones(model: Model, origin: CFrame)
	stoneDisc(model, origin, 0, 14, -1, 5501, 1)
	stoneDisc(model, origin, 19.5, 11, -2, 5502, 2)
	stoneDisc(model, origin, 40, 16, -3, 5503, 3)
	-- the floor edge the stones sit in front of (top +0)
	put(model, origin, "Turf", V3(20, 0.6, 18), V3(-24, -0.3, 0), nil, { name = "EdgeTop" })
	put(model, origin, "Cliff", V3(19.4, 4.7, 17.4), V3(-24.3, -2.75, 0), nil, { name = "EdgeRock" })
	put(model, origin, "CliffDark", V3(16, 4, 14), V3(-24, -7, 0), V3(0, 0, 3), { name = "EdgeTaper_1" })
	put(model, origin, "Bedrock", V3(10, 3.4, 9), V3(-23, -10.4, 0), V3(0, 6, -3), { name = "EdgeTaper_2" })
end

----------------------------------------------------------------------
-- 6. Ledge spit (ramp, mid, tip along local Z)
----------------------------------------------------------------------
local function buildSpit(model: Model, origin: CFrame)
	local rng = Random.new(6601)
	local theta = math.atan(5 / 24.5)
	local normalY, normalZ = math.cos(theta), math.sin(theta)
	local rampLen = 24.5 / normalY + 1
	-- floor behind the ramp
	put(model, origin, "Turf", V3(30, 0.6, 10), V3(0, -0.3, -40.75), nil, { name = "FloorTop" })
	put(model, origin, "Cliff", V3(29.4, 4.8, 9.4), V3(0, -2.9, -40.75), nil, { name = "FloorRock" })
	put(model, origin, "CliffDark", V3(22, 4, 8), V3(0, -7.4, -40.5), V3(0, 0, 2), { name = "FloorTaper" })
	-- ramp: top runs from 0 to -5 over 24.5 studs
	put(model, origin, "CliffLight", V3(22, 3, rampLen), V3(0, -2.5 - 1.5 * normalY, -23.25 - 1.5 * normalZ), V3(math.deg(theta), 0, 0), {
		name = "Ramp",
		color = tone(rng, "CliffLight", 0.02),
	})
	put(model, origin, "Cliff", V3(15, 3, 22), V3(0, -6.5, 0), nil, { name = "Mid" })
	put(model, origin, "CliffLight", V3(9, 3, 21), V3(0, -6.5, 21.5), nil, { name = "Tip", color = tone(rng, "CliffLight", 0.02) })
	-- taper hanging underneath
	put(model, origin, "CliffDark", V3(14, 3, 14), V3(0, -7.6, -26), V3(0, 4, 0), { name = "Under_Ramp" })
	put(model, origin, "Bedrock", V3(8, 3, 8), V3(0.5, -10.6, -24), V3(0, -8, 0), { name = "Under_Ramp2" })
	put(model, origin, "CliffDark", V3(12, 3.4, 30), V3(0, -8.4, -2), V3(0, 2, 0), { name = "Under_1" })
	put(model, origin, "CliffDark", V3(9, 3.4, 22), V3(0.4, -11.5, 0), V3(0, -3, 0), { name = "Under_2" })
	put(model, origin, "Bedrock", V3(6, 3.2, 14), V3(0, -14.4, 2), V3(0, 5, 0), { name = "Under_3" })
	put(model, origin, "Bedrock", V3(3.2, 3, 7), V3(0, -17, 4), nil, { name = "Under_4" })
	put(model, origin, "CliffDark", V3(6, 3, 12), V3(0, -8.4, 22.5), V3(0, 3, 0), { name = "Under_Tip" })
	put(model, origin, "Bedrock", V3(3, 3, 6), V3(0, -11.2, 24), nil, { name = "Under_Tip2" })
	-- angled cuts at the two width steps (wedges lying flat at the lower level), and
	-- hanging wedges under the sides. Tops of the greybox pieces stay exact.
	local FILL_TOP = -5.05
	for _, s in { -1, 1 } do
		local side = V3(s, 0, 0)
		flatWedge(model, origin, "Cliff", 3, 3.8, 6, V3(s * 9.1, FILL_TOP - 1.5, -8.3), side, V3(0, 0, -1), "Bevel_Ramp_" .. s)
		flatWedge(model, origin, "Cliff", 3, 3.3, 6, V3(s * 5.85, FILL_TOP - 1.5, 13.7), side, V3(0, 0, -1), "Bevel_Tip_" .. s)
		wedge(model, origin, "CliffDark", 14, 5, 5.5, V3(s * 5, -8 - 2.5 + 0.3, -4), V3(-s, 0, 0), { hang = true, name = "Side_Mid_" .. s })
		wedge(model, origin, "CliffDark", 12, 4.5, 5, V3(s * 8, -7.2 - 2.25 + 0.3, -24), V3(-s, 0, 0), { hang = true, name = "Side_Ramp_" .. s })
	end
end

----------------------------------------------------------------------
-- 7. Overhang slab (breakable floor)
----------------------------------------------------------------------
local function buildSlab(body: BasePart, origin: CFrame)
	local TOP = -4
	local function seam(n: number, x: number, z: number, len: number, yaw: number)
		put(body, origin, "GateSeam", V3(0.35, 0.2, len), V3(x, TOP - 0.05, z), V3(0, yaw, 0), { name = "Seam_" .. n })
	end
	seam(1, -6, -4, 24, 28)
	seam(2, 7, 6, 17, -38)
	seam(3, -8, 9, 10, 72)
	seam(4, 9, -9, 9, 104)
	put(body, origin, "GateStoneDark", V3(5, 0.7, 4.5), V3(-14.2, TOP + 0.3, -12), V3(0, 12, 7), { name = "Deco_1" })
	put(body, origin, "GateStone", V3(2.8, 1.2, 6), V3(16.1, TOP + 0.5, 4), V3(0, -9, -10), { name = "Deco_2" })
	put(body, origin, "GateStoneDark", V3(4, 0.5, 3.2), V3(13.5, TOP + 0.2, 12.5), V3(0, 25, 0), { name = "Deco_3" })
	put(body, origin, "GateStoneDark", V3(2.2, 0.8, 1.8), V3(1.5, TOP + 0.3, -1), V3(0, 30, 6), { name = "Deco_4" })
end

----------------------------------------------------------------------
-- 8. Island underside
----------------------------------------------------------------------
local function buildUnderside(model: Model, origin: CFrame)
	local rng = Random.new(8801)
	-- top strip: Turf with a drooping lip over the +Z edge, rock rim under it
	put(model, origin, "Turf", V3(60, 0.6, 20.4), V3(0, -0.2, 0.2), nil, { name = "FloorTop" })
	put(model, origin, "Turf", V3(58, 1.1, 1.4), V3(0, -0.8, 10.4), V3(0, 0, 0), { name = "TurfLip" })
	put(model, origin, "Cliff", V3(60, 4, 20.3), V3(0, -2.4, 0.15), nil, { name = "Rim" })
	-- three hanging lobes: { x, width, depth, zMax of the top band }
	local lobes = {
		{ -20, 22, 60, 11 },
		{ 0, 21, 38, 11.5 },
		{ 20, 22, 50, 10.5 },
	}
	local shrink = { 1, 0.8, 0.58, 0.34 }
	local zShrink = { 1, 0.74, 0.46, 0.22 }
	local roles = { "Cliff", "Cliff", "CliffDark", "Bedrock" }
	local ends = { 0.28, 0.55, 0.8, 1 }
	for li, lobe in lobes do
		local lx, lw, depth, zTop = lobe[1], lobe[2], lobe[3], lobe[4]
		local prevY = -3.5
		local zFronts = {}
		for k = 1, 4 do
			local y1 = -4 - (depth - 4) * ends[k]
			local zMax = zTop * zShrink[k]
			local zMin = -6 + (k - 1) * 1.8
			local w = lw * shrink[k]
			local h = prevY - y1
			put(model, origin, roles[k], V3(w, h + 0.3, zMax - zMin), V3(lx + rng:NextNumber(-0.8, 0.8), (prevY + y1) / 2, (zMax + zMin) / 2), V3(rng:NextNumber(-2, 2), rng:NextNumber(-4, 4), rng:NextNumber(-1.5, 1.5)), {
				name = "Lobe" .. li .. "_" .. k,
				color = tone(rng, roles[k], 0.04),
			})
			zFronts[k] = zMax
			-- sloped taper under the outward (+Z) edge: thick on the rock side, slope facing down and out
			if k < 4 then
				local zNext = zTop * zShrink[k + 1]
				local run = zMax - zNext + 1.5
				local wh = math.min(h * 0.7, 9)
				wedge(model, origin, if k == 3 then "Bedrock" else "CliffDark", w * 0.9, wh, run, V3(lx, y1 - wh / 2 + 0.3, zNext - 1.5 + run / 2), V3(0, 0, -1), {
					hang = true,
					name = "Taper" .. li .. "_" .. k,
				})
			end
			prevY = y1 + 0.2
		end
	end
	-- side tapers on the two outer lobes
	wedge(model, origin, "CliffDark", 14, 10, 5, V3(-31.5, -10, 2), V3(1, 0, 0), { hang = true, name = "SideTaper_L" })
	wedge(model, origin, "CliffDark", 14, 10, 5, V3(31.5, -10, 2), V3(-1, 0, 0), { hang = true, name = "SideTaper_R" })
	-- detached floating rocks beside the slice
	for fi, f in { { -40, -20, 16, 9, 7 }, { 39, -36, 14, 11, 8 } } do
		put(model, origin, "Cliff", V3(f[4], f[5] * 0.45, f[4] * 0.9), V3(f[1], f[2], f[3]), V3(3, 20 * fi, 4), { name = "Float_" .. fi .. "_Top" })
		wedge(model, origin, "CliffDark", f[4] * 0.9, f[5] * 1.1, f[4] * 0.8, V3(f[1], f[2] - f[5] * 0.45 / 2 - f[5] * 0.55 + 0.3, f[3]), V3(0, 0, -1), {
			hang = true,
			name = "Float_" .. fi .. "_Hang",
			roll = 8,
		})
		put(model, origin, "Bedrock", V3(f[4] * 0.4, f[5] * 0.6, f[4] * 0.4), V3(f[1] + 1, f[2] - f[5] * 1.1, f[3] - 1), V3(0, 25, 0), { name = "Float_" .. fi .. "_Tip" })
	end
end

----------------------------------------------------------------------
-- Layout and run
----------------------------------------------------------------------
ART.run("LevelArt: terrain kit", function()
	-- front row: floor, ledges, markers
	ART.asset({
		kit = KIT,
		name = "Floor_Swatch",
		at = V3(205, FLOOR_Y, FRONT_Z + 3),
		greybox = V3(60, 4, 60),
		refOffset = V3(0, -2, 0),
		class = "Floor",
		note = "Turf top +0.08; inlays +0.11..0.19; letters R G B W",
		build = buildFloor,
	})
	local cursor = 235 + GAP
	ART.asset({
		kit = KIT,
		name = "Ledge_Stones",
		at = V3(cursor + 34, FLOOR_Y + RAISE_STONES, FRONT_Z),
		greybox = V3(14, 4, 14),
		refOffset = V3(0, -3, 0),
		class = "Ledge",
		note = "Ref = stone 1 (d14, top -1). Stone 2 d11 top -2, stone 3 d16 top -3, 7 gaps. Mounted +20",
		build = buildStones,
	})
	cursor += 34 + 48 + GAP
	ART.asset({
		kit = KIT,
		name = "Ledge_Spit",
		at = V3(cursor + 45.75, FLOOR_Y + RAISE_STONES, FRONT_Z),
		yaw = 90,
		greybox = V3(15, 3, 22),
		refOffset = V3(0, -6.5, 0),
		class = "Ledge",
		note = "yaw 90, ref = mid piece. Ramp 22 x 24.5, mid 15 x 22, tip 9 x 21. Mounted +20",
		build = buildSpit,
	})
	cursor += 45.75 + 32 + GAP
	ART.breakable({
		kit = KIT,
		name = "Overhang_Slab",
		at = V3(cursor + 17, FLOOR_Y + RAISE_SLAB, FRONT_Z),
		size = V3(34, 3, 30),
		sink = 7,
		bodyRole = "GateStone",
		class = "Gate",
		note = "Top -4 via sink 7; whole asset raised +10 so it clears the stage floor",
		build = buildSlab,
	})
	cursor += 34 + GAP
	local markers = {
		{ "Ridge_Marker_Spit", markerSpit, 4401, "Leaning blade", 17, 0 },
		{ "Ridge_Marker_Stones", markerStones, 4402, "Cairn of three", 16.5, 0 },
		{ "Ridge_Marker_Overhang", markerOverhang, 4403, "Split boulder", 17.5, 0 },
	}
	for _, m in markers do
		local top = m[5]
		ART.asset({
			kit = KIT,
			name = m[1],
			at = V3(cursor + 13, FLOOR_Y, FRONT_Z),
			yaw = 90,
			greybox = V3(10, 18, 26),
			class = "Ridge",
			note = m[4] .. ". yaw 90: playfield face = -Z",
			build = function(model, origin)
				buildMass(model, origin, {
					T = 10,
					H = 18,
					L = 26,
					seed = m[3],
					lean = 4,
					noShard = true,
					noMoss = true,
					capWedges = 1,
					cols = { { zc = -6.5, len = 13.5, off = top - 18 }, { zc = 6.5, len = 13.5, off = top - 18 - 0.8 } },
				})
				m[2](model, origin)
			end,
		})
		cursor += 26 + GAP
	end

	-- back row: ridge lips and masses (yaw 90: length along +X, playfield face = world -Z)
	local back = 250
	local function backAsset(name: string, greybox: Vector3, class: string, note: string, build)
		ART.asset({
			kit = KIT,
			name = name,
			at = V3(back + greybox.Z / 2, FLOOR_Y, BACK_Z),
			yaw = 90,
			greybox = greybox,
			class = class,
			note = note,
			build = build,
		})
		back += greybox.Z + GAP
	end
	backAsset("Ridge_Lip_A", V3(9, 5, 45), "Ridge", "yaw 90: length along +X, playfield face = -Z", function(m, o)
		buildLip(m, o, {
			T = 9, L = 45, seed = 2101, scree = -10,
			segs = { { zc = -15.5, len = 13, top = 4.2 }, { zc = 0, len = 14, top = 5.2 }, { zc = 15.5, len = 12, top = 3.7 } },
			chips = { { z = -8, h = 2.2 }, { z = 8, h = 1.8 } },
		})
	end)
	backAsset("Ridge_Lip_B", V3(6, 3.2, 26), "Ridge", "yaw 90: length along +X, playfield face = -Z", function(m, o)
		buildLip(m, o, {
			T = 6, L = 26, seed = 2102, scree = 6,
			segs = { { zc = -6.5, len = 11, top = 2.7 }, { zc = 6.5, len = 11, top = 3.0 } },
			chips = { { z = 0, h = 1.6 } },
		})
	end)
	backAsset("Ridge_Mass_A", V3(10, 24, 42), "Ridge", "yaw 90: length along +X, playfield face = -Z", function(m, o)
		buildMass(m, o, {
			T = 10, H = 24, L = 42, seed = 3101, lean = 4,
			cols = { { zc = -14, len = 14, off = -1.5 }, { zc = 0, len = 15, off = 2 }, { zc = 14, len = 14, off = 0.5 } },
		})
	end)
	backAsset("Ridge_Mass_B", V3(9, 16, 47), "Ridge", "yaw 90: length along +X, playfield face = -Z", function(m, o)
		buildMass(m, o, {
			T = 9, H = 16, L = 47, seed = 3102, lean = 3.5,
			cols = { { zc = -16, len = 15, off = 1 }, { zc = 0, len = 17, off = -1.5 }, { zc = 16, len = 15, off = 2 } },
		})
	end)
	backAsset("Ridge_Mass_Small", V3(6, 18, 8), "Ridge", "yaw 90: length along +X, playfield face = -Z", function(m, o)
		buildMass(m, o, {
			T = 6, H = 18, L = 8, seed = 3103, lean = 5,
			cols = { { zc = 0, len = 8, off = 1 } },
		})
	end)

	ART.asset({
		kit = KIT,
		name = "Island_Underside",
		at = V3(595, FLOOR_Y, UNDERSIDE_Z),
		greybox = V3(60, 4, 20),
		refOffset = V3(0, -2, 0),
		class = "Underside",
		note = "Floor strip hangs off the +Z edge; non-colliding; view from +Z / below",
		build = buildUnderside,
	})
end)
return ART.report(KIT)
