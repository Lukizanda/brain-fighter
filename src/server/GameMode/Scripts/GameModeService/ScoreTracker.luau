----------------------------------------------------------------------
-- ScoreTracker
----------------------------------------------------------------------
-- Server-authoritative kill/death/assist tracking, one instance per
-- session. `RoundManager` constructs its own tracker and forwards roster
-- changes to it, so a round start in one arena zeroes that arena's scores
-- and nobody else's. This used to be one server-wide table (refactor
-- chunk 8, F12): every session's round start wiped every player, and a
-- win check in one arena read the other arena's kills.
--
-- Two things deliberately stay module-level, because they are facts about
-- the server rather than about a session:
--   * the leaderstats mirror — one folder per Player whichever session they
--     are in; a transfer must not rebuild it.
--   * the assist history — damage arrives on HealthService's PlayerDamaged
--     event, which carries no session, and a victim's Humanoid is the same
--     object whichever tracker later asks about it.
--
-- Broadcasts go to the tracker's own members. The scoreboard a player sees
-- therefore lists only their session's roster, and a kill feed entry lands
-- only on the session the kill happened in. Payload shapes are unchanged —
-- `ScoreboardGui` and `KillFeedGui` are untouched.
--
-- Usage:
--   ScoreTracker.initialize({ scoreUpdateRemote = ..., killFeedRemote = ..., playerDamagedEvent = ... })
--   local tracker = ScoreTracker.new({}, "Default")
--   tracker:addPlayer(player)
--   tracker:recordKill(killer, victim, cause)
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("ScoreTracker")

-- Damage dealt within this many seconds of the kill earns an assist.
local ASSIST_TIME_WINDOW = 10

export type PlayerScore = { kills: number, deaths: number, assists: number }
export type Scores = { [Player]: PlayerScore }

type Refs = {
	scoreUpdateRemote: RemoteEvent?,
	killFeedRemote: RemoteEvent?,
	playerDamagedEvent: BindableEvent?,
}
local refs: Refs = {} :: Refs
local initialized = false

----------------------------------------------------------------------
-- Server-wide: leaderstats mirror
----------------------------------------------------------------------
local leaderstatsFolders: { [Player]: Folder } = {}

local function updateLeaderstats(player: Player, score: PlayerScore)
	local folder = leaderstatsFolders[player]
	if not folder then
		return
	end
	local killsValue = folder:FindFirstChild("Kills")
	local deathsValue = folder:FindFirstChild("Deaths")
	if killsValue and killsValue:IsA("IntValue") then
		killsValue.Value = score.kills
	end
	if deathsValue and deathsValue:IsA("IntValue") then
		deathsValue.Value = score.deaths
	end
end

----------------------------------------------------------------------
-- Server-wide: assist history
----------------------------------------------------------------------
-- Keyed by the *victim's* Humanoid. Bounded two ways (chunk 5, F17):
-- entries older than the assist window are dropped on every insert, and the
-- whole key goes when the Humanoid dies or is destroyed. Without both, a
-- boss or NPC humanoid in a session that never ends a round accrues an entry
-- per hit for the lifetime of the server.
type DamageEntry = { player: Player, timestamp: number }
local recentDamage: { [Humanoid]: { DamageEntry } } = {}
-- One Died/Destroying pair per tracked Humanoid, disconnected with the key.
local recentDamageCleanup: { [Humanoid]: { RBXScriptConnection } } = {}

local function forgetDamage(targetHumanoid: Humanoid)
	recentDamage[targetHumanoid] = nil

	local connections = recentDamageCleanup[targetHumanoid]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		recentDamageCleanup[targetHumanoid] = nil
	end
end

local function recordDamage(sourcePlayer: Player?, targetHumanoid: Humanoid)
	if not sourcePlayer then
		return
	end

	local entries = recentDamage[targetHumanoid]
	if not entries then
		entries = {}
		recentDamage[targetHumanoid] = entries
		-- The victim's own signals are the only reliable end of its
		-- history: a Humanoid we never see win or lose a round still dies
		-- or gets destroyed.
		recentDamageCleanup[targetHumanoid] = {
			targetHumanoid.Died:Connect(function()
				forgetDamage(targetHumanoid)
			end),
			targetHumanoid.Destroying:Connect(function()
				forgetDamage(targetHumanoid)
			end),
		}
	end

	-- Expire on insert: anything past the window can never earn an assist,
	-- so it is dead weight from here on.
	local now = os.clock()
	for index = #entries, 1, -1 do
		if (now - entries[index].timestamp) > ASSIST_TIME_WINDOW then
			table.remove(entries, index)
		end
	end

	table.insert(entries, {
		player = sourcePlayer,
		timestamp = now,
	})
