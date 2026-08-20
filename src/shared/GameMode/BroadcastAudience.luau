--!strict

----------------------------------------------------------------------
-- BroadcastAudience
----------------------------------------------------------------------
-- Who should receive a screen-space remote.
--
-- `RoundManager` fires round state at its own roster because it holds one.
-- `ScoreTracker` and `BossService` do not: the first is a server-wide
-- singleton, the second a top-level Script that nothing injects into. This
-- module is the seam that lets them ask the same question anyway —
-- `GameModeService` registers a resolver over its session table at boot, and
-- callers resolve an audience per fire rather than caching one, because a
-- roster changes under a long-lived boss.
--
-- Screen-space only. World-space VFX deliberately keep `FireAllClients`:
-- particles spawn at a world position, so another arena never sees them, and
-- a roster lookup on the hottest path in the game buys nothing the distance
-- culling does not already. See `wiki/design/lobby.md` § Broadcast audience.
--
-- **The fallback is everyone, not nobody.** An unresolved audience means the
-- session manager has not booted yet, or a player is between sessions.
-- Degrading to today's server-wide behaviour leaves a HUD working; degrading
-- to an empty audience would silently blank it, which is the failure mode
-- that takes a playtest to notice. The throttled warn is there so the
-- degradation is visible rather than merely survivable.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("BroadcastAudience")

-- Seconds between repeats of the same fallback warning. A boss fires health
-- updates at 10 Hz, so an unthrottled warn would bury every other log line.
local FALLBACK_WARN_INTERVAL = 30

-- Resolves an audience from whatever owns sessions. Returning `nil` means
-- "no session for this key" and selects the server-wide fallback; returning
-- an empty table means "a session with nobody in it" and is honoured as-is.
export type Resolver = {
	forPlayer: (player: Player) -> { Player }?,
	forArena: (arenaId: string) -> { Player }?,
}

local BroadcastAudience = {}

local resolver: Resolver? = nil

----------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------

-- Called once by `GameModeService` at boot. Passing `nil` restores the
-- server-wide fallback, which is what a teardown wants.
function BroadcastAudience.setResolver(newResolver: Resolver?)
	resolver = newResolver
	log:info(newResolver and "Resolver registered" or "Resolver cleared")
end

----------------------------------------------------------------------
-- Resolution
----------------------------------------------------------------------

local function fallback(reason: string): { Player }
	log:warnThrottled("fallback:" .. reason, FALLBACK_WARN_INTERVAL,
		"Falling back to every client —", reason)
	return Players:GetPlayers()
end

-- The audience for an event centred on one player: their session's roster.
-- Anchor a kill on the victim rather than the killer — the victim is always
-- a real Player in a session, where an environment kill has no killer at all.
function BroadcastAudience.forPlayer(player: Player?): { Player }
	if not player then
		return fallback("no anchor player")
	end

	local active = resolver
	if not active then
		return fallback("no resolver registered")
	end

	local audience = active.forPlayer(player)
	if not audience then
		return fallback("no session for player " .. player.Name)
	end

	return audience
end

-- The audience for an event bound to an arena slot rather than to a player —
-- a boss belongs to its arena, not to whoever happens to be hitting it.
-- A nil id means the default slot, matching `Arena.idOf`'s reading of a
-- missing attribute.
function BroadcastAudience.forArena(arenaId: string?): { Player }
	local resolvedId = arenaId or Arena.DEFAULT_ID

	local active = resolver
	if not active then
		return fallback("no resolver registered")
	end

	local audience = active.forArena(resolvedId)
	if not audience then
		return fallback("no session for arena " .. resolvedId)
	end

	return audience
end

----------------------------------------------------------------------
-- Delivery
----------------------------------------------------------------------

-- `FireClient` per member, skipping players who have left since the audience
-- was resolved. Payload arguments pass through untouched — every caller here
-- is replacing a `FireAllClients` whose consumer must not notice the change.
function BroadcastAudience.fire(remote: RemoteEvent, audience: { Player }, ...: any)
	for _, player in audience do
		if player.Parent then
			remote:FireClient(player, ...)
		end
	end
end

return BroadcastAudience
