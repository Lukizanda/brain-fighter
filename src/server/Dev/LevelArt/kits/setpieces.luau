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
	-- The greybox dais stands 1 stud proud of the floor: a skirt (radius 22) closes its side.
	ART.prim(model, {
		role = "Plum",
		name = "Skirt",
		shape = "Cylinder",
		size = Vector3.new(1, 44, 44),
		cf = o * CFrame.new(0, -0.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
	})
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

-- Cladding on one face: courses of broken slabs, each course cut into segments of
-- different width, so no joint lines up with the one below. The face is a greybox
-- face at (cx, cz) in asset space; `yawDeg` turns local +Z to point outward
-- (0 = +Z, 180 = -Z, 90 = +X, -90 = -X). `courses` entries are
-- { role, y0, y1, outerLo, outerHi }: the outer surface sits that far outside the
-- greybox face (negative = inset); every value stays within 1 stud of it.
local function cladFace(model: Instance, o: CFrame, cx: number, cz: number, yawDeg: number, length: number, courses, thk: number, segMin: number, segMax: number, name: string)
	local face = o * CFrame.new(cx, 0, cz) * CFrame.Angles(0, rad(yawDeg), 0)
	for _, c in courses do
		local cursor = -length / 2
		while cursor < length / 2 - 0.3 do
			local remaining = length / 2 - cursor
			local w = math.min(rng:NextNumber(segMin, segMax), remaining)
			if remaining - w < segMin * 0.6 then
				w = remaining
			end
			local y0 = c[2] + rng:NextNumber(-0.25, 0.25)
			local y1 = c[3] + rng:NextNumber(-0.25, 0.25)
			local outer = rng:NextNumber(c[4], c[5])
			ART.prim(model, {
				role = c[1],
				name = name,
				size = Vector3.new(w + 0.1, y1 - y0, thk),
				cf = face * CFrame.new(cursor + w / 2, (y0 + y1) / 2, outer - thk / 2) * CFrame.Angles(0, rad(rng:NextNumber(-1.5, 1.5)), 0),
				color = ART.shade(c[1], rng:NextNumber(-0.03, 0.03)),
			})
			cursor += w
		end
	end
end

-- Where the real ArrivalPoint pad sits on the real shelf, in the shelf's own space
-- (measured on the island: 2.0 studs toward +Z of the shelf's centre).
local PAD_X, PAD_Z = 0, 2

local function buildOverlook(model: Model, o: CFrame)
	-- Hidden core so no gap shows between slabs.
	box(model, o, "Cliff", -14.2, 14.2, -0.3, 15.6, -10.2, 10.2, nil, "Core")
	-- Four strata. The top one overhangs (+0.4..+0.8) and the one under it is cut back
	-- (-0.9..-0.4), so a shadow line runs under the lip.
	local courses = {
		{ "CliffDark", -0.5, 4.6, -0.3, 0.6 },
		{ "Cliff", 4.3, 8.9, -0.6, 0.5 },
		{ "Cliff", 8.6, 12.7, -0.9, -0.4 },
		{ "CliffLight", 12.4, 15.8, 0.4, 0.8 },
	}
	cladFace(model, o, 0, -11, 180, 30, courses, 2.4, 5.5, 10, "Slab")
	cladFace(model, o, 0, 11, 0, 30, courses, 2.4, 5.5, 10, "Slab")
	cladFace(model, o, -15, 0, -90, 22, courses, 2.4, 5, 9, "Slab")
	cladFace(model, o, 15, 0, 90, 22, courses, 2.4, 5, 9, "Slab")
	-- Steep ribs on the front and the +X side, each over 9 high; run under 1.6 so a rib
	-- is a lean, not a step.
	wedge(model, o, "Cliff", 5, 12, 1.6, Vector3.new(-8, 5.7, -11.2), Vector3.new(0, 0, 1), false, 2, "Buttress")
	wedge(model, o, "CliffDark", 4, 10.5, 1.6, Vector3.new(4, 4.95, -11.2), Vector3.new(0, 0, 1), false, -2, "Buttress")
	wedge(model, o, "Cliff", 7, 13, 1.6, Vector3.new(15.2, 6.2, 3), Vector3.new(-1, 0, 0), false, 1, "Buttress")
	-- Two crags break the top outline (tilted blocks 1.3 over the paving, at the corners).
	ART.prim(model, { role = "CliffLight", name = "Crag", size = Vector3.new(3.4, 1.8, 2.6),
		cf = o * CFrame.new(-12.6, 16.5, -8.6) * CFrame.Angles(rad(4), rad(18), rad(-7)) })
	ART.prim(model, { role = "Cliff", name = "Crag", size = Vector3.new(2.6, 1.5, 3.2),
		cf = o * CFrame.new(12.8, 16.4, 7.4) * CFrame.Angles(rad(-5), rad(-22), rad(6)) })
	-- Paving and a broken lip along the top edge.
	box(model, o, "Flagstone", -14.2, 0.4, 15.5, 16, -10.2, 10.2, nil, "PavingL")
	box(model, o, "Flagstone", -0.2, 14.2, 15.5, 16, -10.2, 10.2, ART.shade("Flagstone", 0.03), "PavingR")
	box(model, o, "FlagstoneDark", -9, -4, 15.5, 15.95, -6, -3, nil, "PavingPatch")
	local lip = {
		{ -9, -10.6, 7, 1.4 }, { 4, -10.7, 9, 1.3 }, { 12, -10.3, 5, 1.6 },
		{ -14.6, 2, 1.6, 10 }, { 14.7, -1, 1.5, 9 }, { -4, 10.7, 11, 1.4 },
	}
	for _, l in lip do
		ART.prim(model, {
			role = "CliffLight",
			name = "Lip",
			size = Vector3.new(l[3], 0.9, l[4]),
			cf = o * CFrame.new(l[1], 15.9, l[2]) * CFrame.Angles(0, rad(rng:NextNumber(-3, 3)), 0),
		})
	end
	-- The arrival pad is a 1-high plinth (the greybox ArrivalPoint): stone with a thin mark.
	local px, pz = PAD_X, PAD_Z
	box(model, o, "FlagstoneDark", px - 4, px + 4, 16, 17, pz - 4, pz + 4, nil, "Plinth")
	box(model, o, "Trim", px - 4, px + 4, 17, 17.15, pz - 4, pz - 3.3, nil, "FrameS")
	box(model, o, "Trim", px - 4, px + 4, 17, 17.15, pz + 3.3, pz + 4, nil, "FrameN")
	box(model, o, "Trim", px - 4, px - 3.3, 17, 17.15, pz - 3.3, pz + 3.3, nil, "FrameW")
	box(model, o, "Trim", px + 3.3, px + 4, 17, 17.15, pz - 3.3, pz + 3.3, nil, "FrameE")
	-- Inlay of pale metal (saturation 12%): no neon, no reserved hue (designer ruling 2026-11-18).
	box(model, o, "TrimLight", px - 3, px + 3, 17.02, 17.1, pz - 3, pz - 2.7, nil, "StripS")
	box(model, o, "TrimLight", px - 3, px + 3, 17.02, 17.1, pz + 2.7, pz + 3, nil, "StripN")
	box(model, o, "TrimLight", px - 3, px - 2.7, 17.02, 17.1, pz - 2.7, pz + 2.7, nil, "StripW")
	box(model, o, "TrimLight", px + 2.7, px + 3, 17.02, 17.1, pz - 2.7, pz + 2.7, nil, "StripE")
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

-- The cave as it really stands: only the sealed shell (the real walls, jambs and roof).
-- The ten real rocks around it are dressed one by one in dress/setpieces.luau.
-- Air space: nothing here may stand in the lane (x within LANE_HALF of the axis, in
-- front of z = -18) above +14. The jambs lean in, but their inner top edge stays
-- outside x = LANE_HALF; the lintel is flush with the front plane, not past it.
local LANE_HALF, MOUTH_HALF = 10.5, 8.5
local function buildCaveShell(model: Model, o: CFrame)
	local inside = ART.shade("CliffDark", -0.06)
	local courses = {
		{ "CliffDark", -0.5, 4.8, 0.05, 0.7 },
		{ "Cliff", 4.5, 9.5, 0.05, 0.8 },
		{ "Cliff", 9.2, 14.6, 0.05, 0.7 },
	}
	-- Real shell: sides x +-18 (z +-14), back z 16, front corners x 8.5..20 at z -16 (4 thick).
	cladFace(model, o, -20, 0, -90, 36, courses, 2.6, 5, 9, "WallL")
	cladFace(model, o, 20, 0, 90, 36, courses, 2.6, 5, 9, "WallR")
	cladFace(model, o, 0, 18, 0, 40, courses, 2.6, 5, 9, "WallBack")
	-- Front corners stop at 13.7 (+0.25 jitter = 13.95): nothing in front of z -18 above +14.
	local frontCourses = {
		{ "CliffDark", -0.5, 4.8, 0.05, 0.7 },
		{ "Cliff", 4.5, 9.3, 0.05, 0.8 },
		{ "Cliff", 9.0, 13.7, 0.05, 0.7 },
	}
	cladFace(model, o, -14.25, -18, 180, 11.5, frontCourses, 2.6, 4, 7, "FrontL")
	cladFace(model, o, 14.25, -18, 180, 11.5, frontCourses, 2.6, 4, 7, "FrontR")
	-- Lining, seen only once the plug is gone.
	box(model, o, "CliffDark", -17.6, -16, 0, 14.2, -16, 16.2, inside, "LiningL")
	box(model, o, "CliffDark", 16, 17.6, 0, 14.2, -16, 16.2, inside, "LiningR")
	box(model, o, "CliffDark", -17.6, 17.6, 0, 14.2, 14, 16.2, inside, "LiningBack")
	box(model, o, "CliffDark", -17.6, -8.6, 0, 14.2, -16, -14, inside, "LiningFrontL")
	box(model, o, "CliffDark", 8.6, 17.6, 0, 14.2, -16, -14, inside, "LiningFrontR")
	-- Reveals: dark rock between the plug and the jambs, so the mouth is a dark opening.
	for _, s in { -1, 1 } do
		local x0, x1 = s * MOUTH_HALF, s * (LANE_HALF + 0.1)
		box(model, o, "CliffDark", math.min(x0, x1), math.max(x0, x1), 0, 14.1, -18, -14.4, ART.shade("CliffDark", -0.04), "Reveal")
		-- Leaning jamb: tips 7 degrees in; centre set so the inner top edge is at |x| >= 10.6.
		ART.prim(model, {
			role = "Cliff",
			name = "Jamb",
			size = Vector3.new(3.6, 15.2, 3.4),
			cf = o * CFrame.new(s * 13.4, 7.5, -17.2) * CFrame.Angles(0, 0, rad(s * 7)),
			color = ART.shade("Cliff", 0.03),
		})
		ART.prim(model, {
			role = "CliffLight",
			name = "JambFoot",
			size = Vector3.new(4.8, 2.6, 3.8),
			cf = o * CFrame.new(s * 13.6, 1.1, -17.1) * CFrame.Angles(0, rad(s * 3), 0),
		})
	end
	-- Heavy lintel: flush with the front plane (z -18), under a roof set back.
	box(model, o, "CliffDark", -12.8, 12.8, 14, 17.5, -18, -14.4, ART.shade("CliffDark", -0.02), "Lintel")
	-- Roof: a dark lower slab (the ceiling) and a lighter upper slab, set back from the front.
	box(model, o, "CliffDark", -20.4, 20.4, 14, 16.4, -17.3, 18.4, nil, "RoofLower")
	ART.prim(model, {
		role = "Cliff",
		name = "RoofUpper",
		size = Vector3.new(39.4, 2.2, 34.4),
		cf = o * CFrame.new(0, 16.9, 0.6) * CFrame.Angles(rad(0.6), rad(1.2), 0),
	})
	-- Boulders on the roof, at the back: at most 3 above the roof top.
	mass(model, o, "CliffLight", -9, 7, 9, 9, 17.5, 20.6, 0, 8, 2, true)
	mass(model, o, "Cliff", 6, 10, 10, 8, 17.5, 21, 0, -10, -3, true)
	mass(model, o, "CliffDark", 15, 0, 6, 7, 17.5, 20, 0, 14, 4, false)
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
	local GAP = 18
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
	place("Cave_Shell", 40, Vector3.new(40, 18, 36), nil, "Cave", "real shell only; rocks are dressed apart", buildCaveShell)
	place("Pad_Entry", 12, Vector3.new(12, 1, 12), nil, "Pad", "go: ring and chevrons", buildPadEntry)
	place("Pad_Return", 14, Vector3.new(14, 1, 14), nil, "Pad", "leave: doorway and arrow out", buildPadReturn)
	place("Pad_Spawn", 8, Vector3.new(8, 1, 8), nil, "Pad", "neutral", buildPadSpawn)
	place("Dressing_Floor", 30, Vector3.new(30, 1, 30), Vector3.new(0, -0.5, 0), "Dressing", "tufts, pebbles, rubble, flags", buildDressing)
	place("Floating_Rock_A", 16, Vector3.new(16, 14, 16), Vector3.new(0, 14, 0), "Floating", "centre +14", buildFloatRock(16, 14, 14, true))
	place("Floating_Rock_B", 9, Vector3.new(9, 8, 9), Vector3.new(0, 10, 0), "Floating", "centre +10", buildFloatRock(9, 8, 10, false))
	place("Rim_Crystals", 12, Vector3.new(12, 10, 6), nil, "Crystals", "outward-face dressing", buildCrystals)
end)

return ART.report(KIT)
