--!strict

----------------------------------------------------------------------
-- MemorizeAction
----------------------------------------------------------------------
-- Phase 2 action — the "Memorize" step of the gameplay loop (see
-- wiki/design/gameplay-loop.md step 5). Validates the buffered word
-- against the dictionary; on success transmutes its value-weighted
-- per-color energy into the reservoirs and clears the buffer. On
-- failure the buffer is preserved so the player can correct typos
-- without retyping.
--
-- This module is the seam between four Phase 1 modules — it does no
-- state of its own:
--   - Dictionary       — validates the word
--   - EnergyEconomy    — computes the per-color split
--   - WordBuffer       — provides the tiles and word; is cleared
--   - EnergyReservoirs — receives the per-color energy
--
-- See wiki/systems/MemorizeAction.md for the contract.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Dictionary = require(ReplicatedStorage.Shared.Dictionary)
local EnergyEconomy = require(ReplicatedStorage.Shared.EnergyEconomy)
local WordBuffer = require(ReplicatedStorage.Shared.WordBuffer)
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)

local log = Logger.new("MemorizeAction")

local EMPTY_BUFFER_SIZE = 0

export type Reason = "empty" | "invalid"

export type Result = {
	ok: boolean,
	reason: Reason?,
	energyByColor: EnergyEconomy.ColorEnergy?,
	word: string?,
}

local MemorizeAction = {}

-- Try to commit the buffered word.
--
-- On `buffer:size() == 0`        → `{ ok = false, reason = "empty" }`,
--                                    no state mutation.
-- On `not Dictionary.isWord(...)` → `{ ok = false, reason = "invalid" }`,
--                                    buffer preserved for typo correction.
-- Otherwise: split the buffered tiles into per-color energy via
-- EnergyEconomy.splitByColor (floor-reconciled so the per-color sums
-- equal the whole-word energy), add each (color, amount) to the
-- reservoirs, then clear the buffer. Returns:
--   `{ ok = true, energyByColor = split, word = word }`.
--
-- Order matters: the split is computed BEFORE clear(), because
-- `tiles()` reads the buffer's internal state. Reservoirs are updated
-- before the clear too, but only because there's no observable
-- consequence to the ordering between them — both are required, and
-- failures inside `:add` would be a contract violation by
-- EnergyReservoirs (which it's specified not to do).
function MemorizeAction.tryMemorize(
	buffer: WordBuffer.WordBuffer,
	reservoirs: EnergyReservoirs.EnergyReservoirs
): Result
	if buffer:size() == EMPTY_BUFFER_SIZE then
		log:info("memorize fizzle — empty buffer")
		return { ok = false, reason = "empty" }
	end

	local word = buffer:asWord()
	if not Dictionary.isWord(word) then
		log:info("memorize fizzle — invalid word", word)
		return { ok = false, reason = "invalid" }
	end

	local tiles = buffer:tiles()
	local energyByColor = EnergyEconomy.splitByColor(tiles)

	for color, amount in energyByColor do
		reservoirs:add(color, amount)
	end

	buffer:clear()

	log:info("memorize ok —", word)

	return {
		ok = true,
		energyByColor = energyByColor,
		word = word,
	}
end

return MemorizeAction
