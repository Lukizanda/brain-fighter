--!strict

----------------------------------------------------------------------
-- ledger_prices_a_cast — validated memorize, end to end (Phase 5.4)
----------------------------------------------------------------------
-- Drives EnergyLedger directly rather than through the two remotes: the
-- interesting inputs are payloads a well-behaved client cannot send, and
-- the ledger is keyed by UserId precisely so a suite can stand in for a
-- player without a Players entry.
--
-- The asymmetry is the thing under test. Every approximation in this
-- design errs toward letting a cheat through rather than refusing an
-- honest cast, so a suite that only proved "cheats are caught" would
-- pass just as happily on a ledger that refused everything. Both halves
-- are asserted for that reason.
--
-- These modules live under ReplicatedStorage but the autorunner is a
-- server Script, so reaching into ServerScriptService is valid here.
----------------------------------------------------------------------

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Dictionary       = require(ReplicatedStorage.Shared.Dictionary)
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)
local SpellRegistry    = require(ReplicatedStorage.Shared.SpellRegistry)
local Wildcard         = require(ReplicatedStorage.Shared.Wildcard)

local EnergyLedger = require(ServerScriptService.Server.Economy.EnergyLedger)

local PLAYER = 1001
local OTHER_PLAYER = 1002

local CREDIT_ON_FAILURE = true
local ENFORCE = false

-- "CAT" is all-red: three tiles, one colour, and a word the dictionary
-- has had pinned since Phase 1.
local function redTiles(word: string): { { letter: string, color: string } }
	local tiles = {}
	for i = 1, #word do
		table.insert(tiles, { letter = string.sub(word, i, i), color = "red" })
	end
	return tiles
end

local function creditWord(userId: number, word: string)
	for i = 1, #word do
		EnergyLedger.creditBlock(userId, string.sub(word, i, i), "red")
	end
end

