--!strict

----------------------------------------------------------------------
-- Dictionary
----------------------------------------------------------------------
-- Word lookup for the Memorize action. Words are validated against
-- this set before buffered energy transmutes into per-color reservoirs
-- (see wiki/design/gameplay-loop.md).
--
-- Implementation: 26 per-letter sub-modules, each holding a packed
-- newline-delimited string (~80k words total from SCOWL size 60).
-- Modules are background-preloaded via task.defer at game start so
-- that isWord() is always an O(1) hashtable hit during gameplay.
--
-- Wildcards: a buffered word may contain the wildcard character (see
-- [[Wildcard]]), which stands for any single letter — "D*G" resolves to
-- DOG. Because the design places no cap on wildcards per word, letter
-- expansion (26^k lookups) is not viable: "***" alone would be 17,576
-- probes and a full 12-slot buffer astronomically more. Instead each
-- letter module is indexed by word length at load time, so matching a
-- pattern scans only the candidates that could possibly fit — the
-- length bucket of the known first letter, or all 26 buckets at that
-- length when the first character is itself a wildcard. This costs one
-- extra array of string references per word (~1 MB across the corpus)
-- and keeps the worst case in the low milliseconds.
--
-- API
--   Dictionary.isWord(s: string) -> boolean
--     Case-insensitive exact lookup. Wildcards are NOT interpreted —
--     use isSpellable/resolve for buffered words.
--
--   Dictionary.isSpellable(s: string) -> boolean
--     Wildcard-aware validity. Early-exits on the first match, so this
--     is the cheap call for per-keystroke HUD feedback.
--
--   Dictionary.resolve(s: string, scoreFn?) -> string?
--     Wildcard-aware resolution to a concrete UPPERCASE word.
--
--   Dictionary.getStats() -> { wordCount, byLength }
--     Returns the loaded word count and a length histogram. Triggers
--     a synchronous load of any letters not yet preloaded.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)

local log = Logger.new("Dictionary")

local Dictionary = {}

export type Stats = {
	wordCount: number,
	byLength: { [number]: number },
}

local LETTERS = {
	"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
	"n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
}

-- Lua pattern class a wildcard expands to. The corpus is lowercase
-- a-z only, so this never needs to admit punctuation or digits.
local WILDCARD_PATTERN_CLASS = "[a-z]"
local LETTER_PATTERN_CLASS = "[a-z]"

local FIRST_CHAR = 1
local NO_SCORE = -math.huge

local loaded: { [string]: { [string]: boolean } } = {}

-- byLength[letter][len] — every loaded word of that first-letter and
-- length, in corpus (alphabetical) order. Built alongside `loaded` so
-- there is no second pass over the packed strings; consumed only by the
-- wildcard matcher.
local byLength: { [string]: { [number]: { string } } } = {}

local _cachedStats: Stats? = nil

