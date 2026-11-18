--!strict

----------------------------------------------------------------------
-- KeyConstants
----------------------------------------------------------------------
-- The published state of a block with a tap reach of its own, which today
-- means a gate's key letters (wiki/design/ai-playtest.md § Gate redesign):
-- pop the letters hung in front of a gate, from close by, and it opens. The
-- pool writes the reach on every block of a volume that carries `PopReach`;
-- BlockShoot reads it (`BlockShoot.reachOf`) for the tap and for the server's
-- range check; the client script KeyLetterVisuals reads it to mark the
-- block. What popping a key word DOES (the gate opening) is between the
-- pool, WordKitWatcher and the walls, not here.
--
-- Shared so the writer and the readers agree on the name without any of
-- them requiring the other.
----------------------------------------------------------------------

local KeyConstants = {
	-- Number on the block model: studs from a character's root within which
	-- the block can be popped.
	POP_REACH_ATTRIBUTE = "Block.PopReach",

	-- ============================================================
	-- Key look (client, KeyLetterVisuals). Greybox.
	-- ============================================================
	HIGHLIGHT_NAME = "KeyLetterMark",
	-- A gold outline, so key letters read as "these open something". The
	-- fill is faint from afar and brighter once the player is within reach.
	OUTLINE_COLOR = Color3.fromRGB(255, 205, 60),
	FILL_COLOR = Color3.fromRGB(255, 205, 60),
	OUTLINE_TRANSPARENCY = 0,
	FILL_TRANSPARENCY_FAR = 0.9,
	FILL_TRANSPARENCY_NEAR = 0.45,
	-- How often the near/far look is refreshed.
	REFRESH_SEC = 0.2,
}

return KeyConstants
