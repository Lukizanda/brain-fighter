----------------------------------------------------------------------
-- NoOpMode
----------------------------------------------------------------------
-- The arena's idle mode, and the fallback when "ActiveGameMode" names a
-- mode that no longer exists. The competitive modes (FFADeathmatch,
-- TeamDeathmatch) were deleted in 6610291; Brain Fighter's arena is a
-- spelling-combat space where the inherited round system has no useful
-- meaning yet — but RoundManager assumes an active mode exists, so this
-- keeps a session runnable in a "no round end, no score" state.
--
-- Behaviour:
--   - No `timeLimit` and `scoreLimit = math.huge`, so the win check never
--     fires: RoundManager enters Active once and stays there, which is
--     what gives spawn protection and the respawn loop something to key on.
--   - No `countdownSec`: the round goes live the moment MIN_PLAYERS is met.
--   - onPlayerKill returns 0 so kill credit doesn't accumulate into a
--     mode-defined score.
--
-- Note the round therefore starts exactly once per session; nothing
-- downstream of RoundStarted can be exercised twice in a playtest of this
-- mode. A finite `timeLimit` would change that, at the cost of re-firing
-- RoundStarted (and the energy-ledger reset that listens to it) every
-- few minutes in the Default arena — a gameplay decision, not taken here.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

local NoOpMode = {}

NoOpMode.name = "No-Op"

function NoOpMode.getConfig()
	return {
		scoreLimit = math.huge,
		-- timeLimit and countdownSec deliberately absent: unlimited, no
		-- countdown. See GameModeDefinition.ModeConfig.
		respawnTime = GameModeConstants.RESPAWN_TIME,
		spawnTag = Arena.SpawnTags.Default,
		-- Idle, but it is still a round: RoundManager enters Active and
		-- stays there.
		runsRounds = true,
		allowsPvP = false,
	}
end

function NoOpMode.onPlayerJoin(player: Player)
	player.Neutral = true
end

function NoOpMode.onPlayerKill(_killer: Player?, _victim: Player, _cause: string): number
	return 0
end

function NoOpMode.checkWinCondition(_scores): (boolean, number?)
	return false, nil
end

function NoOpMode.getRoundLeader(_scores): number?
	return nil
end

function NoOpMode.onRoundStart()
end

function NoOpMode.onRoundEnd()
end

return NoOpMode
