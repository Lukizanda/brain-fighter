--!strict

----------------------------------------------------------------------
-- LobbyMode
----------------------------------------------------------------------
-- The hub. Not a game mode in the sense the other entries in this folder
-- are — nobody wins it — but it implements the same interface so the hub
-- can be an ordinary session bound to an ordinary arena slot.
--
-- See `wiki/design/lobby.md` § Stage 4 detail, decision 1. The alternative
-- was to model the lobby as *no session*, which pushes a `nil` branch into
-- SpawnManager, BlockSpawner and BroadcastAudience — every system stages 1-3
-- spent their budget keying on an arena id.
--
-- Behaviour:
--   - `runsRounds = false` → GameModeService never calls `start()` on this
--     session, so RoundManager stays parked in WaitingForPlayers and
--     broadcasts nothing. RoundManager needs no knowledge of lobbies.
--   - Every callback below is inert. They exist to satisfy the interface;
--     none of them are reachable while `runsRounds` is false, because the
--     round loop that calls them never runs.
--   - `spawnTag` is the lobby pad tag, which is how a player transferred
--     back to the hub lands in the hub rather than at the arena spawn.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

-- Deliberately not NoOpMode's 24-hour idle round: nothing reads this, and
-- a plausible-looking number invites someone to believe the lobby has a
-- round. Zero is the honest answer to "how long is a lobby round".
local NO_ROUND = 0

local LobbyMode = {}

LobbyMode.name = "Lobby"

function LobbyMode.getConfig()
	return {
		scoreLimit = NO_ROUND,
		timeLimit = NO_ROUND,
		-- Read on the respawn path even with no round running: a player who
		-- falls off the hub still has to come back.
		respawnTime = GameModeConstants.RESPAWN_TIME,
		teamBased = false,
		spawnTag = Arena.SpawnTags.Lobby,
		runsRounds = false,
	}
end

function LobbyMode.onPlayerJoin(player: Player)
	player.Neutral = true
end

function LobbyMode.onPlayerKill(_killer: Player, _victim: Player, _weaponName: string): number
	return 0
end

function LobbyMode.checkWinCondition(_scores): (boolean, number?, string?)
	return false, nil, nil
end

function LobbyMode.getRoundLeader(_scores): (number?, string?)
	return nil, nil
end

function LobbyMode.getTeamConfig()
	return nil
end

function LobbyMode.onRoundStart()
end

function LobbyMode.onRoundEnd()
end

return LobbyMode
