--!strict

----------------------------------------------------------------------
-- MemorizeAction
----------------------------------------------------------------------
-- Phase 2 action — the "Memorize" step of the gameplay loop (see
-- wiki/design/gameplay-loop.md step 5). Validates the buffered word
-- against the dictionary; on success transmutes its value-weighted
-- per-color energy into the reservoirs and clears the buffer. On
-- failure (invalid word) the buffer is also cleared — letters are
-- consumed regardless so the player must re-collect and try again.
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
	-- The concrete dictionary word that was committed, e.g. "DOG".
	word: string?,
	-- What the player actually had buffered, e.g. "D*G". Equal to `word`
	-- when no wildcards were used. Present on failure too, so the HUD can
	-- show what fizzled.
	pattern: string?,
}

export type Scored = {
	-- The concrete dictionary word the tiles resolve to, e.g. "DOG".
	word: string,
	energyByColor: EnergyEconomy.ColorEnergy,
}

local MemorizeAction = {}

-- Resolve a set of buffered tiles into the word they spell and the
-- per-color energy that word is worth, or nil if they spell nothing.
--
-- Pure: holds no state, touches neither a buffer nor a reservoir, and
-- does not mutate the caller's tiles — the resolved letters are stamped
-- onto a copy.
--
-- Extracted from tryMemorize for validated memorize (Phase 5.4) so the
-- server can price a reported memorize with the exact code the client
-- scored it with. Two implementations of "what is this word worth"
-- would drift, and the server's copy is only useful while it agrees
-- with the client's on every legitimate play.
function MemorizeAction.scoreTiles(tiles: { WordBuffer.Tile }): Scored?
	if #tiles == EMPTY_BUFFER_SIZE then
		return nil
	end

	local letters = table.create(#tiles)
	for i, tile in tiles do
		letters[i] = tile.letter
	end
	local pattern = table.concat(letters)

	local word = Dictionary.resolve(pattern, EnergyEconomy.computeWordEnergy)
	if not word then
		return nil
	end

	-- Stamp the resolved letter onto every tile so wildcards score as the
	-- letter they became. resolve() matches on length, so the two strings
	-- are always the same size. Colors are deliberately left alone: a
	-- wild tile stays "wild" so splitByColor still spreads its energy
	-- across all three reservoirs rather than banking it in one.
	local scored = table.create(#tiles)
	for i, tile in tiles do
		scored[i] = { letter = string.sub(word, i, i), color = tile.color }
	end

	return {
		word = word,
		energyByColor = EnergyEconomy.splitByColor(scored),
	}
end

-- Try to commit the buffered word.
--
-- On `buffer:size() == 0`         → `{ ok = false, reason = "empty" }`,
--                                    no state mutation.
-- On unresolvable buffer content  → `{ ok = false, reason = "invalid" }`,
--                                    buffer cleared (letters destroyed).
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

	-- The buffer may hold wildcard tiles, so what it spells is a pattern
	-- ("D*G") rather than a word. resolve() collapses it to the concrete
	-- match worth the most energy — every candidate is the same length,
	-- so maximizing whole-word energy is exactly maximizing the letters
	-- the stars stand in for. Wildcard-free buffers resolve to
	-- themselves via an O(1) lookup, so this is also the plain path.
	local pattern = buffer:asWord()
	local scored = MemorizeAction.scoreTiles(buffer:tiles())
	if not scored then
		log:info("memorize fizzle — invalid word", pattern)
		buffer:clear()
		return { ok = false, reason = "invalid", pattern = pattern }
	end

	local word = scored.word
	local energyByColor = scored.energyByColor

	for color, amount in energyByColor do
		reservoirs:add(color, amount)
	end

	buffer:clear()

	if word ~= pattern then
		log:info("memorize ok —", pattern, "→", word)
	else
		log:info("memorize ok —", word)
	end

	return {
		ok = true,
		energyByColor = energyByColor,
		word = word,
		pattern = pattern,
	}
end

return MemorizeAction
