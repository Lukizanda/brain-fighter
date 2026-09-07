--!strict

----------------------------------------------------------------------
-- Lobby
----------------------------------------------------------------------
-- Portal vocabulary — the tag and attribute names the hub geometry, the
-- client panel and the server service all have to agree on, plus the
-- ranges that decide when a portal is usable.
--
-- Same job `Arena.luau` does for arena identity, and for the same reason:
-- these names are read by authored Studio parts, one LocalScript and one
-- server Script. As literals they would be three copies of a coupling
-- with nothing holding them in step.
--
-- See `wiki/design/lobby.md` § Mode selection UX.
----------------------------------------------------------------------

local Lobby = {}

-- Carried by the portal pad BaseParts authored in stage 4b.
Lobby.PORTAL_TAG = "ModePortal"

Lobby.Attributes = {
	-- Arena id this portal sends you to. Empty string means "queue only,
	-- no slot exists yet" — the PvP portal until stage 6 authors pads.
	TargetArenaId = "TargetArenaId",
	-- Player-facing name, drawn on the sign and the panel.
	ModeLabel = "ModeLabel",
	-- Published by LobbyService, read by the sign.
	Occupancy = "Occupancy",
	Capacity = "Capacity",
	Waiting = "Waiting",
}

-- How close the player must be for the confirm panel to appear. The pad
-- is 18 studs across, so this is "standing on it or stepping onto it"
-- rather than "somewhere in the room".
Lobby.PANEL_RANGE_STUDS = 22

-- What the server will accept. Deliberately looser than the client's
-- range: the client decides when to *offer* the portal, the server
-- decides whether to honour it, and a player walking as they tap should
-- not be refused for a stud of latency. Still far too tight to use a
-- portal from across the hub, which is the thing being prevented.
Lobby.SERVER_RANGE_STUDS = 34

-- Minimum seconds between accepted portal requests from one player.
-- A transfer moves a character and re-picks a spawn; letting it run at
-- click speed is a physics problem, not a fairness one.
Lobby.REQUEST_COOLDOWN_SEC = 1

-- Studs above the pad centre for the floating sign.
Lobby.SIGN_HEIGHT_STUDS = 16

export type Action = "join" | "cancel"

return Lobby
