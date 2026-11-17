--!strict

----------------------------------------------------------------------
-- BotVocabulary
----------------------------------------------------------------------
-- What word the playtest bot reaches for. A port of FightSim's
-- `vocabularyFor` and `planWord`, working on the blocks the bot can really
-- see instead of simulated ones: the persona's vocabulary is drawn from the
-- packed dictionary the same way, and a word is chosen the same way.
--
-- Dev tooling: no game system requires this module.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EnergyEconomy = require(Shared.EnergyEconomy)
local PlaytestPersonas = require(Shared.Playtest.PlaytestPersonas)
local Wildcard = require(Shared.Wildcard)

local BotConstants = require(script.Parent.BotConstants)

local WILD = Wildcard.CHAR

export type Visible = { model: Model, letter: string, color: string }
export type Pick = { model: Model, letter: string }
export type Plan = { word: string, picks: { Pick } }

local BotVocabulary = {}

local allWordsByLength: { [number]: { string } }? = nil
local vocabCache: { [string]: { [number]: { string } } } = {}

local function weightedPick(rng: Random, weights: { [any]: number }): any
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng:NextNumber() * total
	local last: any = nil
	for key, w in weights do
		last = key
		roll -= w
		if roll <= 0 then
			return key
		end
	end
	return last
end

local function loadAllWords(): { [number]: { string } }
	if allWordsByLength then
		return allWordsByLength
	end
	local byLength: { [number]: { string } } = {}
	for _, module in Shared.Dictionary.words:GetChildren() do
		if module:IsA("ModuleScript") then
			local packed = require(module) :: string
			for word in packed:gmatch("[^\n]+") do
				if word:match("^%a+$") then
					local bucket = byLength[#word]
					if not bucket then
						bucket = {}
						byLength[#word] = bucket
					end
					table.insert(bucket, word:upper())
				end
			end
		end
	end
	allWordsByLength = byLength
	return byLength
end

-- The words this persona knows, by length: `vocabSize` words drawn evenly
-- across the persona's lengths with a fixed seed.
local function vocabularyFor(persona: PlaytestPersonas.Persona): { [number]: { string } }
	local key = string.format("%d:%d:%d", persona.vocabSize, persona.minLen, persona.maxLen)
	local cached = vocabCache[key]
	if cached then
		return cached
	end
	local all = loadAllWords()
	local total = 0
	for len = persona.minLen, persona.maxLen do
		total += #(all[len] or {})
	end
	local keep = math.min(1, persona.vocabSize / math.max(total, 1))
	local rng = Random.new(persona.vocabSize)
	local vocab: { [number]: { string } } = {}
	for len = persona.minLen, persona.maxLen do
		local bucket: { string } = {}
		for _, word in all[len] or {} do
			if rng:NextNumber() <= keep then
				table.insert(bucket, word)
			end
		end
		vocab[len] = bucket
	end
	vocabCache[key] = vocab
	return vocab
end

-- Load the dictionary now, so the first plan does not stall.
function BotVocabulary.preload(persona: PlaytestPersonas.Persona)
	vocabularyFor(persona)
end

-- First unclaimed block of the list, preferring one of the wanted colour.
local function takeBlock(list: { Visible }?, wanted: string?, claimed: { [Model]: boolean }): Visible?
	if not list then
		return nil
	end
	local fallback: Visible? = nil
	for _, entry in list do
		if not claimed[entry.model] then
			if wanted == nil or entry.color == wanted then
				return entry
			end
			fallback = fallback or entry
		end
	end
	return fallback
end

-- Choose a word spellable from `visible` and the blocks to pop for it, or
-- nil when nothing fits. `mana` is the banked energy by colour, read by the
-- persona's colour preference.
function BotVocabulary.plan(
	persona: PlaytestPersonas.Persona,
	visible: { Visible },
	mana: { [string]: number },
	rng: Random
): Plan?
	local byLetter: { [string]: { Visible } } = {}
	for _, entry in visible do
		local list = byLetter[entry.letter]
		if not list then
			list = {}
			byLetter[entry.letter] = list
		end
		table.insert(list, entry)
	end
	local wildBlocks = byLetter[WILD]

	-- Colour the persona wants this word in, or nil for "whatever".
	local wanted: string? = nil
	if rng:NextNumber() < persona.colorAware then
		wanted = weightedPick(rng, persona.colorWants(mana))
	end

	local vocab = vocabularyFor(persona)
	local best: Plan? = nil
	local bestScore = -math.huge
	for _ = 1, BotConstants.PLAN_LENGTH_TRIES do
		local len = weightedPick(rng, persona.lengthWeights) :: number
		local bucket = vocab[len]
		if bucket and #bucket > 0 then
			for _ = 1, persona.candidates do
				local word = bucket[rng:NextInteger(1, #bucket)]
				local claimed: { [Model]: boolean } = {}
				local picks: { Pick } = {}
				local score = 0
				local ok = true
				for i = 1, len do
					local letter = word:sub(i, i)
					local chosen = takeBlock(byLetter[letter], wanted, claimed)
					if chosen then
						claimed[chosen.model] = true
						table.insert(picks, { model = chosen.model, letter = letter })
						local value = EnergyEconomy.letterValue(letter)
						score += if wanted == nil or chosen.color == wanted then value else value / 2
					else
						local wild = if persona.usesWild then takeBlock(wildBlocks, nil, claimed) else nil
						if not wild then
							ok = false
							break
						end
						claimed[wild.model] = true
						table.insert(picks, { model = wild.model, letter = letter })
					end
				end
				if ok then
					score *= EnergyEconomy.lengthMultiplier(len)
					if score > bestScore then
						bestScore = score
						best = { word = word, picks = picks }
					end
				end
			end
		end
		if best then
			break
		end
	end
	return best
end

return BotVocabulary
