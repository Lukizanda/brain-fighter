--!strict

----------------------------------------------------------------------
-- EnergyEconomy
----------------------------------------------------------------------
-- Pure-Luau formula module for Brain Fighter's word→energy economy.
--
-- The player shoots colored letter blocks into a 12-slot buffer,
-- arranges them into a word, and commits it (Memorize) — at which
-- point this module decides how much per-color mana the word emits.
--
-- Formula: word_energy = Σ letter_values × length_multiplier
--   - letter_values are Scrabble values (case-insensitive)
--   - length_multiplier tiers by word length (≤4 / 5-6 / 7-8 / 9+)
--   - integer result via math.floor (matches pinned worked examples
--     in wiki/design/gameplay-loop.md "Worked examples" table)
--
-- Mixed-color words: each tile's contribution flows to its OWN color
-- reservoir (value-weighted, not count-weighted). The per-color split
-- still sums exactly to computeWordEnergy(asWord) so the bookkeeping
-- never drifts; rounding shortfall is absorbed by the last present
-- color in canonical RGB order.
--
-- This module is pure: no Roblox-instance reads, no signals, no
-- mutation. Callers (MemorizeAction, HUD) read from it freely.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("EnergyEconomy")

local EnergyEconomy = {}

----------------------------------------------------------------------
-- Letter values (Scrabble — pinned in gameplay-loop.md "Tuning")
----------------------------------------------------------------------

local LETTER_VALUE_COMMON = 1
local LETTER_VALUE_D_G = 2
local LETTER_VALUE_B_C_M_P = 3
local LETTER_VALUE_F_H_V_W_Y = 4
local LETTER_VALUE_K = 5
local LETTER_VALUE_J_X = 8
local LETTER_VALUE_Q_Z = 10

local LETTER_VALUES: { [string]: number } = {
	A = LETTER_VALUE_COMMON,
	E = LETTER_VALUE_COMMON,
	I = LETTER_VALUE_COMMON,
	O = LETTER_VALUE_COMMON,
	U = LETTER_VALUE_COMMON,
	L = LETTER_VALUE_COMMON,
	N = LETTER_VALUE_COMMON,
	S = LETTER_VALUE_COMMON,
	T = LETTER_VALUE_COMMON,
	R = LETTER_VALUE_COMMON,

	D = LETTER_VALUE_D_G,
	G = LETTER_VALUE_D_G,

	B = LETTER_VALUE_B_C_M_P,
	C = LETTER_VALUE_B_C_M_P,
	M = LETTER_VALUE_B_C_M_P,
	P = LETTER_VALUE_B_C_M_P,

	F = LETTER_VALUE_F_H_V_W_Y,
	H = LETTER_VALUE_F_H_V_W_Y,
	V = LETTER_VALUE_F_H_V_W_Y,
	W = LETTER_VALUE_F_H_V_W_Y,
	Y = LETTER_VALUE_F_H_V_W_Y,

	K = LETTER_VALUE_K,

	J = LETTER_VALUE_J_X,
	X = LETTER_VALUE_J_X,

	Q = LETTER_VALUE_Q_Z,
	Z = LETTER_VALUE_Q_Z,
}

local UNKNOWN_LETTER_VALUE = 0

----------------------------------------------------------------------
-- Length multipliers
----------------------------------------------------------------------

local LENGTH_TIER_SHORT_MAX = 4
local LENGTH_TIER_MEDIUM_MAX = 6
local LENGTH_TIER_LONG_MAX = 8

local LENGTH_MULTIPLIER_SHORT = 1
local LENGTH_MULTIPLIER_MEDIUM = 1.5
local LENGTH_MULTIPLIER_LONG = 2
local LENGTH_MULTIPLIER_EPIC = 3

----------------------------------------------------------------------
-- Color ordering
----------------------------------------------------------------------
-- Canonical iteration order for splitByColor rounding reconciliation.
-- The LAST present color in this order absorbs the integer remainder
-- so Σ per-color = computeWordEnergy(asWord) exactly. The order
-- itself is design-arbitrary; "RGB" matches every visualization in
-- the codebase (mockups, HUD docs).

local COLOR_RED = "red"
local COLOR_GREEN = "green"
local COLOR_BLUE = "blue"

local CANONICAL_COLOR_ORDER: { string } = {
	COLOR_RED,
	COLOR_GREEN,
	COLOR_BLUE,
}

