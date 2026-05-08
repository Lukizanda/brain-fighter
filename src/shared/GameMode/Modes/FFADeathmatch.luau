local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

local FFADeathmatch = {}

FFADeathmatch.name = "Free-For-All"

function FFADeathmatch.getConfig()
	return {
		scoreLimit = GameModeConstants.SCORE_LIMIT,
		timeLimit = GameModeConstants.ROUND_TIME_LIMIT,
		respawnTime = GameModeConstants.RESPAWN_TIME,
		teamBased = false,
		spawnTag = "FFASpawn",
	}
end

function FFADeathmatch.onPlayerJoin(player: Player)
	-- FFA: every player is Neutral so everyone can damage everyone
	player.Neutral = true
end

function FFADeathmatch.onPlayerKill(_killer: Player, _victim: Player, _weaponName: string): number
	-- Standard deathmatch: 1 point per kill
	return 1
end

function FFADeathmatch.checkWinCondition(scores: { [Player]: { kills: number, deaths: number, assists: number } }): (boolean, number?, string?)
	for player, score in scores do
		if score.kills >= GameModeConstants.SCORE_LIMIT then
			return true, player.UserId, nil
		end
	end
	return false, nil, nil
end

-- Time-out tiebreak: top-kill player wins. Tie → first-encountered wins
-- (deterministic enough for greybox; iterate later if needed).
function FFADeathmatch.getRoundLeader(scores: { [Player]: { kills: number, deaths: number, assists: number } }): (number?, string?)
	local bestUserId: number? = nil
	local bestKills = -1
	for player, score in scores do
		if score.kills > bestKills then
			bestKills = score.kills
			bestUserId = player.UserId
		end
	end
	return bestUserId, nil
end

function FFADeathmatch.getTeamConfig()
	return nil
end

function FFADeathmatch.onRoundStart()
	-- No special setup for FFA
end

function FFADeathmatch.onRoundEnd()
	-- No special cleanup for FFA
end

return FFADeathmatch
