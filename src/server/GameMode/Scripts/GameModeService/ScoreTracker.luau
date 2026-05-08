----------------------------------------------------------------------
-- ScoreTracker
----------------------------------------------------------------------
-- Server-authoritative kill/death/assist tracking.
-- Standalone module — initialized with dependencies, no globals.
-- Supports per-player scores and optional leaderstats integration.
-- Assist tracking uses a configurable time window.
--
-- Usage:
--   ScoreTracker.initialize({ scoreUpdateRemote = ..., killFeedRemote = ... })
--   ScoreTracker.addPlayer(player)
--   ScoreTracker.recordKill(killer, victim, weaponName)
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local log = Logger.new("ScoreTracker")

local ScoreTracker = {}

-- Configuration
local ASSIST_TIME_WINDOW = 10 -- seconds: damage within this window earns an assist

-- Internal state
local scores: { [Player]: { kills: number, deaths: number, assists: number } } = {}
local recentDamage: { [Humanoid]: { { player: Player, timestamp: number } } } = {}
local leaderstatsFolders: { [Player]: Folder } = {}

-- Dependencies (injected via initialize)
type Refs = {
	scoreUpdateRemote: RemoteEvent?,
	killFeedRemote: RemoteEvent?,
	playerDamagedEvent: BindableEvent?,
}
local refs: Refs = {} :: Refs

local initialized = false

----------------------------------------------------------------------
-- Leaderstats
----------------------------------------------------------------------
local function createLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	folder.Parent = player

	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Value = 0
	kills.Parent = folder

	local deaths = Instance.new("IntValue")
	deaths.Name = "Deaths"
	deaths.Value = 0
	deaths.Parent = folder

	leaderstatsFolders[player] = folder
	return folder
end

local function updateLeaderstats(player: Player)
	local folder = leaderstatsFolders[player]
	local score = scores[player]
	if not folder or not score then
		return
	end
	local killsVal = folder:FindFirstChild("Kills")
	local deathsVal = folder:FindFirstChild("Deaths")
	if killsVal then killsVal.Value = score.kills end
	if deathsVal then deathsVal.Value = score.deaths end
end

----------------------------------------------------------------------
-- Damage tracking (for assists)
----------------------------------------------------------------------
local function recordDamage(sourcePlayer: Player?, targetHumanoid: Humanoid)
	if not sourcePlayer then
		return
	end

	if not recentDamage[targetHumanoid] then
		recentDamage[targetHumanoid] = {}
	end

	table.insert(recentDamage[targetHumanoid], {
		player = sourcePlayer,
		timestamp = os.clock(),
	})
end

local function getAssistants(killer: Player?, targetHumanoid: Humanoid): { Player }
	local assistants = {}
	local entries = recentDamage[targetHumanoid]
	if not entries then
		return assistants
	end

	local now = os.clock()
	local seen: { [Player]: boolean } = {}

	for _, entry in entries do
		local isRecent = (now - entry.timestamp) <= ASSIST_TIME_WINDOW
		local isNotKiller = entry.player ~= killer
		local isAlive = entry.player.Parent ~= nil -- still in game
		local isNotCounted = not seen[entry.player]

		if isRecent and isNotKiller and isAlive and isNotCounted then
			seen[entry.player] = true
			table.insert(assistants, entry.player)
		end
	end

	-- Clean up damage history for this target
	recentDamage[targetHumanoid] = nil

	return assistants
end

----------------------------------------------------------------------
-- Score broadcast
----------------------------------------------------------------------
local function broadcastScores()
	local scoreUpdateRemote = refs.scoreUpdateRemote
	if not scoreUpdateRemote then
		return
	end

	-- Serialize scores keyed by UserId for network transport
	local serialized: { [number]: { kills: number, deaths: number, assists: number, playerName: string } } = {}
	for player, score in scores do
		serialized[player.UserId] = {
			kills = score.kills,
			deaths = score.deaths,
			assists = score.assists,
			playerName = player.Name,
		}
	end

	scoreUpdateRemote:FireAllClients(serialized)
end

