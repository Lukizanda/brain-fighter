-- Dress pass: the rocks artist's. Puts the Kit_Rocks assets on the review island's
-- breakable cover, permanent cores and regenerating gates. The greybox parts stay
-- where and what they are (collision, raycasts, tags); see README.md and
-- wiki/design/boss-arena.md § Level art.
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())

local PASS = "Dress_Rocks"
local KIT = "Kit_Rocks"
local SEED = 4417

-- Showcase assets a class of greybox part may be given. Sizes are read from each
-- asset (its GreyboxSize attribute), never copied here.
local LOW = { "Cover_Low_A", "Cover_Low_B", "Cover_Low_C", "Cover_Low_D", "Cover_Low_E", "Cover_Low_F" }
local TALL = { "Cover_Tall", "Cover_Tall_B" }
local SPIRE = { "Spire_A", "Spire_B", "Spire_C" }
local CORE = { "Core_A", "Core_B", "Core_C" }
local GATE_RIDGE = "Gate_Ridge"
local GATE_CAVE = "Gate_CavePlug"

-- Gate greybox parts by name. Their names are unique on the island; the part
-- must also be 4 thick (a ridge gate) or 3 thick (the plug), checked below.
local RIDGE_GATES = { Gate_Spit = true, Gate_Stones = true, Gate_Overhang = true }
local CAVE_GATE = "Gate_CaveRidge"

-- A pick is penalised this much per time that asset was already used, so
-- twenty rocks do not collapse onto the single closest variant. In log-scale
-- fit units (see fitCost): 0.15 is about one 16% stretch on one axis.
local REUSE_PENALTY = 0.15
-- Ties inside this band of cost are broken by the seeded random, so the choice
-- is deterministic but not an artefact of sort order.
local TIE_NOISE = 0.01

-- The designer's envelope (README, "Envelope"): 1 stud on the sides; tops +0.5
-- for low cover, +2 for tall cover / spire / gate. EPS is float slack for
-- rotated parts' corner boxes.
local SIDE_ALLOW = 1
local TOP_ALLOW = { low = 0.5, tall = 3, spire = 3, gate = 2 }
-- Tall cover and spires (ruling of the second round): a child that starts at UPPER_Y
-- over the floor or higher may reach UPPER_SIDE_ALLOW studs out; one that starts lower
-- stays inside SIDE_ALLOW. Tops: +3 over the box.
local UPPER_Y = 12
local UPPER_SIDE_ALLOW = 3
local EPS = 0.1
local GLYPH_HALF = 0.35 -- the glyph square is 0.7 of the smaller face dimension

local rng = Random.new(SEED)
local log: { string } = {}
local issues: { string } = {}

local function assetSize(name: string): Vector3
	local folder = ART.root():FindFirstChild(KIT)
	local model = folder and folder:FindFirstChild(name)
	assert(model, "no showcase asset " .. name .. " (run kits/rocks.luau first)")
	return model:GetAttribute("GreyboxSize") :: Vector3
end

-- A breakable's decoration reaches up to 1 stud outside the box, so growing it
-- by more than ~10% on any axis would push it past the 1 stud envelope. Shrinking
-- is free, so breakables use [FIT_MIN, ADOPT_MAX] and cores the audit's full window.
local ADOPT_MAX = 1.1

-- How far an asset has to be stretched to fit a box: the sum of |ln scale| over
-- the three axes. nil if any axis would leave the allowed window.
local function fitCost(asset: Vector3, box: Vector3, maxStretch: number): number?
	local s = box / asset
	for _, f in { s.X, s.Y, s.Z } do
		if f < ART.FIT_MIN or f > maxStretch then
			return nil
		end
	end
	return math.abs(math.log(s.X)) + math.abs(math.log(s.Y)) + math.abs(math.log(s.Z))
end

local uses: { [string]: number } = {}

-- Closest-fitting variant for a box, with the reuse penalty.
local function pick(variants: { string }, box: Vector3, maxStretch: number): string
	local best, bestScore
	for _, name in variants do
		local cost = fitCost(assetSize(name), box, maxStretch)
		if cost then
			local score = cost + REUSE_PENALTY * (uses[name] or 0) + rng:NextNumber(0, TIE_NOISE)
			if not bestScore or score < bestScore then
				best, bestScore = name, score
			end
		end
	end
	assert(best, string.format("no variant fits a %s box inside the fit window", tostring(box)))
	uses[best] = (uses[best] or 0) + 1
	return best
end

