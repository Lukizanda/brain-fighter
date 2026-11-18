--!strict

----------------------------------------------------------------------
-- keykit_words_valid — every key word is a real, short, modestly valued word
----------------------------------------------------------------------
-- PURE: the key-word lists in WordKits (the words hung in front of a gate as
-- its key letters). For each supported key length (3 and 4): enough words to
-- avoid repeats, uppercase A-Z, the right length, accepted by the Dictionary,
-- listed once, not a palindrome, and worth between the cost of a first-tier
-- cast plus a little and less than a top-tier cast would need, so a key word
-- is a small reward for walking up and never the prize behind the gate.
-- Lengths outside the lists are reported unsupported and map to the nearest.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dictionary = require(ReplicatedStorage.Shared.Dictionary)
local EnergyEconomy = require(ReplicatedStorage.Shared.EnergyEconomy)
local WordKits = require(ReplicatedStorage.Shared.BlockSpawner.WordKits)

local MIN_WORDS = 30
local SUPPORTED_LENGTHS = { 3, 4 }
local MIN_ENERGY = 8
local MAX_ENERGY = 14

type Ctx = {
	failure: string?,
	summary: string?,
}

return {
	name = "keykit_words_valid",

	run = function(ctx: Ctx)
		local lengths = WordKits.keyLengths()
		if #lengths ~= #SUPPORTED_LENGTHS then
			ctx.failure = string.format("key lengths are %s, expected 3 and 4", table.concat(lengths, ", "))
			return
		end
		local parts: { string } = {}
		for index, length in ipairs(SUPPORTED_LENGTHS) do
			if lengths[index] ~= length then
				ctx.failure = string.format("key lengths are %s, expected 3 and 4", table.concat(lengths, ", "))
				return
			end
			local words = WordKits.keyWords(length)
			if #words < MIN_WORDS then
				ctx.failure = string.format("only %d %d-letter key words, need at least %d", #words, length, MIN_WORDS)
				return
			end
			local seen: { [string]: boolean } = {}
			local energyTotal = 0
			for _, word in words do
				if #word ~= length then
					ctx.failure = string.format("%s is in the %d-letter key list but has %d letters", word, length, #word)
					return
				end
				if string.match(word, "^[A-Z]+$") == nil then
					ctx.failure = string.format("%s is not uppercase A-Z", word)
					return
				end
				if not Dictionary.isWord(word) then
					ctx.failure = string.format("%s is not accepted by Dictionary.isWord", word)
					return
				end
				if seen[word] then
					ctx.failure = string.format("%s is listed twice", word)
					return
				end
				seen[word] = true
				if word == string.reverse(word) then
					ctx.failure = string.format("%s is a palindrome", word)
					return
				end
				local energy = EnergyEconomy.computeWordEnergy(word)
				if energy < MIN_ENERGY or energy > MAX_ENERGY then
					ctx.failure = string.format("%s is worth %d energy, outside %d-%d", word, energy, MIN_ENERGY, MAX_ENERGY)
					return
				end
				energyTotal += energy
			end
			table.insert(parts, string.format("%d x %d-letter (mean %.1f energy)", #words, length, energyTotal / #words))
		end

		if WordKits.isSupportedKeyLength(SUPPORTED_LENGTHS[1] - 1) or WordKits.isSupportedKeyLength(SUPPORTED_LENGTHS[#SUPPORTED_LENGTHS] + 1) then
			ctx.failure = "a length just outside the key lists claims to be supported"
			return
		end
		if WordKits.nearestKeyLength(SUPPORTED_LENGTHS[#SUPPORTED_LENGTHS] + 1) ~= SUPPORTED_LENGTHS[#SUPPORTED_LENGTHS]
			or WordKits.nearestKeyLength(SUPPORTED_LENGTHS[1] - 1) ~= SUPPORTED_LENGTHS[1]
		then
			ctx.failure = "nearestKeyLength does not clamp to the supported lengths"
			return
		end
		ctx.summary = table.concat(parts, "; ")
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return ctx.summary ~= nil, ctx.summary or "the test did not finish"
	end,
}
