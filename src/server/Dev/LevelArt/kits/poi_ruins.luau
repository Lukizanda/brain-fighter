-- POI kit: ruins of the letter-stone culture (broken arch, colonnade, stone ring, bridge stub).
-- Run: return require(game.ServerStorage.LevelArtRun:Clone())("kits/poi_ruins.luau")
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())
local row = ART.ROWS.POI
local FLOOR_Y = ART.FLOOR_Y
local V3 = Vector3.new

-- Layout along the strip (x centres), at least ~14 studs of air between pieces.
-- The bridge is shown side-on (yaw 90), so its 37 studs of length run along X.
local ARCH_X, COLONNADE_X, RING_X, BRIDGE_X = 187, 237, 289, 341
local BRIDGE_RAISE = 8 -- the bridge is lifted on the stage so its underside shows

local RUNE_WIDTH = 0.3 -- GateSeam strips stay under 0.4
local RUNE_PROUD = 0.2

local function rad(d: number): number
	return math.rad(d)
end

local function rot(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

-- A block (or other primitive) in the asset's local space.
local function put(model, origin, role, size, lcf, opts)
	opts = opts or {}
	return ART.prim(model, {
		role = role,
		size = size,
		cf = origin * lcf,
		shape = opts.shape,
		name = opts.name,
		color = opts.color,
	})
end

-- A drum: a Cylinder stood up on its end. Axis is local X, so turn 90 about Z.
local function drum(model, origin, role, length, diameter, pos, tilt, rng, name)
	local lcf = CFrame.new(pos) * rot(tilt.X, tilt.Y, tilt.Z) * rot(0, 0, 90)
	return put(model, origin, role, V3(length, diameter, diameter), lcf, {
		shape = "Cylinder",
		name = name,
		color = ART.shade(role, rng:NextNumber(-0.02, 0.02)),
	})
end

-- A wedge chip in local space. dir = local direction the tall face points to.
local function chip(model, origin, role, width, height, run, pos, dir, opts)
	opts = opts or {}
	return ART.wedge(model, {
		role = role,
		width = width,
		height = height,
		run = run,
		center = origin:PointToWorldSpace(pos),
		highToward = origin:VectorToWorldSpace(dir),
		hang = opts.hang,
		roll = opts.roll,
		name = opts.name,
	})
end

----------------------------------------------------------------------
-- 1. Broken arch
----------------------------------------------------------------------
local function buildArch(model: Model, origin: CFrame)
	local rng = Random.new(7101)
	local R, CY, DEPTH = 9.5, 12.2, 7

	-- standing leg: a heavy two-course plinth, wider than the shaft
	put(model, origin, "CliffDark", V3(9.8, 1.4, 8.4), CFrame.new(-9.6, 0.7, 0) * rot(0, 2, 0.8), { name = "PlinthL1" })
	put(model, origin, "Cliff", V3(8.6, 1.8, 8.0), CFrame.new(-9.6, 2.3, 0) * rot(0, -2, -0.6), { name = "PlinthL2" })
	chip(model, origin, "CliffDark", 6, 2.4, 2.8, V3(-14.0, 1.2, -0.3), V3(1, 0, 0), { name = "RubbleL" })
	put(model, origin, "Turf", V3(2.2, 0.3, 1.8), CFrame.new(-12.4, 3.2, -2) * rot(0, 20, 0), { name = "MossPlinth" })

	-- the standing leg: three courses, mixing weathered and cut stone
	put(model, origin, "Cliff", V3(6.6, 4.2, 7.6), CFrame.new(-9.6, 3.6, 0) * rot(0, 1.5, 1.2), { name = "LegBase" })
	put(model, origin, "GateStoneDark", V3(6.0, 3.8, 7.2), CFrame.new(-9.5, 7.4, -0.1) * rot(0, -1.8, -1.0), { name = "LegMid" })
	put(model, origin, "GateStone", V3(5.7, 3.5, 7.0), CFrame.new(-9.4, 10.9, 0) * rot(0, 1.2, 1.4), { name = "LegTop" })

	-- the springing half of the span: tapered voussoirs on a circle about (0, CY)
	local angles = { 170, 148, 126, 104 }
	local roles = { "GateStone", "GateStoneDark", "GateStone", "GateStoneDark" }
	for i, theta in angles do
		local t = rad(theta)
		local sizeX = 5.2 - 0.25 * i -- the blocks taper a little toward the crown
		local lcf = CFrame.new(R * math.cos(t), CY + R * math.sin(t), 0) * rot(0, 0, theta + rng:NextNumber(-3, 3))
		put(model, origin, roles[i], V3(sizeX + 0.4, 4.7, DEPTH - 0.2 * (i % 2)), lcf, { name = "Voussoir_" .. i })
	end
	-- broken, stepped edge: a stub on the outer ring, then a smaller one above it
	do
		local t = rad(91)
		put(
			model,
			origin,
			"CliffLight",
			V3(2.9, 4.3, 6.4),
			CFrame.new((R + 1.4) * math.cos(t), CY + (R + 1.4) * math.sin(t), 0.2) * rot(0, 3, 91 + 2),
			{ name = "StubA" }
		)
		local t2 = rad(82)
		put(
			model,
			origin,
			"Cliff",
			V3(1.7, 3.0, 5.2),
			CFrame.new((R + 2.2) * math.cos(t2), CY + (R + 2.2) * math.sin(t2), 0.2) * rot(0, -4, 82 - 3),
			{ name = "StubB" }
		)
	end
	chip(model, origin, "GateStone", 3.6, 1.8, 2.2, V3(-2.4, 18.6, 0), V3(1, 0, 0), { hang = true, name = "BreakChip" })

	-- the far leg: a broken pier 11.6 tall, one springer block leaning in on top
	put(model, origin, "CliffDark", V3(8.6, 1.4, 8.0), CFrame.new(9.6, 0.7, 0.1) * rot(0, -4, -1.2), { name = "PierFooting" })
	put(model, origin, "GateStoneDark", V3(6.0, 4.0, 7.2), CFrame.new(9.7, 3.4, 0) * rot(0, -2, -1.6), { name = "Pier1" })
	put(model, origin, "Cliff", V3(5.7, 3.6, 7.0), CFrame.new(9.6, 7.0, 0.1) * rot(0, 2, 1.4), { name = "Pier2" })
	put(model, origin, "GateStone", V3(5.4, 3.0, 6.8), CFrame.new(9.5, 10.1, 0) * rot(0, -1.5, -1.2), { name = "Pier3" })
	do
		local t = rad(13)
		put(
			model,
			origin,
			"GateStone",
			V3(4.6, 4.4, 6.6),
			CFrame.new(R * math.cos(t) - 0.3, CY + R * math.sin(t) + 0.3, 0) * rot(0, 0, 13 + 11),
			{ name = "Springer" }
		)
	end
	chip(model, origin, "CliffLight", 3.6, 1.4, 2.6, V3(11.2, 10.9, 0.1), V3(1, 0, 0), { name = "PierChip" })
	put(model, origin, "Turf", V3(2.2, 0.3, 2), CFrame.new(11.4, 11.65, -1.4) * rot(0, 25, 0), { name = "MossPier" })

	-- fallen voussoirs: behind the legs (+Z), never in front
	put(model, origin, "CliffDark", V3(4.6, 2.4, 4.4), CFrame.new(2.4, 1.4, 2.8) * rot(0, 24, 7), { name = "FallenA" })
	put(model, origin, "GateStone", V3(4, 2.2, 4), CFrame.new(-1.6, 1.2, 3.0) * rot(2, -38, -4), { name = "FallenB" })
	put(model, origin, "Cliff", V3(3.4, 1.9, 3.8), CFrame.new(3.4, 3.3, 3.0) * rot(0, 12, 14), { name = "FallenC" })

	ART.proxy(model, origin, V3(-9.6, 6.25, 0), V3(6.6, 12.5, 7.6))
	ART.proxy(model, origin, V3(9.6, 5.8, 0), V3(6.0, 11.6, 7.2)) -- far pier, full height
end

----------------------------------------------------------------------
-- 2. Colonnade
----------------------------------------------------------------------
local function buildColonnade(model: Model, origin: CFrame)
	local rng = Random.new(7202)
	local STEP1_TOP, STEP2_TOP = 1.2, 2.4

	put(model, origin, "CliffDark", V3(38.6, 1.2, 9.8), CFrame.new(0, 0.6, 0) * rot(0, 0.6, 0.3), { name = "Step1" })
	put(model, origin, "Cliff", V3(33, 1.5, 7.8), CFrame.new(0, 1.65, 0.1) * rot(0, -0.8, -0.3), { name = "Step2" })
	chip(model, origin, "CliffDark", 8, 1.6, 3, V3(20.6, 0.8, -1), V3(-1, 0, 0), { name = "StepRubbleR" })
	chip(model, origin, "Cliff", 6, 1.3, 2.6, V3(-20.4, 0.7, 1.4), V3(1, 0, 0), { name = "StepRubbleL" })

	local DRUM_LEN = 3.8
	local diameters = { 3.6, 3.4, 3.3 }
	local function column(x: number, tag: string, count: number, lastLength: number?)
		local roles = { "GateStoneDark", "GateStone", "GateStone" }
		local y = STEP2_TOP - 0.1
		for i = 1, count do
			local len = DRUM_LEN
			if i == count and lastLength then
				len = lastLength
			end
			local jitter = V3(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12))
			drum(
				model,
				origin,
				roles[i],
				len,
				diameters[i],
				V3(x, y + len / 2, 0) + jitter,
				V3(rng:NextNumber(-0.8, 0.8), 0, rng:NextNumber(-0.8, 0.8)),
				rng,
				tag .. "_Drum" .. i
			)
			y += len - 0.2
		end
		return y + 0.2 -- top of the shaft
	end

	-- two complete columns: a wide echinus drum and a square abacus on each
	local capTop = 0
	for i, x in { -14, -7 } do
		local top = column(x, "Col" .. i, 3)
		drum(model, origin, "CliffLight", 0.9, 4.6, V3(x, top + 0.35, 0), V3(0, 0, 0), rng, "CapitalDrum" .. i)
		put(
			model,
			origin,
			"CliffLight",
			V3(5.2, 0.9, 5.2),
			CFrame.new(x, top + 1.25, 0) * rot(0, rng:NextNumber(-3, 3), rng:NextNumber(-0.6, 0.6)),
			{ name = "Abacus" .. i }
		)
		capTop = top + 1.7
	end
	-- entablature: a deep two-course beam, the right end broken off at an angle
	put(model, origin, "Cliff", V3(10.0, 1.6, 4.8), CFrame.new(-11.7, capTop + 0.7, 0) * rot(0, 0.8, 0.7), { name = "Architrave" })
	chip(model, origin, "Cliff", 4.8, 1.6, 3.4, V3(-5.0, capTop + 0.7, 0), V3(-1, 0, 0), { name = "ArchitraveBreak" })
	put(model, origin, "CliffLight", V3(9.4, 1.4, 5.2), CFrame.new(-11.9, capTop + 2.1, 0) * rot(0, -0.6, 0.5), { name = "Cornice" })
	chip(model, origin, "CliffLight", 5.0, 1.2, 2.6, V3(-6.0, capTop + 2.0, 0), V3(-1, 0, 0.2), { name = "CorniceChip" })

	-- one broken half-way
	local top3 = column(0, "Col3", 2, 2.6)
	chip(model, origin, "GateStone", 3.4, 1.4, 2.2, V3(0, top3 + 0.5, 0), V3(0.5, 0, -1), { name = "Col3Chip" })
	-- one stump
	local top4 = column(7, "Col4", 1, 2.2)
	chip(model, origin, "GateStoneDark", 3.2, 1.0, 2.0, V3(7, top4 + 0.4, 0), V3(-1, 0, 0.3), { name = "Col4Chip" })
	put(model, origin, "Turf", V3(1.6, 0.3, 1.4), CFrame.new(7.3, top4 + 0.05, 0.8) * rot(0, 30, 0), { name = "MossStump" })

	-- one fallen, as drums on the steps
	drum(model, origin, "GateStone", 4.0, 3.6, V3(12.6, STEP2_TOP + 1.75, -1.8), V3(0, 12, 0), rng, "Fallen_Drum1")
	drum(model, origin, "GateStoneDark", 4.0, 3.4, V3(15.4, STEP2_TOP + 1.65, 1.4), V3(0, 74, 0), rng, "Fallen_Drum2")
	drum(model, origin, "GateStone", 3.4, 3.3, V3(17.8, STEP1_TOP + 1.6, -0.2), V3(0, 92, 6), rng, "Fallen_Drum3")
	put(model, origin, "CliffLight", V3(5.2, 0.9, 5.2), CFrame.new(3.8, STEP2_TOP + 0.45, 2.0) * rot(0, 28, 3), { name = "FallenAbacus" })

	-- one block as tall as the tallest step, then each standing column
	ART.proxy(model, origin, V3(0, 1.2, 0.1), V3(33, 2.4, 7.8))
	ART.proxy(model, origin, V3(-14, (STEP2_TOP + capTop) / 2, 0), V3(5.2, capTop - STEP2_TOP, 5.2))
	ART.proxy(model, origin, V3(-7, (STEP2_TOP + capTop) / 2, 0), V3(5.2, capTop - STEP2_TOP, 5.2))
	ART.proxy(model, origin, V3(0, (STEP2_TOP + top3) / 2, 0), V3(3.6, top3 - STEP2_TOP, 3.6))
