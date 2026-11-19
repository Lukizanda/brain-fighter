-- POI monuments: single focal pieces with a strong silhouette.
-- Beacon (watchtower), ColossusHead (fallen stone head), RingShrine (levitating ring).
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())
local row = ART.ROWS.POI

local rad = math.rad
local PI = math.pi

-- A block placed in `frame` (a CFrame in world space), with optional Euler degrees.
local function P(model, frame, role, pos, size, rx, ry, rz, extra)
	local spec = {
		role = role,
		size = size,
		cf = frame * CFrame.new(pos) * CFrame.Angles(rad(rx or 0), rad(ry or 0), rad(rz or 0)),
	}
	if extra then
		for k, v in extra do
			spec[k] = v
		end
	end
	return ART.prim(model, spec)
end

-- A wedge in `frame`: tall face at local +Z, slope falls toward local -Z.
local function W(model, frame, role, pos, size, rx, ry, rz)
	return P(model, frame, role, pos, size, rx, ry, rz, { shape = "Wedge" })
end

----------------------------------------------------------------------
-- Beacon
----------------------------------------------------------------------
local function buildBeacon(model, origin)
	-- Rough rock footing
	P(model, origin, "Cliff", Vector3.new(0, 1.3, 0.2), Vector3.new(13.6, 2.6, 12.4), 0, 4, 0)
	P(model, origin, "CliffDark", Vector3.new(0.4, 0.8, 0.5), Vector3.new(11.6, 2.4, 13.2), 0, -8, 0)
	P(model, origin, "Bedrock", Vector3.new(-4.6, 1.0, -4.8), Vector3.new(4.6, 2.0, 3.6), 0, 15, 3)
	W(model, origin, "Cliff", Vector3.new(4.6, 1.1, -5.2), Vector3.new(4.6, 2.2, 3), 0, 0, 0)
		-- Threshold stair and fallen block
	P(model, origin, "GateStoneDark", Vector3.new(0, 0.7, -6.2), Vector3.new(4.2, 1.5, 1.5), 0, 1.5, 0)
	
	-- Stage 1 (battered base)
	local S1 = origin * CFrame.new(0, 7.75, 0) * CFrame.Angles(0, rad(1.5), 0)
	ART.prim(model, { role = "GateStoneDark", size = Vector3.new(9.6, 10.7, 9.6), cf = S1 })
	P(model, S1, "Bedrock", Vector3.new(0, -2.85, -4.85), Vector3.new(2.8, 4.6, 0.3))
	P(model, S1, "GateStone", Vector3.new(0, -0.2, -5.0), Vector3.new(4.0, 0.8, 0.6))
		P(model, origin, "GateStone", Vector3.new(0, 13.35, 0), Vector3.new(10.8, 1.1, 10.8), 0, 0.8, 0, { color = ART.shade("GateStone", 0.03) })
	-- Stage 2
	local S2 = origin * CFrame.new(0, 17.4, 0) * CFrame.Angles(0, rad(-1.2), 0)
	ART.prim(model, { role = "GateStone", size = Vector3.new(8.0, 7.4, 8.0), cf = S2 })
	P(model, S2, "Bedrock", Vector3.new(-1.5, 0.6, -4.05), Vector3.new(0.7, 2.6, 0.3))
	P(model, S2, "Bedrock", Vector3.new(1.5, 0.6, -4.05), Vector3.new(0.7, 2.6, 0.3))
	P(model, origin, "GateStone", Vector3.new(0, 21.0, 0), Vector3.new(9.2, 1.0, 9.2), 0, -1, 0, { color = ART.shade("GateStone", 0.03) })
	-- Stage 3, lower part full, upper part with its front-right corner broken away
	local S3 = origin * CFrame.Angles(0, rad(2), 0)
	P(model, S3, "GateStone", Vector3.new(0, 23.3, 0), Vector3.new(6.6, 4.0, 6.6))
	P(model, S3, "GateStone", Vector3.new(-1.45, 27.25, 0), Vector3.new(3.7, 3.9, 6.6))
	P(model, S3, "GateStone", Vector3.new(1.85, 27.25, 1.65), Vector3.new(2.9, 3.9, 3.3))
	W(model, S3, "GateStone", Vector3.new(1.85, 26.1, -1.65), Vector3.new(2.9, 1.6, 3.3))
	-- Lantern floor, plinth, posts, light (all glow above +35), cap
	P(model, origin, "GateStone", Vector3.new(0, 29.7, 0), Vector3.new(8.8, 1.0, 8.8), 0, -1.5, 0, { color = ART.shade("GateStone", 0.05) })
	P(model, origin, "GateStoneDark", Vector3.new(0, 32.7, 0), Vector3.new(2.4, 5.0, 2.4), 0, 20, 0)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(model, origin, "GateStoneDark", Vector3.new(sx * 3.1, 34.15, sz * 3.1), Vector3.new(1.3, 7.9, 1.3), 0, 0, 0)
		end
	end
	local core = origin * CFrame.new(0, 36.6, 0) * CFrame.Angles(0, rad(30), 0)
	ART.prim(model, { role = "Crystal", size = Vector3.new(3.0, 3.0, 3.0), cf = core, transparency = 0.2, name = "BeaconCore" })
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(model, core, "GateSeam", Vector3.new(sx * 1.5, 0, sz * 1.5), Vector3.new(0.3, 3.0, 0.3))
		end
	end
	for _, sz in { -1, 1 } do
		P(model, core, "GateSeam", Vector3.new(0, 1.5, sz * 1.5), Vector3.new(3.1, 0.3, 0.3))
			end
	P(model, origin, "GateStone", Vector3.new(0, 38.6, 0), Vector3.new(8.4, 1.2, 8.4), 0, 2, 0, { color = ART.shade("GateStone", 0.07) })
	P(model, origin, "GateStone", Vector3.new(0, 39.6, 0), Vector3.new(4.2, 0.8, 4.2), 0, -4, 0, { color = ART.shade("GateStone", 0.08) })

	-- Floating islet: Turf-capped rock platform tapering to a point
	P(model, origin, "Turf", Vector3.new(0, -0.1, 0), Vector3.new(16.8, 0.5, 16.2), 0, 5, 0)
	P(model, origin, "Cliff", Vector3.new(0, -1.5, 0), Vector3.new(17.6, 2.8, 17.0), 0, 6, 0)
	P(model, origin, "CliffDark", Vector3.new(0.3, -4.2, 0), Vector3.new(14.5, 3.0, 14.0), 0, -11, 0)
	P(model, origin, "Bedrock", Vector3.new(-0.2, -6.7, 0.2), Vector3.new(11.0, 2.6, 10.6), 0, 17, 0)
	local dirs = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }
	for i, d in dirs do
		ART.wedge(model, {
			role = if i % 2 == 0 then "CliffDark" else "Bedrock",
			width = 8.5,
			height = 8.0,
			run = 6.0,
			center = origin:PointToWorldSpace(d * 2.6 + Vector3.new(0, -10.6, 0)),
			highToward = origin:VectorToWorldSpace(d),
			hang = true,
			roll = 0,
		})
	end
	
	ART.proxy(model, origin, Vector3.new(0, -1.35, 0), Vector3.new(17.0, 3.0, 16.4))
	ART.proxy(model, origin, Vector3.new(0, 6.5, 0.2), Vector3.new(13, 13, 12.6))
	ART.proxy(model, origin, Vector3.new(0, 25.25, 0), Vector3.new(8.6, 24.5, 8.6))
