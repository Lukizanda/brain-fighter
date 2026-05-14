--!strict

----------------------------------------------------------------------
-- EnergyEconomy smoke test
----------------------------------------------------------------------
-- Pinned ground truth: every entry below MUST match
-- wiki/design/gameplay-loop.md's "Worked examples" and "Color-split
-- worked examples" tables. If a value here drifts from the wiki, the
-- formula is wrong — fix the implementation, not the table.
--
-- Required at module load — failing asserts will error out in the
-- console (TestRunner integration is overkill for a pure formula
-- module; the asserts ARE the test). Returns a summary table when
-- everything passes:
--   { passed = N, failed = 0, results = { ... } }
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local EnergyEconomy = require(ReplicatedStorage.Shared.EnergyEconomy)

local log = Logger.new("EnergyEconomy.tests")

type WordCase = {
	word: string,
	expectedEnergy: number,
}

type ColorSplitCase = {
	label: string,
	tiles: { EnergyEconomy.Tile },
	expectedSplit: EnergyEconomy.ColorEnergy,
	expectedTotal: number,
}

local WORD_CASES: { WordCase } = {
	{ word = "CAT", expectedEnergy = 5 },
	{ word = "FIRE", expectedEnergy = 7 },
	{ word = "ROCK", expectedEnergy = 10 },
	{ word = "FLAME", expectedEnergy = 15 },
	{ word = "DRAGON", expectedEnergy = 12 },
	{ word = "FROZEN", expectedEnergy = 27 },
	{ word = "FIREBALL", expectedEnergy = 26 },
	{ word = "LIGHTNING", expectedEnergy = 42 },
	{ word = "EARTHQUAKES", expectedEnergy = 81 },
	{ word = "CHARACTERIZE", expectedEnergy = 84 },
}

local COLOR_SPLIT_CASES: { ColorSplitCase } = {
	{
		label = "FLAME (F-L-M red, A-E green)",
		tiles = {
			{ letter = "F", color = "red" },
			{ letter = "L", color = "red" },
			{ letter = "A", color = "green" },
			{ letter = "M", color = "red" },
			{ letter = "E", color = "green" },
		},
		expectedSplit = { red = 12, green = 3 },
		expectedTotal = 15,
	},
	{
		label = "FROZEN (F-R-Z red, O-E-N blue)",
		tiles = {
			{ letter = "F", color = "red" },
			{ letter = "R", color = "red" },
			{ letter = "O", color = "blue" },
			{ letter = "Z", color = "red" },
			{ letter = "E", color = "blue" },
			{ letter = "N", color = "blue" },
		},
		expectedSplit = { red = 22, blue = 5 },
		expectedTotal = 27,
	},
	{
		label = "ROCK (R-O red, C-K blue)",
		tiles = {
			{ letter = "R", color = "red" },
			{ letter = "O", color = "red" },
			{ letter = "C", color = "blue" },
			{ letter = "K", color = "blue" },
		},
		expectedSplit = { red = 2, blue = 8 },
		expectedTotal = 10,
	},
}

type CaseResult = {
	label: string,
	passed: boolean,
	message: string?,
}

local function checkWordCase(case: WordCase): CaseResult
	local actual = EnergyEconomy.computeWordEnergy(case.word)
	if actual == case.expectedEnergy then
		return { label = case.word, passed = true }
	end
	return {
		label = case.word,
		passed = false,
		message = string.format(
			"expected %d, got %d",
			case.expectedEnergy,
			actual
		),
	}
end

local function splitsEqual(
	actual: EnergyEconomy.ColorEnergy,
	expected: EnergyEconomy.ColorEnergy
): (boolean, string?)
	for color, expectedValue in expected do
		if actual[color] ~= expectedValue then
			return false, string.format(
				"%s: expected %d, got %s",
				color,
				expectedValue,
				tostring(actual[color])
			)
		end
	end
	for color, actualValue in actual do
		if expected[color] == nil and actualValue ~= 0 then
			return false, string.format(
				"%s: unexpected entry with value %d",
				color,
				actualValue
			)
		end
	end
	return true, nil
end

local function sumSplit(split: EnergyEconomy.ColorEnergy): number
	local s = 0
	for _, v in split do
		s += v
	end
	return s
end

local function checkColorSplitCase(case: ColorSplitCase): CaseResult
	local actual = EnergyEconomy.splitByColor(case.tiles)
	local ok, msg = splitsEqual(actual, case.expectedSplit)
	if not ok then
		return { label = case.label, passed = false, message = msg }
	end

	local total = sumSplit(actual)
	if total ~= case.expectedTotal then
		return {
			label = case.label,
			passed = false,
			message = string.format(
				"sum mismatch: expected %d, got %d",
				case.expectedTotal,
				total
			),
		}
	end

	return { label = case.label, passed = true }
end

local function runAll()
	local results: { CaseResult } = {}
	local passed = 0
	local failed = 0

	for _, case in WORD_CASES do
		local result = checkWordCase(case)
		table.insert(results, result)
		if result.passed then
			passed += 1
			log:info(string.format("[PASS] %s = %d", case.word, case.expectedEnergy))
		else
			failed += 1
			log:warn(string.format("[FAIL] %s — %s", case.word, result.message or "?"))
		end
	end

	for _, case in COLOR_SPLIT_CASES do
		local result = checkColorSplitCase(case)
		table.insert(results, result)
		if result.passed then
			passed += 1
			log:info(string.format("[PASS] split %s", case.label))
		else
			failed += 1
			log:warn(string.format("[FAIL] split %s — %s", case.label, result.message or "?"))
		end
	end

	if failed > 0 then
		error(string.format(
			"EnergyEconomy smoke test: %d/%d cases failed — see warnings above",
			failed,
			passed + failed
		), 2)
	end

	log:info(string.format("[SUITE PASS] %d/%d cases passed", passed, passed + failed))

	return {
		passed = passed,
		failed = failed,
		results = results,
	}
end

return runAll()
