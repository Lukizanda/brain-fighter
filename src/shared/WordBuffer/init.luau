--!strict

----------------------------------------------------------------------
-- WordBuffer
----------------------------------------------------------------------
-- Pure-Luau state container for the 12-slot word buffer described in
-- wiki/design/gameplay-loop.md "Buffer & input". Each tile remembers
-- the color of the letter-block it came from so MemorizeAction can
-- split energy value-weighted across the three color reservoirs.
--
-- Append-on-shot, drag-to-reorder, double-tap-to-destroy semantics —
-- this module owns the data; the HUD owns presentation.
--
-- See also: wiki/systems/WordBuffer.md
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)

local DEFAULT_CAP = 12
local FIRST_INDEX = 1
local APPEND_FULL_LOG_INTERVAL = 30

-- "wild" is the gold ★ block (see [[Wildcard]]). It is a legal tile
-- color but not a reservoir color — EnergyEconomy spreads its energy
-- across red/green/blue rather than banking it into a single one.
local VALID_COLORS: { [string]: boolean } = {
	red = true,
	green = true,
	blue = true,
	[Wildcard.COLOR] = true,
}

export type Color = "red" | "green" | "blue" | "wild"
export type Tile = { letter: string, color: Color }

local WordBuffer = {}
WordBuffer.__index = WordBuffer

-- Exported so the server's economy ledger can express "well past what a
-- buffer can hold" against the real capacity instead of a copy of 12.
WordBuffer.DEFAULT_CAP = DEFAULT_CAP

export type WordBuffer = typeof(setmetatable(
	{} :: {
		_cap: number,
		_tiles: { Tile },
		_log: Logger.Logger,
		_changedSignal: BindableEvent,
		_destroyed: boolean,
		changed: RBXScriptSignal,
	},
	WordBuffer
))

function WordBuffer.new(cap: number?): WordBuffer
	local self = setmetatable({}, WordBuffer)
	self._cap = cap or DEFAULT_CAP
	self._tiles = {}
	self._log = Logger.new("WordBuffer")
	self._changedSignal = Instance.new("BindableEvent")
	self.changed = self._changedSignal.Event
	self._destroyed = false
	return (self :: any) :: WordBuffer
end

function WordBuffer:size(): number
	return #self._tiles
end

function WordBuffer:isFull(): boolean
	return #self._tiles >= self._cap
end

function WordBuffer:append(letter: string, color: Color): boolean
	if self:isFull() then
		self._log:warnThrottled("append_full", APPEND_FULL_LOG_INTERVAL, "append rejected — buffer full")
		return false
	end
	if not VALID_COLORS[color] then
		self._log:warn(string.format("append rejected — invalid color '%s'", tostring(color)))
		return false
	end
	table.insert(self._tiles, { letter = letter, color = color })
	self._changedSignal:Fire()
	return true
end

function WordBuffer:remove(index: number)
	local n = #self._tiles
	if index < FIRST_INDEX or index > n then
		self._log:warn(string.format("remove rejected — index %d out of range [%d,%d]", index, FIRST_INDEX, n))
		return
	end
	table.remove(self._tiles, index)
	self._changedSignal:Fire()
end

-- Take back one tile that turned out never to have been earned.
--
-- The append that put it here is optimistic: BlockTapController adds the
-- letter before the server has agreed the block was theirs to take. In
-- solo play that is always safe, because nobody else can take your block.
-- In PvP the loser of a same-frame race for one block must give the
-- letter back, or they keep a phantom tile for the rest of the round.
--
-- Removes the LAST tile matching (letter, color), and this is the whole
-- subtlety:
--
--   * Not `remove(size())`. The round trip is long enough for the player
--     to have tapped two more blocks, and popping the newest slot would
--     confiscate a letter they did earn.
--   * Not the index the tile was appended at either — `reorder` and
--     `remove` both shuffle indices, so a remembered index goes stale the
--     moment the player touches their buffer.
--   * Last-matching rather than first: appends land at the end, so absent
--     any reordering the phantom *is* the last match. Once the player has
--     reordered, two tiles of the same letter and colour are genuinely
--     indistinguishable — the buffer has no tile identity — so any match
--     is as defensible as another, and the newest is the best guess at
--     the one that just arrived.
--
-- Returns false and changes nothing when there is no match: the player
-- may have already destroyed the tile themselves, and a rejection that
-- arrives afterwards must be a no-op rather than eat an innocent letter.
function WordBuffer:removeLastMatching(letter: string, color: Color): boolean
	for index = #self._tiles, FIRST_INDEX, -1 do
		local tile = self._tiles[index]
		if tile.letter == letter and tile.color == color then
			table.remove(self._tiles, index)
			self._changedSignal:Fire()
			return true
		end
	end
	return false
end

function WordBuffer:reorder(fromIdx: number, toIdx: number)
	local n = #self._tiles
	if fromIdx < FIRST_INDEX or fromIdx > n or toIdx < FIRST_INDEX or toIdx > n then
		self._log:warn(
			string.format("reorder rejected — indices (%d → %d) out of range [%d,%d]", fromIdx, toIdx, FIRST_INDEX, n)
		)
		return
	end
	if fromIdx == toIdx then
		return
	end
	local tile = table.remove(self._tiles, fromIdx)
	table.insert(self._tiles, toIdx, tile)
	self._changedSignal:Fire()
end

function WordBuffer:clear()
	-- Skip firing when already empty so subscribers don't get spurious
	-- no-op notifications (e.g. boss-defeat hooks calling clear() on
	-- every level reset would chain into HUD redraws for nothing).
	if #self._tiles == 0 then
		return
	end
	table.clear(self._tiles)
	self._changedSignal:Fire()
end

-- Uppercased concatenation of the buffered letters. Wildcard tiles
-- contribute their raw character, so this may be a pattern ("D*G")
-- rather than a word — pass it through Dictionary.resolve to get the
-- concrete word.
function WordBuffer:asWord(): string
	local letters = table.create(#self._tiles)
	for i, tile in self._tiles do
		letters[i] = tile.letter
	end
	return string.upper(table.concat(letters))
end

function WordBuffer:colorBag(): { [Color]: number }
	local bag: { [Color]: number } = {}
	for _, tile in self._tiles do
		bag[tile.color] = (bag[tile.color] or 0) + 1
	end
	return bag
end

function WordBuffer:tiles(): { Tile }
	local copy = table.create(#self._tiles)
	for i, tile in self._tiles do
		copy[i] = { letter = tile.letter, color = tile.color }
	end
	return copy
end

function WordBuffer:destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._changedSignal:Destroy()
	table.clear(self._tiles)
end

return WordBuffer
