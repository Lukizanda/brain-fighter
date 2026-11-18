local ART = require(game.ServerStorage.LevelArtPrelude:Clone())
local KIT = "Kit_Rocks"
local row = ART.ROWS.Rocks

-- Rocks kit: breakable letter-stone cover / spires / gates and permanent bedrock cores.
-- All coordinates are in the local space of the greybox (origin = footprint centre at
-- floor level). Wedge convention: the vertical wall is on local +Z, the slope faces -Z
-- (yaw 90 puts the wall on +X and the slope facing -X; yaw -90 the opposite; yaw 180
-- puts the wall on -Z).

local SINK = 1
local GAP = 14 -- air between assets
local PAIR_GAP = 6 -- Core_A beside Cover_Low_A

-- Part helper: position and rotation (degrees) are local to the asset origin.
local function pr(parent, origin, role, shape, name, size, pos, rot, shadeDelta)
	rot = rot or Vector3.zero
	return ART.prim(parent, {
		role = role,
		shape = shape,
		name = name,
		size = size,
		cf = origin * CFrame.new(pos) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z)),
		color = if shadeDelta and shadeDelta ~= 0 then ART.shade(role, shadeDelta) else nil,
	})
end

-- Deco_<n> adder bound to a body.
local function decoAdder(body, origin)
	local n = 0
	return function(role, shape, size, pos, rot, d)
		n += 1
		return pr(body, origin, role, shape, "Deco_" .. n, size, pos, rot, d)
	end
end

----------------------------------------------------------------------
-- Low cover: a small yawed off-centre cap, a plinth below the glyph square, a
-- sloping wedge shoulder on each end (different heights), two end bands of
-- different lengths and corner rubble. 8 children.
----------------------------------------------------------------------
local function coverBuild(W, H, D, seed, cfg)
	return function(body, origin)
		local rng = Random.new(seed)
		local sq = 0.35 * math.min(W, H) -- half side of the glyph square
		local midY = H / 2 - SINK
		local top = H - SINK
		local deco = decoAdder(body, origin)
		-- small off-centre weathered cap
		deco(
			"LetterstoneLight",
			"Block",
			Vector3.new(W * 0.6, 0.55, D - 2.4),
			Vector3.new(cfg.capSide * W * 0.12 + rng:NextNumber(-0.2, 0.2), top + 0.15, rng:NextNumber(-0.2, 0.2)),
			Vector3.new(0, cfg.capYaw, rng:NextNumber(-1.0, 1.0)),
			0.02
		)
		-- plinth, stopping under the glyph square
		local plinthTop = midY - sq - 0.05
		deco(
			"LetterstoneDark",
			"Block",
			Vector3.new(W + 0.5, plinthTop + SINK + 0.1, D + 0.5),
			Vector3.new(0, (plinthTop - SINK - 0.1) / 2, 0),
			nil,
			rng:NextNumber(-0.03, 0.03)
		)
		-- sloping shoulders: wall just inside the end face, slope facing outward
		for _, side in { -1, 1 } do
			local h = if side < 0 then cfg.hl else cfg.hr
			deco(
				"Letterstone",
				"Wedge",
				Vector3.new(D - 0.8, h, 1.2),
				Vector3.new(side * (W / 2 + 0.4), -1.1 + h / 2, 0),
				Vector3.new(0, 90 * -side, 0),
				rng:NextNumber(-0.04, 0.04)
			)
		end
		-- two strata bands on the ends, of different lengths
		local bandW = W / 2 - sq - 0.4
		for _, b in cfg.bands do
			local w = bandW * b.k
			deco(
				b.role,
				"Block",
				Vector3.new(w + 0.2, b.h, D + 0.4),
				Vector3.new(b.side * (W / 2 - w / 2 + 0.1), -SINK + b.frac * H, 0),
				nil,
				rng:NextNumber(-0.04, 0.04)
			)
		end
		-- corner rubble
		for _, r in cfg.rubble do
			deco(
				"LetterstoneDark",
				"Block",
				r.size,
				Vector3.new(r.x, r.size.Y / 2 - 0.25, r.z),
				Vector3.new(0, r.yaw, r.tilt or 0),
				rng:NextNumber(-0.04, 0.02)
			)
		end
	end
end

