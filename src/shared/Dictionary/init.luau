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
-- API
--   Dictionary.isWord(s: string) -> boolean
--     Case-insensitive lookup. Returns true if the word is known.
--
--   Dictionary.getStats() -> { wordCount, byLength }
--     Returns the loaded word count and a length histogram. Triggers
--     a synchronous load of any letters not yet preloaded.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

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

local loaded: { [string]: { [string]: boolean } } = {}
local _cachedStats: Stats? = nil

local function ensureLoaded(letter: string)
	if loaded[letter] then
		return
	end
	local mod = script.words:FindFirstChild(letter)
	if not mod then
		loaded[letter] = {}
		return
	end
	local packed = require(mod) :: string
	local t: { [string]: boolean } = {}
	for w in packed:gmatch("[^\n]+") do
		t[w] = true
	end
	loaded[letter] = t
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
	if not letter:match("[a-z]") then
		return false
	end
	ensureLoaded(letter)
	return loaded[letter][lower] == true
end

function Dictionary.getStats(): Stats
	if _cachedStats == nil then
		_cachedStats = buildStats()
	end
	return _cachedStats :: Stats
end

return Dictionary
