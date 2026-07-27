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

-- isWord does NOT interpret wildcards — that's resolve/isSpellable's job
expect("isWord('D*G')", Dictionary.isWord("D*G"), false)

----------------------------------------------------------------------
-- Wildcards
----------------------------------------------------------------------

-- resolve — wildcard-free input resolves to itself, uppercased
expect("resolve('fire')", Dictionary.resolve("fire"), "FIRE")
expect("resolve('XYZQQ')", Dictionary.resolve("XYZQQ"), nil)
expect("resolve('')", Dictionary.resolve(""), nil)

-- resolve — the design's headline example: "d*g" must be spellable
expect("isSpellable('d*g')", Dictionary.isSpellable("d*g"), true)
expect("isSpellable('D*G')", Dictionary.isSpellable("D*G"), true)

-- A leading wildcard forces the all-26-buckets scan path
expect("isSpellable('*og')", Dictionary.isSpellable("*og"), true)
expect("isSpellable('***')", Dictionary.isSpellable("***"), true)

-- Wildcards can't rescue an impossible pattern
expect("isSpellable('xq*zj')", Dictionary.isSpellable("xq*zj"), false)

-- A lone wildcard is NOT a free pass: the SCOWL-60 corpus carries no
-- single-letter entries (not even "a" or "i"), so there is nothing for
-- it to resolve to.
expect("isSpellable('*')", Dictionary.isSpellable("*"), false)

-- Illegal characters are rejected rather than pattern-injected. A raw
-- "." would match any letter if the pattern were built unguarded.
expect("isSpellable('d.g')", Dictionary.isSpellable("d.g"), false)
expect("isSpellable('d1g')", Dictionary.isSpellable("d1g"), false)

-- resolve returns a concrete word of the same length, with the fixed
-- letters preserved in place
local resolvedDog = Dictionary.resolve("d*g")
if type(resolvedDog) ~= "string" or #resolvedDog ~= 3 then
	error("[Dictionary.tests] resolve('d*g') expected a 3-letter word, got " .. tostring(resolvedDog), 0)
end
if string.sub(resolvedDog, 1, 1) ~= "D" or string.sub(resolvedDog, 3, 3) ~= "G" then
	error("[Dictionary.tests] resolve('d*g') should keep D_G fixed, got " .. resolvedDog, 0)
end
expect("resolve('d*g') is a real word", Dictionary.isWord(resolvedDog), true)

-- scoreFn picks the highest-scoring candidate, not merely the first.
-- Score by "prefer the letter O" and the resolution must be DOG.
local function preferO(word: string): number
	return if string.find(word, "o", 1, true) then 1 else 0
end
expect("resolve('d*g', preferO)", Dictionary.resolve("d*g", preferO), "DOG")

-- Same pattern, opposite preference — proves the scoreFn is actually
-- steering the result rather than corpus order deciding it.
local function preferU(word: string): number
	return if string.find(word, "u", 1, true) then 1 else 0
end
expect("resolve('d*g', preferU)", Dictionary.resolve("d*g", preferU), "DUG")

-- An unscored resolve of an unmatchable pattern still returns nil
expect("resolve('xq*zj', preferO)", Dictionary.resolve("xq*zj", preferO), nil)

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