local function cover(name, at, W, H, D, seed, cfg, note)
	return ART.breakable({
		kit = KIT,
		name = name,
		at = at,
		size = Vector3.new(W, H, D),
		sink = SINK,
		bodyRole = "Letterstone",
		class = "Cover",
		note = note,
		build = coverBuild(W, H, D, seed, cfg),
	})
end

local CFG_A = { -- high shoulder on the left
	capSide = 1,
	capYaw = 8,
	hl = 4.4,
	hr = 2.4,
	bands = {
		{ side = -1, frac = 0.62, h = 0.9, role = "LetterstoneLight", k = 1.0 },
		{ side = 1, frac = 0.34, h = 0.8, role = "LetterstoneDark", k = 0.6 },
	},
	rubble = {
		{ x = -4.8, z = -4.15, size = Vector3.new(2.0, 1.5, 1.8), yaw = 30, tilt = 4 },
		{ x = 5.6, z = 4.1, size = Vector3.new(1.8, 1.2, 1.6), yaw = -35, tilt = -5 },
	},
}
local CFG_B = { -- high shoulder on the right
	capSide = -1,
	capYaw = -7,
	hl = 2.6,
	hr = 4.2,
	bands = {
		{ side = 1, frac = 0.55, h = 0.9, role = "LetterstoneDark", k = 1.0 },
		{ side = -1, frac = 0.30, h = 0.8, role = "LetterstoneLight", k = 0.55 },
	},
	rubble = {
		{ x = 7.5, z = -3.9, size = Vector3.new(2.2, 1.6, 1.8), yaw = -25, tilt = 5 },
		{ x = -6.5, z = 3.9, size = Vector3.new(1.6, 1.1, 1.4), yaw = 40, tilt = -4 },
	},
}
local CFG_C = { -- high shoulder on the left
	capSide = 1,
	capYaw = 10,
	hl = 4.0,
	hr = 2.4,
	bands = {
		{ side = -1, frac = 0.62, h = 0.9, role = "LetterstoneLight", k = 1.0 },
		{ side = 1, frac = 0.38, h = 0.8, role = "LetterstoneDark", k = 0.55 },
	},
	rubble = {
		{ x = 4.2, z = -3.4, size = Vector3.new(1.8, 1.4, 1.6), yaw = 20, tilt = 5 },
		{ x = -4.0, z = 3.4, size = Vector3.new(1.7, 1.2, 1.5), yaw = -30, tilt = -4 },
	},
}

----------------------------------------------------------------------
-- Tall cover and spire: a broken two-wedge summit, diagonal strata slabs on the
-- upper / lower thirds, one leaning buttress at the base, one rubble block.
----------------------------------------------------------------------
-- cfg: peakA / peakB wedge heights, strata = { {x, y, len, tiltDeg, role}, ... },
-- buttressH, rubbleZ
local function monolithBuild(W, H, D, cfg)
	return function(body, origin)
		local deco = decoAdder(body, origin)
		local top = H - SINK
		-- broken summit: tall wedge leaning toward +X, shorter one pointing back
		deco(
			"LetterstoneLight",
			"Wedge",
			Vector3.new(D - 1.0, cfg.peakA, W * 0.55),
			Vector3.new(W * 0.2, top - 0.2 + cfg.peakA / 2, 0),
			Vector3.new(0, 90, 0),
			0.05
		)
		deco(
			"Letterstone",
			"Wedge",
			Vector3.new(D * 0.6, cfg.peakB, W * 0.45),
			Vector3.new(-W * 0.22, top - 0.2 + cfg.peakB / 2, 0.4),
			Vector3.new(0, -90, 0),
			0.02
		)
		-- diagonal strata, through the depth so they show on the ends and both faces
		for _, s in cfg.strata do
			deco(
				s.role,
				"Block",
				Vector3.new(s.len, 1.1, D + 0.5),
				Vector3.new(s.x, s.y, 0),
				Vector3.new(0, 0, s.tilt),
				if s.role == "LetterstoneDark" then -0.03 else 0.03
			)
		end
		-- leaning buttress on the -X side, tipped in toward the body
		deco(
			"LetterstoneDark",
			"Block",
			Vector3.new(2.4, cfg.buttressH, D - 3.0),
			Vector3.new(-W / 2 + 1.2, -1 + cfg.buttressH / 2, 0.4),
			Vector3.new(0, 0, -7),
			-0.02
		)
		-- rubble on the other side
		deco(
			"LetterstoneDark",
			"Block",
			Vector3.new(2.2, 1.8, 2.0),
			Vector3.new(W / 2 - 0.5, 0.65, -1.5),
			Vector3.new(0, 20, -4),
			-0.04
		)
	end