return {
	name = "ledger_prices_a_cast",

	setup = function()
		EnergyLedger.reset()
	end,

	teardown = function()
		EnergyLedger.reset()
	end,

	verify = function(): (boolean, string?)
		----------------------------------------------------------------
		-- 1. A cast with nothing earned is refused.
		----------------------------------------------------------------
		local ok = EnergyLedger.checkCast(PLAYER, "red", SpellRegistry.getSpell("red", 1).cost)
		if ok then
			return false, "priced a cast for a player who has taken no blocks"
		end

		----------------------------------------------------------------
		-- 2. Shooting alone earns nothing. This is the whole reason the
		--    energy-ceiling ledger was rejected — a design that credited
		--    block traffic would pass here, and passing here is the bug.
		----------------------------------------------------------------
		creditWord(PLAYER, "CAT")
		ok = EnergyLedger.checkCast(PLAYER, "red", SpellRegistry.getSpell("red", 1).cost)
		if ok then
			return false, "shooting blocks alone paid for a cast — spelling is optional"
		end

		----------------------------------------------------------------
		-- 3. Memorizing what you actually took credits real energy.
		----------------------------------------------------------------
		local verdict = EnergyLedger.reportMemorize(PLAYER, redTiles("CAT"), ENFORCE)
		if not verdict.ok then
			return false, string.format("honest memorize refused — %s", verdict.reason or "?")
		end
		if verdict.word ~= "CAT" then
			return false, string.format("resolved %s, expected CAT", tostring(verdict.word))
		end

		local snapshot = EnergyLedger.snapshot(PLAYER)
		if (snapshot.ceiling.red or 0) <= 0 then
			return false, "a valid memorize credited no red energy"
		end
		if snapshot.heldCount ~= 0 then
			return false, string.format("memorize left %d letters held", snapshot.heldCount)
		end

		----------------------------------------------------------------
		-- 4. Claiming a word you never took the letters for is refused,
		--    even though it is a perfectly real dictionary word.
		----------------------------------------------------------------
		creditWord(OTHER_PLAYER, "CAT")
		verdict = EnergyLedger.reportMemorize(OTHER_PLAYER, redTiles("DOG"), ENFORCE)
		if verdict.ok then
			return false, "credited a word whose letters were never taken"
		end
		if verdict.fizzle then
			return false, "a coverage failure was reported as an ordinary fizzle"
		end

		----------------------------------------------------------------
		-- 5. Letters you did take but that spell nothing are a fizzle,
		--    not a cheat — and they still clear, because the client's
		--    buffer cleared on the same event.
		----------------------------------------------------------------
		EnergyLedger.reset()
		creditWord(PLAYER, "XQZ")
		verdict = EnergyLedger.reportMemorize(PLAYER, redTiles("XQZ"), ENFORCE)
		if verdict.ok then
			return false, "credited energy for letters that spell no word"
		end
		if not verdict.fizzle then
			return false, "an honest fizzle was not flagged as one"
		end
		if EnergyLedger.snapshot(PLAYER).heldCount ~= 0 then
			return false, "a fizzle left letters held on the server"
		end

		----------------------------------------------------------------
		-- 6. Memorize clears the WHOLE held set, not the word's letters.
		--    This is what makes double-tap-discard need no second remote.
		----------------------------------------------------------------
		EnergyLedger.reset()
		creditWord(PLAYER, "CAT")
		creditWord(PLAYER, "DOG")
		verdict = EnergyLedger.reportMemorize(PLAYER, redTiles("CAT"), ENFORCE)
		if not verdict.ok then
			return false, "memorize refused while holding surplus letters"
		end
		if EnergyLedger.snapshot(PLAYER).heldCount ~= 0 then
			return false, "memorize kept the letters the word did not use"
		end

		----------------------------------------------------------------
		-- 7. A wildcard cannot be pre-resolved by the client. The buffer
		--    holds "*", so claiming the letter it became names a tile
		--    the player does not hold.
		----------------------------------------------------------------
		EnergyLedger.reset()
		EnergyLedger.creditBlock(PLAYER, "D", "red")
		EnergyLedger.creditBlock(PLAYER, Wildcard.CHAR, Wildcard.COLOR)
		EnergyLedger.creditBlock(PLAYER, "G", "red")

		verdict = EnergyLedger.reportMemorize(PLAYER, {
			{ letter = "D", color = "red" },
			{ letter = "O", color = Wildcard.COLOR },
			{ letter = "G", color = "red" },
		}, ENFORCE)
		if verdict.ok then
			return false, "a client resolved its own wildcard and was believed"
		end

		verdict = EnergyLedger.reportMemorize(PLAYER, {
			{ letter = "D", color = "red" },
			{ letter = Wildcard.CHAR, color = Wildcard.COLOR },
			{ letter = "G", color = "red" },
		}, ENFORCE)
		if not verdict.ok then
			return false, string.format("honest wildcard memorize refused — %s", verdict.reason or "?")
		end
		-- Asserted as a shape, not a literal. Every candidate for D*G
		-- (DAG/DIG/DOG/DUG) is the same length and scores identically, so
		-- which one resolve() returns is a tie-break this suite has no
		-- business pinning — what matters is that the SERVER filled the
		-- star in, and filled it with something real.
		local resolved = verdict.word or ""
		if not string.match(resolved, "^D%uG$") then
			return false, string.format("server resolved D*G to %q, not a D_G word", resolved)
		end
		if not Dictionary.isWord(resolved) then
			return false, string.format("server resolved D*G to %q, which is not a word", resolved)
		end

		----------------------------------------------------------------
		-- 8. The ceiling clamps where the real reservoir clamps, or it
		--    would price casts the player could never have paid for.
		----------------------------------------------------------------
		EnergyLedger.reset()
		for _ = 1, 20 do
			creditWord(PLAYER, "CAT")
			EnergyLedger.reportMemorize(PLAYER, redTiles("CAT"), ENFORCE)
		end
		local ceiling = EnergyLedger.snapshot(PLAYER).ceiling.red or 0
		if ceiling > EnergyReservoirs.CAP_PER_COLOR then
			return false, string.format(
				"ceiling %d exceeds the reservoir cap %d",
				ceiling, EnergyReservoirs.CAP_PER_COLOR
			)
		end

		----------------------------------------------------------------
		-- 9. Casting debits, and enough casts exhaust the ledger.
		----------------------------------------------------------------
		local spec = SpellRegistry.getSpell("red", 1)
		local before = EnergyLedger.snapshot(PLAYER).ceiling.red or 0
		EnergyLedger.debitCast(PLAYER, "red", spec.cost)
		local after = EnergyLedger.snapshot(PLAYER).ceiling.red or 0
		if after ~= before - spec.cost then
			return false, string.format("debit moved the ceiling %d -> %d, expected -%d", before, after, spec.cost)
		end

		for _ = 1, 100 do
			EnergyLedger.debitCast(PLAYER, "red", spec.cost)
		end
		if EnergyLedger.checkCast(PLAYER, "red", spec.cost) then
			return false, "ledger still affording casts after being drained"
		end
		if (EnergyLedger.snapshot(PLAYER).ceiling.red or 0) < 0 then
			return false, "ceiling went negative"
		end

		----------------------------------------------------------------
		-- 10. Shadow mode credits through a failed check, so a coverage
		--     bug cannot starve the ceiling and cascade into cast
		--     rejections that drown the signal the mode exists to log.
		----------------------------------------------------------------
		EnergyLedger.reset()
		verdict = EnergyLedger.reportMemorize(PLAYER, redTiles("CAT"), CREDIT_ON_FAILURE)
		if verdict.ok then
			return false, "coverage check passed for a player holding nothing"
		end
		if (EnergyLedger.snapshot(PLAYER).ceiling.red or 0) <= 0 then
			return false, "shadow mode refused the credit and would starve the ceiling"
		end

		----------------------------------------------------------------
		-- 11. Malformed payloads are refused rather than throwing.
		----------------------------------------------------------------
		EnergyLedger.reset()
		local malformed: { any } = {
			"not a table",
			{ "not a tile" },
			{ { letter = 5, color = "red" } },
			{ { letter = "A", color = "purple" } },
			{ { letter = "AB", color = "red" } },
			{},
		}
		for i, payload in malformed do
			local got = EnergyLedger.reportMemorize(PLAYER, payload, ENFORCE)
			if got.ok then
				return false, string.format("malformed payload %d was accepted", i)
			end
		end

		----------------------------------------------------------------
		-- 12. Accounts are per player.
		----------------------------------------------------------------
		EnergyLedger.reset()
		creditWord(PLAYER, "CAT")
		EnergyLedger.reportMemorize(PLAYER, redTiles("CAT"), ENFORCE)
		if EnergyLedger.checkCast(OTHER_PLAYER, "red", SpellRegistry.getSpell("red", 1).cost) then
			return false, "one player's memorize paid for another player's cast"
		end

		EnergyLedger.forget(PLAYER)
		if (EnergyLedger.snapshot(PLAYER).ceiling.red or 0) ~= 0 then
			return false, "forget left the account behind"
		end

		return true, nil
	end,
}
