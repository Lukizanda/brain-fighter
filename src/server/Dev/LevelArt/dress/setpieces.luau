-- Dress pass: set pieces. Boss dais, arrival overlook, the cave (shell and its ten
-- rocks), the ready room pads and floor, and the island's dressing (floor scatter,
-- floating rocks, rim crystals). Run: see README.md.
-- Claims only parts of those names; ART.dress refuses anything another pass owns.
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())

local PASS = "Dress_SetPieces"
local KIT = "Kit_SetPieces"
local SEED = 2611

-- Rulings (README, boss-arena.md § Level art), as numbers.
local DAIS_BOX = Vector3.new(44, 1, 44) -- radius 22 exactly: Ground Slam's reach
local SCATTER_MIN_RADIUS = 26 -- rule: none within 24 of the centre; 2 studs margin
local SCATTER_CLUSTERS = 24
local SCATTER_CLUSTER_GAP = 20 -- min distance between two clusters
local SCATTER_LANE_CLEAR = 9 -- keep this far from a lane's centre line (lane is 21 wide)
local SCATTER_BLOCKER_MARGIN = 3.5 -- keep this far from any solid greybox part
local SCATTER_TRIES = 6000
local TUFT_MAX_HEIGHT = 1.4 -- rule: at most 1.5 tall
local FLOOR_TOLERANCE = 0.2 -- a scatter point must land on floor level within this
local CRYSTAL_SETS = 4
local CRYSTAL_MIN_SPACING = 90 -- between two crystal sets, so they spread round the ring
local CRYSTAL_GATE_CLEAR = 40 -- no crystals on the mass beside a gate: that one has a marker
local CRYSTAL_MIN_MASS_HEIGHT = 18 -- a ridge mass, not a lip
local CRYSTAL_MAX_ROLL = 8 -- degrees; the cluster follows the mass's lean
local CRYSTAL_BELOW_TOP = 6.5 -- cluster centre this far under the mass top (tips stay under +3)
local CRYSTAL_EMBED = 0.5 -- the base sinks this far into the greybox face
local ROCK_TALL_MIN = 12 -- rocks at least this tall get a cap course over the mass
local ROCK_MASS_FRACTION = 0.72 -- the dominant mass is this share of the rock's height
local ROCK_COURSE_YAW = 1.2 -- degrees of yaw between mass and cap
local ROCK_MAX_INSET = 0.9 -- a course sits at most this far inside the greybox rock (rule: 1)
local ROCK_MAX_OUTSET = 0.5

-- Floating rocks: { asset, angle (deg from +X toward +Z), radius, height of box centre }.
-- Angles avoid the three ledge directions (Spit ~169, Stones ~70, Overhang ~-71) by 40+
-- degrees so none can be mistaken for a way across, and all sit beyond the ridge ring.
local FLOATING = {
	{ "Floating_Rock_A", 25, 250, 44 },
	{ "Floating_Rock_A", 215, 260, 48 },
	{ "Floating_Rock_B", 125, 230, 34 },
	{ "Floating_Rock_B", 335, 235, 38 },
}

local function rad(d: number)
	return math.rad(d)
end

local rng = Random.new(SEED)
-- The cave rocks draw from their own generator, so changing their look never moves the
-- approved scatter, floating rocks and crystals. The shared one is first advanced by the
-- draws the first rock design consumed (RESERVED_DRAWS), so those placements stay as approved.
local rockRng = Random.new(SEED + 1)
local function reservedDraws(rock: BasePart): number
	local courses = math.max(2, math.floor(rock.Size.Y / 6 + 0.5))
	return 6 * courses + 15
end

local function showcase(name: string): Model
	local model = ART.root():FindFirstChild(KIT) and ART.root()[KIT]:FindFirstChild(name)
	assert(model, "run kits/setpieces.luau first: no " .. name)
	return model
end

