--!strict

----------------------------------------------------------------------
-- EnergyLedger
----------------------------------------------------------------------
-- The server's answer to "could this player afford that spell?".
--
-- Energy itself still lives client-side in client/PlayerSession — this
-- module does not mirror EnergyReservoirs. It tracks two things per
-- player, both derived from traffic the server already sees or is now
-- told about:
--
--   held    — the letters consumed since that player's last memorize,
--             credited from accepted ConsumeBlock fires;
--   ceiling — per-color energy earned minus spent, credited from
--             validated memorizes and debited on accepted casts.
--
-- The pairing is the point. Crediting energy from block traffic alone
-- (the rejected energy-ceiling ledger) saturates the cap within seconds
-- of shooting and passes every cast an active client makes; requiring
-- the player to name the word they spelled, and checking it against the
-- letters they actually took, is what makes spelling non-optional.
--
-- Deliberately NOT authoritative: this refuses casts a player provably
-- could not have paid for, and is silent about everything else. The
-- full mirror (LetterBlock -> WordBuffer -> Dictionary -> EnergyEconomy
-- server-side) remains the real fix, and this is a stepping stone to it
-- rather than a replacement.
--
-- Keyed by UserId rather than Player so the suite can drive it without
-- a real Players entry.
--
-- See wiki/systems/SpellCastService.md § Validated memorize.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)
local MemorizeAction = require(ReplicatedStorage.Shared.MemorizeAction)
local WordBuffer = require(ReplicatedStorage.Shared.WordBuffer)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)

local EconomyConstants = require(script.Parent.EconomyConstants)

local log = Logger.new("EnergyLedger")

local EMPTY = 0
local SINGLE_LETTER_LENGTH = 1

-- The three reservoir colors plus "wild", which is a legal tile color
-- but never a cast color — see EnergyEconomy.splitByColor.
local VALID_TILE_COLORS: { [string]: true } = {
	red = true,
	green = true,
	blue = true,
	[Wildcard.COLOR] = true,
}

export type Verdict = {
	ok: boolean,
	reason: string?,
	-- The tiles were covered by the held set but spell no word. An
	-- ordinary fizzle, not a cheat signal — the distinction matters
	-- because shadow mode's whole output is its failure log, and a
	-- player mistyping FROG as FRGO must not read as an exploit.
	fizzle: boolean?,
	-- Present when ok: what the server independently resolved the
	-- reported tiles to, and what it credited.
	word: string?,
	energyByColor: { [string]: number }?,
}

type Account = {
	-- color -> letter -> count. A wild tile is held under Wildcard.COLOR
	-- with Wildcard.CHAR as its letter, exactly as the buffer holds it.
	held: { [string]: { [string]: number } },
	heldCount: number,
	ceiling: { [string]: number },
}

local accounts: { [number]: Account } = {}

local EnergyLedger = {}

local function newAccount(): Account
	return {
		held = {},
		heldCount = EMPTY,
		ceiling = {},
	}
end

local function accountFor(userId: number): Account
	local account = accounts[userId]
	if not account then
		account = newAccount()
		accounts[userId] = account
	end
	return account
end

-- Normalize a reported tile into the (letter, color) pair the held set
-- is keyed by, or nil if it could not have come from a real block.
--
-- The glyph normalization matters: the buffer stores wildcards as "*"
-- but a hand-rolled payload might send "★", and the two must not be
-- able to name different entries in the same multiset.
local function normalizeTile(tile: any): (string?, string?)
	if typeof(tile) ~= "table" then
		return nil, nil
	end

	local letter = tile.letter
	local color = tile.color
	if typeof(letter) ~= "string" or typeof(color) ~= "string" then
		return nil, nil
	end
	if not VALID_TILE_COLORS[color] then
		return nil, nil
	end

	letter = Wildcard.normalize(string.upper(letter))
	if #letter ~= SINGLE_LETTER_LENGTH then
		return nil, nil
	end

	return letter, color
end

----------------------------------------------------------------------
-- Credit: a block the player actually took
----------------------------------------------------------------------

-- Record one consumed block. Called only from the branch of the
-- ConsumeBlock handler that has already accepted the fire, so a
-- rejected consume never credits — which is what keeps this in step
-- with the client buffer, since Phase 5.7 stage 4 rolls a rejected
-- letter back out of that buffer.
function EnergyLedger.creditBlock(userId: number, letter: string, color: string)
	local normLetter, normColor = normalizeTile({ letter = letter, color = color })
	if not normLetter or not normColor then
		-- A block whose attributes we cannot read is not the player's
		-- fault; stay silent rather than penalizing them for it.
		log:warn(string.format("unreadable block attributes (letter=%s color=%s)", tostring(letter), tostring(color)))
		return
	end

	local account = accountFor(userId)
	local byLetter = account.held[normColor]
	if not byLetter then
		byLetter = {}
		account.held[normColor] = byLetter
	end
	byLetter[normLetter] = (byLetter[normLetter] or EMPTY) + 1
	account.heldCount += 1

	-- Banking telemetry, not a gate. See EconomyConstants.
	if account.heldCount == EconomyConstants.HELD_BANKING_LOG_THRESHOLD then
		log:warn(string.format(
			"userId %d holding %d letters without memorizing (threshold %d) — banking signal, not a rejection",
			userId, account.heldCount, EconomyConstants.HELD_BANKING_LOG_THRESHOLD
		))
	end
