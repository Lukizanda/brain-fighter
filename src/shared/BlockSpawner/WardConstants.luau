--!strict

----------------------------------------------------------------------
-- WardConstants
----------------------------------------------------------------------
-- The published mark of a ward letter: an ordinary letter block that orbits
-- the boss while its word ward is up (wiki/design/ai-playtest.md, the ward
-- decision). The pool (BlockSpawner.spawnWardLetter) writes the mark on the
-- block; a client that wants to draw ward letters differently reads it. What
-- the ward DOES (the boss's health held until every letter is popped) belongs
-- to the Boss system and its numbers are in BossConfig, not here.
--
-- Shared so the writer and any reader agree on the name without requiring
-- each other.
----------------------------------------------------------------------

local WardConstants = {
	-- Boolean on the block model: this block is a ward letter.
	ATTRIBUTE = "Block.Ward",
}

return WardConstants
