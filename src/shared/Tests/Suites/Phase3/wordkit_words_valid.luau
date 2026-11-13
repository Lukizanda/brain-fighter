--!strict

----------------------------------------------------------------------
-- wordkit_words_valid
----------------------------------------------------------------------
-- The curated kit words are what a player is promised can be spelled, so
-- every one must be: uppercase A to Z, of its stated length, accepted by
-- Dictionary.isWord, not a duplicate, not a palindrome (a palindrome has no
-- order that reads differently from the two ends of the row). Each list has
-- at least MIN_WORDS words. And the design intent that a kit pays for
-- roughly one top-tier cast is pinned: every word's energy as a single
-- colour (EnergyEconomy.computeWordEnergy) lies between MIN_FRACTION and
-- MAX_FRACTION of the T3 spell cost (SpellRegistry), so adding a word that
-- would pay almost nothing, or a free T3 and more, fails here.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dictionary = require(ReplicatedStorage.Shared.Dictionary)
local EnergyEconomy = require(ReplicatedStorage.Shared.EnergyEconomy)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)
local WordKits = require(ReplicatedStorage.Shared.BlockSpawner.WordKits)

local MIN_WORDS = 60
local SUPPORTED_LENGTHS = { 5, 6 }
local T3_TIER = 3
local MIN_FRACTION_OF_T3 = 0.75
local MAX_FRACTION_OF_T3 = 1.5

type Ctx = {
	failure: string?,
	summary: string?,
}

return {
	name = "wordkit_words_valid",

	run = function(ctx: Ctx)
		local t3Cost = SpellRegistry.TIER_COSTS[T3_TIER]
		local minEnergy = t3Cost * MIN_FRACTION_OF_T3
		local maxEnergy = t3Cost * MAX_FRACTION_OF_T3

		local lengths = WordKits.lengths()
		if #lengths ~= #SUPPORTED_LENGTHS then
			ctx.failure = string.format("supported lengths are %s, expected 5 and 6", table.concat(lengths, ", "))
			return
		end
		local parts: { string } = {}
		for index, length in ipairs(SUPPORTED_LENGTHS) do
			if lengths[index] ~= length then
				ctx.failure = string.format("supported lengths are %s, expected 5 and 6", table.concat(lengths, ", "))
				return
			end
			local words = WordKits.words(length)
			if #words < MIN_WORDS then
				ctx.failure = string.format("only %d %d-letter words, need at least %d", #words, length, MIN_WORDS)
				return
			end

			local seen: { [string]: boolean } = {}
			local energyTotal = 0
			for _, word in words do
				if #word ~= length then
					ctx.failure = string.format("%s is in the %d-letter list but has %d letters", word, length, #word)
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
				if energy < minEnergy or energy > maxEnergy then
					ctx.failure = string.format(
						"%s is worth %d energy, outside %.0f-%.0f (%.2f-%.2f of a T3 cast, %d)",
						word, energy, minEnergy, maxEnergy, MIN_FRACTION_OF_T3, MAX_FRACTION_OF_T3, t3Cost
					)
					return
				end
				energyTotal += energy
			end
			table.insert(parts, string.format("%d x %d-letter (mean %.1f energy)", #words, length, energyTotal / #words))
		end

		-- Unsupported lengths are reported as such and map to the nearest.
		if WordKits.isSupportedLength(SUPPORTED_LENGTHS[1] - 1) or WordKits.isSupportedLength(SUPPORTED_LENGTHS[#SUPPORTED_LENGTHS] + 1) then
			ctx.failure = "a length just outside the lists claims to be supported"
			return
		end
		if WordKits.nearestLength(SUPPORTED_LENGTHS[#SUPPORTED_LENGTHS] + 1) ~= SUPPORTED_LENGTHS[#SUPPORTED_LENGTHS]
			or WordKits.nearestLength(SUPPORTED_LENGTHS[1] - 1) ~= SUPPORTED_LENGTHS[1]
		then
			ctx.failure = "nearestLength does not clamp to the supported lengths"
			return
		end
		ctx.summary = table.concat(parts, "; ")
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if ctx.failure then
			return false, ctx.failure
		end
		return true, ctx.summary
	end,
}
