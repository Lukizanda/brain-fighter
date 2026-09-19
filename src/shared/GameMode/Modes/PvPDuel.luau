--!strict

----------------------------------------------------------------------
-- PvPDuel
----------------------------------------------------------------------
-- 1v1 on a duel pad: two players, a kill limit, a clock, and back to the
-- hub when it ends. Phase 6 stage 6 — see `wiki/design/lobby.md`
-- § Stage 6 detail.
--
-- Behaviour:
--   - `minPlayers = maxPlayers = DUEL_PLAYERS`. The session waits for two
--     and takes no third; LobbyService fills a pad from the portal queue
--     only when it has enough waiting to start it. A capped round fills
--     before it starts (RoundManager.freeSeats), so nobody drops into a
--     duel in progress.
--   - The kill limit and the clock are designer tunables: Workspace
--     attributes read on every round start, with the constants as the
--     fallback when the attribute is absent or nonsense. Same mechanism
--     as `ActiveGameMode`, same reason — a duel's length is a knob the
--     place file should own, not a code change.
--   - A roster that drops below two while Active ends the round at once
--     and the survivor is credited (`Forfeit`). Leaving by the return pad
--     and disconnecting are the same event to the score table, so this
--     one rule answers both of the lobby page's open questions and frees
--     the pad. An emptied roster ends with nobody credited (`Abandoned`).
--   - On the clock, the kill leader wins (`TimeUp`); equal kills is a
--     `Draw`.
--   - `allowsPvP = true` is what lets `applyDamage` pass player-on-player
--     hits for anyone whose session runs this mode.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

local RoundOutcome = GameModeConstants.RoundOutcome

local PvPDuel = {}

PvPDuel.name = "Duel"

-- Kill limit each arena's current round started with. Snapshotted on
-- round start so a designer retuning the Workspace attribute mid-round
-- changes the *next* duel, not the one being fought.
local killLimits: { [string]: number } = {}

-- A positive number on the Workspace attribute wins; anything else falls
-- back to the constant.
local function tunable(attribute: string, fallback: number): number
	local value = workspace:GetAttribute(attribute)
	if type(value) == "number" and value > 0 then
		return value
	end
	return fallback
end

function PvPDuel.getConfig()
	return {
		scoreLimit = tunable(GameModeConstants.DUEL_KILL_LIMIT_ATTRIBUTE, GameModeConstants.DUEL_KILL_LIMIT),
		timeLimit = tunable(GameModeConstants.DUEL_TIME_LIMIT_ATTRIBUTE, GameModeConstants.DUEL_TIME_LIMIT_MIN)
			* GameModeConstants.SECONDS_PER_MINUTE,
		countdownSec = GameModeConstants.DUEL_COUNTDOWN_SEC,
		respawnTime = GameModeConstants.RESPAWN_TIME,
		spawnTag = Arena.SpawnTags.PvPArena,
		runsRounds = true,
		allowsPvP = true,
		minPlayers = GameModeConstants.DUEL_PLAYERS,
		maxPlayers = GameModeConstants.DUEL_PLAYERS,
	}
end

function PvPDuel.onPlayerJoin(player: Player)
	player.Neutral = true
end

function PvPDuel.onPlayerKill(_killer: Player?, _victim: Player, _cause: string): number
	return 1
end

function PvPDuel.checkWinCondition(scores: { [Player]: any }, arenaId: string): (boolean, number?, string?)
	local killLimit = killLimits[arenaId] or PvPDuel.getConfig().scoreLimit

	local remaining = 0
	local survivor: Player? = nil
	for player, score in scores do
		if score.kills >= killLimit then
			return true, player.UserId, RoundOutcome.ScoreLimit
		end
		remaining += 1
		survivor = player
	end

	if remaining == 0 then
		return true, nil, RoundOutcome.Abandoned
	end
	if remaining < GameModeConstants.DUEL_PLAYERS and survivor then
		return true, survivor.UserId, RoundOutcome.Forfeit
	end
	return false, nil, nil
end

function PvPDuel.getRoundLeader(scores: { [Player]: any }, _arenaId: string): (number?, string?)
	local leader: Player? = nil
	local bestKills = -1
	local tied = false
	for player, score in scores do
		if score.kills > bestKills then
			bestKills = score.kills
			leader = player
			tied = false
		elseif score.kills == bestKills then
			tied = true
		end
	end

	if not leader or tied then
		return nil, RoundOutcome.Draw
	end
	return leader.UserId, RoundOutcome.TimeUp
end

function PvPDuel.onRoundStart(arenaId: string)
	killLimits[arenaId] = PvPDuel.getConfig().scoreLimit
end

function PvPDuel.onRoundEnd(arenaId: string)
	killLimits[arenaId] = nil
end

return PvPDuel
