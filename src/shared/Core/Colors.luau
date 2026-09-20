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
--
-- Also owns the **palette**: the Color3 each tile colour is drawn with on
-- every surface a player *reads* — block faces, buffer tiles, the spell
-- menu discs. One table per palette, one active palette, and `tint()` is
-- the only way a drawing site should get a colour for "red". The
-- high-contrast palette exists because spells are colour-typed: a player
-- who cannot tell the default red from the default green is locked out
-- of the core verb, and no amount of tuning one surface fixes that if
-- the other three keep their own literals. Selected client-side by the
-- settings surface (`Settings`); the server only ever sees the default.
-- VFX keep their own brighter colours in VfxConfig — a burst is not read,
-- it is felt.
----------------------------------------------------------------------

local Colors = {}

export type SpellColor = "red" | "green" | "blue"
export type TileColor = SpellColor | "wild"
export type Tile = { letter: string, color: TileColor }
export type PaletteName = "default" | "high_contrast"
export type Palette = { [string]: Color3 }

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

----------------------------------------------------------------------
-- Palettes
----------------------------------------------------------------------

Colors.Palette = {
	Default = "default" :: PaletteName,
	HighContrast = "high_contrast" :: PaletteName,
}

-- The tile colour a drawing site falls back to for an unknown key. Red
-- rather than nothing: a block or tile with no colour reads as broken,
-- a wrong hue reads as a bug someone can see and file.
local FALLBACK_COLOR: TileColor = "red"

-- `default` is the shipped look (LetterBlocks' original tints, 2026-05).
-- `high_contrast` is Okabe–Ito: vermillion / bluish-green / blue / yellow,
-- the standard colour-blind-safe set — distinguishable under
-- protanopia, deuteranopia and tritanopia while each still reads as the
-- colour its name says.
local PALETTES: { [string]: Palette } = {
	[Colors.Palette.Default] = {
		red = Color3.fromHex("#dc2626"),
		green = Color3.fromHex("#16a34a"),
		blue = Color3.fromHex("#2563eb"),
		wild = Color3.fromHex("#eab308"),
	},
	[Colors.Palette.HighContrast] = {
		red = Color3.fromRGB(213, 94, 0),
		green = Color3.fromRGB(0, 158, 115),
		blue = Color3.fromRGB(0, 114, 178),
		wild = Color3.fromRGB(240, 228, 66),
	},
}
Colors.PALETTES = PALETTES

local activePalette: string = Colors.Palette.Default

local paletteChangedEvent = Instance.new("BindableEvent")
paletteChangedEvent.Name = "PaletteChanged"
-- Fires with the new palette name after `setPalette` switches. Drawing
-- sites that painted once (block faces, menu discs) repaint on it.
Colors.paletteChanged = paletteChangedEvent.Event

function Colors.isPalette(name: any): boolean
	return type(name) == "string" and PALETTES[name] ~= nil
end

function Colors.getPalette(): string
	return activePalette
end

-- Switch the active palette. Returns false and changes nothing for an
-- unknown name; a no-op switch to the current palette does not fire.
function Colors.setPalette(name: string): boolean
	if not Colors.isPalette(name) then
		return false
	end
	if name == activePalette then
		return true
	end
	activePalette = name
	paletteChangedEvent:Fire(name)
	return true
end

-- The Color3 to draw tile colour `color` with, in the active palette.
function Colors.tint(color: string?): Color3
	local palette = PALETTES[activePalette]
	local tint = if color then palette[color] else nil
	return tint or palette[FALLBACK_COLOR]
end

return Colors
