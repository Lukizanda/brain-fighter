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

local DEFAULT_CAP = 12
local FIRST_INDEX = 1
local APPEND_FULL_LOG_INTERVAL = 30

local VALID_COLORS: { [string]: boolean } = {
	red = true,
	green = true,
	blue = true,
}

export type Color = "red" | "green" | "blue"
export type Tile = { letter: string, color: Color }

local WordBuffer = {}
WordBuffer.__index = WordBuffer

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
