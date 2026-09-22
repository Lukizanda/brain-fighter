--!strict

----------------------------------------------------------------------
-- AnalyticsReporter
----------------------------------------------------------------------
-- Turns the server's domain events into Roblox analytics: the Phase 5.4
-- onboarding funnel and the loop-health custom events. Listens only —
-- no gameplay system knows analytics exists. Each domain fires its own
-- BindableEvent on the branch where the thing actually happened
-- (BlockConsumed after the credit, WordMemorized after the ledger said
-- yes, SpellCast after the executor ran), so this file can never
-- report a pop the server refused.
--
-- Two attributes on each Player make the funnel visible without a
-- dashboard: `Analytics_FunnelStep` (highest step logged) and
-- `Analytics_Events` (custom events sent for that player). The suite
-- and the playtest probe read those.
--
-- See wiki/systems/Analytics.md.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local AnalyticsConstants = require(script.Parent.AnalyticsConstants)
local AnalyticsSink = require(script.Parent.AnalyticsSink)
local OnboardingFunnel = require(script.Parent.OnboardingFunnel)
local BossSpawner = require(script.Parent.Parent.Boss.Scripts.BossSpawner)
local SessionRegistry = require(ServerScriptService.Server.GameMode.Scripts.SessionRegistry)

local log = Logger.new("Analytics")

local server = script.Parent.Parent
local blockConsumedEvent = server.BlockShoot.Events.BlockConsumed :: BindableEvent
local wordMemorizedEvent = server.Economy.Events.WordMemorized :: BindableEvent
local memorizeFizzledEvent = server.Economy.Events.MemorizeFizzled :: BindableEvent
local spellCastEvent = server.SpellCast.Events.SpellCast :: BindableEvent
local playerDamagedEvent = server.Health.Events.PlayerDamaged :: BindableEvent
local roundStartedEvent = server.GameMode.Events.RoundStarted :: BindableEvent
local roundEndedEvent = server.GameMode.Events.RoundEnded :: BindableEvent
local bossDefeatedEvent = ReplicatedStorage.Shared.Boss.BossEvents.BossDefeated :: BindableEvent

local Step = AnalyticsConstants.Funnel
local Event = AnalyticsConstants.Event
local Field = AnalyticsConstants.Field
local ATTR = AnalyticsConstants.Attributes

local sink = AnalyticsSink.new()
local funnel = OnboardingFunnel.new(sink)

-- Per-player bookkeeping for the aggregated events.
local joinedAt: { [Player]: number } = {}
local popsBy: { [Player]: number } = {}

local ROUND_PLAYED_VALUE = 1
local FIZZLE_VALUE = 1

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function publishStep(player: Player)
	if player.Parent then
		player:SetAttribute(ATTR.FunnelStep, funnel:stepOf(player))
	end
end

local function reach(player: Player, step: number)
	if funnel:reach(player, step) then
		log:info(string.format("%s → %s", player.Name, AnalyticsConstants.FUNNEL_NAMES[step]))
		publishStep(player)
	end
end

local function custom(player: Player, eventName: string, value: number, fields: AnalyticsSink.Fields?)
	if not sink:custom(player, eventName, value, fields) then
		return
	end
	if player.Parent then
		local count = player:GetAttribute(ATTR.Events)
		player:SetAttribute(ATTR.Events, (if type(count) == "number" then count else 0) + 1)
	end
end

local function isBoss(humanoid: Instance?): boolean
	local model = humanoid and humanoid:FindFirstAncestorOfClass("Model")
	return model ~= nil and CollectionService:HasTag(model, BossSpawner.BOSS_TAG)
end

local function rosterOf(arenaId: string): { Player }
	return SessionRegistry.rosterOf(arenaId) or {}
end

local function modeNameOf(arenaId: string): string
	local session = SessionRegistry.forArena(arenaId)
	local mode = session and session:getMode()
	return if mode and type(mode.name) == "string" then mode.name else arenaId
end

----------------------------------------------------------------------
-- Player lifecycle
----------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	joinedAt[player] = os.clock()
	popsBy[player] = 0
	player:SetAttribute(ATTR.Events, 0)
	reach(player, Step.Joined)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	local started = joinedAt[player]
	if started then
		custom(player, Event.SessionLength, math.floor(os.clock() - started), nil)
	end
	local pops = popsBy[player]
	if pops and pops > 0 then
		custom(player, Event.BlocksPopped, pops, nil)
	end
	joinedAt[player] = nil
	popsBy[player] = nil
	funnel:forget(player)
end)

----------------------------------------------------------------------
-- The loop
----------------------------------------------------------------------

blockConsumedEvent.Event:Connect(function(player: Player, _letter: string, _color: string, _arenaId: string)
	popsBy[player] = (popsBy[player] or 0) + 1
	reach(player, Step.FirstPop)
end)

wordMemorizedEvent.Event:Connect(function(player: Player, word: string, energyByColor: { [string]: number }?)
	reach(player, Step.FirstMemorize)
	local energy = 0
	for _, amount in energyByColor or {} do
		energy += amount
	end
	custom(player, Event.WordMemorized, energy, {
		[Field.One] = tostring(#word),
	})
end)

memorizeFizzledEvent.Event:Connect(function(player: Player)
	custom(player, Event.MemorizeFizzle, FIZZLE_VALUE, nil)
end)

spellCastEvent.Event:Connect(function(player: Player, spellName: string, color: string, tier: number, cost: number, _targetName: string?)
	reach(player, Step.FirstCast)
	custom(player, Event.SpellCast, cost, {
		[Field.One] = color,
		[Field.Two] = tostring(tier),
		[Field.Three] = spellName,
	})
end)

playerDamagedEvent.Event:Connect(function(sourcePlayer: Player?, targetHumanoid: Instance?, _result: any)
	if sourcePlayer and isBoss(targetHumanoid) then
		reach(sourcePlayer, Step.FirstBossDamage)
	end
end)

bossDefeatedEvent.Event:Connect(function(arenaId: string)
	for _, player in rosterOf(arenaId) do
		reach(player, Step.BossKill)
	end
end)

----------------------------------------------------------------------
-- Rounds
----------------------------------------------------------------------

roundStartedEvent.Event:Connect(function(_roster: { Player }?, _arenaId: string)
	-- Nothing logged at start: a round that ends tells the whole story,
	-- and a player who leaves mid-round is visible as a round_played
	-- they are missing from.
end)

roundEndedEvent.Event:Connect(function(winnerId: number?, _winnerName: string?, arenaId: string, outcome: string?)
	local modeName = modeNameOf(arenaId)
	for _, player in rosterOf(arenaId) do
		local result = if winnerId == nil then "none" elseif winnerId == player.UserId then "won" else "lost"
		custom(player, Event.RoundPlayed, ROUND_PLAYED_VALUE, {
			[Field.One] = modeName,
			[Field.Two] = tostring(outcome),
			[Field.Three] = result,
		})
	end
end)

log:info(string.format("ready — funnel of %d steps, budget %d burst / %.1f per s",
	#AnalyticsConstants.FUNNEL_NAMES, AnalyticsConstants.SEND_BURST, AnalyticsConstants.SEND_PER_SEC))