----------------------------------------------------------------------
-- Public types
----------------------------------------------------------------------

export type Color = "red" | "green" | "blue"

export type Tile = {
	letter: string,
	color: Color,
}

export type ColorEnergy = { [string]: number }

----------------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------------

local FIRST_CHAR_START = 1
local FIRST_CHAR_END = 1

local function firstCharUpper(s: string): string
	return string.upper(string.sub(s, FIRST_CHAR_START, FIRST_CHAR_END))
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- Scrabble value for a single letter (case-insensitive).
-- Unknown / non-letter chars return 0 (with a one-shot warn so callers
-- notice spawner config drift rather than silently emitting zeros).
function EnergyEconomy.letterValue(c: string): number
	if c == "" then
		return UNKNOWN_LETTER_VALUE
	end

	local key = firstCharUpper(c)
	local value = LETTER_VALUES[key]
	if value == nil then
		log:warn("letterValue: unknown letter", c, "→ returning 0")
		return UNKNOWN_LETTER_VALUE
	end
	return value
end

-- Length-tier multiplier. Negative / zero lengths fall into the short
-- tier so a malformed call doesn't crash.
function EnergyEconomy.lengthMultiplier(len: number): number
	if len <= LENGTH_TIER_SHORT_MAX then
		return LENGTH_MULTIPLIER_SHORT
	elseif len <= LENGTH_TIER_MEDIUM_MAX then
		return LENGTH_MULTIPLIER_MEDIUM
	elseif len <= LENGTH_TIER_LONG_MAX then
		return LENGTH_MULTIPLIER_LONG
	else
		return LENGTH_MULTIPLIER_EPIC
	end
end

-- Σ letter_values × length_multiplier, floored to integer for parity
-- with the pinned worked-example table in gameplay-loop.md.
function EnergyEconomy.computeWordEnergy(word: string): number
	local letterSum = 0
	local wordLength = #word
	for i = 1, wordLength do
		letterSum += EnergyEconomy.letterValue(string.sub(word, i, i))
	end
	return math.floor(letterSum * EnergyEconomy.lengthMultiplier(wordLength))
end

-- Value-weighted per-color split. Each tile contributes
-- letter_value × length_multiplier to its own color bucket. Length
-- multiplier is derived from total tile count, NOT per-color count —
-- so "FLAME" is a 5-letter word for multiplier purposes whether its
-- tiles are all red or mixed.
--
-- Rounding reconciliation: floor each color's raw share; assign any
-- integer shortfall to the LAST present color in canonical RGB order,
-- so Σ buckets = computeWordEnergy(asWord) exactly. Without this,
-- a 1.5× word that splits 50/50 between two colors would lose 1
-- point of energy to floor() rounding.
--
-- Colors with zero tiles are omitted from the result.
function EnergyEconomy.splitByColor(tiles: { Tile }): ColorEnergy
	local tileCount = #tiles
	local multiplier = EnergyEconomy.lengthMultiplier(tileCount)

	local letterSumByColor: { [string]: number } = {
		[COLOR_RED] = 0,
		[COLOR_GREEN] = 0,
		[COLOR_BLUE] = 0,
	}
	local colorPresent: { [string]: boolean } = {
		[COLOR_RED] = false,
		[COLOR_GREEN] = false,
		[COLOR_BLUE] = false,
	}
	local totalLetterSum = 0

	for _, tile in tiles do
		local value = EnergyEconomy.letterValue(tile.letter)
		letterSumByColor[tile.color] = (letterSumByColor[tile.color] or 0) + value
		colorPresent[tile.color] = true
		totalLetterSum += value
	end

	local totalEnergy = math.floor(totalLetterSum * multiplier)

	local presentInOrder: { string } = {}
	for _, color in CANONICAL_COLOR_ORDER do
		if colorPresent[color] then
			table.insert(presentInOrder, color)
		end
	end

	local result: ColorEnergy = {}
	local assignedSoFar = 0
	local lastIndex = #presentInOrder
	for i, color in presentInOrder do
		if i == lastIndex then
			result[color] = totalEnergy - assignedSoFar
		else
			local share = math.floor(letterSumByColor[color] * multiplier)
			result[color] = share
			assignedSoFar += share
		end
	end

	return result
end

return EnergyEconomy
