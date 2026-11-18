-- Dress pass: local lights on the boss island. The sky, sun, haze and grade
-- are not here: they are game code (client/Arena/ArenaLighting, presets in
-- Shared/Arena/ArenaLightingConstants), applied only while a player is in
-- the arena. This pass adds the few local lights that preset was lit for.
-- Run after the set-pieces pass: it reads that pass's crystal clusters.
--
-- Rules for lights on the island (lighting pass, 2026-11-18):
--   * Colours come from palette roles: a light never introduces a hue the
--     island does not already show.
--   * No light on a breakable (walls, gates, the cave plug, the Overhang
--     slab): a light would outlive the wall it belongs to. Their seams are
--     Neon, and the arena preset's bloom makes them glow.
--   * Nothing in the letter bands or the lanes (designer rulings): every
--     holder sits low over the dais, inside the cave, or outside the ring.
--   * Shadows off, ranges short: a handful of cheap accents, not fill.
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())

local PASS = "Dress_Lighting"

-- Rune glow over the dais. Low and wide enough to pool plum on the dais
-- (radius 22, Ground Slam's reach) without spilling onto the floor past it.
local DAIS_LIGHT_HEIGHT = 3
local DAIS_LIGHT_RANGE = 20
local DAIS_LIGHT_BRIGHTNESS = 0.6

-- A dim cool glow at the back of the cave chamber: from outside the cave is
-- still a dark mouth (the preset's dark Ambient), but there is something to
-- go in for, and the cave word's key letters read inside.
local CAVE_LIGHT_LIFT = 4 -- above the chamber volume's centre
local CAVE_LIGHT_BACK = 4 -- toward the chamber's back wall, away from the plug
local CAVE_LIGHT_RANGE = 14
local CAVE_LIGHT_BRIGHTNESS = 0.6

-- Each rim crystal cluster catches a little cold light, so the island's
-- edge sparkles against the dusk haze.
local CRYSTAL_LIGHT_LIFT = 3
local CRYSTAL_LIGHT_RANGE = 12
local CRYSTAL_LIGHT_BRIGHTNESS = 0.8

local HOLDER_SIZE = Vector3.new(0.2, 0.2, 0.2)

local function holder(folder: Instance, name: string, at: Vector3): BasePart
	return ART.prim(folder, {
		role = "Crystal",
		name = name,
		size = HOLDER_SIZE,
		cf = CFrame.new(at),
		transparency = 1,
		shadow = false,
	})
end

local function pointLight(parent: Instance, role: string, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = ART.PAL[role][2]
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
	return light
end

local function only(prefix: string): BasePart
	local found = ART.greybox(prefix)
	assert(#found == 1, string.format("expected one %s on the island, found %d", prefix, #found))
	return found[1]
end

local function pivotOf(inst: Instance): Vector3
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	local sum, n = Vector3.zero, 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			sum += d.Position
			n += 1
		end
	end
	assert(n > 0, inst:GetFullName() .. " has no parts to light")
	return sum / n
end

local placed = {}

local audit = ART.dress(PASS, function(folder)
	-- Dais
	local dais = only("Dais_Boss")
	-- The dais is a Cylinder on its side: Size.X is its height.
	local daisTop = Vector3.new(dais.Position.X, dais.Position.Y + dais.Size.X / 2 + DAIS_LIGHT_HEIGHT, dais.Position.Z)
	pointLight(holder(folder, "Light_Dais", daisTop), "Rune", DAIS_LIGHT_RANGE, DAIS_LIGHT_BRIGHTNESS)
	table.insert(placed, "Light_Dais @" .. tostring(daisTop))

	-- Cave: the chamber is the hold zone's volume; its back is away from the plug.
	local chamber = only("Hold_CaveRidge")
	local plug = only("Gate_CaveRidge")
	local away = chamber.Position - plug.Position
	away = Vector3.new(away.X, 0, away.Z)
	away = if away.Magnitude > 1e-3 then away.Unit else Vector3.zero
	local caveAt = chamber.Position + Vector3.new(0, CAVE_LIGHT_LIFT, 0) + away * CAVE_LIGHT_BACK
	pointLight(holder(folder, "Light_Cave", caveAt), "GateSeam", CAVE_LIGHT_RANGE, CAVE_LIGHT_BRIGHTNESS)
	table.insert(placed, "Light_Cave @" .. tostring(caveAt))

	-- Rim crystals, from the set-pieces pass
	local root = workspace:FindFirstChild(ART.DRESS_ROOT_NAME)
	local setPieces = root and root:FindFirstChild("Dress_SetPieces")
	local crystals = setPieces and setPieces:FindFirstChild("RimCrystals")
	assert(crystals, "Dress_SetPieces.RimCrystals is missing: run dress/setpieces.luau first")
	local clusters = crystals:GetChildren()
	table.sort(clusters, function(a, b)
		return a.Name < b.Name
	end)
	for i, cluster in clusters do
		local at = pivotOf(cluster) + Vector3.new(0, CRYSTAL_LIGHT_LIFT, 0)
		local name = "Light_Crystal_" .. i
		pointLight(holder(folder, name, at), "Crystal", CRYSTAL_LIGHT_RANGE, CRYSTAL_LIGHT_BRIGHTNESS)
		table.insert(placed, name .. " @" .. tostring(at))
	end
end)

return audit .. "\n" .. table.concat(placed, "\n")
