--!strict

----------------------------------------------------------------------
-- Colors
----------------------------------------------------------------------
-- Single source of truth for the three castable spell/reservoir colors
-- (red/green/blue) and the tile colors a letter-block can carry (the
-- same three, plus the wild gold star — see [[Wildcard]]). Was
-- independently redeclared in WordBuffer, EnergyEconomy, EnergyReservoirs,
-- SpellRegistry and BlockSpawner; every consumer now re-exports these as
-- aliases so external call sites don't churn.
----------------------------------------------------------------------

local Colors = {}

export type SpellColor = "red" | "green" | "blue"
export type TileColor = SpellColor | "wild"
export type Tile = { letter: string, color: TileColor }

-- Canonical order (matches every visualization in the codebase — mockups,
-- HUD docs). If a fourth castable color is ever added, this is the single
-- point of truth for spawn weighting, snapshot order, and validation.
local SPELL_COLORS: { SpellColor } = { "red", "green", "blue" }
Colors.SPELL_COLORS = SPELL_COLORS

local VALID_SPELL_COLORS: { [string]: boolean } = {
	red = true,
	green = true,
	blue = true,
}

function Colors.isSpellColor(color: string): boolean
	return VALID_SPELL_COLORS[color] == true
end

return Colors
