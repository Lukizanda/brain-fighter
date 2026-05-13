----------------------------------------------------------------------
-- TeamService
----------------------------------------------------------------------
-- Owns the Team instances under game.Teams and handles assignment.
-- Designed for the simple auto-balance flow today, but the API surface
-- is shaped so it can absorb pick-your-team menus and party-grouped
-- joins later without redesign:
--
--   getSmallestTeam()              → for a future party flow that
--                                    wants to land an entire group on
--                                    one side
--   setTeamForPlayer(player, name) → for a future menu UI / party
--                                    follow-leader logic
--   assignToSmallestTeam(player)   → today's auto-balance flow
--
-- AutoAssignable on each Team is forced to false so Roblox's built-in
-- balancer doesn't fight ours. All assignment goes through this
-- service.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local GameConfig = require(ReplicatedStorage.Shared.Core.GameConfig)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("TeamService")

local TeamService = {}

-- Team registry. Add entries here to introduce additional sides; the
-- balance and assignment logic is generic over count.
local TEAM_DEFS = {
	{ name = "Red",  color = BrickColor.new("Bright red") },
	{ name = "Blue", color = BrickColor.new("Bright blue") },
}

local teams: { [string]: Team } = {}
local initialized = false

local function findOrCreateTeam(def: { name: string, color: BrickColor }): Team
	local existing = Teams:FindFirstChild(def.name)
	if existing and existing:IsA("Team") then
		existing.TeamColor = def.color
		existing.AutoAssignable = false
		return existing
	end
	local team = Instance.new("Team")
	team.Name = def.name
	team.TeamColor = def.color
	team.AutoAssignable = false
	team.Parent = Teams
	return team
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function TeamService.initialize()
	if initialized then
		return
	end
	-- Teams gate: when TEAMS_ENABLED is false, swallow the call. No Team
	-- instances are created and every accessor below returns the neutral
	-- defaults (nil team, empty list, no-op assignment). Re-enabling
	-- TEAMS_ENABLED restores the normal init path.
	if not GameConfig.TEAMS_ENABLED then
		initialized = true
		log:info("TEAMS_ENABLED=false — team service running as no-op")
		return
	end
	for _, def in TEAM_DEFS do
		teams[def.name] = findOrCreateTeam(def)
	end
	initialized = true
	log:info(string.format("Initialized with %d teams: %s",
		#TEAM_DEFS, table.concat(({ "Red", "Blue" }), ", ")))
end

function TeamService.getTeam(name: string): Team?
	return teams[name]
end

function TeamService.getAllTeams(): { Team }
	local out = {}
	for _, t in teams do
		table.insert(out, t)
	end
	return out
end

function TeamService.getTeamCounts(): { [string]: number }
	local counts: { [string]: number } = {}
	for name in teams do
		counts[name] = 0
	end
	for _, player in Players:GetPlayers() do
		if player.Team and counts[player.Team.Name] ~= nil then
			counts[player.Team.Name] += 1
		end
	end
	return counts
end

-- Returns the team currently holding the fewest players. Tie → first
-- registered team in TEAM_DEFS order, so the result is deterministic.
-- Returns nil when TEAMS_ENABLED is off (no teams exist to balance).
function TeamService.getSmallestTeam(): Team?
	if not GameConfig.TEAMS_ENABLED then
		return nil
	end
	local counts = TeamService.getTeamCounts()
	local smallest: Team? = nil
	local smallestCount = math.huge
	for _, def in TEAM_DEFS do
		local count = counts[def.name] or 0
		if count < smallestCount then
			smallest = teams[def.name]
			smallestCount = count
		end
	end
	return smallest
end

-- Place the player on a specific team by name. Returns nil if the
-- team doesn't exist (logs a warning).
function TeamService.setTeamForPlayer(player: Player, teamName: string): Team?
	if not GameConfig.TEAMS_ENABLED then
		return nil
	end
	local team = teams[teamName]
	if not team then
		log:warn(string.format("setTeamForPlayer: unknown team '%s'", teamName))
		return nil
	end
	player.Team = team
	player.Neutral = false
	log:info(string.format("%s → %s", player.Name, teamName))
	return team
end

-- The default auto-balance flow. New joiner lands on whichever team
-- has fewer players (deterministic tie-break favours the first team
-- in TEAM_DEFS order).
function TeamService.assignToSmallestTeam(player: Player): Team?
	if not GameConfig.TEAMS_ENABLED then
		return nil
	end
	local team = TeamService.getSmallestTeam()
	if not team then
		return nil
	end
	player.Team = team
	player.Neutral = false
	log:info(string.format("%s auto-balanced → %s", player.Name, team.Name))
	return team
end

return TeamService