end

-- Everyone other than the killer who damaged this Humanoid inside the
-- window and is still on the server. Clears the history: the kill is the
-- end of it.
local function takeAssistants(killer: Player?, targetHumanoid: Humanoid): { Player }
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
		local isPresent = entry.player.Parent ~= nil
		local isNotCounted = not seen[entry.player]

		if isRecent and isNotKiller and isPresent and isNotCounted then
			seen[entry.player] = true
			table.insert(assistants, entry.player)
		end
	end

	forgetDamage(targetHumanoid)

	return assistants
end

----------------------------------------------------------------------
-- Module API (server-wide)
----------------------------------------------------------------------

local ScoreTracker = {}
ScoreTracker.__index = ScoreTracker

function ScoreTracker.initialize(dependencies: Refs)
	if initialized then
		log:warn("Already initialized")
		return
	end

	refs = dependencies
	initialized = true

	local playerDamagedEvent = refs.playerDamagedEvent
	if playerDamagedEvent then
		playerDamagedEvent.Event:Connect(function(sourcePlayer: Player?, targetHumanoid: Humanoid, _result: any)
			recordDamage(sourcePlayer, targetHumanoid)
		end)
	end

	log:info("Initialized")
end

-- One leaderstats folder per Player for the life of their connection.
-- Idempotent, so a transfer between sessions cannot rebuild it.
function ScoreTracker.ensureLeaderstats(player: Player)
	if leaderstatsFolders[player] then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Value = 0
	kills.Parent = folder

	local deaths = Instance.new("IntValue")
	deaths.Name = "Deaths"
	deaths.Value = 0
	deaths.Parent = folder

	folder.Parent = player
	leaderstatsFolders[player] = folder
end

-- Called when a player leaves the server. Session membership is the
-- session's business (`RoundManager:removePlayer`); this drops the
-- server-wide state that referenced them.
function ScoreTracker.forgetPlayer(player: Player)
	leaderstatsFolders[player] = nil

	for _, entries in recentDamage do
		for index = #entries, 1, -1 do
			if entries[index].player == player then
				table.remove(entries, index)
			end
		end
	end
end

----------------------------------------------------------------------
-- Instances
----------------------------------------------------------------------

export type ScoreTracker = typeof(setmetatable(
	{} :: {
		_label: string,
		_scores: Scores,
		_enabled: boolean,
		_destroyed: boolean,
	},
	ScoreTracker
))

-- `roster` seeds the members; `label` is the owning session's arena id,
-- used only in logs.
function ScoreTracker.new(roster: { Player }, label: string?): ScoreTracker
	local self = setmetatable({
		_label = label or "?",
		_scores = {},
		_enabled = true,
		_destroyed = false,
	}, ScoreTracker)

	for _, player in roster do
		self:addPlayer(player)
	end

	return self
end

----------------------------------------------------------------------
-- Membership
----------------------------------------------------------------------

function ScoreTracker:addPlayer(player: Player)
	if self._destroyed or self._scores[player] then
		return
	end
	self._scores[player] = { kills = 0, deaths = 0, assists = 0 }
end

function ScoreTracker:removePlayer(player: Player)
	self._scores[player] = nil
end

function ScoreTracker:hasPlayer(player: Player): boolean
	return self._scores[player] ~= nil
end

function ScoreTracker:getMembers(): { Player }
	local members: { Player } = {}
	for player in self._scores do
		table.insert(members, player)
	end
	return members
end

----------------------------------------------------------------------
-- Reads
----------------------------------------------------------------------

function ScoreTracker:getScore(player: Player): PlayerScore?
	return self._scores[player]
end

function ScoreTracker:getAllScores(): Scores
	return self._scores
end

