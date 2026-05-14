--!strict

----------------------------------------------------------------------
-- Dictionary
----------------------------------------------------------------------
-- Word lookup for the Memorize action. The buffered word is validated
-- against this set before its energy transmutes into the per-color
-- reservoirs (see wiki/design/gameplay-loop.md).
--
-- Implementation: O(1) hashtable from src/shared/Dictionary/WordList.
-- Bootstrap data is ~700 K-12-friendly entries; the curated 10–30k
-- SCOWL list is the planned replacement (see wiki/systems/Dictionary.md).
--
-- API
--   Dictionary.isWord(s: string) -> boolean
--     Case-insensitive lookup. `isWord("FIRE")`, `isWord("fire")`,
--     `isWord("Fire")` all return true if "fire" is in the list.
--
--   Dictionary.getStats() -> { wordCount, byLength }
--     Returns the loaded word count and a length histogram. Cached
--     on first call.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local WordList = require(script.WordList)

local log = Logger.new("Dictionary")

local Dictionary = {}

export type Stats = {
	wordCount: number,
	byLength: { [number]: number },
}

local _cachedStats: Stats? = nil

local function buildStats(): Stats
	local wordCount = 0
	local byLength: { [number]: number } = {}
	for word in WordList do
		wordCount += 1
		local len = #word
		byLength[len] = (byLength[len] or 0) + 1
	end
	return { wordCount = wordCount, byLength = byLength }
end

function Dictionary.isWord(s: string): boolean
	if type(s) ~= "string" or #s == 0 then
		return false
	end
	return WordList[string.lower(s)] == true
end

function Dictionary.getStats(): Stats
	if _cachedStats == nil then
		_cachedStats = buildStats()
	end
	return _cachedStats :: Stats
end

local stats = Dictionary.getStats()
log:info("Dictionary loaded", stats.wordCount, "words")

return Dictionary
