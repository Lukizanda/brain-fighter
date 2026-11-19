-- The showcase stage: three dark strips (one per kit) with a title board each.
-- Send this file as one execute_luau chunk (Edit datamodel).
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())
ART.run("LevelArt: stage", function()
	local stage = ART.folder("_Stage")
	stage:ClearAllChildren()
	local titles = { Rocks = "ROCKS  ·  cover, cores, spires, gates, cave", Terrain = "TERRAIN  ·  floor, ridge, ledges, underside", SetPieces = "SET PIECES  ·  dais, overlook, pads, dressing", POI = "POINTS OF INTEREST  ·  ruins, natural wonders, monuments" }
	for name, row in ART.ROWS do
		local length = row.xMax - row.xMin + 40
		local midX = (row.xMin + row.xMax) / 2
		ART.prim(stage, {
			role = "Stage",
			name = "Strip_" .. name,
			size = Vector3.new(length, 4, row.depth),
			cf = CFrame.new(midX, ART.FLOOR_Y - 2, row.z),
			collide = true,
		})
		local board = ART.prim(stage, {
			role = "StageSign",
			name = "Title_" .. name,
			size = Vector3.new(10, 0.4, 120),
			cf = CFrame.new((row.xMin + row.xMax) / 2, ART.FLOOR_Y + 0.2, row.z - row.depth / 2 + 6)
				* CFrame.Angles(0, math.rad(-90), 0),
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Rotation = 180
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.Text = titles[name]
		label.Parent = gui
	end
end)
return "stage built"
