--!strict

----------------------------------------------------------------------
-- EconomyService
----------------------------------------------------------------------
-- Owns the ReportMemorize remote and the EnergyLedger's lifecycle.
--
-- The credit and debit hooks live in the two handlers that already own
-- their remotes (BlockShootService, SpellCastService) rather than here,
-- because both need to run on the exact branch that accepted the fire —
-- a credit for a consume the server refused would put the ledger out of
-- step with the client's buffer.
--
-- See wiki/systems/SpellCastService.md § Validated memorize.
----------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")

local Colors = require(ReplicatedStorage.Shared.Core.Colors)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local SpellRegistry = require(ReplicatedStorage.Shared.SpellRegistry)

local EconomyConstants = require(script.Parent.EconomyConstants)
local EnergyLedger     = require(script.Parent.EnergyLedger)
local RateLimiter      = require(script.Parent.Parent.Utility.RateLimiter)

local log = Logger.new("EconomyService")

local reportRemote = ReplicatedStorage.Shared.MemorizeAction.Remotes.ReportMemorize :: RemoteEvent
local devGrantRemote = ReplicatedStorage.Shared.Economy.Remotes.DevGrantEnergy :: RemoteEvent
local devCreditRemote = ReplicatedStorage.Shared.Economy.Remotes.DevCreditLetter :: RemoteEvent

-- Server-side round signal. A sibling folder under Server, so it is in
-- the tree by the time this Script runs, same as the Utility require.
local roundStartedEvent = script.Parent.Parent.GameMode.Events.RoundStarted :: BindableEvent

local reportLimiter = RateLimiter.new(
	EconomyConstants.REPORT_BURST_CAPACITY,
	EconomyConstants.REPORT_REFILL_PER_SEC
)

local rejectionLogBudget = RateLimiter.new(1, 1 / EconomyConstants.REJECTION_LOG_THROTTLE_SEC)

-- Shadow-mode findings are the entire product of this phase, so they log
-- as warnings even though nothing is refused — a line nobody reads is
-- the same as not having shipped the mode.
local function noteFailure(player: Player, reason: string)
	local key = string.format("%d:%s", player.UserId, reason)
	if not rejectionLogBudget:consume(key) then
		return
	end
	local verb = if EconomyConstants.ENFORCE then "rejected" else "would reject"
	log:warn(string.format("%s memorize from %s — %s", verb, player.Name, reason))
end

reportRemote.OnServerEvent:Connect(function(player: Player, tiles: any)
	if not reportLimiter:consume(player) then
		noteFailure(player, "rate limit")
		return
	end

	local verdict = EnergyLedger.reportMemorize(player.UserId, tiles, not EconomyConstants.ENFORCE)
	if verdict.fizzle then
		-- The player spelled nothing. Their letters are gone on both
		-- sides and nothing was earned; that is the game working.
		return
	end
	if not verdict.ok then
		noteFailure(player, verdict.reason or "unknown")
		return
	end

	log:info(string.format("%s memorized %s", player.Name, verdict.word or "?"))
end)

-- The ledger's ceiling has to zero where the client's reservoirs zero,
-- and the client zeroes them on the transition into Active
-- (client/EnergyRoundReset). Without this the server accumulates across
-- rounds and lobby banking while the client does not, ending up
-- permanently richer than the thing it is pricing — an affordability
-- check that can never refuse anything.
--
-- The roster comes in on the event rather than being looked up here,
-- because a round belongs to one arena session and not to the server.
-- Until SessionRegistry exists (chunk 8) a missing payload means an
-- older caller, and every player on the server is the honest guess.
roundStartedEvent.Event:Connect(function(roster: { Player }?)
	local members = roster or Players:GetPlayers()

	local userIds: { number } = {}
	for _, player in members do
		table.insert(userIds, player.UserId)
	end

	local cleared = EnergyLedger.resetRound(userIds)
	log:info(string.format(
		"round start — reset %d of %d roster accounts%s",
		cleared, #userIds,
		if roster then "" else " (no roster on the event, fell back to all players)"
	))
end)

----------------------------------------------------------------------
-- Dev mana cheat
----------------------------------------------------------------------
-- DevDebug's 1-4 keys fill the client's reservoirs. Under ENFORCE those
-- casts then die at `checkCast`, because the ledger never saw the
-- letters — the cheat conjures energy and the ledger only credits
-- energy that was spelled for. The server half of the same cheat lives
-- here so the two agree.
--
-- The wire carries a **tier**, not an amount: the client cannot name a
-- number, so the worst a forged fire can ask for is the T4 fill the
-- keyboard already gives.
--
-- Studio only, and that is the real guard rather than the config flag it
-- could have been — a granted-energy remote that ships live is a hole
-- whatever a constant says. `RunService:IsStudio()` is false on a
-- Roblox server, so the handler cannot fire there even if the client
-- half survives to production.
local DEV_CHEAT_ALLOWED = RunService:IsStudio()

devGrantRemote.OnServerEvent:Connect(function(player: Player, tier: any)
	if not DEV_CHEAT_ALLOWED then
		log:warn(string.format("dev mana grant from %s refused — not a Studio session", player.Name))
		return
	end

	local costs = SpellRegistry.TIER_COSTS
	if typeof(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 or tier > #costs then
		log:warn(string.format("dev mana grant from %s ignored — want an integer tier 1-%d, got %s",
			player.Name, #costs, tostring(tier)))
		return
	end

	local amount = costs[tier]
	for _, color in Colors.SPELL_COLORS do
		EnergyLedger.devSetCeiling(player.UserId, color, amount)
	end

	log:info(string.format("dev mana grant — %s ledger set to T%d (%d per colour)",
		player.Name, tier, amount))
end)

-- DevDebug's `[` key conjures a letter into the buffer without popping a
-- block, so the ledger never saw it arrive and the `]` memorize that
-- follows fails coverage ("claimed 2 x A/blue, holds 0"). Under ENFORCE
-- that is not just a noisy log: the memorize credits the client's
-- reservoirs and nothing on the server, so the dev word earns energy
-- that no cast can spend.
--
-- Crediting the held set is the honest repair, and a better one than the
-- tier grant above: the `]` that follows goes through the real
-- ReportMemorize path, the real coverage check and the real
-- EnergyEconomy split, so the dev word earns exactly what a spelled word
-- earns. The cheat is in where the letter came from, not in what it is
-- worth.
--
-- Same Studio-only guard, for the same reason.
devCreditRemote.OnServerEvent:Connect(function(player: Player, letter: any, color: any)
	if not DEV_CHEAT_ALLOWED then
		log:warn(string.format("dev letter credit from %s refused — not a Studio session", player.Name))
		return
	end

	if typeof(letter) ~= "string" or typeof(color) ~= "string" then
		log:warn(string.format("dev letter credit from %s ignored — want (letter, color) strings", player.Name))
		return
	end

	-- creditBlock normalizes and refuses anything that could not have
	-- come from a real block, so a malformed pair costs a warn and not a
	-- corrupt held set.
	EnergyLedger.creditBlock(player.UserId, letter, color)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	EnergyLedger.forget(player.UserId)
	reportLimiter:forget(player)
	rejectionLogBudget:forgetPrefix(string.format("%d:", player.UserId))
end)

log:info(string.format(
	"ready — validated memorize active (%s), dev mana grant %s",
	if EconomyConstants.ENFORCE then "ENFORCING" else "shadow mode, refusing nothing",
	if DEV_CHEAT_ALLOWED then "enabled (Studio)" else "refused (live server)"
))