end

----------------------------------------------------------------------
-- Memorize: the word, checked against the letters
----------------------------------------------------------------------

-- Validate a reported memorize and credit the energy it was worth.
--
-- `creditOnFailure` credits anyway when the check fails, which is what
-- shadow mode passes: a coverage bug that silently starved the ceiling
-- would cascade into cast rejections and drown the signal this mode
-- exists to collect.
--
-- On success the ENTIRE held set is cleared, not just the letters the
-- word used. That mirrors MemorizeAction.tryMemorize draining the whole
-- buffer — there is no such thing as memorizing a sub-word — and it is
-- also how discards are handled without a second remote: letters the
-- player threw away are cleared on the same event they cleared them.
-- Any resulting divergence leaves the server holding MORE than the
-- client, which is the direction that cannot reject honest play.
function EnergyLedger.reportMemorize(
	userId: number,
	tiles: any,
	creditOnFailure: boolean
): Verdict
	if typeof(tiles) ~= "table" then
		return { ok = false, reason = "payload is not a table" }
	end

	local account = accountFor(userId)

	local normalized: { WordBuffer.Tile } = {}
	local required: { [string]: { [string]: number } } = {}

	for _, tile in tiles :: { any } do
		local letter, color = normalizeTile(tile)
		if not letter or not color then
			return { ok = false, reason = "malformed tile" }
		end

		table.insert(normalized, { letter = letter, color = color :: any })

		local byLetter = required[color]
		if not byLetter then
			byLetter = {}
			required[color] = byLetter
		end
		byLetter[letter] = (byLetter[letter] or EMPTY) + 1
	end

	if #normalized == EMPTY then
		return { ok = false, reason = "empty memorize" }
	end

	-- Coverage: every reported tile must be a letter this player took.
	for color, byLetter in required do
		local heldByLetter = account.held[color]
		for letter, count in byLetter do
			local heldCount = heldByLetter and heldByLetter[letter] or EMPTY
			if heldCount < count then
				local verdict: Verdict = {
					ok = false,
					reason = string.format(
						"claimed %d x %s/%s, holds %d",
						count, letter, color, heldCount
					),
				}
				if creditOnFailure then
					EnergyLedger._applyMemorize(account, normalized)
				end
				return verdict
			end
		end
	end

	-- The word is resolved HERE, from the letters, rather than taken
	-- from the client. A payload only names the tiles it holds; which
	-- word a wildcard helped spell is the server's to decide, using the
	-- same scoring the client ran.
	local scored = MemorizeAction.scoreTiles(normalized)
	if not scored then
		-- Covered by the held set, but spells nothing. The client cleared
		-- its buffer on this same event (tryMemorize destroys the letters
		-- on an invalid word), so clear ours and credit nothing — in both
		-- modes, because this is what honest play looks like rather than
		-- something shadow mode is measuring.
		EnergyLedger._applyMemorize(account, normalized)
		return { ok = false, fizzle = true, reason = "tiles spell no word" }
	end

	EnergyLedger._applyMemorize(account, normalized)

	return {
		ok = true,
		word = scored.word,
		energyByColor = scored.energyByColor,
	}
end

-- Clear the held set and credit what the tiles were worth. Split out so
-- the shadow-mode failure path applies exactly the same state change as
-- the success path, rather than an approximation of it.
function EnergyLedger._applyMemorize(account: Account, tiles: { WordBuffer.Tile })
	local scored = MemorizeAction.scoreTiles(tiles)

	account.held = {}
	account.heldCount = EMPTY

	if not scored then
		return
	end

	for color, amount in scored.energyByColor do
		-- Clamped for the same reason the real reservoir clamps: energy
		-- above the cap is discarded on add, so a ceiling that kept it
		-- would price casts the player could never have paid for.
		local credited = (account.ceiling[color] or EMPTY) + amount
		account.ceiling[color] = math.min(credited, EnergyReservoirs.CAP_PER_COLOR)
	end
end

----------------------------------------------------------------------
-- Cast: the price check
----------------------------------------------------------------------

-- True when the player has provably earned enough of `color` to pay
-- `cost`. Pure — the caller decides what to do with a false, which is
-- what lets shadow mode log a verdict without acting on it.
function EnergyLedger.checkCast(userId: number, color: string, cost: number): (boolean, string?)
	local account = accounts[userId]
	local available = account and account.ceiling[color] or EMPTY
	if available < cost then
		return false, string.format("%s cast costs %d, ledger has %d", color, cost, available)
	end
	return true, nil
end

function EnergyLedger.debitCast(userId: number, color: string, cost: number)
	local account = accountFor(userId)
	local available = account.ceiling[color] or EMPTY
	account.ceiling[color] = math.max(EMPTY, available - cost)
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function EnergyLedger.forget(userId: number)
	accounts[userId] = nil
end

-- Test seam: the ledger is a per-server singleton because there is one
-- economy per server, so a suite needs a way back to a clean slate.
function EnergyLedger.reset()
	accounts = {}
end

-- Read-only view for tests and telemetry.
function EnergyLedger.snapshot(userId: number): { heldCount: number, ceiling: { [string]: number } }
	local account = accounts[userId]
	if not account then
		return { heldCount = EMPTY, ceiling = {} }
	end
	return {
		heldCount = account.heldCount,
		ceiling = table.clone(account.ceiling),
	}
end

return EnergyLedger