function ScoreTracker:getWinner(): Player?
	local bestPlayer: Player? = nil
	local bestKills = -1
	for player, score in self._scores do
		if score.kills > bestKills then
			bestKills = score.kills
			bestPlayer = player
		end
	end
	return bestPlayer
end

----------------------------------------------------------------------
-- Broadcast (to members only)
----------------------------------------------------------------------

function ScoreTracker:_fireMembers(remote: RemoteEvent, payload: any)
	for player in self._scores do
		if player.Parent then
			remote:FireClient(player, payload)
		end
	end
end

function ScoreTracker:_broadcastScores()
	local scoreUpdateRemote = refs.scoreUpdateRemote
	if not scoreUpdateRemote then
		return
	end

	-- Serialize keyed by UserId for network transport. Only this session's
	-- members are in it, which is what makes the scoreboard per session.
	local serialized: { [number]: { kills: number, deaths: number, assists: number, playerName: string } } = {}
	for player, score in self._scores do
		serialized[player.UserId] = {
			kills = score.kills,
			deaths = score.deaths,
			assists = score.assists,
			playerName = player.Name,
		}
	end

	self:_fireMembers(scoreUpdateRemote, serialized)
end

function ScoreTracker:_broadcastKillFeed(killer: Player?, victim: Player, cause: string)
	local killFeedRemote = refs.killFeedRemote
	if not killFeedRemote then
		return
	end

	self:_fireMembers(killFeedRemote, {
		killerId = killer and killer.UserId or 0,
		killerName = killer and killer.Name or "Environment",
		victimId = victim.UserId,
		victimName = victim.Name,
		weaponName = cause,
	})
end

----------------------------------------------------------------------
-- Writes
----------------------------------------------------------------------

-- Record a kill whose victim is in this session. A killer or assistant who
-- is not a member earns nothing here — they are in some other session's
-- fight, and cross-session damage is PvP-gated anyway. Returns the
-- assistants credited.
function ScoreTracker:recordKill(killer: Player?, victim: Player, cause: string): { Player }
	if not self._enabled then
		return {}
	end

	local victimScore = self._scores[victim]
	if victimScore then
		victimScore.deaths += 1
		updateLeaderstats(victim, victimScore)
	else
		log:warn(string.format("[%s] Kill recorded for a non-member victim: %s", self._label, victim.Name))
	end

	local killerScore = killer and self._scores[killer]
	if killer and killerScore then
		killerScore.kills += 1
		updateLeaderstats(killer, killerScore)
	end

	local victimCharacter = victim.Character
	local targetHumanoid = victimCharacter and victimCharacter:FindFirstChildOfClass("Humanoid")
	local assistants = targetHumanoid and takeAssistants(killer, targetHumanoid) or {}

	local credited: { Player } = {}
	for _, assistant in assistants do
		local assistantScore = self._scores[assistant]
		if assistantScore then
			assistantScore.assists += 1
			updateLeaderstats(assistant, assistantScore)
			table.insert(credited, assistant)
		end
	end

	log:info(string.format(
		"[%s] Kill: %s -> %s (cause=%s, assists=%d)",
		self._label,
		killer and killer.Name or "Environment",
		victim.Name,
		cause,
		#credited
	))

	self:_broadcastKillFeed(killer, victim, cause)
	self:_broadcastScores()

	return credited
end

-- Zero every member's score — a round start. Only this session's members,
-- and only the assist history on their own characters; another session's
-- fight is not ours to forget.
function ScoreTracker:reset()
	if not self._enabled then
		return
	end

	for player, score in self._scores do
		score.kills = 0
		score.deaths = 0
		score.assists = 0
		updateLeaderstats(player, score)

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			forgetDamage(humanoid)
		end
	end

	self:_broadcastScores()
	log:info(string.format("[%s] Scores reset", self._label))
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

-- Paused: kills and resets are ignored; membership and scores are kept.
function ScoreTracker:disable()
	self._enabled = false
end

function ScoreTracker:enable()
	if not self._destroyed then
		self._enabled = true
	end
end

function ScoreTracker:destroy()
	if self._destroyed then
		return
	end
	self:disable()
	self._destroyed = true
	table.clear(self._scores)
end

return ScoreTracker