end

local TALL_CFG = {
	peakA = 2.2,
	peakB = 1.4,
	buttressH = 9,
	strata = {
		{ x = 3.9, y = 1.8, len = 4.5, tilt = 10, role = "LetterstoneLight" },
		{ x = -3.5, y = 14.4, len = 5.0, tilt = -9, role = "LetterstoneDark" },
	},
}
local SPIRE_CFG = {
	peakA = 2.9,
	peakB = 1.6,
	buttressH = 12,
	strata = {
		{ x = 4.0, y = 6.0, len = 6.0, tilt = 12, role = "LetterstoneLight" },
		{ x = -3.5, y = 10.5, len = 5.0, tilt = -9, role = "LetterstoneDark" },
		{ x = 3.8, y = 29.0, len = 6.0, tilt = 10, role = "LetterstoneLight" },
	},
}

----------------------------------------------------------------------
-- Gates: cut pale stone, dark pilasters, a keystone lintel, and a few light leaks
-- from the joints (0.2 wide, open frame: the bottom stays dark).
----------------------------------------------------------------------
-- Ridge gate: local X is the 4 thick axis, broad faces face +-X.
local function gateRidgeBuild(body, origin)
	local deco0 = decoAdder(body, origin)
	local function deco(role, size, pos, shape, rot, d)
		return deco0(role, shape, size, pos, rot, d)
	end
	local s = 0
	local function seam(size, pos)
		s += 1
		return pr(body, origin, "GateSeam", "Block", "Seam_" .. s, size, pos)
	end
	deco("GateStoneDark", Vector3.new(5.0, 17.6, 2.6), Vector3.new(0, 9.0, -8.8), "Block", nil, 0)
	deco("GateStoneDark", Vector3.new(5.0, 17.6, 2.6), Vector3.new(0, 9.0, 8.8), "Block", nil, 0)
	deco("GateStone", Vector3.new(5.4, 2.0, 20.8), Vector3.new(0, 18.0, 0), "Block", nil, 0.04)
	deco("GateStone", Vector3.new(5.6, 3.4, 5.0), Vector3.new(0, 18.2, 0), "Block", nil, 0.08)
	deco("GateStoneDark", Vector3.new(5.0, 1.6, 20.6), Vector3.new(0, 0.7, 0), "Block", nil, -0.02)
	-- joints: two vertical seams of unequal length, one short seam under the lintel
	seam(Vector3.new(4.4, 14.2, 0.2), Vector3.new(0, 8.9, -7.3))
	seam(Vector3.new(4.4, 9.0, 0.2), Vector3.new(0, 11.7, 7.3))
	seam(Vector3.new(4.4, 0.2, 6.0), Vector3.new(0, 16.25, -2.0))
end

-- Cave plug: same language, broad faces face +-Z.
local function cavePlugBuild(body, origin)
	local deco0 = decoAdder(body, origin)
	local function deco(role, size, pos, shape, rot, d)
		return deco0(role, shape, size, pos, rot, d)
	end
	local s = 0
	local function seam(size, pos)
		s += 1
		return pr(body, origin, "GateSeam", "Block", "Seam_" .. s, size, pos)
	end
	deco("GateStoneDark", Vector3.new(2.6, 13.4, 4.0), Vector3.new(-7.0, 7.0, 0), "Block", nil, 0)
	deco("GateStoneDark", Vector3.new(2.6, 13.4, 4.0), Vector3.new(7.0, 7.0, 0), "Block", nil, 0)
	deco("GateStone", Vector3.new(17.6, 1.6, 4.0), Vector3.new(0, 13.8, 0), "Block", nil, 0.04)
	deco("GateStone", Vector3.new(4.6, 3.0, 4.4), Vector3.new(0, 14.1, 0), "Block", nil, 0.08)
	deco("GateStoneDark", Vector3.new(17.4, 1.0, 4.0), Vector3.new(0, 0.4, 0), "Block", nil, -0.02)
	seam(Vector3.new(0.2, 11.4, 3.4), Vector3.new(-5.4, 6.9, 0))
	seam(Vector3.new(0.2, 8.0, 3.4), Vector3.new(5.4, 8.6, 0))
	seam(Vector3.new(6.0, 0.2, 3.4), Vector3.new(-1.0, 12.35, 0))
