--!strict

----------------------------------------------------------------------
-- Dictionary __tests
----------------------------------------------------------------------
-- Smoke tests for the Dictionary module. Runs assertions on require
-- (use `require(ReplicatedStorage.Shared.Dictionary.__tests)` in
-- a playtest console or via MCP execute_luau to invoke).
--
-- These are pinned to the gameplay-loop design — every word in the
-- worked-examples table (FIRE, FLAME, DRAGON, ROCK, LIGHTNING, ...)
-- must be recognized; one nonsense input must not be.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dictionary = require(ReplicatedStorage.Shared.Dictionary)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("Dictionary.tests")

local MIN_WORD_COUNT = 70000

local function expect(label: string, actual: any, expected: any)
	if actual ~= expected then
		error(
			string.format(
				"[Dictionary.tests] %s — expected %s, got %s",
				label,
				tostring(expected),
				tostring(actual)
			),
			0
		)
	end
end

-- isWord — case-insensitive recognition of pinned design words
expect("isWord('FIRE')", Dictionary.isWord("FIRE"), true)
expect("isWord('fire')", Dictionary.isWord("fire"), true)
expect("isWord('Fire')", Dictionary.isWord("Fire"), true)
expect("isWord('FLAME')", Dictionary.isWord("FLAME"), true)
expect("isWord('LIGHTNING')", Dictionary.isWord("LIGHTNING"), true)
expect("isWord('DRAGON')", Dictionary.isWord("DRAGON"), true)
expect("isWord('ROCK')", Dictionary.isWord("ROCK"), true)

-- isWord — gap-regression words (previously missing from bootstrap list)
expect("isWord('tout')", Dictionary.isWord("tout"), true)
expect("isWord('colour')", Dictionary.isWord("colour"), true)

-- isWord — rejects non-words and bad input
expect("isWord('XYZQQ')", Dictionary.isWord("XYZQQ"), false)
expect("isWord('')", Dictionary.isWord(""), false)

-- getStats — bootstrap minimum size + length histogram sanity
local stats = Dictionary.getStats()
if stats.wordCount <= MIN_WORD_COUNT then
	error(
		string.format(
			"[Dictionary.tests] getStats().wordCount expected > %d, got %d",
			MIN_WORD_COUNT,
			stats.wordCount
		),
		0
	)
end
if type(stats.byLength) ~= "table" then
	error("[Dictionary.tests] getStats().byLength expected table", 0)
end

log:info(
	string.format(
		"[TEST PASS] Dictionary smoke tests — %d words loaded",
		stats.wordCount
	)
)

return true
