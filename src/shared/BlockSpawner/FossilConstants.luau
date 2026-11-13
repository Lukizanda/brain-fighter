--!strict

----------------------------------------------------------------------
-- FossilConstants
----------------------------------------------------------------------
-- The vocabulary and tuning of fossil letters (Phase 8 stage 8,
-- wiki/design/boss-arena.md § Fossil letters). Shared rather than
-- server-only because the wall-visuals client reads the attribute names and
-- the glyph look; only the server reads the height and the lifetime.
--
-- A `BreakableWall` part carries `FossilTable`; FossilWatcher (server) rolls
-- one letter from that table, publishes it, and frees it as an ordinary
-- letter block when the wall breaks.
----------------------------------------------------------------------

local FossilConstants = {}

-- Set by the level author on a BreakableWall part: a LetterTables name.
FossilConstants.TABLE_ATTRIBUTE = "FossilTable"

-- Published by the server on the same part; the client reads them.
FossilConstants.LETTER_ATTRIBUTE = "FossilLetter"
FossilConstants.COLOR_ATTRIBUTE = "FossilColor"

-- Set on the freed block: when it expires, in `workspace:GetServerTimeNow()`
-- seconds (never os.clock(), which differs per VM). The block removes itself
-- on the server at this time; a client may use it to tell the end is near.
FossilConstants.EXPIRES_ATTRIBUTE = "FossilExpiresAt"

-- How long a freed letter floats before it fades away.
FossilConstants.LIFETIME_SEC = 20

-- Where the freed block appears: this far above the wall's base (the
-- bottom of its box). It must clear the floor by the block's tumble radius
-- (checked by the fossil suite), and 8 studs puts the block about a head
-- above a 5-stud character: seen over the rocks, and a tap away.
FossilConstants.HEIGHT_ABOVE_BASE_STUDS = 8

-- Glyph on a cracked wall (client look, greybox). Fractions of the face.
FossilConstants.Glyph = {
	GUI_NAME = "FossilGlyph",
	-- The SurfaceGui canvas, in pixels, per stud of face: enough to stay
	-- crisp up close without a huge texture.
	PIXELS_PER_STUD = 24,
	-- How much of the face the letter fills (it is a square in the middle).
	SIZE_FRACTION = 0.7,
	-- A little see-through so it reads as in the rock, not on it.
	TEXT_TRANSPARENCY = 0.1,
	-- Dark outline so a light letter reads on a light rock and vice versa.
	STROKE_THICKNESS = 3,
	STROKE_COLOR = Color3.fromRGB(20, 16, 12),
	-- Pull the tint toward white so it matches the lightened glyph on a block.
	LIGHTEN = 0.35,
}

return FossilConstants