end

----------------------------------------------------------------------
-- Colossus head
----------------------------------------------------------------------
local function buildHead(model, origin)
	local PIVOT = Vector3.new(0, 5.5, 0)
	local TILT = CFrame.Angles(0, 0, rad(-20))
	local H = origin * CFrame.new(PIVOT) * TILT
	local function hb(role, pos, size, rx, ry, rz, extra)
		return P(model, H, role, pos, size, rx, ry, rz, extra)
	end
	local function hw(role, pos, size, rx, ry, rz)
		return W(model, H, role, pos, size, rx, ry, rz)
	end
	local light = { color = ART.shade("GateStone", 0.05) }
	-- Cheekbone block (widest, 18), jaw (11) with wedge jaw lines, chin
	hb("GateStone", Vector3.new(0, -0.5, 0), Vector3.new(18, 5.5, 14))
	hb("GateStoneDark", Vector3.new(0, -6.0, -0.7), Vector3.new(11, 5.0, 13))
	hw("GateStoneDark", Vector3.new(7.25, -5.25, -0.7), Vector3.new(13, 3.5, 3.5), 0, 90, 0)
	hw("GateStoneDark", Vector3.new(-7.25, -5.25, -0.7), Vector3.new(13, 3.5, 3.5), 0, -90, 0)
	hb("GateStone", Vector3.new(0, -7.6, -7.4), Vector3.new(8.5, 2.4, 1.6))
	-- Heavy brow bar, deep sockets, cheekbones, long nose, mouth slot
	hb("GateStoneDark", Vector3.new(0, 2.9, -8.4), Vector3.new(18.6, 2.6, 3.6))
	hb("Bedrock", Vector3.new(-4.6, 0.5, -7.05), Vector3.new(4.6, 2.6, 0.5))
	hb("Bedrock", Vector3.new(4.6, 0.5, -7.05), Vector3.new(4.6, 2.6, 0.5))
	hb("GateStone", Vector3.new(-5.4, -1.9, -7.6), Vector3.new(5.6, 1.6, 1.4), 0, 0, 2, light)
	hb("GateStone", Vector3.new(5.4, -1.9, -7.6), Vector3.new(5.6, 1.6, 1.4), 0, 0, -2, light)
	hw("GateStone", Vector3.new(0, -0.2, -9.2), Vector3.new(3.4, 8.0, 4.6), 0, 0, 0)
	hb("Bedrock", Vector3.new(0, -5.3, -7.25), Vector3.new(7.5, 0.9, 0.4))
	-- Cranium: stepped dome, one side sheared off jaggedly
	hb("GateStone", Vector3.new(0, 3.8, 0), Vector3.new(17, 3.0, 14.5), nil, nil, nil, light)
	hb("GateStone", Vector3.new(0, 6.6, 0), Vector3.new(14.5, 3.0, 12.5))
	hb("GateStone", Vector3.new(3.4, 9.1, 0), Vector3.new(7.6, 2.4, 10.5), 0, 4, 0, light)
	hw("GateStone", Vector3.new(-3.6, 9.1, -0.8), Vector3.new(8.0, 2.4, 6.5), 0, 90, 0)
	hw("GateStoneDark", Vector3.new(-3.0, 8.6, 4.2), Vector3.new(5.5, 1.6, 4.5), 0, -90, 0)
	hb("CliffDark", Vector3.new(-2.0, 8.0, 1.5), Vector3.new(4.0, 0.5, 4.0), 0, 15, 0)
	-- Block ear on the upper side
	hb("GateStone", Vector3.new(-9.7, 0.2, 1.5), Vector3.new(1.6, 4.4, 3.2), 0, 0, 3)
	hb("Bedrock", Vector3.new(-10.55, 0.1, 1.5), Vector3.new(0.3, 2.2, 1.4))
	-- Two small moss caps
	hb("Turf", Vector3.new(-5.0, 4.3, -8.6), Vector3.new(3.2, 0.35, 1.8))
	hb("Turf", Vector3.new(5.0, 5.3, -6.6), Vector3.new(3.5, 0.35, 0.9))

	-- Rubble skirt: fills under the raised cheek and banks the buried side
	P(model, origin, "Cliff", Vector3.new(9.8, 1.6, -3.5), Vector3.new(4.2, 3.4, 5.5), 5, 20, 8)
	P(model, origin, "CliffDark", Vector3.new(10.0, 1.2, 3.5), Vector3.new(4.2, 2.6, 5.5), 0, -15, -6)
	P(model, origin, "Cliff", Vector3.new(-10.2, 2.2, -2.5), Vector3.new(4.4, 4.6, 7.0), 0, 10, 5)
	P(model, origin, "CliffDark", Vector3.new(-10.0, 1.4, 5.0), Vector3.new(3.4, 2.8, 4.2), 0, 35, 3)

	local function hc(p)
		return (CFrame.new(PIVOT) * TILT * CFrame.new(p)).Position
	end
	ART.proxy(model, origin, hc(Vector3.new(0, -0.5, 0)), Vector3.new(17.8, 5.5, 13.8), TILT)
	ART.proxy(model, origin, hc(Vector3.new(0, -5.9, -0.6)), Vector3.new(17.0, 5.2, 12.8), TILT)
	ART.proxy(model, origin, hc(Vector3.new(0, 6.3, 0)), Vector3.new(16.4, 8.0, 13.6), TILT)
	ART.proxy(model, origin, hc(Vector3.new(0, 0, -9.2)), Vector3.new(18.4, 8.4, 4.6), TILT)
