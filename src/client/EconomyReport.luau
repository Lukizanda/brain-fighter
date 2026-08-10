--!strict

----------------------------------------------------------------------
-- EconomyReport
----------------------------------------------------------------------
-- Runs a memorize and tells the server which letters it spent.
--
-- Every client path that memorizes goes through here rather than
-- calling MemorizeAction.tryMemorize directly, so the wire format
-- exists in one place and a new call site cannot silently skip the
-- report — under EconomyConstants.ENFORCE, skipping it means that
-- player's casts stop being affordable.
--
-- What is sent is the RAW buffer tiles, wildcards still unresolved. The
-- server re-resolves the word itself, so a client never gets to claim
-- which letter its star became: it only names the tiles it holds, and
-- the server checks those against the blocks it saw that player take.
--
-- See wiki/systems/SpellCastService.md § Validated memorize.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MemorizeAction = require(ReplicatedStorage.Shared.MemorizeAction)
local PlayerSession = require(script.Parent.PlayerSession)

local reportRemote = ReplicatedStorage.Shared.MemorizeAction.Remotes.ReportMemorize :: RemoteEvent

local EconomyReport = {}

-- Memorize the buffered word and report the spend.
--
-- The tiles are snapshotted BEFORE tryMemorize, which clears the buffer
-- on every outcome except an empty one — read them after and there is
-- nothing left to report.
--
-- An "empty" result is not reported: it mutates no state on either side,
-- so there is nothing for the server to stay in step with.
function EconomyReport.memorize(session: PlayerSession.Session): MemorizeAction.Result
	local spent = session.wordBuffer:tiles()

	local result = MemorizeAction.tryMemorize(session.wordBuffer, session.energyReservoirs)

	if result.reason ~= "empty" then
		reportRemote:FireServer(spent)
	end

	return result
end

return EconomyReport