-- Clone a showcase asset and put its GreyboxRef centre at `cf`.
local function drop(folder: Folder, assetName: string, cf: CFrame, name: string): Model
	local clone = showcase(assetName):Clone()
	clone.Name = name
	clone:PivotTo(cf)
	clone.Parent = folder
	return clone
end

----------------------------------------------------------------------
-- Cave rocks: natural rock built to each real rock's own box
----------------------------------------------------------------------
-- Courses of slabs inside the greybox rock (each side inset at most ROCK_MAX_INSET,
-- or out at most ROCK_MAX_OUTSET), a shoulder on top, two cracks, moss on the low ones.
local function dressRock(folder: Folder, rock: BasePart)
	local sx, sy, sz = rock.Size.X, rock.Size.Y, rock.Size.Z
	local f = rock.CFrame
	-- One dominant mass (the lower ROCK_MASS_FRACTION of a tall rock) and a cap course on
	-- top, nearly aligned; low rocks are a single course.
	local courses = if sy >= ROCK_TALL_MIN then { { 0, ROCK_MASS_FRACTION }, { ROCK_MASS_FRACTION, 1 } } else { { 0, 1 } }
	for i, span in courses do
		local a = rockRng:NextNumber(-ROCK_MAX_OUTSET, ROCK_MAX_INSET)
		local b = rockRng:NextNumber(-ROCK_MAX_OUTSET, ROCK_MAX_INSET)
		local c = rockRng:NextNumber(-ROCK_MAX_OUTSET, ROCK_MAX_INSET)
		local d = rockRng:NextNumber(-ROCK_MAX_OUTSET, ROCK_MAX_INSET)
		local y0 = -sy / 2 + span[1] * sy - (if i > 1 then 0.2 else 0)
		local y1 = -sy / 2 + span[2] * sy
		if i == #courses then
			y1 += rockRng:NextNumber(-1.2, 1.2) -- tops within +-2 of the greybox top
			topLocal = y1
		end
		local x0, x1 = -sx / 2 + a, sx / 2 - b
		local z0, z1 = -sz / 2 + c, sz / 2 - d
		local role = if i == 1 then "Cliff" else "CliffLight"
		ART.prim(folder, {
			role = role,
			name = if i == 1 then "Mass" else "Cap",
			size = Vector3.new(x1 - x0, y1 - y0, z1 - z0),
			cf = f * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2) * CFrame.Angles(0, rad(rockRng:NextNumber(-ROCK_COURSE_YAW, ROCK_COURSE_YAW)), 0),
			color = ART.shade(role, rockRng:NextNumber(-0.02, 0.02)),
		})
	end
	-- Shoulder: a tilted chunk on the top, at most 1.8 above the top course.
	local shoulderH = 1.4
	ART.prim(folder, {
		role = "CliffLight",
		name = "Shoulder",
		size = Vector3.new(sx * 0.5, shoulderH, sz * 0.5),
		cf = f
			* CFrame.new(rockRng:NextNumber(-sx * 0.15, sx * 0.15), topLocal + shoulderH / 2 - 0.4, rockRng:NextNumber(-sz * 0.15, sz * 0.15))
			* CFrame.Angles(rad(rockRng:NextNumber(-8, 8)), rad(rockRng:NextNumber(-25, 25)), rad(rockRng:NextNumber(-8, 8))),
		color = ART.shade("CliffLight", rockRng:NextNumber(-0.03, 0.03)),
	})
	-- Two cracks on opposite broad faces (dark thin strips, 0.15 proud).
	for _, side in { -1, 1 } do
		local len = sy * rockRng:NextNumber(0.4, 0.65)
		ART.prim(folder, {
			role = "CliffDark",
			name = "Crack",
			size = Vector3.new(0.35, len, 0.3),
			cf = f
				* CFrame.new(rockRng:NextNumber(-sx * 0.3, sx * 0.3), rockRng:NextNumber(-sy * 0.3, sy * 0.15), side * (sz / 2 - 0.5))
				* CFrame.Angles(0, 0, rad(rockRng:NextNumber(-12, 12))),
			shadow = false,
		})
	end
	if sy <= 8 then
		ART.prim(folder, {
			role = "Turf",
			name = "Moss",
			size = Vector3.new(sx * 0.6, 0.4, sz * 0.6),
			cf = f * CFrame.new(0, topLocal - 0.1, 0),
		})
	end
