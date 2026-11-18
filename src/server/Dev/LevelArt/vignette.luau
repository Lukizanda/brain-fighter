-- The vignette: a slice of the island assembled from clones of the three kits,
-- so the pieces can be judged together at player height. Looking +Z from the
-- dais you face the rim. Re-run after any kit changes: it clones what is there.
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())

local CENTER = Vector3.new(400, ART.FLOOR_Y, 1540)
local SIZE = 120 -- two floor swatches each way
local RIM_Z = CENTER.Z + 50 -- centre line of the ridge
local LETTER_HEIGHT = 22 -- middle of the open-ground letter band
local DAIS_OFFSET_Z = -34
local DAIS_CENTER = CENTER + Vector3.new(0, 0, DAIS_OFFSET_Z)
local DAIS_CLEAR_RADIUS = 28 -- dais radius 22 plus the largest dressing piece
local DRESSING_MAX_SIZE = 20 -- anything smaller than this on a swatch is dressing

type Place = { kit: string, asset: string, x: number, z: number, yaw: number?, y: number? }

-- x / z are offsets from CENTER. The clone keeps its showcase height and facing
-- (ridge pieces already face -Z); `yaw` turns it further, `y` lifts it.
local PLACES: { Place } = {
	-- Rim, left to right: low lip, the Spit's marker mass, its gate, a tall mass.
	{ kit = "Kit_Terrain", asset = "Ridge_Lip_A", x = -37, z = 50 },
	{ kit = "Kit_Terrain", asset = "Ridge_Marker_Spit", x = -1, z = 50 },
	{ kit = "Kit_Rocks", asset = "Gate_Ridge", x = 22, z = 50 },
	{ kit = "Kit_Terrain", asset = "Ridge_Mass_A", x = 53, z = 50 },
	{ kit = "Kit_SetPieces", asset = "Rim_Crystals", x = 50, z = 60, yaw = 180 },
	-- Beyond the rim.
	{ kit = "Kit_SetPieces", asset = "Floating_Rock_A", x = -30, z = 92, y = 4 },
	{ kit = "Kit_SetPieces", asset = "Floating_Rock_B", x = 44, z = 84, y = -8 },
	-- An outer cover formation: a tall landmark, a permanent core, low cover.
	{ kit = "Kit_Rocks", asset = "Cover_Tall", x = -30, z = 18, yaw = 20 },
	{ kit = "Kit_Rocks", asset = "Core_A", x = -14, z = 12, yaw = -12 },
	{ kit = "Kit_Rocks", asset = "Cover_Low_C", x = -40, z = 4, yaw = 70 },
	-- A spire and its companions.
	{ kit = "Kit_Rocks", asset = "Spire_A", x = 34, z = 22, yaw = -15 },
	{ kit = "Kit_Rocks", asset = "Cover_Low_A", x = 20, z = 8, yaw = 10 },
	{ kit = "Kit_Rocks", asset = "Core_B", x = 44, z = 6, yaw = 35 },
	-- A cracked rock showing its fossil, alone in the open.
	{ kit = "Kit_Rocks", asset = "Cover_Low_A_Cracked", x = 2, z = -14, yaw = -8 },
	-- The boss's dais at the near edge.
	{ kit = "Kit_SetPieces", asset = "Dais_Boss", x = 0, z = DAIS_OFFSET_Z },
}

local LETTERS = {
	{ "Q", "red", -26, -6 },
	{ "A", "green", -8, 2 },
	{ "T", "blue", 12, -4 },
	{ "★", "wild", 30, 4 },
	{ "E", "blue", -18, 26 },
	{ "S", "red", 6, 28 },
	{ "N", "green", 40, 30 },
}

local function cloneOf(kit: string, asset: string): Model?
	local folder = ART.root():FindFirstChild(kit)
	local model = folder and folder:FindFirstChild(asset)
	return if model then model:Clone() else nil
end

local missing = {}

ART.run("LevelArt: vignette", function()
	local folder = ART.folder("Vignette")
	folder:ClearAllChildren()

	-- Something to stand on: the art floor does not collide.
	ART.prim(folder, {
		role = "Stage",
		name = "StandingSlab",
		size = Vector3.new(SIZE, 4, SIZE),
		cf = CFrame.new(CENTER - Vector3.new(0, 2, 0)),
		collide = true,
	})

	-- Floor: four swatches, each turned a different way so the tiling does not
	-- show, with the palette-test letters taken out.
	local quarter = SIZE / 4
	local turns = { 0, 90, 180, 270 }
	local index = 0
	for _, dx in { -quarter, quarter } do
		for _, dz in { -quarter, quarter } do
			index += 1
			local swatch = cloneOf("Kit_Terrain", "Floor_Swatch")
			if swatch then
				for _, child in swatch:GetDescendants() do
					if child.Name:match("^TestLetter_") then
						child:Destroy()
					end
				end
				local pivot = swatch:GetPivot()
				swatch.Name = "Floor_" .. index
				swatch:PivotTo(
					CFrame.new(CENTER.X + dx, pivot.Y, CENTER.Z + dz) * CFrame.Angles(0, math.rad(turns[index]), 0)
				)
				-- The designer's rule: no inlay, tuft or pebble near the dais.
				for _, child in swatch:GetDescendants() do
					if child:IsA("BasePart") and child.Size.X < DRESSING_MAX_SIZE and child.Size.Z < DRESSING_MAX_SIZE then
						local offset = child.Position - DAIS_CENTER
						if Vector3.new(offset.X, 0, offset.Z).Magnitude < DAIS_CLEAR_RADIUS then
							child:Destroy()
						end
					end
				end
				swatch.Parent = folder
			else
				missing["Kit_Terrain.Floor_Swatch"] = true
			end
		end
	end

	for _, place in PLACES do
		local model = cloneOf(place.kit, place.asset)
		if model then
			local pivot = model:GetPivot()
			model:PivotTo(
				CFrame.new(CENTER.X + place.x, pivot.Y + (place.y or 0), CENTER.Z + place.z)
					* pivot.Rotation
					* CFrame.Angles(0, math.rad(place.yaw or 0), 0)
			)
			model.Parent = folder
		else
			missing[place.kit .. "." .. place.asset] = true
		end
	end

	for _, letter in LETTERS do
		ART.letterBlock(
			folder,
			CENTER + Vector3.new(letter[3], LETTER_HEIGHT, letter[4]),
			letter[1],
			letter[2]
		)
	end
end)

local names = {}
for name in missing do
	table.insert(names, name)
end
local parts = 0
for _, d in ART.folder("Vignette"):GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end
return string.format(
	"vignette built: %d parts; missing: %s",
	parts,
	if #names > 0 then table.concat(names, ", ") else "none"
)