local function ensureLoaded(letter: string)
	if loaded[letter] then
		return
	end
	local mod = script.words:FindFirstChild(letter)
	if not mod then
		loaded[letter] = {}
		byLength[letter] = {}
		return
	end
	local packed = require(mod) :: string
	local t: { [string]: boolean } = {}
	local buckets: { [number]: { string } } = {}
	for w in packed:gmatch("[^\n]+") do
		t[w] = true
		local len = #w
		local bucket = buckets[len]
		if not bucket then
			bucket = {}
			buckets[len] = bucket
		end
		bucket[#bucket + 1] = w
	end
	loaded[letter] = t
	byLength[letter] = buckets
end

-- Background preload — spread across frames so game start isn't hitched.
-- Completes in < 1 second; MemorizeAction requires several seconds of typing,
-- so all 26 letters are cached long before the first word can be submitted.
task.defer(function()
	local total = 0
	for _, letter in LETTERS do
		ensureLoaded(letter)
		for _ in loaded[letter] do
			total += 1
		end
		task.wait()
	end
	log:info("Dictionary preload complete —", total, "words")
end)

local function buildStats(): Stats
	local wordCount = 0
	local byLength: { [number]: number } = {}
	for _, letter in LETTERS do
		ensureLoaded(letter)
		for word in loaded[letter] do
			wordCount += 1
			local len = #word
			byLength[len] = (byLength[len] or 0) + 1
		end
	end
	return { wordCount = wordCount, byLength = byLength }
end

function Dictionary.isWord(s: string): boolean
	if type(s) ~= "string" or #s == 0 then
		return false
	end
	local lower = string.lower(s)
	local letter = lower:sub(1, 1)
	if not letter:match(LETTER_PATTERN_CLASS) then
		return false
	end
	ensureLoaded(letter)
	return loaded[letter][lower] == true
end

----------------------------------------------------------------------
-- Wildcard matching
----------------------------------------------------------------------

-- Lowercase `s` if every character is a letter or a wildcard, else nil.
-- Rejecting up front means the compiled pattern below only ever
-- concatenates known-safe characters, so no escaping is required.
local function normalizeForMatch(s: string): string?
	if type(s) ~= "string" or #s == 0 then
		return nil
	end
	local lower = string.lower(s)
	for i = 1, #lower do
		local c = string.sub(lower, i, i)
		if not Wildcard.isWildcard(c) and not string.match(c, LETTER_PATTERN_CLASS) then
			return nil
		end
	end
	return lower
end

-- "d*g" -> "^d[a-z]g$"
local function buildPattern(lower: string): string
	local parts = table.create(#lower + 2)
	parts[1] = "^"
	for i = 1, #lower do
		local c = string.sub(lower, i, i)
		parts[i + 1] = if Wildcard.isWildcard(c) then WILDCARD_PATTERN_CLASS else c
	end
	parts[#lower + 2] = "$"
	return table.concat(parts)
end

-- Resolve a possibly-wildcarded word to a concrete dictionary word,
-- returned UPPERCASE to match WordBuffer:asWord(). Returns nil when
-- nothing matches (or the input contains illegal characters).
--
-- Without `scoreFn` the first match wins and the scan early-exits —
-- the cheap "is this spellable?" path.
--
-- With `scoreFn` every candidate is scored and the highest wins, per
-- the design decision that a wildcard pays out the best letter it could
-- have been (MemorizeAction passes EnergyEconomy.computeWordEnergy).
-- Ties keep the first candidate in corpus order, which is alphabetical,
-- so resolution is deterministic across runs and machines.
function Dictionary.resolve(s: string, scoreFn: ((word: string) -> number)?): string?
	local lower = normalizeForMatch(s)
	if not lower then
		return nil
	end

	-- Fast path: no wildcard means the existing O(1) hash lookup answers
	-- it, and there is exactly one possible resolution — the word itself.
	if not Wildcard.hasWildcard(lower) then
		return if Dictionary.isWord(lower) then string.upper(lower) else nil
	end

	local length = #lower
	local pattern = buildPattern(lower)

	-- A concrete first letter confines the scan to one bucket; a leading
	-- wildcard has to consider every letter's bucket at this length.
	local firstChar = string.sub(lower, FIRST_CHAR, FIRST_CHAR)
	local lettersToScan = if Wildcard.isWildcard(firstChar) then LETTERS else { firstChar }

	local best: string? = nil
	local bestScore = NO_SCORE

	for _, letter in lettersToScan do
		ensureLoaded(letter)
		local bucket = byLength[letter][length]
		if bucket then
			for _, candidate in bucket do
				if string.match(candidate, pattern) then
					if scoreFn == nil then
						return string.upper(candidate)
					end
					local score = scoreFn(candidate)
					if score > bestScore then
						bestScore = score
						best = candidate
					end
				end
			end
		end
	end

	return if best then string.upper(best) else nil
end

-- Wildcard-aware validity check. Equivalent to isWord() for words with
-- no wildcards; for wildcarded input it early-exits on the first match.
function Dictionary.isSpellable(s: string): boolean
	return Dictionary.resolve(s) ~= nil
end

function Dictionary.getStats(): Stats
	if _cachedStats == nil then
		_cachedStats = buildStats()
	end
	return _cachedStats :: Stats
end

return Dictionary
