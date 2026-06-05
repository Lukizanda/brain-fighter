--!strict

--[[
	EnergyReservoirs — pure-Luau state container for the three per-color
	energy bars (red / green / blue) Brain Fighter's wizard accumulates by
	Memorizing words.

	State only. No knowledge of tiers, spells, words, or Roblox instances
	beyond the BindableEvent used for the `changed` signal. Tier thresholds
	live in `SpellRegistry`; this module just stores numbers and emits a
	signal when one changes.

	Usage:
		local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)
		local reservoirs = EnergyReservoirs.new()

		reservoirs.changed:Connect(function(color)
			print(color, reservoirs:get(color))
		end)

		reservoirs:add("red", 25)           -- caps at CAP_PER_COLOR per color
		reservoirs:canAfford("red", 10)     -- true
		reservoirs:drain("red", 10)         -- returns true; bar -= 10
		reservoirs:snapshot()               -- { red = 15, green = 0, blue = 0 }
		reservoirs:destroy()

	`.changed` is a `BindableEvent.Event` — Roblox runs these connections in
	Deferred mode by default, so handlers fire on the next resumption cycle
	rather than synchronously inside `:add` / `:drain`. Read state via
	`:get(color)` inside the handler; do not assume the handler has run by
	the time `:add` / `:drain` return.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local log = Logger.new("EnergyReservoirs")

-- Cap per color. 3× the T3 cost (20) — holds enough headroom to stockpile a
-- few big casts without letting energy accumulate indefinitely and trivialize
-- encounters. Sourced from `design/gameplay-loop.md` "Spell economy".
local CAP_PER_COLOR = 60

-- Canonical color list. Used for `:snapshot()` order, validation, and
-- per-color state initialization. If a new color is ever added, this is the
-- single point of truth.
local COLORS = { "red", "green", "blue" }

export type Color = "red" | "green" | "blue"

export type Snapshot = {
	red: number,
	green: number,
	blue: number,
}

local EnergyReservoirs = {}
EnergyReservoirs.__index = EnergyReservoirs

export type EnergyReservoirs = typeof(setmetatable(
	{} :: {
		_values: { [string]: number },
		_changedEvent: BindableEvent,
		changed: RBXScriptSignal,
	},
	EnergyReservoirs
))

EnergyReservoirs.CAP_PER_COLOR = CAP_PER_COLOR
EnergyReservoirs.COLORS = COLORS

local function isKnownColor(color: string): boolean
	for _, known in COLORS do
		if known == color then
			return true
		end
	end
	return false
end

local function assertColor(color: string)
	if not isKnownColor(color) then
		local message = string.format(
			"EnergyReservoirs: unknown color %q (expected one of: %s)",
			tostring(color),
			table.concat(COLORS, ", ")
		)
		log:warn(message)
		error(message, 3)
	end
end

function EnergyReservoirs.new(): EnergyReservoirs
	local changedEvent = Instance.new("BindableEvent")
	changedEvent.Name = "EnergyReservoirsChanged"

	local values: { [string]: number } = {}
	for _, color in COLORS do
		values[color] = 0
	end

	local self = setmetatable({
		_values = values,
		_changedEvent = changedEvent,
		changed = changedEvent.Event,
	}, EnergyReservoirs)

	return self
end

function EnergyReservoirs:get(color: Color): number
	assertColor(color)
	return self._values[color]
end

-- Add `amount` to `color`. Caps at CAP_PER_COLOR; overflow discarded.
-- Non-positive `amount` is a no-op (no signal fire), so callers don't have
-- to guard against zero-energy words.
function EnergyReservoirs:add(color: Color, amount: number)
	assertColor(color)
	if amount <= 0 then
		return
	end

	local current = self._values[color]
	local nextValue = math.min(current + amount, CAP_PER_COLOR)
	if nextValue == current then
		return
	end

	self._values[color] = nextValue
	self._changedEvent:Fire(color)
end

function EnergyReservoirs:canAfford(color: Color, n: number): boolean
	assertColor(color)
	return self._values[color] >= n
end

-- Drain `n` from `color`. Returns false (and leaves the value untouched) if
-- the bar can't afford the full cost — partial drains don't exist. The
-- `changed` signal only fires on a successful drain.
function EnergyReservoirs:drain(color: Color, n: number): boolean
	assertColor(color)
	local current = self._values[color]
	if current < n then
		return false
	end

	self._values[color] = current - n
	self._changedEvent:Fire(color)
	return true
end

-- Defensive copy of current state. Callers can mutate the returned table
-- without affecting the reservoir.
function EnergyReservoirs:snapshot(): Snapshot
	return {
		red = self._values.red,
		green = self._values.green,
		blue = self._values.blue,
	}
end

function EnergyReservoirs:destroy()
	if self._changedEvent then
		self._changedEvent:Destroy()
		self._changedEvent = nil :: any
		self.changed = nil :: any
	end
end

return EnergyReservoirs
