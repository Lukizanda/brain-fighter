--!strict

----------------------------------------------------------------------
-- Wildcard
----------------------------------------------------------------------
-- Single source of truth for the wildcard letter — the gold "★" block
-- that stands in for any letter when spelling a word (so "D★G" is a
-- valid buffer that resolves to DOG / DIG / DUG).
--
-- Deliberately dependency-free so every layer of the spelling chain can
-- require it without pulling anything heavy in:
--   BlockSpawner   — rolls CHAR as a 27th "letter"
--   LetterBlocks   — tints the block gold and paints GLYPH on its face
--   WordBuffer     — accepts COLOR as a 4th tile color
--   Dictionary     — expands CHAR into any [a-z] when matching
--   EnergyEconomy  — spreads a wild tile's energy across all reservoirs
--   Hud            — renders GLYPH on the buffer tile
--
-- CHAR vs GLYPH: the internal representation is ASCII "*" so it is safe
-- in instance attributes, log lines, and Lua patterns. "★" is presented
-- to the player and never round-trips back into game logic.
--
-- See wiki/systems/LetterBlock.md.
----------------------------------------------------------------------

local CHAR = "*"
local GLYPH = "★"

-- Wild blocks carry their own color rather than one of the three
-- reservoir colors — see EnergyEconomy.splitByColor, which spreads a
-- wild tile's energy evenly across red/green/blue instead of banking it
-- into a single reservoir.
local COLOR = "wild"

local FIRST_CHAR_START = 1
local FIRST_CHAR_END = 1

local Wildcard = {}

Wildcard.CHAR = CHAR
Wildcard.GLYPH = GLYPH
Wildcard.COLOR = COLOR

-- True when `c` is exactly the wildcard character. Callers pass single
-- characters; a longer string is never a wildcard.
function Wildcard.isWildcard(c: string): boolean
	return c == CHAR
end

-- True when `s` contains at least one wildcard. Used as the fast-path
-- guard so wildcard-free words keep their O(1) dictionary lookup.
function Wildcard.hasWildcard(s: string): boolean
	return string.find(s, CHAR, FIRST_CHAR_START, true) ~= nil
end

-- Player-facing text for a buffered/blocked letter: the star for a
-- wildcard, the uppercased letter otherwise. Both the block face and
-- the HUD tile route through this so they can never disagree.
function Wildcard.toDisplay(letter: string): string
	if Wildcard.isWildcard(letter) then
		return GLYPH
	end
	return string.upper(letter)
end

-- Normalize an arbitrary caller-supplied letter to the single character
-- actually stored on a block: the wildcard as-is, otherwise the first
-- character uppercased.
function Wildcard.normalize(letter: string): string
	if Wildcard.isWildcard(letter) then
		return CHAR
	end
	return string.upper(string.sub(letter, FIRST_CHAR_START, FIRST_CHAR_END))
end

return Wildcard
