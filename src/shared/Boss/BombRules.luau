--!strict

----------------------------------------------------------------------
-- BombRules
----------------------------------------------------------------------
-- The scramble bomb's pure rules (wiki/design/scramble-bomb.md § The rule),
-- shared by the server (BossBombs judges with them) and every client (which
-- predicts accept / reject and finds the hint with the same functions;
-- wiki/concepts/ClientServerPredictionParity.md). No Instances, no clock, no
-- remotes: tile letters, the allowed words and the accepted tile indices in,
-- an answer out.
--
-- Tiles are numbered 1..N in orbit order; `letters` is the list of their
-- letters (uppercase). `accepted` is the tile indices already locked, in tap
-- order. A tap is accepted when the letters accepted so far plus this tile's
-- begin at least one ALLOWED word that uses exactly the bomb's letters (T-A-C
-- is solved by CAT and, if it is allowed, ACT).
--
-- The allowed words are the permutations of the chosen word's letters that
-- are in the key-word and kit word lists (WordKits), NOT the whole
-- dictionary, which has no filter for words unsuitable for children. The
-- server publishes them on the bomb so a client can run these functions.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WordKits = require(ReplicatedStorage.Shared.BlockSpawner.WordKits)
local BombConstants = require(script.Parent.BombConstants)

local BombRules = {}

-- "CAT" -> { "C", "A", "T" }.
function BombRules.lettersOf(word: string): { string }
	local out: { string } = {}
	for index = 1, #word do
		table.insert(out, string.sub(word, index, index))
	end
	return out
end

-- The letters of a word, sorted and joined: two words are anagrams exactly
-- when this is equal.
local function signature(word: string): string
	local letters = BombRules.lettersOf(word)
	table.sort(letters)
	return table.concat(letters)
end

-- The words a bomb of `length` may be built from and solved with: the key
-- words and the kit words of that length, uppercase, without repeats.
function BombRules.poolFor(length: number): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, list in { WordKits.keyWords(length), WordKits.words(length) } do
		for _, word in list do
			if not seen[word] then
				seen[word] = true
				table.insert(out, word)
			end
		end
	end
	return out
end

