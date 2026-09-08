--!strict

----------------------------------------------------------------------
-- ledger_resets_on_round_start — F9, the drift that made ENFORCE moot
----------------------------------------------------------------------
-- The client zeroes its reservoirs on the transition into Active
-- (client/EnergyRoundReset). Before this hook nothing zeroed the server
-- ledger, so its ceiling carried across rounds and lobby banking and the
-- server ended up permanently richer than the client it was pricing —
-- an affordability check in that state can never refuse anything, which
-- is why flipping ENFORCE without this would have proved nothing.
--
-- Driven through the REAL BindableEvent rather than the ledger seam,
-- because the wiring is the thing that was missing; a test that called
-- resetRound directly would have passed just as happily on the broken
-- build. The ledger seam is only the fallback for a headless run with no
-- player to put on the roster.
--
-- These modules live under ReplicatedStorage but the autorunner is a
-- server Script, so reaching into ServerScriptService is valid here.
----------------------------------------------------------------------

local ServerScriptService = game:GetService("ServerScriptService")

local EnergyLedger = require(ServerScriptService.Server.Economy.EnergyLedger)

local roundStartedEvent = ServerScriptService.Server.GameMode.Events.RoundStarted :: BindableEvent

-- A signal fired on a BindableEvent is delivered at the next resumption
-- point under deferred signal behaviour, so the fire and the assertions
-- cannot share a frame.
local SIGNAL_SETTLE_SEC = 0.1

-- Stand-in userId for the headless path, well clear of any real one.
local FALLBACK_USER = 1003

-- Only the fields this test puts on the shared context, plus the one the
-- runner supplies. See TestRunner's header for the rest.
type Ctx = {
	player: Player?,
	economyUserId: number,
	economyWired: boolean,
	economySeeded: boolean,
}

local function creditWord(userId: number, word: string)
	for i = 1, #word do
		EnergyLedger.creditBlock(userId, string.sub(word, i, i), "red")
	end
end

local function redTiles(word: string): { { letter: string, color: string } }
	local tiles = {}
	for i = 1, #word do
		table.insert(tiles, { letter = string.sub(word, i, i), color = "red" })
	end
	return tiles
end

return {
	name = "ledger_resets_on_round_start",

	setup = function(ctx: Ctx)
		EnergyLedger.reset()
		local player = ctx.player
		ctx.economyUserId = if player then player.UserId else FALLBACK_USER
		ctx.economyWired = player ~= nil

		-- Earn a real ceiling the way a player does: take the letters,
		-- then name the word they spell.
		creditWord(ctx.economyUserId, "CAT")
		local verdict = EnergyLedger.reportMemorize(ctx.economyUserId, redTiles("CAT"), false)
		ctx.economySeeded = verdict.ok and (EnergyLedger.snapshot(ctx.economyUserId).ceiling.red or 0) > 0
	end,

	run = function(ctx: Ctx)
		-- Leave some letters held as well, so the assertion covers both
		-- halves of the account rather than only the ceiling.
		creditWord(ctx.economyUserId, "DOG")

		local player = ctx.player
		if player then
			roundStartedEvent:Fire({ player })
			task.wait(SIGNAL_SETTLE_SEC)
		else
			EnergyLedger.resetRound({ ctx.economyUserId })
		end
	end,

	teardown = function()
		EnergyLedger.reset()
	end,

	verify = function(ctx: Ctx): (boolean, string?)
		if not ctx.economySeeded then
			return false, "setup failed to earn a ceiling — the reset assertion would be vacuous"
		end

		local snapshot = EnergyLedger.snapshot(ctx.economyUserId)
		if (snapshot.ceiling.red or 0) ~= 0 then
			return false, string.format(
				"round start left %d red on the ledger — the ceiling carries across rounds%s",
				snapshot.ceiling.red or 0,
				if ctx.economyWired then " (EconomyService is not listening to RoundStarted)" else ""
			)
		end
		if snapshot.heldCount ~= 0 then
			return false, string.format("round start left %d letters held", snapshot.heldCount)
		end

		-- A reset account is a usable one, not a hole: the player is
		-- mid-session and their next block has to credit as normal.
		creditWord(ctx.economyUserId, "CAT")
		if EnergyLedger.snapshot(ctx.economyUserId).heldCount ~= #"CAT" then
			return false, "the reset account stopped accepting credits"
		end

		-- The reset is per roster, not per server. Someone who was not on
		-- the roster keeps what they earned.
		EnergyLedger.reset()
		creditWord(FALLBACK_USER, "CAT")
		EnergyLedger.reportMemorize(FALLBACK_USER, redTiles("CAT"), false)
		local untouched = EnergyLedger.snapshot(FALLBACK_USER).ceiling.red or 0
		EnergyLedger.resetRound({ FALLBACK_USER + 1 })
		if (EnergyLedger.snapshot(FALLBACK_USER).ceiling.red or 0) ~= untouched then
			return false, "a round reset cleared a player who was not on the roster"
		end

		return true, nil
	end,
}
