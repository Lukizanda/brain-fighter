----------------------------------------------------------------------
-- TeamDeathmatch (mode definition)
----------------------------------------------------------------------
-- First-cut TDM. The team-assignment + spawning + friendly-fire
-- machinery is owned by GameModeService / TeamService / SpawnManager;
-- this module just declares the mode's intent via getConfig and the
-- mode interface hooks.
--
-- Win condition for this first cut: same as FFA — first PLAYER to
-- reach the score limit wins. Team-keyed scoring + team win condition
-- is the next iteration; we want this mode shippable end-to-end before
-- changing the GameModeDefinition / RoundManager scoring contract.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModeConstants = require(ReplicatedStorage.Shared.GameMode.GameModeConstants)

local TeamDeathmatch = {}

TeamDeathmatch.name = "Team Deathmatch"

function TeamDeathmatch.getConfig()
	return {
		scoreLimit = GameModeConstants.SCORE_LIMIT,
		timeLimit = GameModeConstants.ROUND_TIME_LIMIT,
		respawnTime = GameModeConstants.RESPAWN_TIME,
		teamBased = true,
		-- No spawnTag yet — SpawnManager falls back to all SpawnLocations
		-- and the team-color filter handles per-team selection. If we add
		-- non-SpawnLocation team spawn markers later, set a tag here.
		spawnTag = nil :: string?,
	}
end

-- GameModeService inspects getConfig().teamBased and routes through
-- TeamService.assignToSmallestTeam itself. The mode's onPlayerJoin is
-- the override slot for mode-specific tweaks (e.g. faction roles); for
-- vanilla TDM there's nothing extra to do here.
function TeamDeathmatch.onPlayerJoin(_player: Player) end

function TeamDeathmatch.onPlayerKill(_killer: Player, _victim: Player, _weaponName: string): number
	-- Each kill is +1 to the killer's per-player score; team totals are
	-- derived by summing on demand inside checkWinCondition / getRoundLeader.
	return 1
end

-- Sum kills per team, keyed by Team.Name. Players without a team are
-- silently skipped (shouldn't happen in TDM, but defensive).
local function sumKillsByTeam(scores: { [Player]: { kills: number, deaths: number, assists: number } }): { [string]: number }
	local totals: { [string]: number } = {}
	for player, score in scores do
		if player.Team then
			local name = player.Team.Name
			totals[name] = (totals[name] or 0) + score.kills
		end
	end
	return totals
end

function TeamDeathmatch.checkWinCondition(scores: { [Player]: { kills: number, deaths: number, assists: number } }): (boolean, number?, string?)
	local totals = sumKillsByTeam(scores)
	for teamName, kills in totals do
		if kills >= GameModeConstants.SCORE_LIMIT then
			return true, nil, teamName
		end
	end
	return false, nil, nil
end

-- Time-out tiebreak: team with more kills wins. Tie → no winner.
function TeamDeathmatch.getRoundLeader(scores: { [Player]: { kills: number, deaths: number, assists: number } }): (number?, string?)
	local totals = sumKillsByTeam(scores)
	local leader: string? = nil
	local leaderKills = -1
	local tied = false
	for teamName, kills in totals do
		if kills > leaderKills then
			leaderKills = kills
			leader = teamName
			tied = false
		elseif kills == leaderKills then
			tied = true
		end
	end
	if tied or leaderKills <= 0 then
		return nil, nil
	end
	return nil, leader
end

function TeamDeathmatch.getTeamConfig()
	return nil
end

function TeamDeathmatch.onRoundStart() end

function TeamDeathmatch.onRoundEnd() end

return TeamDeathmatch