end

----------------------------------------------------------------------
-- Cores: cold faceted basalt, tilted plates and sharp wedges, no bands.
----------------------------------------------------------------------
local function coreBuildA(model, origin)
	local P = function(role, shape, name, size, pos, rot, d)
		return pr(model, origin, role, shape, name, size, pos, rot, d)
	end
	P("Bedrock", "Block", "Base", Vector3.new(19.4, 4.6, 9.4), Vector3.new(0, 1.3, 0))
	P("BedrockLight", "Block", "PlateL", Vector3.new(11.0, 2.8, 8.8), Vector3.new(-4.3, 4.3, 0.1), Vector3.new(0, 3, 5))
	P("Bedrock", "Block", "PlateR", Vector3.new(10.2, 2.6, 9.0), Vector3.new(5.0, 4.0, -0.1), Vector3.new(0, -4, -7), 0.04)
	P("Bedrock", "Wedge", "FrontL", Vector3.new(8, 3.0, 2.2), Vector3.new(-4.8, 0.5, -4.6), nil, -0.04)
	P("Bedrock", "Wedge", "FrontR", Vector3.new(6, 2.2, 1.8), Vector3.new(5.4, 0.1, -4.6), nil, -0.06)
	P("BedrockLight", "Wedge", "EndL", Vector3.new(7, 2.8, 2.4), Vector3.new(-8.9, 0.4, 0.5), Vector3.new(0, 90, 0), -0.02)
	P("Bedrock", "Wedge", "EndR", Vector3.new(6, 2.4, 2.2), Vector3.new(8.8, 0.2, -0.5), Vector3.new(0, -90, 0), -0.03)
	P("BedrockLight", "Block", "Crown", Vector3.new(4.8, 1.5, 3.8), Vector3.new(0.8, 5.0, 0.2), Vector3.new(8, 25, -6), 0.03)
	P("Bedrock", "Block", "Split", Vector3.new(0.5, 4.6, 9.6), Vector3.new(-0.2, 3.0, 0), Vector3.new(0, 0, 12), -0.06)
	P("Bedrock", "Block", "RubbleA", Vector3.new(2.4, 1.5, 2.0), Vector3.new(-6.5, -0.1, -4.7), Vector3.new(0, 28, 6), -0.05)
	P("Bedrock", "Block", "RubbleB", Vector3.new(2.2, 1.2, 1.8), Vector3.new(6.8, -0.2, 4.6), Vector3.new(0, -35, -5), -0.02)
end

local function coreBuildB(model, origin)
	local P = function(role, shape, name, size, pos, rot, d)
		return pr(model, origin, role, shape, name, size, pos, rot, d)
	end
	P("Bedrock", "Block", "Base", Vector3.new(13.4, 4.2, 9.4), Vector3.new(0, 1.1, 0))
	P("BedrockLight", "Block", "PlateL", Vector3.new(8.2, 2.4, 8.8), Vector3.new(-3.3, 3.9, 0), Vector3.new(0, -4, 6))
	P("Bedrock", "Block", "PlateR", Vector3.new(7.6, 2.2, 9.0), Vector3.new(3.5, 3.6, 0.1), Vector3.new(0, 5, -8), 0.04)
	P("Bedrock", "Wedge", "Front", Vector3.new(7, 2.8, 2.2), Vector3.new(-1.5, 0.4, -4.6), nil, -0.04)
	P("BedrockLight", "Wedge", "EndL", Vector3.new(6, 2.6, 2.2), Vector3.new(-6.1, 0.3, 0), Vector3.new(0, 90, 0), -0.02)
	P("Bedrock", "Wedge", "EndR", Vector3.new(5, 2.2, 2.0), Vector3.new(6.0, 0.0, 0.8), Vector3.new(0, -90, 0), -0.03)
	P("BedrockLight", "Block", "Crown", Vector3.new(4.2, 1.3, 3.4), Vector3.new(-0.5, 4.6, -0.3), Vector3.new(-9, -20, 7), 0.03)
	P("Bedrock", "Block", "Split", Vector3.new(0.45, 4.0, 9.6), Vector3.new(0.1, 2.7, 0), Vector3.new(0, 0, -10), -0.06)
	P("Bedrock", "Block", "Rubble", Vector3.new(2.2, 1.4, 1.8), Vector3.new(5.2, -0.2, -4.6), Vector3.new(0, 30, 5), -0.05)
	P("Bedrock", "Wedge", "Back", Vector3.new(5, 2.0, 1.8), Vector3.new(2.5, 0, 4.6), Vector3.new(0, 180, 0), -0.03)