end

----------------------------------------------------------------------
-- Floor scatter
----------------------------------------------------------------------
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Distance in the XZ plane from point p to the segment a-b.
local function distToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

-- True when the XZ point lies within `margin` of the part's footprint.
local function nearPart(p: Vector3, part: BasePart, margin: number): boolean
	local l = part.CFrame:PointToObjectSpace(Vector3.new(p.X, part.Position.Y, p.Z))
	return math.abs(l.X) <= part.Size.X / 2 + margin and math.abs(l.Z) <= part.Size.Z / 2 + margin
end

local function tuft(folder: Folder, at: Vector3, yaw: number)
	for i = 1, 3 do
		local hgt = rng:NextNumber(0.8, TUFT_MAX_HEIGHT)
		local a = rad(yaw + i * 120)
		local off = CFrame.new(math.cos(a) * 0.3, 0, math.sin(a) * 0.3)
		ART.prim(folder, {
			role = "TurfLight",
			name = "Tuft",
			shape = "Wedge",
			size = Vector3.new(0.4, hgt, 0.4),
			cf = CFrame.new(at) * off * CFrame.Angles(rad(rng:NextNumber(-12, 12)), -a, rad(rng:NextNumber(-12, 12))) * CFrame.new(0, hgt / 2 - 0.05, 0),
		})
	end
end

local function pebbles(folder: Folder, at: Vector3, count: number)
	local roles = { "Cliff", "CliffDark", "CliffLight", "Letterstone", "LetterstoneDark" }
	for _ = 1, count do
		local d = rng:NextNumber(0.4, 0.8)
		local role = roles[rng:NextInteger(1, #roles)]
		local ball = rng:NextInteger(0, 1) == 1
		ART.prim(folder, {
			role = role,
			name = "Pebble",
			shape = if ball then "Ball" else "Block",
			size = Vector3.new(d, d * 0.7, d * rng:NextNumber(0.8, 1.2)),
			cf = CFrame.new(at + Vector3.new(rng:NextNumber(-1.2, 1.2), d * 0.25, rng:NextNumber(-1.2, 1.2)))
				* CFrame.Angles(rad(rng:NextNumber(-15, 15)), rad(rng:NextNumber(0, 360)), rad(rng:NextNumber(-15, 15))),
		})
	end
end

local function scatter(folder: Folder)
	local center = ART.islandCenter()
	local island = ART.island()
	-- Solid greybox the scatter keeps clear of.
	local blockers: { BasePart } = {}
	for _, prefix in { "Cover_", "Core_", "Ridge_Segment", "Cave_", "Gate_", "Ledge_", "Overlook_Shelf", "ArrivalPoint" } do
		for _, p in ART.greybox(prefix) do
			table.insert(blockers, p)
		end
	end
	-- Lane centre lines: centre to each gate and to the cave plug.
	local lanes: { Vector3 } = {}
	for _, prefix in { "Gate_Spit", "Gate_Stones", "Gate_Overhang", "Gate_CaveRidge" } do
		table.insert(lanes, flat(ART.greybox(prefix)[1].Position))
	end
	local origin = flat(center)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { island }

	local accepted: { Vector3 } = {}
	for _ = 1, SCATTER_TRIES do
		if #accepted >= SCATTER_CLUSTERS then
			break
		end
		local r = rng:NextNumber(SCATTER_MIN_RADIUS, 135)
		local a = rng:NextNumber(0, math.pi * 2)
		local p = origin + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local ok = true
		for _, lane in lanes do
			if distToSegment(p, origin, lane) < SCATTER_LANE_CLEAR then
				ok = false
				break
			end
		end
		if ok then
			for _, q in accepted do
				if (flat(q) - p).Magnitude < SCATTER_CLUSTER_GAP then
					ok = false
					break
				end
			end
		end
		if ok then
			for _, b in blockers do
				if nearPart(p, b, SCATTER_BLOCKER_MARGIN) then
					ok = false
					break
				end
			end
		end
		if ok then
			local hit = workspace:Raycast(Vector3.new(p.X, center.Y + 30, p.Z), Vector3.new(0, -60, 0), params)
			if hit and hit.Instance.Name == "Floor_Wedge" and math.abs(hit.Position.Y - center.Y) <= FLOOR_TOLERANCE then
				table.insert(accepted, Vector3.new(p.X, hit.Position.Y, p.Z))
			end
		end
	end
	for _, at in accepted do
		for _ = 1, rng:NextInteger(1, 2) do
			tuft(folder, at + Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5)), rng:NextNumber(0, 360))
		end
		pebbles(folder, at, rng:NextInteger(2, 3))
		if rng:NextInteger(0, 1) == 1 then
			ART.prim(folder, {
				role = "Letterstone",
				name = "Chip",
				size = Vector3.new(0.9, 0.6, 0.8),
				cf = CFrame.new(at + Vector3.new(rng:NextNumber(-1.5, 1.5), 0.25, rng:NextNumber(-1.5, 1.5)))
					* CFrame.Angles(rad(rng:NextNumber(-10, 10)), rad(rng:NextNumber(0, 360)), rad(rng:NextNumber(-10, 10))),
			})
		end
	end
	return #accepted
