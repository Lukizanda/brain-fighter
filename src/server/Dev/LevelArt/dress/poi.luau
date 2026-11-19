-- Dress pass: points of interest. Clones five showcase POIs (Kit_POI) onto and
-- around the island at the designer's measured spots (ART.POI_SPOTS). Each is
-- on or beyond the ridge ring, out of reach, so its Collide_ proxies are
-- dropped and nothing in this pass collides. Claims no greybox part.
-- Run after dress/setpieces.luau (the geode takes a crystal cluster's spot).
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())

local PASS = "Dress_POI"

local placed = {}
local audit = ART.dress(PASS, function(folder)
	for _, spot in ART.POI_SPOTS do
		local model = ART.placePoi(folder, spot.poi, spot.at, spot.yaw, spot.why)
		if not spot.floats then
			table.insert(placed, ART.seatPoi(model, spot.sink))
		end
		local cf, size = model:GetBoundingBox()
		local floorY = ART.islandCenter().Y
		table.insert(
			placed,
			string.format(
				"%s yaw %d: top %+.1f, bottom %+.1f",
				spot.poi,
				spot.yaw,
				cf.Position.Y + size.Y / 2 - floorY,
				cf.Position.Y - size.Y / 2 - floorY
			)
		)
	end
end)

return audit .. "\n" .. table.concat(placed, "\n")
