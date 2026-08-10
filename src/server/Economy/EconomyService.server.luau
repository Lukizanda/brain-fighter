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

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local EconomyConstants = require(script.Parent.EconomyConstants)
local EnergyLedger     = require(script.Parent.EnergyLedger)
local RateLimiter      = require(script.Parent.Parent.Utility.RateLimiter)

local log = Logger.new("EconomyService")

local reportRemote = ReplicatedStorage.Shared.MemorizeAction.Remotes.ReportMemorize :: RemoteEvent

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

Players.PlayerRemoving:Connect(function(player: Player)
	EnergyLedger.forget(player.UserId)
	reportLimiter:forget(player)
	rejectionLogBudget:forgetPrefix(string.format("%d:", player.UserId))
end)

log:info(string.format(
	"ready — validated memorize active (%s)",
	if EconomyConstants.ENFORCE then "ENFORCING" else "shadow mode, refusing nothing"
))
