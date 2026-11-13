--!strict

----------------------------------------------------------------------
-- wordKitFixture
----------------------------------------------------------------------
-- Phase3 word-kit suites: a container for the test's own pools, a default
-- kit volume (a rotated part, so the "row along local X" claim is tested
-- against a real rotation), and the readings the suites make of a kit's
-- blocks. Every pool made through `pool()` is destroyed, with the
-- container, by `destroy()`, which every test calls from teardown.
--
-- Kits sit far above the playable place so nothing a character does can
-- reach them.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local WordKits = require(ReplicatedStorage.Shared.BlockSpawner.WordKits)

local CONTAINER_NAME = "WordKitTestContainer"
local KIT_ORIGIN = Vector3.new(0, 5000, 0)
-- Long enough that a 6-letter row clears TEST_MIN_SPACING per letter.
local KIT_ROW_STUDS = 90
local KIT_THICKNESS_STUDS = 6
local KIT_YAW_DEGREES = 30
local KIT_WORD_LENGTH = 5
-- What a block needs between centres in these tests; the live value is
-- derived from the block prefab.
local TEST_MIN_SPACING = 10
-- Block positions are exact up to float noise.
local LOCAL_TOLERANCE_STUDS = 0.01
local HALF = 0.5

local fixture = {}
fixture.__index = fixture

fixture.KIT_ROW_STUDS = KIT_ROW_STUDS
fixture.KIT_WORD_LENGTH = KIT_WORD_LENGTH
fixture.TEST_MIN_SPACING = TEST_MIN_SPACING
fixture.LOCAL_TOLERANCE_STUDS = LOCAL_TOLERANCE_STUDS

export type Fixture = typeof(setmetatable({} :: {
	arenaId: string,
	container: Folder,
	pools: { BlockSpawner.BlockSpawner },
}, fixture))

function fixture.new(arenaId: string): Fixture
	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME
	container.Parent = workspace
	return setmetatable({ arenaId = arenaId, container = container, pools = {} }, fixture)
end

-- A kit volume: rotated about Y so that local X is not world X.
function fixture.kitBox(_self: Fixture, overrides: { [string]: any }?): BlockSpawner.BoxDef
	local size = Vector3.new(KIT_ROW_STUDS, KIT_THICKNESS_STUDS, KIT_THICKNESS_STUDS)
	local cframe = CFrame.new(KIT_ORIGIN) * CFrame.Angles(0, math.rad(KIT_YAW_DEGREES), 0)
	local box: { [string]: any } = {
		boxMin = KIT_ORIGIN - size * HALF,
		boxMax = KIT_ORIGIN + size * HALF,
		cframe = cframe,
		size = size,
		wordKit = KIT_WORD_LENGTH,
		label = "TestKitVolume",
	}
	for key, value in overrides or {} do
		box[key] = value
	end
	return box :: any
end

-- A pool of this fixture's, in this fixture's arena, parented to its
-- container. Not started.
function fixture.pool(self: Fixture, opts: BlockSpawner.Opts): BlockSpawner.BlockSpawner
	opts.arenaId = opts.arenaId or self.arenaId
	opts.parent = self.container
	if opts.minSpacing == nil then
		opts.minSpacing = TEST_MIN_SPACING
	end
	local pool = BlockSpawner.new(opts)
	table.insert(self.pools, pool)
	return pool
end

function fixture.letterOf(_self: Fixture, block: Model): string
	return tostring(block:GetAttribute(LetterBlocks.LETTER_ATTRIBUTE))
end

function fixture.colorOf(_self: Fixture, block: Model): string
	return tostring(block:GetAttribute(LetterBlocks.COLOR_ATTRIBUTE))
end

-- The distinct colours across `blocks`.
function fixture.colorsOf(self: Fixture, blocks: { Model }): { string }
	local seen: { [string]: boolean } = {}
	local colors: { string } = {}
	for _, block in blocks do
		local color = self:colorOf(block)
		if not seen[color] then
			seen[color] = true
			table.insert(colors, color)
		end
	end
	return colors
end

-- The blocks' letters read from the low end of `cframe`'s local X axis to
-- the high end, e.g. "ABCDE".
function fixture.readingOrder(self: Fixture, blocks: { Model }, cframe: CFrame): string
	local entries: { { x: number, letter: string } } = {}
	for _, block in blocks do
		local localPosition = cframe:PointToObjectSpace(block:GetPivot().Position)
		table.insert(entries, { x = localPosition.X, letter = self:letterOf(block) })
	end
	table.sort(entries, function(a, b)
		return a.x < b.x
	end)
	local letters: { string } = {}
	for _, entry in entries do
		table.insert(letters, entry.letter)
	end
	return table.concat(letters)
end

local function sortedLetters(word: string): string
	local letters: { string } = {}
	for i = 1, #word do
		table.insert(letters, string.sub(word, i, i))
	end
	table.sort(letters)
	return table.concat(letters)
end

-- The curated words `blocks` are an anagram of (empty if none: not a kit).
function fixture.wordsMatching(self: Fixture, blocks: { Model }): { string }
	local letters: { string } = {}
	for _, block in blocks do
		table.insert(letters, self:letterOf(block))
	end
	table.sort(letters)
	local key = table.concat(letters)
	local matches: { string } = {}
	local words = WordKits.words(#blocks)
	for _, word in words do
		if sortedLetters(word) == key then
			table.insert(matches, word)
		end
	end
	return matches
end

-- How many of `blocks` are still in the world.
function fixture.liveCount(_self: Fixture, blocks: { Model }): number
	local live = 0
	for _, block in blocks do
		if block.Parent ~= nil then
			live += 1
		end
	end
	return live
end

function fixture.destroy(self: Fixture)
	for _, pool in self.pools do
		pool:destroy()
	end
	table.clear(self.pools)
	self.container:Destroy()
end

return fixture
