-- Set pieces kit: boss dais, overlook shelf, cave outcrop, pads, floor dressing,
-- floating rocks, rim crystals. Run: see README.md.
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())
local KIT = "Kit_SetPieces"
local row = ART.ROWS.SetPieces
local FLOOR = ART.FLOOR_Y
local rng = Random.new(1380)

local function rad(d: number)
	return math.rad(d)
end

-- Axis-aligned box from extents, in the asset's local space.
local function box(model: Instance, o: CFrame, role: string, x0, x1, y0, y1, z0, z1, color: Color3?, name: string?)
	return ART.prim(model, {
		role = role,
		name = name,
		size = Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		cf = o * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		color = color,
	})
end

-- Flat disc whose top surface is at `top` (local Y), diameter `dia`.
local function disc(model: Instance, o: CFrame, role: string, dia: number, top: number, name: string?)
	local t = 0.3
	return ART.prim(model, {
		role = role,
		name = name,
		shape = "Cylinder",
		size = Vector3.new(t, dia, dia),
		cf = o * CFrame.new(0, top - t / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
	})
end

-- Flat strip laid out radially at angle `ang` (radians) and radius `r`.
-- size = (radial length, thickness, tangential width).
local function radial(model: Instance, o: CFrame, role: string, r: number, ang: number, size: Vector3, top: number)
	return ART.prim(model, {
		role = role,
		size = size,
		cf = o * CFrame.Angles(0, -ang, 0) * CFrame.new(r, top - size.Y / 2, 0),
	})
end

-- Thin flat bar from the point (x, z) heading along `yawDeg`, for chevrons/arrows.
local function bar(model: Instance, o: CFrame, role: string, x: number, z: number, len: number, yawDeg: number, y: number)
	return ART.prim(model, {
		role = role,
		size = Vector3.new(len, 0.1, 0.3),
		cf = o * CFrame.new(x, y, z) * CFrame.Angles(0, rad(yawDeg), 0),
	})
end

-- A rock mass: block whose top centre is at topY, tilted, with a Turf cap if asked.
local function mass(model: Instance, o: CFrame, role: string, x, z, w, d, y0, topY, rx, ry, rz, moss: boolean)
	local h = topY - y0
	local cf = o * CFrame.new(x, y0 + h / 2, z) * CFrame.Angles(rad(rx), rad(ry), rad(rz))
	local p = ART.prim(model, {
		role = role,
		size = Vector3.new(w, h, d),
		cf = cf,
		color = ART.shade(role, rng:NextNumber(-0.03, 0.03)),
	})
	if moss then
		ART.prim(model, {
			role = "Turf",
			name = "Moss",
			size = Vector3.new(w * 0.82, 0.5, d * 0.82),
			cf = cf * CFrame.new(0, h / 2, 0),
		})
	end
	return p
end

----------------------------------------------------------------------
-- Individual assets
----------------------------------------------------------------------
local function buildDais(model: Model, o: CFrame)
	-- Layers, each at its own height (<= 0.2), larger-dark under smaller-light.
	disc(model, o, "PlumLight", 44, 0.04, "Rim") -- the radius-22 edge: light line against dark floor
	disc(model, o, "Plum", 42.4, 0.06, "Field")
	disc(model, o, "Rune", 41.6, 0.08, "RuneRing") -- neon ring r 20.5..20.8, 0.3 wide
	disc(model, o, "Plum", 41, 0.10, "FieldInner")
	disc(model, o, "PlumLight", 37, 0.12, "RingOuterBand")
	disc(model, o, "Plum", 35.6, 0.14, "BandField")
	disc(model, o, "PlumLight", 26, 0.16, "RingInnerBand")
	disc(model, o, "Plum", 24.8, 0.18, "Centre")
	-- Boss point plate: 8 x 8, subtle.
	ART.prim(model, {
		role = "PlumLight",
		name = "BossPlate",
		size = Vector3.new(8, 0.3, 8),
		cf = o * CFrame.new(0, 0.2 - 0.15, 0),
	})
	-- Radial inlays.
	for k = 0, 7 do
		radial(model, o, "PlumLight", 15.4, rad(22.5 + k * 45), Vector3.new(4, 0.3, 0.6), 0.16)
	end
	for k = 0, 3 do
		radial(model, o, "PlumLight", 9.4, rad(k * 90), Vector3.new(5.6, 0.3, 0.6), 0.19)
	end
	-- Glyph-like neon marks in the outer band (r 18.5..20.5).
	for k = 0, 7 do
		local a = rad(k * 45)
		radial(model, o, "Rune", 19.5, a, Vector3.new(1.6, 0.1, 0.3), 0.13)
		radial(model, o, "Rune", 19.0, a, Vector3.new(0.3, 0.1, 1.1), 0.14)
		radial(model, o, "Rune", 19.5, a + rad(22.5), Vector3.new(0.9, 0.1, 0.3), 0.13)
	end
end

-- Verified wedge, in asset-local terms: `at` = box centre, `toward` = tall face direction.
local function wedge(model: Instance, o: CFrame, role: string, w, h, run, at: Vector3, toward: Vector3, hang: boolean?, roll: number?, name: string?)
	return ART.wedge(model, {
		role = role,
		width = w,
		height = h,
		run = run,
		center = o:PointToWorldSpace(at),
		highToward = o:VectorToWorldSpace(toward),
		hang = hang,
		roll = roll,
		name = name,
		color = ART.shade(role, rng:NextNumber(-0.02, 0.02)),
	})
end

local function buildOverlook(model: Model, o: CFrame)
	-- Four strata, each a pair of long slabs yawed against each other and shifted in/out.
	local strata = {
		{ "CliffDark", -0.5, 4.6 },
		{ "Cliff", 4.2, 8.8 },
		{ "Cliff", 8.4, 12.6 },
		{ "CliffLight", 12.2, 15.7 },
	}
	for i, s in strata do
		for side = -1, 1, 2 do
			local shiftZ = rng:NextNumber(-0.5, 0.5)
			local shiftX = rng:NextNumber(-0.4, 0.4)
			ART.prim(model, {
				role = s[1],
				name = "Stratum" .. i,
				size = Vector3.new(15.2, s[3] - s[2], 21),
				cf = o * CFrame.new(side * 7.3 + shiftX * 0.5, (s[2] + s[3]) / 2, shiftZ)
					* CFrame.Angles(0, rad(side * rng:NextNumber(0.8, 1.2)), 0),
				color = ART.shade(s[1], rng:NextNumber(-0.02, 0.02)),
			})
		end
	end
	-- Steep buttress wedges: front (x2) and the +X side, each over 9 high, run 1.6.
	wedge(model, o, "Cliff", 5, 12, 1.6, Vector3.new(-8, 5.7, -11.2), Vector3.new(0, 0, 1), false, 2, "Buttress")
	wedge(model, o, "CliffLight", 4, 10.5, 1.6, Vector3.new(4, 4.95, -11.2), Vector3.new(0, 0, 1), false, -2, "Buttress")
	wedge(model, o, "Cliff", 7, 13, 1.6, Vector3.new(15.4, 6.2, 3), Vector3.new(-1, 0, 0), false, 1, "Buttress")
	-- Irregular paved lip: broken curb blocks at the edge, then paving at +16.
	local lip = {
		{ -9, -9.9, 7, 1.6 }, { 4, -10.1, 9, 1.4 }, { 12, -9.2, 5, 2 },
		{ -13.7, 2, 2.2, 10 }, { 13.9, -1, 1.8, 9 }, { -4, 10, 11, 1.6 },
	}
	for _, l in lip do
		ART.prim(model, {
			role = "CliffLight",
			name = "Lip",
			size = Vector3.new(l[3], 0.9, l[4]),
			cf = o * CFrame.new(l[1], 15.45, l[2]) * CFrame.Angles(0, rad(rng:NextNumber(-4, 4)), 0),
		})
	end
	box(model, o, "Flagstone", -13, 0.4, 15.5, 16, -9.4, 9.4, nil, "PavingL")
	box(model, o, "Flagstone", -0.2, 13, 15.5, 16, -9.4, 9.4, ART.shade("Flagstone", 0.03), "PavingR")
	box(model, o, "FlagstoneDark", 7, 12.6, 15.5, 15.95, 3, 7, nil, "PavingPatch")
	-- Pad_Arrival: 8 x 8 mark. Trim frame, thin PadArrive strips.
	local px, pz = 0, -1
	box(model, o, "Trim", px - 4, px + 4, 16, 16.15, pz - 4, pz - 3.3, nil, "FrameS")
	box(model, o, "Trim", px - 4, px + 4, 16, 16.15, pz + 3.3, pz + 4, nil, "FrameN")
	box(model, o, "Trim", px - 4, px - 3.3, 16, 16.15, pz - 3.3, pz + 3.3, nil, "FrameW")
	box(model, o, "Trim", px + 3.3, px + 4, 16, 16.15, pz - 3.3, pz + 3.3, nil, "FrameE")
	box(model, o, "PadArrive", px - 3, px + 3, 16.02, 16.1, pz - 3, pz - 2.7, nil, "StripS")
	box(model, o, "PadArrive", px - 3, px + 3, 16.02, 16.1, pz + 2.7, pz + 3, nil, "StripN")
	box(model, o, "PadArrive", px - 3, px - 2.7, 16.02, 16.1, pz - 2.7, pz + 2.7, nil, "StripW")
	box(model, o, "PadArrive", px + 2.7, px + 3, 16.02, 16.1, pz - 2.7, pz + 2.7, nil, "StripE")
end

local function buildCave(model: Model, o: CFrame)
	local inside = ART.shade("CliffDark", -0.06)
	-- Hidden shell: Cliff outside, CliffDark lining. Chamber x +-16, z +-14, y 0..14 stays empty.
	box(model, o, "Cliff", -20, -17.4, 0, 18, -18, 18, nil, "WallL")
	box(model, o, "Cliff", 17.4, 20, 0, 18, -18, 18, nil, "WallR")
	box(model, o, "Cliff", -20, 20, 0, 18, 15.4, 18, nil, "WallBack")
	box(model, o, "Cliff", -20, 20, 16, 18, -18, 18, nil, "Roof")
	box(model, o, "Cliff", -20, -8.5, 0, 14.5, -18, -15.4, nil, "FrontL")
	box(model, o, "Cliff", 8.5, 20, 0, 14.5, -18, -15.4, nil, "FrontR")
	box(model, o, "CliffDark", -19, -16, 0, 16.2, -16.2, 16.4, inside, "LiningL")
	box(model, o, "CliffDark", 16, 19, 0, 16.2, -16.2, 16.4, inside, "LiningR")
	box(model, o, "CliffDark", -19, 19, 0, 16.2, 14, 16.4, inside, "LiningBack")
	box(model, o, "CliffDark", -19, -8.6, 0, 14, -16.2, -14, inside, "LiningFrontL")
	box(model, o, "CliffDark", 8.6, 19, 0, 14, -16.2, -14, inside, "LiningFrontR")
	box(model, o, "CliffDark", -19.5, 19.5, 14, 16.2, -17.9, 14, inside, "Ceiling")
	-- Jambs lean 10 degrees inward at the top; at most 1 stud proud of the front face (z -18).
	for _, s in { -1, 1 } do
		ART.prim(model, {
			role = "Cliff",
			name = "Jamb",
			size = Vector3.new(3.4, 15.6, 3.4),
			cf = o * CFrame.new(s * 11.8, 7.9, -17.3) * CFrame.Angles(0, 0, rad(s * 10)),
			color = ART.shade("Cliff", 0.02),
		})
	end
	-- One heavy lintel, 26 wide, bottom above +14.5.
	ART.prim(model, {
		role = "CliffDark",
		name = "Lintel",
		size = Vector3.new(26, 2.9, 3.4),
		cf = o * CFrame.new(0, 16.1, -17.3),
	})
	-- Front corner rocks, outside the lane.
	mass(model, o, "CliffDark", -17.8, -18.4, 5, 3, 0, 8, 0, 8, 5, false)
	mass(model, o, "CliffDark", 17.8, -18.4, 5, 3, 0, 6.5, 0, -10, -6, false)
	-- Sloped masses: mound sides and back, taller on the spur (+X, back right).
	wedge(model, o, "CliffDark", 24, 15, 7, Vector3.new(-23.5, 7.5, 2), Vector3.new(1, 0, 0), false, 3, "SideL")
	wedge(model, o, "Cliff", 24, 22, 9, Vector3.new(24.5, 11, 2), Vector3.new(-1, 0, 0), false, -2, "SideR")
	wedge(model, o, "CliffDark", 22, 11, 8, Vector3.new(-10, 5.5, 22), Vector3.new(0, 0, -1), false, 2, "BackL")
	wedge(model, o, "Cliff", 20, 28, 11, Vector3.new(10, 14, 23.5), Vector3.new(0, 0, -1), false, -3, "BackR")
	wedge(model, o, "CliffLight", 10, 8, 5, Vector3.new(-18, 4, 21), Vector3.new(1, 0, -1), false, 0, "BackCorner")
	mass(model, o, "CliffLight", 21, 18, 6, 6, 0, 30, 2, 12, 5, true)
	mass(model, o, "CliffDark", -22, -10, 4, 5, 0, 5, 0, 6, -4, true)
	mass(model, o, "CliffDark", 22.5, -9, 4.5, 6, 0, 8.5, 0, -8, 4, true)
	-- Roof line: wedges and blocks climbing toward the spur, Turf on flat tops. Front roof stays clear.
	wedge(model, o, "Cliff", 12, 4, 9, Vector3.new(-12, 19.8, 5), Vector3.new(1, 0, 0), false, 0, "RoofWedge")
	mass(model, o, "Cliff", -3, 6, 9, 11, 17.5, 24, 0, 5, 3, true)
	wedge(model, o, "CliffLight", 11, 7, 8, Vector3.new(6, 21.3, 6), Vector3.new(1, 0, 0), false, 0, "RoofWedge")
	mass(model, o, "CliffLight", 14.5, 6, 8.5, 11, 17.5, 30, -2, 8, 4, true)
	mass(model, o, "Cliff", -12, 11, 5, 5, 17.5, 22, 0, 15, -4, true)
end

local function padFrame(model: Instance, o: CFrame, size: number, bodyTop: number, frameRole: string)
	local h = size / 2
	box(model, o, "Trim", -h, h, 0, bodyTop, -h, h, nil, "Body")
	local w = 0.9
	box(model, o, frameRole, -h, h, bodyTop - 0.4, 1, -h, -h + w, nil, "FrameS")
	box(model, o, frameRole, -h, h, bodyTop - 0.4, 1, h - w, h, nil, "FrameN")
	box(model, o, frameRole, -h, -h + w, bodyTop - 0.4, 1, -h + w, h - w, nil, "FrameW")
	box(model, o, frameRole, h - w, h, bodyTop - 0.4, 1, -h + w, h - w, nil, "FrameE")
end

local function buildPadEntry(model: Model, o: CFrame)
	padFrame(model, o, 12, 0.8, "TrimLight")
	box(model, o, "Trim", -5, 5, 0.7, 0.9, -5, 5, ART.shade("Trim", 0.03), "Field")
	disc(model, o, "PadEnter", 6.8, 0.94, "Ring")
	disc(model, o, "Trim", 6.2, 0.97, "RingInner")
	-- Two chevrons pointing +Z (up the screen, into the fight).
	for _, az in { 1.6, -0.6 } do
		bar(model, o, "PadEnter", -0.78, az - 0.78, 2.2, -45, 1.0)
		bar(model, o, "PadEnter", 0.78, az - 0.78, 2.2, 45, 1.0)
	end
	-- Corner posts: the "gate" tell.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(model, o, "TrimLight", sx * 5.1 - 0.5, sx * 5.1 + 0.5, 0.9, 1.5, sz * 5.1 - 0.5, sz * 5.1 + 0.5, nil, "Post")
		end
	end
end

local function buildPadReturn(model: Model, o: CFrame)
	padFrame(model, o, 14, 0.8, "TrimLight")
	box(model, o, "Trim", -6, 6, 0.7, 0.9, -6, 6, ART.shade("Trim", 0.03), "Field")
	-- Doorway outline 6 wide x 9 long, open at the -Z end (the way out).
	box(model, o, "PadReturn", -3, -2.7, 0.9, 0.98, -4, 4.5, nil, "DoorL")
	box(model, o, "PadReturn", 2.7, 3, 0.9, 0.98, -4, 4.5, nil, "DoorR")
	box(model, o, "PadReturn", -3, 3, 0.9, 0.98, 4.2, 4.5, nil, "DoorTop")
	-- Threshold and a big arrow out (-Z).
	box(model, o, "TrimLight", -3.4, 3.4, 0.9, 1.3, -4.6, -4, nil, "Threshold")
	box(model, o, "TrimLight", -3.4, -2.6, 0.9, 1.7, 4.1, 4.9, nil, "LintelPostL")
	box(model, o, "TrimLight", 2.6, 3.4, 0.9, 1.7, 4.1, 4.9, nil, "LintelPostR")
	box(model, o, "PadReturn", -0.15, 0.15, 0.92, 1.0, -2.2, 3, nil, "Shaft")
	bar(model, o, "PadReturn", -0.9, -1.5, 2.2, 45, 1.02)
	bar(model, o, "PadReturn", 0.9, -1.5, 2.2, -45, 1.02)
end

local function buildPadSpawn(model: Model, o: CFrame)
	padFrame(model, o, 8, 0.8, "TrimLight")
	disc(model, o, "TrimLight", 4.4, 0.9, "Ring")
	disc(model, o, "Trim", 3.4, 0.95, "RingInner")
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(model, o, "TrimLight", sx * 2.7 - 0.3, sx * 2.7 + 0.3, 0.8, 1.05, sz * 2.7 - 0.3, sz * 2.7 + 0.3, nil, "Stud")
		end
	end
end

local function buildDressing(model: Model, o: CFrame)
	ART.prim(model, { role = "Turf", name = "Plate", size = Vector3.new(30, 0.3, 30), cf = o * CFrame.new(0, -0.1, 0) })
	local base = 0.05 -- plate top
	local xs = { -12, -6, 0, 6, 12 }
	local zA, zB = 6, -6
	local function blade(role, x, z, w, h, rx, rz, shape)
		ART.prim(model, {
			role = role,
			shape = shape,
			size = Vector3.new(w, h, w),
			cf = o * CFrame.new(x, base + h / 2 - 0.05, z) * CFrame.Angles(rad(rx), 0, rad(rz)),
		})
	end
	-- Grass tufts.
	for i = 1, 5 do
		blade("TurfLight", xs[1] - 1.0 + (i - 1) * 0.5, zA + (i % 2) * 0.4, 0.25, 1.0 + (i % 3) * 0.15, 0, (i - 3) * 9)
	end
	for i = 1, 4 do
		local a = rad(i * 90 + 20)
		local x, z = xs[2] + math.cos(a) * 0.5, zA + math.sin(a) * 0.5
		ART.prim(model, {
			role = "TurfLight",
			shape = "Wedge",
			size = Vector3.new(0.5, 1.4, 0.5),
			cf = o * CFrame.new(x, base + 0.7 - 0.05, z) * CFrame.Angles(0, -a, 0),
		})
	end
	for i = 1, 3 do
		blade("TurfLight", xs[3] + (i - 2) * 0.7, zA - (i - 2) ^ 2 * 0.3, 0.35, 0.8 + i * 0.2, (i - 2) * 12, (2 - i) * 14)
	end
	-- Rubble chips (Letterstone).
	for i = 1, 3 do
		ART.prim(model, {
			role = if i == 2 then "LetterstoneLight" else "Letterstone",
			size = Vector3.new(0.9 + i * 0.15, 0.6 + i * 0.1, 0.8),
			cf = o * CFrame.new(xs[4] + (i - 2) * 0.9, base + 0.35, zA + (i % 2) * 0.7) * CFrame.Angles(rad(i * 7), rad(i * 35), rad(i * 5)),
		})
	end
	for i = 1, 4 do
		ART.prim(model, {
			role = if i == 3 then "LetterstoneDark" else "Letterstone",
			size = Vector3.new(0.7, 0.5 + (i % 2) * 0.4, 0.9),
			cf = o * CFrame.new(xs[5] + (i - 2.5) * 0.8, base + 0.3, zA + ((i * 7) % 3) * 0.4 - 0.4) * CFrame.Angles(rad(i * 9), rad(i * 50), rad(-i * 6)),
		})
	end
	-- Pebble clusters (Cliff family).
	local pr = { "Cliff", "CliffDark", "CliffLight" }
	for i = 1, 3 do
		local d = 0.5 + i * 0.12
		ART.prim(model, {
			role = pr[i], shape = "Ball", size = Vector3.new(d, d * 0.8, d),
			cf = o * CFrame.new(xs[1] + (i - 2) * 0.8, base + d * 0.3, zB + (i % 2) * 0.5),
		})
	end
	for i = 1, 4 do
		ART.prim(model, {
			role = pr[(i % 3) + 1],
			size = Vector3.new(0.7, 0.5, 0.6),
			cf = o * CFrame.new(xs[2] + math.cos(i * 1.6) * 0.8, base + 0.25, zB + math.sin(i * 1.6) * 0.8) * CFrame.Angles(rad(i * 12), rad(i * 40), rad(i * 8)),
		})
	end
	for i = 1, 5 do
		local ball = i % 2 == 0
		ART.prim(model, {
			role = pr[(i % 3) + 1], shape = if ball then "Ball" else "Block",
			size = Vector3.new(0.5 + (i % 3) * 0.2, 0.45 + (i % 2) * 0.2, 0.55),
			cf = o * CFrame.new(xs[3] + (i - 3) * 0.55, base + 0.25, zB + ((i * 5) % 3) * 0.35 - 0.35) * CFrame.Angles(rad(i * 11), rad(i * 33), 0),
		})
	end
	-- Flagstone fragments.
	ART.prim(model, { role = "Flagstone", size = Vector3.new(2.0, 0.25, 1.5), cf = o * CFrame.new(xs[4] - 0.3, base + 0.1, zB) * CFrame.Angles(0, rad(20), rad(2)) })
	ART.prim(model, { role = "FlagstoneDark", size = Vector3.new(1.3, 0.25, 1.1), cf = o * CFrame.new(xs[4] + 1.2, base + 0.18, zB + 0.9) * CFrame.Angles(rad(3), rad(-30), 0) })
	ART.prim(model, { role = "FlagstoneDark", size = Vector3.new(1.9, 0.25, 1.4), cf = o * CFrame.new(xs[5] - 0.5, base + 0.1, zB) * CFrame.Angles(0, rad(-15), 0) })
	ART.prim(model, { role = "Flagstone", size = Vector3.new(1.2, 0.3, 1.0), cf = o * CFrame.new(xs[5] + 0.6, base + 0.2, zB + 0.2) * CFrame.Angles(rad(4), rad(40), rad(3)) })
	ART.prim(model, { role = "Flagstone", size = Vector3.new(0.8, 0.25, 0.7), cf = o * CFrame.new(xs[5] + 0.2, base + 0.15, zB - 1.1) * CFrame.Angles(0, rad(10), 0) })
end

-- Hovering rock: Turf top, stacked tapering layers, a few chunks. cy = centre height.
local function buildFloatRock(w: number, h: number, cy: number, extra: boolean)
	return function(model: Model, o: CFrame)
		local topY = cy + h / 2
		local layers = {
			{ 0.97, 0.09, "Turf", 0 },
			{ 0.9, 0.24, "Cliff", 8 },
			{ 0.69, 0.22, "CliffDark", -12 },
			{ 0.46, 0.2, "Cliff", 20 },
		}
		local cursor = topY
		for i, l in layers do
			local t = l[2] * h
			local top = cursor + (if i == 1 then 0 else 0.3)
			ART.prim(model, {
				role = l[3],
				name = "Layer" .. i,
				size = Vector3.new(l[1] * w, t, l[1] * w),
				cf = o * CFrame.new(0, top - t / 2, 0) * CFrame.Angles(rad(if i > 3 then 4 else 0), rad(l[4]), rad(if i > 2 then 3 else 0)),
			})
			cursor = top - t
		end
		local hh = 0.27 * h + 0.3
		for _, s in { -1, 1 } do
			ART.wedge(model, {
				role = "CliffDark",
				name = "Taper",
				width = w * 0.3,
				height = hh,
				run = w * 0.2,
				center = o:PointToWorldSpace(Vector3.new(s * w * 0.1, cursor + 0.3 - hh / 2, 0)),
				highToward = o:VectorToWorldSpace(Vector3.new(-s, 0, 0)),
				hang = true,
			})
		end
		for _, s in { -1, 1 } do
			ART.prim(model, {
				role = "CliffLight",
				name = "Chunk",
				size = Vector3.new(w * 0.28, h * 0.3, w * 0.22),
				cf = o * CFrame.new(s * w * 0.38, topY - h * 0.28, s * w * 0.1) * CFrame.Angles(rad(s * 6), rad(s * 25), rad(-s * 8)),
			})
		end
		if extra then
			for _, s in { -1, 1 } do
				ART.prim(model, {
					role = "CliffDark",
					name = "Chip",
					size = Vector3.new(w * 0.16, h * 0.2, w * 0.16),
					cf = o * CFrame.new(s * w * 0.2, topY - h * 0.62, -s * w * 0.18) * CFrame.Angles(rad(s * 10), rad(s * 50), rad(-s * 12)),
				})
			end
		end
	end
end

local function buildCrystals(model: Model, o: CFrame)
	box(model, o, "Bedrock", -5.6, 5.6, 0, 1.4, -2.4, 2.4, nil, "Base")
	box(model, o, "BedrockLight", -3.4, 3.4, 1.0, 1.8, -1.6, 1.4, nil, "BaseCap")
	local data = {
		{ -4.2, 0.4, 4.2, 2.0, 1.7 },
		{ -2.1, -1.0, 5.4, 2.2, 1.9 },
		{ 0.2, 0.6, 6.2, 2.4, 2.0 },
		{ 2.3, -0.8, 5.0, 2.2, 1.8 },
		{ 4.3, 0.5, 3.8, 1.8, 1.5 },
	}
	for i, d in data do
		local sgn = if d[1] < 0 then 1 else -1 -- rotation about Z that tips the top outward
		local lean = if d[1] == 0.2 then -3 else sgn * (5 + i)
		local base = o * CFrame.new(d[1], 1.2, d[2]) * CFrame.Angles(rad(if i % 2 == 0 then -5 else 4), 0, rad(lean))
		ART.prim(model, {
			role = "Crystal", name = "Shaft", transparency = 0.18 + (i % 3) * 0.05,
			size = Vector3.new(d[5], d[3], d[5]), cf = base * CFrame.new(0, d[3] / 2, 0),
		})
		ART.prim(model, {
			role = "Crystal", name = "Tip", transparency = 0.2 + (i % 3) * 0.05,
			size = Vector3.new(d[5] * 0.6, d[4], d[5] * 0.6),
			cf = base * CFrame.new(0, d[3] - 0.2, 0) * CFrame.Angles(0, rad(45), rad(lean * 0.6)) * CFrame.new(0, d[4] / 2, 0),
		})
	end
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
ART.run("LevelArt: set pieces kit", function()
	local GAP = 24
	local cursor = row.xMin + 6
	local function place(name, w, greybox, refOffset, class, note, build)
		local x = cursor + w / 2
		cursor += w + GAP
		ART.asset({
			kit = KIT,
			name = name,
			at = Vector3.new(x, FLOOR, row.z),
			greybox = greybox,
			refOffset = refOffset,
			class = class,
			note = note,
			build = build,
		})
	end

	place("Dais_Boss", 44, Vector3.new(44, 1, 44), Vector3.new(0, -0.5, 0), "Dais", "flush plum rune disc, radius 22", buildDais)
	place("Overlook_Shelf", 30, Vector3.new(30, 16, 22), nil, "Overlook", "rock shelf, paved top, arrival mark", buildOverlook)
	place("Cave_Outcrop", 40, Vector3.new(40, 18, 36), nil, "Cave", "chamber and mouth left empty", buildCave)
	place("Pad_Entry", 12, Vector3.new(12, 1, 12), nil, "Pad", "go: ring and chevrons", buildPadEntry)
	place("Pad_Return", 14, Vector3.new(14, 1, 14), nil, "Pad", "leave: doorway and arrow out", buildPadReturn)
	place("Pad_Spawn", 8, Vector3.new(8, 1, 8), nil, "Pad", "neutral", buildPadSpawn)
	place("Dressing_Floor", 30, Vector3.new(30, 1, 30), Vector3.new(0, -0.5, 0), "Dressing", "tufts, pebbles, rubble, flags", buildDressing)
	place("Floating_Rock_A", 16, Vector3.new(16, 14, 16), Vector3.new(0, 14, 0), "Floating", "centre +14", buildFloatRock(16, 14, 14, true))
	place("Floating_Rock_B", 9, Vector3.new(9, 8, 9), Vector3.new(0, 10, 0), "Floating", "centre +10", buildFloatRock(9, 8, 10, false))
	place("Rim_Crystals", 12, Vector3.new(12, 10, 6), nil, "Crystals", "outward-face dressing", buildCrystals)
end)

return ART.report(KIT)
