--!strict

----------------------------------------------------------------------
-- bomb_rules — the scramble bomb's pure rules: accept / reject / solved / hint, the allowed set and the scramble
----------------------------------------------------------------------
-- MODULE LEVEL, no player, no world: BombRules on sample letters and
-- hand-made word pools (the shipped key and kit lists hold almost no
-- anagram pairs, so CAT/ACT and SEE/ESE come from an injected pool).
--   CAT / ACT   tiles T-A-C: tile 3 or 2 first is accepted, tile 1 (T) is not;
--               after C a T is refused; C-A-T solves CAT, A-C-T solves ACT;
--               the hint is the next tile of the first consistent word.
--   SEE / ESE   duplicate letters: the hint is the lowest unlocked index.
--   scramble    never the word nor an allowed word when one exists; reports
--               false when none does.
--   shipped     every 3- and 4-letter pool word is its own first allowed
--               word and scrambles to a non-solution.
--   encoding    the published lists round-trip.
--
-- NOT covered: the server judging a tap (bomb_* world tests) and a client's
-- prediction.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BombRules = require(ReplicatedStorage.Shared.Boss.BombRules)

local SCRAMBLE_RUNS = 200
local SHIPPED_LENGTHS = { 3, 4 }

local function sameList(a: { any }, b: { any }): boolean
	if #a ~= #b then
		return false
	end
	for index, value in a do
		if b[index] ~= value then
			return false
		end
	end
	return true
end

local function sorted(word: string): string
	local letters = BombRules.lettersOf(word)
	table.sort(letters)
	return table.concat(letters)
end

return {
	name = "bomb_rules",

	setup = function(_ctx: any) end,

	run = function(ctx: any)
		local failures: { string } = {}
		ctx.failures = failures
		local function check(condition: boolean, message: string)
			if not condition then
				table.insert(failures, message)
			end
		end

		-- CAT / ACT on tiles T-A-C.
		local letters = { "T", "A", "C" }
		local allowed = BombRules.allowedWords("CAT", { "CAT", "ACT", "DOG", "TACO" })
		check(sameList(allowed, { "CAT", "ACT" }), "allowed set was " .. table.concat(allowed, ","))
		check(not BombRules.isAccepted(letters, allowed, {}, 1), "T first was accepted")
		check(BombRules.isAccepted(letters, allowed, {}, 3), "C first was refused")
		check(BombRules.isAccepted(letters, allowed, {}, 2), "A first was refused")
		check(BombRules.isAccepted(letters, allowed, { 3 }, 2), "A after C was refused")
		check(not BombRules.isAccepted(letters, allowed, { 3 }, 1), "T after C was accepted (wrong prefix)")
		check(BombRules.isAccepted(letters, allowed, { 3, 2 }, 1), "T after C-A was refused")
		check(not BombRules.isAccepted(letters, allowed, { 3 }, 3), "a locked tile was accepted")
		check(not BombRules.isAccepted(letters, allowed, {}, 0), "tile 0 was accepted")
		check(not BombRules.isAccepted(letters, allowed, {}, 4), "tile 4 was accepted")
		check(not BombRules.isAccepted(letters, allowed, {}, 1.5), "tile 1.5 was accepted")
		check(BombRules.solvedWord(letters, allowed, { 3, 2, 1 }) == "CAT", "C-A-T did not solve CAT")
		check(BombRules.solvedWord(letters, allowed, { 2, 3, 1 }) == "ACT", "A-C-T did not solve ACT")
		check(not BombRules.isSolved(letters, allowed, { 3, 2 }), "two tiles counted as solved")
		check(BombRules.isSolved(letters, allowed, { 3, 2, 1 }), "three tiles were not solved")
		check(BombRules.hintTile(letters, allowed, {}) == 3, "hint at the start was not C (tile 3)")
		check(BombRules.hintTile(letters, allowed, { 2 }) == 3, "hint after A was not C (ACT)")
		check(BombRules.hintTile(letters, allowed, { 3, 2 }) == 1, "hint after C-A was not T")
		check(BombRules.hintTile(letters, allowed, { 3, 2, 1 }) == nil, "a hint was given when solved")

		-- Duplicate letters.
		local dup = { "E", "S", "E" }
		local dupAllowed = BombRules.allowedWords("SEE", { "SEE", "ESE" })
		check(sameList(dupAllowed, { "SEE", "ESE" }), "duplicate allowed set was " .. table.concat(dupAllowed, ","))
		check(BombRules.hintTile(dup, dupAllowed, {}) == 2, "SEE: hint was not S")
		check(BombRules.hintTile(dup, dupAllowed, { 2 }) == 1, "SEE: hint was not the lowest E")
		check(BombRules.hintTile(dup, dupAllowed, { 2, 1 }) == 3, "SEE: last hint was not the other E")
		check(BombRules.isAccepted(dup, dupAllowed, { 2 }, 3), "SEE: the higher E was refused")
		check(BombRules.isSolved(dup, dupAllowed, { 2, 3, 1 }), "SEE: S-E-E in tiles 2,3,1 not solved")
		check(BombRules.isAccepted(dup, dupAllowed, {}, 1), "ESE: E first was refused")

		-- Scramble.
		local scrambleOk = true
		for _ = 1, SCRAMBLE_RUNS do
			local result, found = BombRules.scramble("CAT", allowed)
			local word = table.concat(result)
			if not found or word == "CAT" or word == "ACT" or sorted(word) ~= sorted("CAT") then
				scrambleOk = false
			end
		end
		check(scrambleOk, "a scramble was a solution, or not a permutation, or reported none")
		local _, none = BombRules.scramble("AB", { "AB", "BA" })
		check(not none, "scramble claimed a non-solution when every order is allowed")
		local _, same = BombRules.scramble("OO", { "OO" })
		check(not same, "scramble claimed a non-solution for identical letters")

		-- The shipped pools.
		for _, length in SHIPPED_LENGTHS do
			local pool = BombRules.poolFor(length)
			check(#pool > 0, "no pool words of length " .. length)
			for _, word in pool do
				local words = BombRules.allowedWords(word, pool)
				check(words[1] == word, word .. " is not its own first allowed word")
				for _, other in words do
					check(sorted(other) == sorted(word), other .. " is not an anagram of " .. word)
				end
				local result, found = BombRules.scramble(word, words)
				local scrambled = table.concat(result)
				if found then
					check(table.find(words, scrambled) == nil, word .. " scrambled to a solution " .. scrambled)
				end
			end
		end

		-- Encoding.
		check(sameList(BombRules.decodeWords(BombRules.encodeWords(allowed)), allowed), "word list did not round-trip")
		check(sameList(BombRules.decodeIndices(BombRules.encodeIndices({ 3, 1, 2 })), { 3, 1, 2 }), "indices did not round-trip")
		check(#BombRules.decodeIndices("") == 0, "empty indices did not decode to nothing")
	end,

	verify = function(ctx: any): (boolean, string?)
		if ctx.failures and #ctx.failures > 0 then
			return false, table.concat(ctx.failures, "; ")
		end
		return true, nil
	end,

	teardown = function(_ctx: any) end,
}