end

----------------------------------------------------------------------
-- 3. Stone ring
----------------------------------------------------------------------
local function buildRing(model: Model, origin: CFrame)
	local rng = Random.new(7303)
	local PLINTH_TOP = 0.8
	local R = 13.5
	local STONE_W, STONE_D = 4.5, 2.2
	-- lean (degrees about X, about Z) of each stone, every one a different way
	local LEANS = { { 3, -2 }, { -4, 3 }, { 2.5, 4 }, { -3, -4 }, { 4, 2.5 }, { 0, 0 }, { -2.5, 4.5 } }

	-- plinth: a low slab, the plinth and one thin concentric ring inlay
	drum(model, origin, "CliffDark", 0.5, 35, V3(0, 0.25, 0), V3(0, 0, 0), rng, "PlinthRim")
	drum(model, origin, "GateStone", PLINTH_TOP, 32, V3(0, PLINTH_TOP / 2, 0), V3(0, 0, 0), rng, "Plinth")
	drum(model, origin, "GateStoneDark", 0.1, 24, V3(0, PLINTH_TOP + 0.05, 0), V3(0, 0, 0), rng, "RingOuter")
	drum(model, origin, "GateStone", 0.18, 22.6, V3(0, PLINTH_TOP + 0.09, 0), V3(0, 0, 0), rng, "RingInner")

	local heights = { 11.6, 12, 12.4, 9.6, 10, 12, 8.4 }
	local roles = { "GateStone", "GateStoneDark", "Cliff", "GateStone", "CliffLight", "GateStoneDark", "Cliff" }
	local FALLEN = 6 -- index (1-based) of the stone that lies inward
	local tops = {}

	-- Rune strokes: parallel slashes only, two at most. No V, I, L or T shape a
	-- player could read as a letter.
	local function rune(frame: CFrame, z: number, h: number, i: number)
		local pattern = i % 3
		local function stroke(x: number, y: number, len: number, deg: number)
			put(
				model,
				origin,
				"GateSeam",
				V3(RUNE_WIDTH, len, RUNE_WIDTH),
				frame * CFrame.new(x, y, z) * rot(0, 0, deg),
				{ name = "Rune" }
			)
		end
		local y = h * 0.55
		if pattern == 0 then
			stroke(-0.6, y, 4.4, 35)
			stroke(0.7, y - 0.4, 3.2, 35)
		elseif pattern == 1 then
			stroke(0, y, 5.0, -50)
		else
			stroke(-0.5, y, 4.4, 60)
			stroke(0.8, y + 0.5, 2.4, 60)
		end
	end

	for i = 1, 7 do
		local phi = rad(90 + (i - 4) * (360 / 7))
		local pos = V3(R * math.cos(phi), 0, R * math.sin(phi))
		local h = heights[i]
		local face = CFrame.lookAt(pos, V3(0, 0, 0)) -- local -Z looks at the plinth centre
		if i == FALLEN then
			-- fell inward: top end toward the centre, resting on the plinth
			local frame = face * CFrame.new(0, PLINTH_TOP + 0.4, -0.6) * rot(-80, 0, 2)
			put(model, origin, roles[i], V3(STONE_W, h, STONE_D), frame * CFrame.new(0, h / 2, 0), { name = "StoneFallen" })
			rune(frame, STONE_D / 2 + RUNE_WIDTH / 2 - RUNE_PROUD, h, i)
			chip(
				model,
				origin,
				"GateStoneDark",
				STONE_W - 0.4,
				1.4,
				STONE_D,
				(frame * CFrame.new(0, h + 0.4, 0)).Position,
				frame.RightVector,
				{ name = "StoneChipFallen" }
			)
		else
			local tilt = rot(LEANS[i][1], rng:NextNumber(-3, 3), LEANS[i][2])
			local frame = face * CFrame.new(0, PLINTH_TOP - 0.2, 0) * tilt
			local s = put(
				model,
				origin,
				roles[i],
				V3(STONE_W, h, STONE_D),
				frame * CFrame.new(0, h / 2, 0),
				{ name = "Stone" .. i }
			)
			rune(frame, -(STONE_D / 2 + RUNE_WIDTH / 2 - RUNE_PROUD), h, i)
			tops[i] = { frame = frame, h = h, pos = s.Position }
			ART.proxy(model, origin, face.Position + V3(0, (h + PLINTH_TOP) / 2 - 0.1, 0), V3(STONE_W, h - 0.2, STONE_D), face.Rotation)
		end
	end

	-- two neighbouring pairs still joined by a lintel
	local function lintel(a: number, b: number, name: string)
		local pa = origin:PointToObjectSpace(tops[a].pos)
		local pb = origin:PointToObjectSpace(tops[b].pos)
		local mid = (pa + pb) / 2
		local lowTop = math.min(tops[a].h, tops[b].h) + PLINTH_TOP - 0.2
		local chord = V3(pb.X - pa.X, 0, pb.Z - pa.Z)
		local frame = CFrame.lookAt(V3(mid.X, 0, mid.Z), V3(mid.X, 0, mid.Z) + chord) * rot(0, 90, 0)
		put(
			model,
			origin,
			"CliffLight",
			V3(chord.Magnitude + 4.2, 1.8, 3.0),
			CFrame.new(mid.X, lowTop + 0.7, mid.Z) * frame.Rotation * rot(0, 0, 1.2),
			{ name = name }
		)
	end
	lintel(1, 2, "LintelA")
	lintel(4, 5, "LintelB")

	-- broken tops: a wedge on each free-standing stone (the others carry a lintel), a little moss, rubble
	for _, i in { 3, 7 } do
		local t = tops[i]
		chip(
			model,
			origin,
			if i == 3 then "GateStone" else "Cliff",
			STONE_W - 0.3,
			1.5,
			STONE_D,
			(t.frame * CFrame.new(0, t.h + 0.45, 0)).Position,
			t.frame.RightVector * (if i == 3 then 1 else -1),
			{ name = "StoneChip" .. i }
		)
	end
	put(
		model,
		origin,
		"Turf",
		V3(1.8, 0.3, 1.4),
		CFrame.new((tops[7].frame * CFrame.new(-0.6, tops[7].h - 0.1, 0)).Position) * rot(0, 20, 0),
		{ name = "MossStone7" }
	)
	chip(model, origin, "CliffDark", 4, 1.6, 2.4, V3(-15.5, 0.8, -6), V3(1, 0, 0.3), { name = "RubbleA" })
	chip(model, origin, "Cliff", 3.4, 1.3, 2.2, V3(16, 0.65, 4), V3(-1, 0, -0.2), { name = "RubbleB" })

	-- plinth: one centred box inside the footprint
	ART.proxy(model, origin, V3(0, PLINTH_TOP / 2, 0), V3(25, PLINTH_TOP, 25))
