-- Dress pass: the lead's. Hides the greybox markers a player should never see
-- (designer ruling "What gets art": zones, key volumes and the boss point are
-- invisible and get no art). Run it last; it claims only what no kit pass owns.
local ART = require(game.ServerStorage.LevelArtPrelude:Clone())

local PASS = "Dress_Lead"

-- Name prefixes of the greybox's working volumes, drawn at 0.8 transparency
-- while the level was being laid out.
local MARKER_PREFIXES = { "Zone_", "Key_", "BossPoint" }

return ART.dress(PASS, function()
	for _, prefix in MARKER_PREFIXES do
		for _, part in ART.greybox(prefix) do
			ART.hide(PASS, part)
		end
	end
end) .. "\nstill grey:\n" .. ART.undressed()
