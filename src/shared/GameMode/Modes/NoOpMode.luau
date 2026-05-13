----------------------------------------------------------------------
-- NoOpMode
----------------------------------------------------------------------
-- Fallback mode for when the competitive modes (FFADeathmatch,
-- TeamDeathmatch) are gated out by GameConfig.TEAMS_ENABLED /
-- PLAYER_VS_PLAYER_ENABLED. Brain Fighter is being repurposed as an
-- educational shooter and the inherited round system has no useful
-- meaning in that context — but GameModeService and RoundManager
-- assume an active mode exists, so this stub keeps them runnable in
-- a "no round end, no team, no score" idle state.
--
-- Behaviour:
--   - teamBased = false → no team auto-balance, no team UI.
--   - timeLimit / scoreLimit chosen so the win check never fires;
--     RoundManager enters Active once and stays there.
--   - onPlayerKill returns 0 so kill credit doesn't accumulate into a
--     mode-defined score.
--
-- Re-enabling PvP / Teams flips a flag in GameConfig; FFA / TDM are
-- registered again automatically and this stub is bypassed.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

-- Picked far above any realistic round length so RoundManager's
-- timeRemaining never reaches zero in normal play. Not math.huge — that
-- gets serialized over GameStateChanged and we'd rather not surprise the
-- client with an "inf" countdown.
local IDLE_ROUND_SECONDS = 60 * 60 * 24 -- 24 hours

local NoOpMode = {}

NoOpMode.name = "No-Op"

function NoOpMode.getConfig()
	return {
		scoreLimit = math.huge,
		timeLimit = IDLE_ROUND_SECONDS,
		respawnTime = GameModeConstants.RESPAWN_TIME,
		teamBased = false,
		spawnTag = "FFASpawn",
	}
end

function NoOpMode.onPlayerJoin(player: Player)
	player.Neutral = true
end

function NoOpMode.onPlayerKill(_killer: Player, _victim: Player, _weaponName: string): number
	return 0
end

function NoOpMode.checkWinCondition(_scores): (boolean, number?, string?)
	return false, nil, nil
end

function NoOpMode.getRoundLeader(_scores): (number?, string?)
	return nil, nil
end

function NoOpMode.getTeamConfig()
	return nil
end

function NoOpMode.onRoundStart()
end

function NoOpMode.onRoundEnd()
end

return NoOpMode