end

----------------------------------------------------------------------
-- 4. Bridge stub
----------------------------------------------------------------------
local function buildBridge(model: Model, origin: CFrame)
	local rng = Random.new(7404)
	local DECK_T = 1.7 -- thin deck, top at 0

	-- a short narrow stone pier carries the near end
	put(model, origin, "CliffDark", V3(6, 5.2, 4.6), CFrame.new(0, -4.1, -17.6) * rot(0, 2, 0.8), { name = "Pier" })
	put(model, origin, "Cliff", V3(7.4, 1.2, 5.8), CFrame.new(0, -6.5, -17.4) * rot(0, -3, -0.5), { name = "PierFoot" })

	-- paved deck: two solid slabs, then three that end at three different lengths
	put(model, origin, "GateStone", V3(14, DECK_T, 9.6), CFrame.new(0, -DECK_T / 2, -15.2) * rot(0, 0.5, 0.2), { name = "DeckA" })
	put(model, origin, "GateStoneDark", V3(13.8, DECK_T, 12.6), CFrame.new(0.1, -DECK_T / 2 - 0.05, -4.2) * rot(0, -0.8, -0.3), { name = "DeckB" })
	put(model, origin, "GateStone", V3(4.8, DECK_T, 8.2), CFrame.new(-4.5, -DECK_T / 2 - 0.4, 6.0) * rot(5, 2, 0), { name = "BreakSlab1" }) -- ends near z 10
	put(model, origin, "CliffLight", V3(4.6, DECK_T, 4.8), CFrame.new(0, -DECK_T / 2 - 0.25, 4.0) * rot(3, -2, 1), { name = "BreakSlab2" }) -- ends near 6.4
	put(model, origin, "GateStoneDark", V3(4.6, DECK_T, 6.6), CFrame.new(4.6, -DECK_T / 2 - 0.5, 5.0) * rot(9, 3, -1), { name = "BreakSlab3" }) -- ends near 8.3

	-- two corbel arms: a seat, then hanging wedges that taper toward the break
	for i, x in { -4.6, 4.6 } do
		put(model, origin, "Cliff", V3(3.6, 1.3, 6.2), CFrame.new(x, -2.3, -15.4) * rot(0, rng:NextNumber(-1.5, 1.5), 0), { name = "CorbelSeat" .. i })
		chip(model, origin, "CliffDark", 3.4, 3.0, 11, V3(x, -3.0, -12.6), V3(0, 0, -1), { hang = true, name = "CorbelArm" .. i })
		chip(model, origin, "Cliff", 3.0, 2.0, 6, V3(x, -4.6, -16.2), V3(0, 0, -1), { hang = true, name = "CorbelStep" .. i })
	end

	-- two chunks hanging 2 to 4 studs beyond the break, a little lower
	put(model, origin, "Cliff", V3(3.8, 1.5, 3.4), CFrame.new(-4.2, -2.4, 13.4) * rot(14, 25, -12), { name = "ChunkA" })
	put(model, origin, "GateStoneDark", V3(3, 1.3, 2.8), CFrame.new(3.4, -3.0, 11.6) * rot(-12, 50, 14), { name = "ChunkB" })

	-- low kerbs and three posts of uneven height
	put(model, origin, "Cliff", V3(1.2, 1.1, 14), CFrame.new(-6.4, 0.5, -13) * rot(0, 0.6, 0.4), { name = "KerbL" })
	put(model, origin, "CliffDark", V3(1.2, 1.0, 18.4), CFrame.new(6.4, 0.45, -10.8) * rot(0, -0.5, -0.4), { name = "KerbR" })
	chip(model, origin, "CliffLight", 1.2, 1.0, 1.8, V3(6.4, 0.9, -0.9), V3(0, 0, -1), { name = "KerbChip" })
	local posts = { { -6.4, -16, 3.6 }, { 6.4, -8, 2.5 }, { -6.4, -5.2, 1.9 } }
	for i, d in posts do
		put(model, origin, "GateStone", V3(1.7, d[3], 1.7), CFrame.new(d[1], d[3] / 2 - 0.1, d[2]) * rot(0, 8 * i, (i - 2) * 1.8), { name = "Post" .. i })
	end
	put(model, origin, "CliffLight", V3(2.2, 0.55, 2.2), CFrame.new(-6.4, 3.65, -16) * rot(0, -6, 2), { name = "PostCap1" })
	chip(model, origin, "GateStoneDark", 1.7, 0.8, 1.2, V3(6.4, 2.6, -8), V3(1, 0, 0), { name = "PostChip2" })
	put(model, origin, "Turf", V3(1.6, 0.3, 1.4), CFrame.new(-6.3, 1.15, -9.5) * rot(0, 15, 0), { name = "MossKerb" })

	-- the solid deck (top 0) and the kerbs
	ART.proxy(model, origin, V3(0, -DECK_T / 2, -9), V3(14, DECK_T, 22))
	ART.proxy(model, origin, V3(-6.4, 0.55, -13), V3(1.2, 1.1, 14))
	ART.proxy(model, origin, V3(6.4, 0.5, -10.8), V3(1.2, 1.0, 18.4))