end

----------------------------------------------------------------------
-- Ring shrine
----------------------------------------------------------------------
local function buildShrine(model, origin)
	local flat = CFrame.Angles(0, 0, PI / 2)
	local function disc(role, y, thick, diameter, shade)
		ART.prim(model, {
			role = role,
			shape = "Cylinder",
			size = Vector3.new(thick, diameter, diameter),
			cf = origin * CFrame.new(0, y, 0) * flat,
			color = shade and ART.shade(role, shade) or nil,
		})
	end
	disc("GateStoneDark", 0.5, 1.0, 20)
	disc("GateStone", 1.45, 1.1, 15.5)
	disc("GateStone", 2.45, 1.1, 11, 0.05)
	disc("GateStone", 3.85, 1.8, 3.8, 0.08)

	-- Inlay ring on the top step
	for i = 0, 11 do
		local a = i / 12 * PI * 2
		P(model, origin, "GateSeam", Vector3.new(math.cos(a) * 3.9, 3.04 + (i % 2) * 0.02, math.sin(a) * 3.9), Vector3.new(2.5, 0.1, 0.4), 0, math.deg(-a) + 90, 0)
	end

	-- Four tall, unequal, broken posts (stump front-left, tallest back-right)
	local heights = { 2.0, 8.0, 5.0, 10.0 }
	local k = 1
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local h = heights[k]
			local pos = Vector3.new(sx * 6.1, 0.9 + h / 2, sz * 6.1)
			P(model, origin, if k % 2 == 0 then "GateStone" else "GateStoneDark", pos, Vector3.new(2.2, h, 2.2), 0, k * 17, 0)
			W(model, origin, "GateStone", pos + Vector3.new(0, h / 2 + 0.5, 0), Vector3.new(2.2, 1.4, 2.2), 0, k * 70, 0)
			k += 1
		end
	end
	P(model, origin, "GateStoneDark", Vector3.new(3.5, 1.3, -8.0), Vector3.new(1.5, 1.4, 2.4), 3, 30, 5)

	-- The levitating ring: 16 across, tilted to face the viewer like a broken halo
	local rng = Random.new(7)
	local R = origin * CFrame.new(0, 14, 0) * CFrame.Angles(rad(-35), 0, rad(8))
	local lens = { 3.5, 5.4, 3.6, 4.8, 3.5, 3.9, 5.5, 3.5, 3.7 }
	local radial = { 2.2, 1.6, 2.0, 1.5, 2.2, 1.7, 1.9, 2.2, 1.6 }
	local vert = { 1.4, 1.8, 1.2, 1.6, 1.3, 1.7, 1.2, 1.5, 1.4 }
	local total = 0
	for _, l in lens do
		total += l
	end
	local gap = (PI * 2 * 7.0 - total) / #lens
	local arc = gap / 2
	for i = 1, #lens do
		local a = (arc + lens[i] / 2) / 7.0
		arc += lens[i] + gap
		local BF = R * CFrame.new(math.cos(a) * 7.0, 0, math.sin(a) * 7.0) * CFrame.Angles(0, -a, 0)
		BF = BF * CFrame.new(rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.15, 0.15), 0)
			* CFrame.Angles(rad(rng:NextNumber(-3, 3)), rad(rng:NextNumber(-3, 3)), rad(rng:NextNumber(-3, 3)))
		if i == 5 then
			BF = CFrame.new(0.5, -1.6, -0.5) * BF * CFrame.Angles(rad(12), rad(8), rad(24))
		elseif i == 8 then
			BF = CFrame.new(-0.4, -1.9, 0.3) * BF * CFrame.Angles(rad(-10), rad(-12), rad(-30))
		end
		ART.prim(model, {
			role = if i % 2 == 1 then "GateStone" else "GateStoneDark",
			size = Vector3.new(radial[i], vert[i], lens[i]),
			cf = BF,
			name = "RingPiece_" .. i,
		})
		if i % 2 == 1 then
			ART.prim(model, {
				role = "GateSeam",
				size = Vector3.new(0.2, math.min(vert[i] * 0.8, 1.2), 0.4),
				cf = BF * CFrame.new(-(radial[i] / 2 + 0.05), 0, 0),
				name = "RingSeam_" .. i,
			})
		end
	end

	ART.proxy(model, origin, Vector3.new(0, 0.5, 0), Vector3.new(1.0, 20, 20), flat).Shape = Enum.PartType.Cylinder
	ART.proxy(model, origin, Vector3.new(0, 1.45, 0), Vector3.new(1.1, 15.5, 15.5), flat).Shape = Enum.PartType.Cylinder
	ART.proxy(model, origin, Vector3.new(0, 2.45, 0), Vector3.new(1.1, 11, 11), flat).Shape = Enum.PartType.Cylinder
	ART.proxy(model, origin, Vector3.new(0, 3.85, 0), Vector3.new(1.8, 3.8, 3.8), flat).Shape = Enum.PartType.Cylinder
end

ART.run("LevelArt: POI monuments", function()
	ART.poi({
		name = "POI_Beacon",
		at = Vector3.new(524, ART.FLOOR_Y + 16, row.z),
		footprint = Vector3.new(18, 40, 18),
		placement = "outside",
		note = "watchtower on a floating islet; footprint excludes the 15-stud taper below the origin, so the model sits 16 raised",
		build = buildBeacon,
	})
	ART.poi({
		name = "POI_ColossusHead",
		at = Vector3.new(561, ART.FLOOR_Y, row.z),
		footprint = Vector3.new(22, 20, 24),
		placement = "outside",
		note = "fallen stone head",
		build = buildHead,
	})
	ART.poi({
		name = "POI_RingShrine",
		at = Vector3.new(598, ART.FLOOR_Y, row.z),
		footprint = Vector3.new(20, 22, 20),
		placement = "hub",
		note = "levitating ring altar",
		build = buildShrine,
	})
end)
return ART.report("Kit_POI")