end

local function core(name, at, size, build, note)
	return ART.asset({
		kit = KIT,
		name = name,
		at = at,
		greybox = size,
		refOffset = Vector3.new(0, size.Y / 2 - SINK, 0),
		class = "Core",
		note = note,
		build = build,
	})
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
ART.run("LevelArt: rocks kit", function()
	local cursor = row.xMin + 12
	local function slot(width, gap)
		local x = cursor + width / 2
		cursor = cursor + width + (gap or GAP)
		return Vector3.new(x, ART.FLOOR_Y, row.z)
	end

	-- Hero cover, with Core_A six studs beside it
	cover("Cover_Low_A", slot(16, PAIR_GAP), 16, 7, 9, 101, CFG_A, "hero cover; permanent core beside it")
	core("Core_A", slot(20), Vector3.new(20, 7, 10), coreBuildA, "bedrock: never breaks")

	-- Damage states of the hero build
	local cracked = cover("Cover_Low_A_Cracked", slot(16), 16, 7, 9, 101, CFG_A, "damage tint 0.30")
	ART.damage(cracked, 0.30, 0)
	ART.glyph(cracked.Body, "R", "red")
	local critical = cover("Cover_Low_A_Critical", slot(16), 16, 7, 9, 101, CFG_A, "tint 0.60, transparency 0.15")
	ART.damage(critical, 0.60, 0.15)
	ART.glyph(critical.Body, "K", "blue")
	local ghost = cover("Cover_Low_A_Ghost", slot(16), 16, 7, 9, 101, CFG_A, "regen ghost, transparency 0.82")
	ART.damage(ghost, 0, 0.82)

	-- Variants
	cover("Cover_Low_B", slot(22), 22, 6.5, 8.5, 202, CFG_B, "long low variant")
	cover("Cover_Low_C", slot(11), 11, 7, 8.5, 303, CFG_C, "short stubby variant")
	core("Core_B", slot(14), Vector3.new(14, 6.5, 10), coreBuildB, "bedrock, smaller")

	-- Tall cover
	ART.breakable({
		kit = KIT,
		name = "Cover_Tall",
		at = slot(12.5),
		size = Vector3.new(12.5, 17.5, 10.5),
		sink = SINK,
		bodyRole = "Letterstone",
		class = "Cover",
		note = "not climbable",
		build = monolithBuild(12.5, 17.5, 10.5, TALL_CFG),
	})

	-- Spires
	local function spire(name, note)
		return ART.breakable({
			kit = KIT,
			name = name,
			at = slot(14),
			size = Vector3.new(14, 40, 9.5),
			sink = SINK,
			bodyRole = "Letterstone",
			class = "Cover",
			note = note,
			build = monolithBuild(14, 40, 9.5, SPIRE_CFG),
		})
	end
	spire("Spire_A", "leaning letter-stone obelisk")
	local sc = spire("Spire_A_Cracked", "wild gold glyph test")
	ART.glyph(sc.Body, "★", "wild")

	-- Gates (the ridge gate is turned so its broad faces face -Z)
	ART.breakable({
		kit = KIT,
		name = "Gate_Ridge",
		at = slot(20),
		yaw = 90,
		size = Vector3.new(4, 18, 20),
		bodyRole = "GateStone",
		class = "Gate",
		note = "regenerating ridge gate, 14x14 carving field",
		build = gateRidgeBuild,
	})
	ART.breakable({
		kit = KIT,
		name = "Gate_CavePlug",
		at = slot(17),
		size = Vector3.new(17, 14, 3),
		bodyRole = "GateStone",
		class = "Gate",
		note = "cave plug, 10x10 carving field",
		build = cavePlugBuild,
	})
end)
return ART.report(KIT)