end

----------------------------------------------------------------------
-- Placement
----------------------------------------------------------------------
ART.run("LevelArt: POI ruins", function()
	ART.poi({
		name = "POI_BrokenArch",
		at = V3(ARCH_X, FLOOR_Y, row.z),
		footprint = V3(28, 26, 8),
		placement = "rim",
		note = "one leg and half the span stand; fallen voussoirs",
		build = buildArch,
	})
	ART.poi({
		name = "POI_Colonnade",
		at = V3(COLONNADE_X, FLOOR_Y, row.z),
		footprint = V3(40, 18, 10),
		placement = "rim",
		note = "behind the overlook; two whole, one broken, one stump, one fallen",
		build = buildColonnade,
	})
	ART.poi({
		name = "POI_StoneRing",
		at = V3(RING_X, FLOOR_Y, row.z),
		footprint = V3(36, 14, 36),
		placement = "hub",
		note = "seven stones, two lintels, one fallen; abstract runes only",
		build = buildRing,
	})
	ART.poi({
		name = "POI_BridgeStub",
		at = V3(BRIDGE_X, FLOOR_Y + BRIDGE_RAISE, row.z),
		yaw = 90,
		footprint = V3(14, 10, 40),
		placement = "hub",
		note = "hub only; raised +8 and turned 90 deg on stage (length along X); deck top is +0 when placed",
		build = buildBridge,
	})
end)

return ART.report("Kit_POI")
