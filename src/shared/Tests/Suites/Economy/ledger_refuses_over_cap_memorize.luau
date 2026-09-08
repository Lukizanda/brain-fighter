--!strict

----------------------------------------------------------------------
-- ledger_refuses_over_cap_memorize — A28, the one impossible payload
----------------------------------------------------------------------
-- Every other check in EnergyLedger errs toward letting a cheat through
-- rather than refusing an honest player, and shadow mode credits through
-- all of them. The tile cap is the exception: the client's WordBuffer
-- drops letters past its cap rather than growing, so a report naming
-- more tiles than the cap did not come from a buffer at all. It is
-- refused in both modes, ahead of the per-tile walk, so a looping client
-- cannot make the ledger do unbounded work per fire.
--
-- The ordering half matters as much as the refusal: an over-cap payload
-- of malformed tiles must come back with the CAP reason, or the cap
-- check is running after the work it exists to skip.
----------------------------------------------------------------------

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WordBuffer = require(ReplicatedStorage.Shared.WordBuffer)

local EconomyConstants = require(ServerScriptService.Server.Economy.EconomyConstants)
local EnergyLedger     = require(ServerScriptService.Server.Economy.EnergyLedger)

local PLAYER = 1004

local SHADOW = true
local ENFORCE = false

local ONE_OVER = 1

-- Matches the phrasing EnergyLedger builds for the cap verdict, so the
-- log line a shadow-mode operator reads is distinguishable from a
-- coverage failure rather than merely being some other rejection.
local CAP_REASON_PATTERN = "buffer holds at most"

local function creditWord(userId: number, word: string)
	for i = 1, #word do
		EnergyLedger.creditBlock(userId, string.sub(word, i, i), "red")
	end
end

-- `count` legal red tiles, all "A" — a shape the coverage check would
-- reject on its own merits, which is the point: the cap must fire first.
local function redTileRun(count: number): { { letter: string, color: string } }
	local tiles = {}
	for _ = 1, count do
		table.insert(tiles, { letter = "A", color = "red" })
	end
	return tiles
end

return {
	name = "ledger_refuses_over_cap_memorize",

	setup = function()
		EnergyLedger.reset()
	end,

	teardown = function()
		EnergyLedger.reset()
	end,

	verify = function(): (boolean, string?)
		local cap = EconomyConstants.MEMORIZE_TILE_CAP

		----------------------------------------------------------------
		-- 1. The cap is the buffer's, or the two can drift apart and the
		--    check starts refusing payloads a real buffer can produce.
		----------------------------------------------------------------
		if cap ~= WordBuffer.DEFAULT_CAP then
			return false, string.format(
				"ledger cap %d does not track the buffer cap %d",
				cap, WordBuffer.DEFAULT_CAP
			)
		end

		----------------------------------------------------------------
		-- 2. Over-cap is refused in BOTH modes, with the cap's own
		--    reason, and is never mistaken for an ordinary fizzle.
		----------------------------------------------------------------
		for _, creditOnFailure in { SHADOW, ENFORCE } do
			local verdict = EnergyLedger.reportMemorize(PLAYER, redTileRun(cap + ONE_OVER), creditOnFailure)
			if verdict.ok then
				return false, string.format(
					"accepted %d tiles from a buffer that holds %d (creditOnFailure=%s)",
					cap + ONE_OVER, cap, tostring(creditOnFailure)
				)
			end
			if verdict.fizzle then
				return false, "an over-cap payload was reported as an ordinary fizzle"
			end
			if not string.find(verdict.reason or "", CAP_REASON_PATTERN, 1, true) then
				return false, string.format(
					"over-cap refusal read %q, which does not name the cap",
					verdict.reason or "?"
				)
			end
		end

		----------------------------------------------------------------
		-- 3. It runs before the per-tile work. A malformed over-cap
		--    payload still comes back with the cap reason.
		----------------------------------------------------------------
		local junk: { any } = {}
		for _ = 1, cap + ONE_OVER do
			table.insert(junk, "not a tile")
		end
		local verdict = EnergyLedger.reportMemorize(PLAYER, junk, SHADOW)
		if not string.find(verdict.reason or "", CAP_REASON_PATTERN, 1, true) then
			return false, string.format(
				"malformed over-cap payload refused as %q — the cap check runs after the tile walk",
				verdict.reason or "?"
			)
		end

		----------------------------------------------------------------
		-- 4. The refusal does not touch the account. Shadow mode credits
		--    through every other failure, so an over-cap report that
		--    reached _applyMemorize would clear a real player's held
		--    letters and hand them free energy on the way past.
		----------------------------------------------------------------
		EnergyLedger.reset()
		creditWord(PLAYER, "CAT")
		local before = EnergyLedger.snapshot(PLAYER)

		EnergyLedger.reportMemorize(PLAYER, redTileRun(cap + ONE_OVER), SHADOW)

		local after = EnergyLedger.snapshot(PLAYER)
		if after.heldCount ~= before.heldCount then
			return false, string.format(
				"an over-cap report moved the held set %d -> %d",
				before.heldCount, after.heldCount
			)
		end
		if (after.ceiling.red or 0) ~= (before.ceiling.red or 0) then
			return false, "an over-cap report credited energy"
		end

		----------------------------------------------------------------
		-- 5. Exactly at the cap is honest play and must still pass the
		--    cap gate — a full buffer memorized in one go is the normal
		--    case, not the edge one.
		----------------------------------------------------------------
		EnergyLedger.reset()
		verdict = EnergyLedger.reportMemorize(PLAYER, redTileRun(cap), SHADOW)
		if string.find(verdict.reason or "", CAP_REASON_PATTERN, 1, true) then
			return false, string.format("a full buffer of %d tiles was refused by the cap", cap)
		end

		return true, nil
	end,
}
