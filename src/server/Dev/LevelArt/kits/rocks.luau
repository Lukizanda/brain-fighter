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
local CRACK_W = 0.45 -- a fissure strip across a low cover's face
local FLUTE_W = 1.9 -- a pilaster on a monolith's end; it sticks out 0.9
local LANE2_DZ = 30 -- the second showcase lane, behind the first (signs need the room)

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
-- Low cover: weathered caps, a plinth below the glyph square, a sloping wedge
-- shoulder on the ends (different heights), end bands of different lengths, an
-- optional fissure and corner rubble. At most 8 children.
-- cfg: caps?, hl / hr (shoulder heights, 0 = none), bands, cracks?, rubble
----------------------------------------------------------------------
local function coverBuild(W, H, D, seed, cfg)
	return function(body, origin)
		local rng = Random.new(seed)
		local sq = 0.35 * math.min(W, H) -- half side of the glyph square
		local midY = H / 2 - SINK
		local top = H - SINK
		local deco = decoAdder(body, origin)
		-- caps: x and w are fractions of W, dy is the centre over the top, inset is
		-- how far the cap stops short of D. The default is the hero build's small
		-- yawed off-centre cap.
		local caps = cfg.caps
			or {
				{
					role = "LetterstoneLight",
					w = 0.6,
					t = 0.55,
					inset = 2.4,
					x = cfg.capSide * 0.12,
					dy = 0.15,
					yaw = cfg.capYaw,
				},
			}
		for _, c in caps do
			local jx, jz, jt = rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.2, 0.2), rng:NextNumber(-1.0, 1.0)
			deco(
				c.role,
				"Block",
				Vector3.new(W * c.w, c.t, D - c.inset),
				Vector3.new(c.x * W + jx, top + c.dy, jz),
				Vector3.new(0, c.yaw, c.tilt or jt),
				0.02
			)
		end
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
			local d = rng:NextNumber(-0.04, 0.04)
			if h > 0 then
				deco(
					"Letterstone",
					"Wedge",
					Vector3.new(D - 0.8, h, 1.2),
					Vector3.new(side * (W / 2 + 0.4), -1.1 + h / 2, 0),
					Vector3.new(0, 90 * -side, 0),
					d
				)
			end
		end
		-- strata bands on the ends, of different lengths
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
		-- a leaning fissure across the face, outside the glyph square
		for _, k in cfg.cracks or {} do
			deco(
				"LetterstoneDark",
				"Block",
				Vector3.new(CRACK_W, k.h, D + 0.4),
				Vector3.new(k.x * W, k.y0 + k.h / 2, 0),
				Vector3.new(0, 0, k.tilt),
				-0.05
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
local CFG_D = { -- deep chunk: split crown, one fissure, high shoulder on the left
	caps = {
		{ role = "LetterstoneLight", w = 0.5, t = 0.5, inset = 2.2, x = 0.14, dy = 0.1, yaw = -12 },
		{ role = "Letterstone", w = 0.3, t = 0.9, inset = 1.2, x = -0.3, dy = 0.05, yaw = 6, tilt = 0 },
	},
	hl = 3.8,
	hr = 2.2,
	bands = {
		{ side = 1, frac = 0.45, h = 0.9, role = "LetterstoneDark", k = 0.8 },
	},
	cracks = { { x = 0.34, h = 4.8, y0 = -0.5, tilt = 10 } },
	rubble = {
		{ x = -5.0, z = -4.8, size = Vector3.new(2.2, 1.6, 2.0), yaw = 25, tilt = 4 },
	},
}
local CFG_E = { -- stepped slab: three loose caps at different heights, one ramp end
	caps = {
		{ role = "LetterstoneLight", w = 0.38, t = 0.5, inset = 1.6, x = -0.27, dy = 0.2, yaw = 5 },
		{ role = "Letterstone", w = 0.3, t = 0.4, inset = 2.4, x = 0.3, dy = 0.15, yaw = -8 },
		{ role = "LetterstoneLight", w = 0.17, t = 0.8, inset = 5.0, x = 0.02, dy = 0.1, yaw = 22 },
	},
	hl = 3.4,
	hr = 0,
	bands = {
		{ side = 1, frac = 0.4, h = 0.8, role = "LetterstoneDark", k = 0.55 },
		{ side = -1, frac = 0.62, h = 0.9, role = "LetterstoneLight", k = 1.0 },
	},
	rubble = {
		{ x = 7.0, z = -3.9, size = Vector3.new(2.0, 1.4, 1.8), yaw = -30, tilt = 5 },
	},
}
local CFG_F = { -- small leaning slab with a long ramp on one end
	caps = {
		{ role = "LetterstoneLight", w = 0.76, t = 0.8, inset = 1.2, x = 0.04, dy = -0.25, yaw = 12, tilt = -5 },
	},
	hl = 5.0,
	hr = 2.0,
	bands = {
		{ side = 1, frac = 0.7, h = 0.8, role = "LetterstoneLight", k = 1.0 },
		{ side = -1, frac = 0.25, h = 0.8, role = "LetterstoneDark", k = 0.8 },
	},
	rubble = {
		{ x = -3.9, z = -4.0, size = Vector3.new(1.9, 1.4, 1.7), yaw = 30, tilt = 4 },
		{ x = 4.0, z = 3.9, size = Vector3.new(1.7, 1.1, 1.5), yaw = -35, tilt = -5 },
	},
}

----------------------------------------------------------------------
-- Tall cover and spire. The box is the silhouette, so every piece works on it:
-- a crown (gable, twin horns or a slipped capstone, at most +2 over the top), two
-- full-height pilasters on the ends that flare the outline by 0.9 each side and
-- break the face into vertical bands, strata that tilt across the thirds the glyph
-- square leaves free, and a leaning buttress or a rubble block at the base.
-- cfg: crown, crownH = { a, b }, flutes = { {side, role, h} }, strata = { {x, y, len,
-- tilt, role} }, buttress = { side, h }?, rubble = true?
-- Above +12 (UPPER_Y) the ruling lets the upper mass reach 3 studs out and +3 over
-- the top: `upper` pieces are built to that, with their lowest point at 12 or more,
-- and keep clear of the glyph square. At most ART.MAX_WALL_CHILDREN children.
----------------------------------------------------------------------
local function monolithBuild(W, H, D, cfg)
	return function(body, origin)
		local deco = decoAdder(body, origin)
		local top = H - SINK
		local a, b = cfg.crownH[1], cfg.crownH[2]
		-- the upper mass: pieces that start above +12 and may reach 3 studs out and
		-- +3 over the top ({ role, shape, size, pos, rot, shade }, asset space)
		for _, u in cfg.upper or {} do
			deco(u[1], u[2], u[3], u[4], u[5], u[6])
		end
		if cfg.crown == "none" then
			-- the upper mass is the crown
		elseif cfg.crown == "gable" then
			-- two wedges rising to a ridge in the middle, one taller than the other
			deco(
				"LetterstoneLight",
				"Wedge",
				Vector3.new(D - 1.0, a, W * 0.32),
				Vector3.new(-W * 0.16, top - 0.2 + a / 2, 0.2),
				Vector3.new(0, 90, 0),
				0.05
			)
			deco(
				"Letterstone",
				"Wedge",
				Vector3.new(D - 1.6, b, W * 0.3),
				Vector3.new(W * 0.15, top - 0.2 + b / 2, -0.2),
				Vector3.new(0, -90, 0),
				0.02
			)
		elseif cfg.crown == "horns" then
			-- two horns on the ends with a cleft between them
			deco(
				"LetterstoneLight",
				"Wedge",
				Vector3.new(D - 1.0, a, W * 0.42),
				Vector3.new(-W * 0.27, top - 0.2 + a / 2, 0.2),
				Vector3.new(0, -90, 0),
				0.05
			)
			deco(
				"Letterstone",
				"Wedge",
				Vector3.new(D - 1.4, b, W * 0.38),
				Vector3.new(W * 0.29, top - 0.2 + b / 2, -0.2),
				Vector3.new(0, 90, 0),
				0.02
			)
		else
			-- a capstone slipped to one side, and a chip on the low end
			deco(
				"LetterstoneLight",
				"Block",
				Vector3.new(W * 0.8, a, D - 0.8),
				Vector3.new(W * 0.04, top + 0.3, 0.2),
				Vector3.new(0, 4, 9),
				0.05
			)
			deco(
				"Letterstone",
				"Block",
				Vector3.new(2.4, b, 2.2),
				Vector3.new(-W * 0.3, top + b / 2 - 0.4, -1.0),
				Vector3.new(0, 25, 0),
				0.02
			)
		end
		for _, f in cfg.flutes do
			deco(
				f.role,
				"Block",
				Vector3.new(FLUTE_W, f.h, D + 0.8),
				Vector3.new(f.side * (W / 2 - 0.05), -SINK + f.h / 2, 0),
				nil,
				if f.role == "LetterstoneDark" then -0.02 else 0.03
			)
		end
		-- diagonal strata, through the depth so they show on the ends and both faces
		for _, s in cfg.strata do
			deco(
				s.role,
				"Block",
				Vector3.new(s.len, 1.0, D + 0.6),
				Vector3.new(s.x, s.y, 0),
				Vector3.new(0, 0, s.tilt),
				if s.role == "LetterstoneDark" then -0.03 else 0.03
			)
		end
		if cfg.buttress then
			-- leaning buttress, tipped in toward the body
			local bt = cfg.buttress
			deco(
				"LetterstoneDark",
				"Block",
				Vector3.new(2.4, bt.h, D - 3.0),
				Vector3.new(bt.side * (W / 2 - 1.2), -1 + bt.h / 2, 0.4),
				Vector3.new(0, 0, 7 * bt.side),
				-0.02
			)
		end
		if cfg.rubble then
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
end

local DARK, LIGHT = "LetterstoneDark", "LetterstoneLight"

local V = Vector3.new
local LS = "Letterstone"

-- Each of the five has its own outline. Upper pieces: { role, shape, size, pos, rot, shade }.
local TALL_A = { -- capstone sliding toward +X, a shoulder under it, one horn on the left
	crown = "none",
	crownH = { 0, 0 },
	flutes = { { side = -1, role = DARK, h = 11 }, { side = 1, role = LIGHT, h = 7.5 } },
	strata = { { x = -2.5, y = 1.4, len = 7.0, tilt = -7, role = DARK } },
	buttress = { side = -1, h = 8 },
	rubble = true,
	upper = {
		{ LIGHT, "Block", V(9, 3.5, 8.5), V(2, 17.1, 0), V(0, 5, 9), 0.05 },
		{ LS, "Block", V(3.4, 3.5, 6), V(7.5, 14, 0), nil, 0.02 },
		{ LS, "Wedge", V(8, 3.0, 4), V(-4.2, 17.8, 0), V(0, -90, 0), 0.03 },
		{ DARK, "Block", V(2.6, 3, 5), V(-7.4, 14.8, 0), V(0, 0, 6), -0.03 },
	},
}
local TALL_B = { -- capstone sliding the other way, a leaning chip on the right, a spike
	crown = "none",
	crownH = { 0, 0 },
	flutes = { { side = -1, role = LIGHT, h = 9 }, { side = 1, role = DARK, h = 12.5 } },
	strata = { { x = -1.0, y = 1.2, len = 9.0, tilt = 5, role = DARK } },
	buttress = { side = 1, h = 7 },
	rubble = true,
	upper = {
		{ LIGHT, "Block", V(9.5, 3.3, 8.4), V(-1.8, 17.1, 0), V(0, -6, -9), 0.05 },
		{ LS, "Block", V(3.2, 4, 6.5), V(-7.4, 14.3, 0), nil, 0.02 },
		{ LS, "Wedge", V(7.0, 3.0, 4.5), V(3.8, 17.8, 0), V(0, 90, 0), 0.03 },
		{ LIGHT, "Block", V(2.6, 3.4, 4.5), V(7.3, 14.5, 0), V(0, 0, -8), 0.03 },
	},
}
local SPIRE_A = { -- the upper third leans out over +X on a broken shoulder
	crown = "none",
	crownH = { 0, 0 },
	flutes = { { side = -1, role = DARK, h = 24 }, { side = 1, role = LIGHT, h = 15 } },
	strata = {
		{ x = 4.0, y = 6.0, len = 6.0, tilt = 12, role = LIGHT },
		{ x = -3.5, y = 9.5, len = 5.0, tilt = -9, role = DARK },
	},
	rubble = true,
	upper = {
		{ LS, "Block", V(13, 9, 9), V(2.5, 33.5, 0), V(0, 0, -8), 0.04 },
		{ DARK, "Block", V(3, 2.2, 6), V(8.2, 26, 0), V(0, 0, -12), -0.03 },
		{ LIGHT, "Wedge", V(7, 3.4, 6), V(4, 40.2, 0), V(0, 90, 0), 0.05 },
		{ LS, "Block", V(2.6, 2.4, 3), V(-4.8, 40, 0.5), V(0, 20, 10), 0.02 },
		{ DARK, "Block", V(2.8, 4, 6), V(-8.2, 20, 0), nil, -0.04 },
	},
}
local SPIRE_B = { -- twin horns of different heights, shelves jutting from both ends
	crown = "none",
	crownH = { 0, 0 },
	flutes = { { side = -1, role = DARK, h = 31 }, { side = 1, role = DARK, h = 20 } },
	strata = {
		{ x = 0.0, y = 7.5, len = 13.0, tilt = 4, role = LIGHT },
		{ x = 1.0, y = 30.5, len = 12.5, tilt = -5, role = DARK },
	},
	rubble = true,
	upper = {
		{ LIGHT, "Wedge", V(7.5, 6, 5.5), V(-3.5, 43, 0), V(0, -90, 0), 0.05 },
		{ LS, "Wedge", V(6, 3.2, 5), V(4, 43.1, 0), V(0, 90, 0), 0.02 },
		{ LS, "Block", V(4.2, 2.4, 6.5), V(7.7, 33, 0), V(0, 0, 8), 0.03 },
		{ LIGHT, "Block", V(3, 7, 6.5), V(-8, 31, 0), V(0, 0, 6), 0.04 },
		{ DARK, "Block", V(2.4, 3.2, 4.4), V(8, 21, 0), nil, -0.04 },
	},
}
local SPIRE_C = { -- a capstone slipped off to one side, a notch below it, a shoulder on the left
	crown = "none",
	crownH = { 0, 0 },
	flutes = { { side = 1, role = LIGHT, h = 26 }, { side = -1, role = DARK, h = 12 } },
	strata = { { x = -2.0, y = 8.0, len = 9.0, tilt = -6, role = DARK } },
	buttress = { side = 1, h = 11 },
	upper = {
		{ LIGHT, "Block", V(11, 4, 9), V(3, 35, 0), V(0, 6, 10), 0.05 },
		{ LS, "Block", V(4, 6, 6), V(-7.4, 27, 0), V(0, 0, -9), 0.02 },
		{ DARK, "Block", V(3, 3, 5), V(7.8, 30.5, 0), V(0, 0, -14), -0.03 },
		{ LS, "Block", V(3, 2.5, 3.5), V(-3.8, 36.5, 0.4), V(0, 20, -6), 0.02 },
		{ LIGHT, "Block", V(3.6, 3, 6), V(7.6, 25.5, 0), V(0, 0, 5), 0.03 },
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

-- Basalt columns: two rows of four upright prisms with their own tops, a few
-- stones' worth of difference in height (all within the greybox top +0.5 / -1)
-- and two fallen columns in front. Reads as a different rock from the plated
-- cores, and is the one that says "volcanic, cold, permanent".
local COLUMN_FOOT = -1.2 -- column bottoms, below the floor
local COLUMNS = {
	-- { x, z, width, depth, top, yaw, tilt, role, shade }
	{ -6.6, 2.6, 4.2, 4.6, 5.7, 8, 2, "Bedrock", 0.02 },
	{ -2.3, 2.5, 4.4, 4.4, 6.9, -12, -2, "BedrockLight", 0.0 },
	{ 2.1, 2.7, 4.2, 4.6, 6.2, 14, 3, "Bedrock", -0.02 },
	{ 6.5, 2.6, 4.4, 4.4, 5.8, -6, -3, "BedrockLight", -0.04 },
	{ -6.2, -2.6, 4.4, 4.2, 6.3, -10, 3, "BedrockLight", -0.02 },
	{ -2.0, -2.5, 4.2, 4.4, 6.0, 9, -2, "Bedrock", -0.04 },
	{ 2.4, -2.7, 4.4, 4.2, 6.7, -14, 2, "Bedrock", 0.03 },
	{ 6.6, -2.6, 4.2, 4.4, 5.6, 7, -3, "BedrockLight", -0.03 },
}
local function coreBuildC(model, origin)
	for i, c in COLUMNS do
		local top = c[5]
		pr(
			model,
			origin,
			c[8],
			"Block",
			"Column_" .. i,
			Vector3.new(c[3], top - COLUMN_FOOT, c[4]),
			Vector3.new(c[1], (top + COLUMN_FOOT) / 2, c[2]),
			Vector3.new(0, c[6], c[7]),
			c[9]
		)
	end
	pr(model, origin, "Bedrock", "Block", "FallenA", Vector3.new(5.5, 1.3, 1.3), Vector3.new(-3.5, 0.35, -5.0), Vector3.new(0, 8, 0), -0.05)
	pr(model, origin, "BedrockLight", "Block", "FallenB", Vector3.new(3.8, 1.1, 1.1), Vector3.new(5.5, 0.2, -5.2), Vector3.new(0, -20, 0), -0.05)
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
-- Layout: lane 1 is the reviewed set, lane 2 (behind it) holds the variants
-- added for the island.
----------------------------------------------------------------------
ART.run("LevelArt: rocks kit", function()
	local function lane(dz)
		local cursor = row.xMin + 12
		return function(width, gap)
			local x = cursor + width / 2
			cursor = cursor + width + (gap or GAP)
			return Vector3.new(x, ART.FLOOR_Y, row.z + dz)
		end
	end
	local slot = lane(0)
	local slot2 = lane(LANE2_DZ)

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
		note = "not climbable; gable crown",
		build = monolithBuild(12.5, 17.5, 10.5, TALL_A),
	})

	-- Spires
	local function spire(name, at, W, H, D, cfg, note)
		return ART.breakable({
			kit = KIT,
			name = name,
			at = at,
			size = Vector3.new(W, H, D),
			sink = SINK,
			bodyRole = "Letterstone",
			class = "Cover",
			note = note,
			build = monolithBuild(W, H, D, cfg),
		})
	end
	spire("Spire_A", slot(14), 14, 40, 9.5, SPIRE_A, "fluted obelisk, gable crown")
	local sc = spire("Spire_A_Cracked", slot(14), 14, 40, 9.5, SPIRE_A, "wild gold glyph test")
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

	-- Lane 2: variants for the island dress pass
	cover("Cover_Low_D", slot2(12.5), 12.5, 7.5, 10.5, 404, CFG_D, "deep chunk, split crown, fissure")
	cover("Cover_Low_E", slot2(18), 18, 6.5, 8.5, 505, CFG_E, "stepped slab, three loose caps")
	cover("Cover_Low_F", slot2(10), 10, 7, 8.5, 606, CFG_F, "small, leaning slab, long ramp")
	core("Core_C", slot2(18), Vector3.new(18, 7.5, 10), coreBuildC, "basalt columns, two fallen")
	ART.breakable({
		kit = KIT,
		name = "Cover_Tall_B",
		at = slot2(12),
		size = Vector3.new(12, 17.4, 10),
		sink = SINK,
		bodyRole = "Letterstone",
		class = "Cover",
		note = "not climbable; twin horns",
		build = monolithBuild(12, 17.4, 10, TALL_B),
	})
	spire("Spire_B", slot2(14), 14, 44, 9, SPIRE_B, "twin horns, dark pilasters")
	spire("Spire_C", slot2(14), 14, 36, 9.5, SPIRE_C, "slipped capstone, leaning buttress")
end)
return ART.report(KIT)