-- Check an adopted wall's children against the envelope and the glyph square,
-- in the wall's own space. A rotated child is judged by its corner box, which
-- over-reports (never under-reports) what it covers.
local function envelope(wall: BasePart, kind: string)
	local size = wall.Size
	local faceAxisZ = size.X >= size.Z -- broad faces face +-Z
	local faceWidth = if faceAxisZ then size.X else size.Z
	local sq = GLYPH_HALF * math.min(faceWidth, size.Y)
	for _, child in wall:GetChildren() do
		if child:IsA("BasePart") then
			local rel = wall.CFrame:ToObjectSpace(child.CFrame)
			local h = child.Size / 2
			local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = rel:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
						lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
						hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
					end
				end
			end
			local half = size / 2
			local tag = string.format("%s/%s", wall.Name, child.Name)
			local sideAllow = SIDE_ALLOW
			if kind == "tall" or kind == "spire" then
				-- height of the child's lowest point over the floor top
				local lowest = wall.Position.Y + lo.Y - ART.islandCenter().Y
				if lowest >= UPPER_Y - EPS then
					sideAllow = UPPER_SIDE_ALLOW
				end
			end
			if math.max(-lo.X, hi.X) - half.X > sideAllow + EPS or math.max(-lo.Z, hi.Z) - half.Z > sideAllow + EPS then
				table.insert(issues, string.format("%s leaves the %g stud envelope", tag, sideAllow))
			end
			if hi.Y - half.Y > TOP_ALLOW[kind] + EPS then
				table.insert(issues, string.format("%s rises %.2f over the top", tag, hi.Y - half.Y))
			end
			-- glyph square: only a child that sticks out of a broad face can cover it
			local facePlane = if faceAxisZ then half.Z else half.X
			local faceLo = if faceAxisZ then lo.Z else lo.X
			local faceHi = if faceAxisZ then hi.Z else hi.X
			if faceHi > facePlane + 0.02 or faceLo < -facePlane - 0.02 then
				local acrossLo = if faceAxisZ then lo.X else lo.Z
				local acrossHi = if faceAxisZ then hi.X else hi.Z
				if acrossLo < sq and acrossHi > -sq and lo.Y < sq and hi.Y > -sq then
					table.insert(issues, tag .. " covers the glyph square")
				end
			end
		end
	end
end

local function dressCovers()
	local kinds = { low = 0, tall = 0, spire = 0 }
	for _, part in ART.greybox("Cover_") do
		local kind = part:GetAttribute("CoverHeight")
		local variants = if kind == "low" then LOW elseif kind == "tall" then TALL elseif kind == "spire" then SPIRE else nil
		assert(variants, part.Name .. " has no usable CoverHeight")
		kinds[kind] += 1
		local asset = pick(variants, part.Size, ADOPT_MAX)
		-- every wall, flipped half the time so the strata do not line up
		local flip = rng:NextNumber() < 0.5
		ART.adopt(PASS, KIT, asset, part, flip)
		envelope(part, kind)
		table.insert(log, string.format("%s %s -> %s%s", part.Name, tostring(part.Size), asset, if flip then " (flip)" else ""))
	end
	return kinds
end

local function dressCores()
	local n = 0
	for _, part in ART.greybox("Core_") do
		n += 1
		local asset = pick(CORE, part.Size, ART.FIT_MAX)
		-- the asset's front (-Z: fallen stones, front wedges) looks at the island centre
		local toward = ART.towardCenter(part)
		local turn = if toward.Z < 0 then 0 else 180
		ART.place(PASS, KIT, asset, part, { name = string.format("%s_%02d", part.Name, n), turn = turn })
		table.insert(log, string.format("%s %s -> %s turn %d", part.Name, tostring(part.Size), asset, turn))
	end
	return n
end

local function dressGates()
	local n = 0
	for _, part in ART.greybox("Gate_") do
		local asset, faceAxis
		if RIDGE_GATES[part.Name] then
			assert(part.Size.X == 4, part.Name .. " is not a 4 thick ridge gate")
			asset, faceAxis = GATE_RIDGE, "X"
		elseif part.Name == CAVE_GATE then
			assert(part.Size.Z == 3, part.Name .. " is not the 3 thick cave plug")
			asset, faceAxis = GATE_CAVE, "Z"
		end
		-- (Gate_OverhangSlab is the terrain artist's: it is in neither list)
		if asset then
			n += 1
			-- the asset's carving face is its +X (ridge gate) or +Z (plug); flip
			-- when the island centre is on the other side
			local toward = ART.towardCenter(part)
			local flip = (if faceAxis == "X" then toward.X else toward.Z) < 0
			ART.adopt(PASS, KIT, asset, part, flip)
			envelope(part, "gate")
			table.insert(log, string.format("%s %s -> %s%s", part.Name, tostring(part.Size), asset, if flip then " (flip)" else ""))
		end
	end
	return n
end

local report = ART.dress(PASS, function()
	local kinds = dressCovers()
	local cores = dressCores()
	local gates = dressGates()
	table.insert(log, 1, string.format("covers low %d / tall %d / spire %d, cores %d, gates %d", kinds.low, kinds.tall, kinds.spire, cores, gates))
end)

local usage = {}
for name, count in uses do
	table.insert(usage, string.format("%s x%d", name, count))
end
table.sort(usage)

return report
	.. string.format("\nenvelope: %d issues%s", #issues, if #issues > 0 then "\n  " .. table.concat(issues, "\n  ") else "")
	.. "\nvariants: "
	.. table.concat(usage, ", ")
	.. "\n"
	.. table.concat(log, "\n")
	.. "\nstill grey:\n"
	.. ART.undressed()