end

----------------------------------------------------------------------
-- Rim crystals: on the outward face of ridge masses, pointing out
----------------------------------------------------------------------
local function crystals(folder: Folder)
	local center = ART.islandCenter()
	local gates: { Vector3 } = {}
	for _, prefix in { "Gate_Spit", "Gate_Stones", "Gate_Overhang", "Gate_CaveRidge" } do
		table.insert(gates, flat(ART.greybox(prefix)[1].Position))
	end
	local chosen: { Vector3 } = {}
	local count = 0
	for _, mass in ART.greybox("Ridge_Segment") do
		if count >= CRYSTAL_SETS then
			break
		end
		local _, _, roll = mass.CFrame:ToOrientation()
		local pos = flat(mass.Position)
		local ok = mass.Size.Y >= CRYSTAL_MIN_MASS_HEIGHT and mass.Size.Z >= 19 and math.abs(math.deg(roll)) <= CRYSTAL_MAX_ROLL
		for _, g in gates do
			if (g - pos).Magnitude < CRYSTAL_GATE_CLEAR then
				ok = false
			end
		end
		for _, q in chosen do
			if (q - pos).Magnitude < CRYSTAL_MIN_SPACING then
				ok = false
			end
		end
		if ok then
			table.insert(chosen, pos)
			count += 1
			local sign = if mass.CFrame.RightVector:Dot(mass.Position - center) >= 0 then 1 else -1
			local out = mass.CFrame.RightVector * sign
			local along = mass.CFrame.LookVector
			local shift = rng:NextNumber(-mass.Size.Z / 2 + 8, mass.Size.Z / 2 - 8)
			local base = mass.CFrame * Vector3.new(sign * (mass.Size.X / 2 - CRYSTAL_EMBED), mass.Size.Y / 2 - CRYSTAL_BELOW_TOP, shift)
			-- Asset +Y points out of the face, asset X runs along it.
			local cf = CFrame.fromMatrix(base, along, out)
			drop(folder, "Rim_Crystals", cf * CFrame.new(0, 5, 0), "Crystals_" .. count)
		end
	end
	return count
end

----------------------------------------------------------------------
-- The pass
----------------------------------------------------------------------
local log = {}