-- The allowed solution words for a bomb built from `word`: `word` itself
-- first, then every other word of `pool` (default: poolFor(#word)) that is a
-- permutation of its letters, in alphabetical order.
function BombRules.allowedWords(word: string, pool: { string }?): { string }
	local source = pool or BombRules.poolFor(#word)
	local wanted = signature(word)
	local others: { string } = {}
	local seen: { [string]: boolean } = { [word] = true }
	for _, candidate in source do
		if not seen[candidate] and #candidate == #word and signature(candidate) == wanted then
			seen[candidate] = true
			table.insert(others, candidate)
		end
	end
	table.sort(others)
	table.insert(others, 1, word)
	return others
end

local function contains(list: { string }, value: string): boolean
	return table.find(list, value) ~= nil
end

-- A scrambled order of `word`'s letters that is neither the word nor any of
-- `allowed`. Random shuffles first (up to SCRAMBLE_MAX_ATTEMPTS), then a scan
-- of every distinct order, so one is found whenever one exists. The second
-- value is false when none exists (every order is allowed, or the letters are
-- all the same): the letters come back shuffled anyway and the bomb is
-- solvable at once. `rng` returns an integer in [1, n] (default math.random).
function BombRules.scramble(word: string, allowed: { string }, rng: ((number) -> number)?): ({ string }, boolean)
	local pick = rng or function(n: number): number
		return math.random(1, n)
	end
	local letters = BombRules.lettersOf(word)
	for _ = 1, BombConstants.SCRAMBLE_MAX_ATTEMPTS do
		for i = #letters, 2, -1 do
			local j = pick(i)
			letters[i], letters[j] = letters[j], letters[i]
		end
		local arranged = table.concat(letters)
		if arranged ~= word and not contains(allowed, arranged) then
			return letters, true
		end
	end

	-- Exhaustive: every distinct order of the letters.
	local result: { found: { string }? } = { found = nil }
	local function permute(prefix: string, remaining: { string })
		if result.found ~= nil then
			return
		end
		if #remaining == 0 then
			if prefix ~= word and not contains(allowed, prefix) then
				result.found = BombRules.lettersOf(prefix)
			end
			return
		end
		local tried: { [string]: boolean } = {}
		for index, letter in remaining do
			if not tried[letter] then
				tried[letter] = true
				local rest = table.clone(remaining)
				table.remove(rest, index)
				permute(prefix .. letter, rest)
			end
		end
	end
	permute("", BombRules.lettersOf(word))
	local foundLetters = result.found
	if foundLetters ~= nil then
		return foundLetters, true
	end
	return letters, false
end

-- The letters of the tiles in `accepted`, in tap order, joined.
function BombRules.spelled(letters: { string }, accepted: { number }): string
	local out: { string } = {}
	for _, tile in accepted do
		table.insert(out, letters[tile] or "")
	end
	return table.concat(out)
end

local function isLocked(accepted: { number }, tile: number): boolean
	return table.find(accepted, tile) ~= nil
end

-- Does `word` use exactly the bomb's letters?
local function usesBombLetters(word: string, letters: { string }): boolean
	return #word == #letters and signature(word) == signature(table.concat(letters))
end

-- Is tapping tile `tile` accepted now? False for a tile that does not exist,
-- one already locked, or one that would take the spelling off every allowed
-- word. (A locked tile is a no-op, not a rejection: use isLocked-aware
-- callers via `isLockedTile`.)
function BombRules.isAccepted(letters: { string }, allowed: { string }, accepted: { number }, tile: number): boolean
	if tile ~= math.floor(tile) or tile < 1 or tile > #letters or isLocked(accepted, tile) then
		return false
	end
	local prefix = BombRules.spelled(letters, accepted) .. letters[tile]
	for _, word in allowed do
		if usesBombLetters(word, letters) and string.sub(word, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- Is `tile` already locked?
function BombRules.isLockedTile(accepted: { number }, tile: number): boolean
	return isLocked(accepted, tile)
end

-- The allowed word the accepted taps spelled, once every tile is accepted;
-- nil before that.
function BombRules.solvedWord(letters: { string }, allowed: { string }, accepted: { number }): string?
	if #accepted ~= #letters then
		return nil
	end
	local spelled = BombRules.spelled(letters, accepted)
	for _, word in allowed do
		if word == spelled and usesBombLetters(word, letters) then
			return word
		end
	end
	return nil
end

function BombRules.isSolved(letters: { string }, allowed: { string }, accepted: { number }): boolean
	return BombRules.solvedWord(letters, allowed, accepted) ~= nil
end

-- The tile to light: the next tile of the first allowed word that agrees with
-- the progress so far. With duplicate letters, the lowest unlocked index.
-- Nil when solved or when no allowed word agrees.
function BombRules.hintTile(letters: { string }, allowed: { string }, accepted: { number }): number?
	if #accepted >= #letters then
		return nil
	end
	local spelled = BombRules.spelled(letters, accepted)
	for _, word in allowed do
		if usesBombLetters(word, letters) and string.sub(word, 1, #spelled) == spelled then
			local nextLetter = string.sub(word, #spelled + 1, #spelled + 1)
			for index, letter in letters do
				if letter == nextLetter and not isLocked(accepted, index) then
					return index
				end
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Published-attribute encoding (attributes cannot hold tables)
----------------------------------------------------------------------

local function split(text: string): { string }
	local out: { string } = {}
	if text == "" then
		return out
	end
	for part in string.gmatch(text, "[^" .. BombConstants.LIST_SEPARATOR .. "]+") do
		table.insert(out, part)
	end
	return out
end

function BombRules.encodeWords(words: { string }): string
	return table.concat(words, BombConstants.LIST_SEPARATOR)
end

function BombRules.decodeWords(text: string): { string }
	return split(text)
end

function BombRules.encodeIndices(indices: { number }): string
	local parts: { string } = {}
	for _, index in indices do
		table.insert(parts, tostring(index))
	end
	return table.concat(parts, BombConstants.LIST_SEPARATOR)
end

function BombRules.decodeIndices(text: string): { number }
	local out: { number } = {}
	for _, part in split(text) do
		local number = tonumber(part)
		if number ~= nil then
			table.insert(out, number)
		end
	end
	return out
end

return BombRules
