--!strict

----------------------------------------------------------------------
-- LetterTables
----------------------------------------------------------------------
-- Named weighted letter tables for BlockSpawner volumes (Phase 8 stage 2,
-- wiki/design/boss-arena.md § Letter zones).
--
--   Standard — the full Scrabble bag plus the wildcard roll. Identical to
--              the single table the spawner always used.
--   Common   — low-value letters only, no wildcard.
--   Premium  — high-value letters, with a heavier wildcard weight.
--   Wildcard — the wildcard and nothing else.
--
-- Common and Premium are DERIVED from EnergyEconomy.letterValue with the
-- thresholds below, so a change to a letter's value moves it between
-- tables instead of leaving a hand-written list stale. Weight within a
-- table is still the Scrabble frequency, so Premium is not all Q and Z.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnergyEconomy = require(ReplicatedStorage.Shared.EnergyEconomy)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)

-- Scrabble letter frequencies (standard English bag of 98 tiles). Kept here
-- rather than imported from EnergyEconomy: frequency is conceptually
-- distinct from per-letter point values.
local LETTER_FREQUENCIES: { [string]: number } = {
	A = 9,  B = 2,  C = 2,  D = 4,  E = 12,
	F = 2,  G = 3,  H = 2,  I = 9,  J = 1,
	K = 1,  L = 4,  M = 2,  N = 6,  O = 8,
	P = 2,  Q = 1,  R = 6,  S = 4,  T = 6,
	U = 4,  V = 2,  W = 2,  X = 1,  Y = 2,
	Z = 1,
}

local ALPHABET = {
	"A","B","C","D","E","F","G","H","I","J","K","L","M",
	"N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
}

-- Wildcard blocks roll as a 27th "letter" against the same cumulative
-- table. The bag totals 98, so weight 4 lands at 4/102 ≈ 3.9% — roughly
-- one ★ in the ~24-block reference arena. Set to 0 to disable wildcard
-- spawns in the Standard table.
local STANDARD_WILDCARD_FREQUENCY = 4

-- Common: letters worth at most this (A E I O U L N S T R D G — 70 of 98
-- tiles, plenty of vowels).
local COMMON_MAX_LETTER_VALUE = 2
local COMMON_WILDCARD_FREQUENCY = 0

-- Premium: letters worth at least this (F H V W Y K J X Q Z — 15 tiles).
-- With weight 3 the wildcard is 3/18 ≈ 17% of premium rolls, against
-- 3.9% in Standard: the reward for reaching the inner ring.
local PREMIUM_MIN_LETTER_VALUE = 4
local PREMIUM_WILDCARD_FREQUENCY = 3

local WILDCARD_ONLY_FREQUENCY = 1

local NAME_STANDARD = "Standard"
local NAME_COMMON = "Common"
local NAME_PREMIUM = "Premium"
local NAME_WILDCARD = "Wildcard"

type Entry = { letter: string, threshold: number }

type Table = {
	entries: { Entry },
	total: number,
}

local function build(include: (letter: string) -> boolean, wildcardWeight: number): Table
	local entries: { Entry } = {}
	local total = 0
	for _, letter in ipairs(ALPHABET) do
		local weight = LETTER_FREQUENCIES[letter] or 0
		if weight > 0 and include(letter) then
			total += weight
			table.insert(entries, { letter = letter, threshold = total })
		end
	end
	if wildcardWeight > 0 then
		total += wildcardWeight
		table.insert(entries, { letter = Wildcard.CHAR, threshold = total })
	end
	return { entries = entries, total = total }
end

local TABLES: { [string]: Table } = {
	[NAME_STANDARD] = build(function()
		return true
	end, STANDARD_WILDCARD_FREQUENCY),
	[NAME_COMMON] = build(function(letter)
		return EnergyEconomy.letterValue(letter) <= COMMON_MAX_LETTER_VALUE
	end, COMMON_WILDCARD_FREQUENCY),
	[NAME_PREMIUM] = build(function(letter)
		return EnergyEconomy.letterValue(letter) >= PREMIUM_MIN_LETTER_VALUE
	end, PREMIUM_WILDCARD_FREQUENCY),
	[NAME_WILDCARD] = build(function()
		return false
	end, WILDCARD_ONLY_FREQUENCY),
}

local LetterTables = {}

LetterTables.STANDARD = NAME_STANDARD
LetterTables.COMMON = NAME_COMMON
LetterTables.PREMIUM = NAME_PREMIUM
LetterTables.WILDCARD = NAME_WILDCARD
LetterTables.DEFAULT = NAME_STANDARD

LetterTables.LETTER_FREQUENCIES = LETTER_FREQUENCIES
LetterTables.STANDARD_WILDCARD_FREQUENCY = STANDARD_WILDCARD_FREQUENCY
LetterTables.COMMON_MAX_LETTER_VALUE = COMMON_MAX_LETTER_VALUE
LetterTables.PREMIUM_MIN_LETTER_VALUE = PREMIUM_MIN_LETTER_VALUE
LetterTables.PREMIUM_WILDCARD_FREQUENCY = PREMIUM_WILDCARD_FREQUENCY

function LetterTables.isValid(name: string): boolean
	return TABLES[name] ~= nil
end

-- Every distinct letter the named table can roll (wildcard included), for
-- tests and for the warning that lists valid names.
function LetterTables.members(name: string): { string }
	local out: { string } = {}
	local tbl = TABLES[name]
	if tbl then
		for _, entry in ipairs(tbl.entries) do
			table.insert(out, entry.letter)
		end
	end
	return out
end

function LetterTables.names(): { string }
	return { NAME_STANDARD, NAME_COMMON, NAME_PREMIUM, NAME_WILDCARD }
end

-- Weighted pick from the named table. Unknown names fall back to Standard;
-- callers are expected to have validated, this just never returns nil.
function LetterTables.pick(name: string): string
	local tbl = TABLES[name] or TABLES[NAME_STANDARD]
	local roll = math.random() * tbl.total
	for _, entry in ipairs(tbl.entries) do
		if roll <= entry.threshold then
			return entry.letter
		end
	end
	-- Float-rounding edge: roll can land just past the last threshold.
	return tbl.entries[#tbl.entries].letter
end

return LetterTables