local result = ART.dress(PASS, function(folder)
	local center = ART.islandCenter()

	-- Boss dais: a cylinder lying on its side; the art box lies flat on it.
	local dais = ART.greybox("Dais_Boss")[1]
	ART.place(PASS, KIT, "Dais_Boss", dais, { at = CFrame.new(dais.Position), size = DAIS_BOX })

	-- Overlook shelf, and its arrival pad (a hidden plinth: the asset draws it).
	local shelf = ART.greybox("Overlook_Shelf")[1]
	ART.place(PASS, KIT, "Overlook_Shelf", shelf)
	ART.hide(PASS, ART.greybox("ArrivalPoint")[1])

	-- Cave: shell asset over the roof's box, the rest of the shell hidden, rocks dressed.
	local roof = ART.greybox("Cave_Ridge_Roof")[1]
	ART.place(PASS, KIT, "Cave_Shell", roof, {
		at = roof.CFrame * CFrame.new(0, -7, 0), -- roof is 14..18 of an 18 high footprint box
		size = Vector3.new(40, 18, 36),
	})
	for _, prefix in { "Cave_Ridge_Back", "Cave_Ridge_Jamb", "Cave_Ridge_Side" } do
		for _, p in ART.greybox(prefix) do
			ART.hide(PASS, p)
		end
	end
	local rockFolder = Instance.new("Folder")
	rockFolder.Name = "CaveRocks"
	rockFolder.Parent = folder
	for _, rock in ART.greybox("Cave_Ridge_Rock") do
		dressRock(rockFolder, rock)
		for _ = 1, reservedDraws(rock) do
			rng:NextNumber(0, 1)
		end
		ART.hide(PASS, rock)
	end

	-- Ready room.
	local room = ART.readyRoom()
	assert(room, "the ready room is missing")
	for _, d in room:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "Floor" then
				ART.skin(PASS, d, "FlagstoneDark")
			elseif d.Name == "Rail" then
				ART.skin(PASS, d, "Timber")
			elseif d.Name == "EntryPad" then
				ART.place(PASS, KIT, "Pad_Entry", d, { turn = 270 }) -- chevrons point -X, toward the island
			elseif d.Name == "LobbyReturnPad" then
				ART.place(PASS, KIT, "Pad_Return", d)
			elseif d.Name == "SpawnPad" then
				ART.place(PASS, KIT, "Pad_Spawn", d)
			end
		end
	end

	-- Dressing.
	local floorFolder = Instance.new("Folder")
	floorFolder.Name = "FloorScatter"
	floorFolder.Parent = folder
	local clusters = scatter(floorFolder)

	local floatFolder = Instance.new("Folder")
	floatFolder.Name = "FloatingRocks"
	floatFolder.Parent = folder
	for i, f in FLOATING do
		local a = rad(f[2])
		local pos = center + Vector3.new(math.cos(a) * f[3], f[4], math.sin(a) * f[3])
		drop(floatFolder, f[1], CFrame.new(pos) * CFrame.Angles(0, rad(rng:NextInteger(0, 3) * 90), 0), f[1] .. "_" .. i)
	end

	local crystalFolder = Instance.new("Folder")
	crystalFolder.Name = "RimCrystals"
	crystalFolder.Parent = folder
	local sets = crystals(crystalFolder)
	table.insert(log, string.format("scatter clusters %d, crystal sets %d", clusters, sets))
end)

local total = 0
local root = workspace:FindFirstChild(ART.DRESS_ROOT_NAME)
if root and root:FindFirstChild(PASS) then
	for _, d in root[PASS]:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "GreyboxRef" then
			total += 1
		end
	end
	for _, d in ART.island():GetDescendants() do
		if d:GetAttribute("ArtAdded") == PASS then
			total += 1
		end
	end
end
return result .. "\n" .. table.concat(log, "; ") .. "\nnew parts: " .. total .. "\nstill grey:\n" .. ART.undressed()