local function broadcastKillFeed(killer: Player?, victim: Player, weaponName: string)
	local killFeedRemote = refs.killFeedRemote
	if not killFeedRemote then
		return
	end

	killFeedRemote:FireAllClients({
		killerId = killer and killer.UserId or 0,
		killerName = killer and killer.Name or "Environment",
		victimId = victim.UserId,
		victimName = victim.Name,
		weaponName = weaponName or "Unknown",
	})
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function ScoreTracker.initialize(dependencies: {
	scoreUpdateRemote: RemoteEvent?,
	killFeedRemote: RemoteEvent?,
	playerDamagedEvent: BindableEvent?,
})
	if initialized then
		log:warn("Already initialized")
		return
	end

	refs = dependencies
	initialized = true

	-- Listen to damage events for assist tracking
	local playerDamagedEvent = refs.playerDamagedEvent
	if playerDamagedEvent then
		playerDamagedEvent.Event:Connect(function(sourcePlayer, targetHumanoid, _result)
			recordDamage(sourcePlayer, targetHumanoid)
		end)
	end

	log:info("Initialized")
end

function ScoreTracker.addPlayer(player: Player)
	if scores[player] then
		return
	end

	scores[player] = { kills = 0, deaths = 0, assists = 0 }
	createLeaderstats(player)
	log:info("Added player:", player.Name)
end

function ScoreTracker.removePlayer(player: Player)
	scores[player] = nil
	leaderstatsFolders[player] = nil

	-- Clean up any damage entries referencing this player
	for humanoid, entries in recentDamage do
		for i = #entries, 1, -1 do
			if entries[i].player == player then
				table.remove(entries, i)
			end
		end
	end

	log:info("Removed player:", player.Name)
end

-- Record a kill. Returns the list of assistants.
function ScoreTracker.recordKill(killer: Player?, victim: Player, weaponName: string): { Player }
	-- Record death
	if scores[victim] then
		scores[victim].deaths += 1
		updateLeaderstats(victim)
	end

	-- Record kill
	if killer and scores[killer] then
		scores[killer].kills += 1
		updateLeaderstats(killer)
	end

	-- Find and record assists
	local victimCharacter = victim.Character
	local targetHumanoid = victimCharacter and victimCharacter:FindFirstChildOfClass("Humanoid")
	local assistants = targetHumanoid and getAssistants(killer, targetHumanoid) or {}

	for _, assistant in assistants do
		if scores[assistant] then
			scores[assistant].assists += 1
			updateLeaderstats(assistant)
		end
	end

	log:info(string.format(
		"Kill: %s -> %s (weapon=%s, assists=%d)",
		killer and killer.Name or "Environment",
		victim.Name,
		weaponName or "Unknown",
		#assistants
	))

	broadcastKillFeed(killer, victim, weaponName)
	broadcastScores()

	return assistants
end

-- Record a kill on a non-Player victim (dev bot, NPC, etc). Increments the
-- killer's score and fires a kill-feed entry that includes explicit team-
-- color overrides so the UI doesn't try to look the victim up via UserId.
-- Does NOT track victim deaths (no Player to track) and does NOT broadcast
-- assists. Used by `BotSpawner` so Step-5 tuning can run solo.
function ScoreTracker.recordBotKill(killer: Player?, victimDisplayName: string, victimTeamColor: Color3?, weaponName: string)
	if killer and scores[killer] then
		scores[killer].kills += 1
		updateLeaderstats(killer)
	end

	local killFeedRemote = refs.killFeedRemote
	if killFeedRemote then
		killFeedRemote:FireAllClients({
			killerId = killer and killer.UserId or 0,
			killerName = killer and killer.Name or "Environment",
			victimId = -1, -- sentinel: non-Player victim
			victimName = victimDisplayName,
			victimTeamColor = victimTeamColor,
			weaponName = weaponName or "Unknown",
		})
	end

	broadcastScores()

	log:info(string.format(
		"Bot kill: %s -> %s (weapon=%s)",
		killer and killer.Name or "Environment",
		victimDisplayName,
		weaponName or "Unknown"
	))
end

function ScoreTracker.getScore(player: Player): { kills: number, deaths: number, assists: number }?
	return scores[player]
end

function ScoreTracker.getAllScores(): { [Player]: { kills: number, deaths: number, assists: number } }
	return scores
end

function ScoreTracker.resetAll()
	for player, score in scores do
		score.kills = 0
		score.deaths = 0
		score.assists = 0
		updateLeaderstats(player)
	end
	recentDamage = {}
	broadcastScores()
	log:info("All scores reset")
end

function ScoreTracker.getWinner(): Player?
	local bestPlayer: Player? = nil
	local bestKills = -1
	for player, score in scores do
		if score.kills > bestKills then
			bestKills = score.kills
			bestPlayer = player
		end
	end
	return bestPlayer
end

return ScoreTracker
