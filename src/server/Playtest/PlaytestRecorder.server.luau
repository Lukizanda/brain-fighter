--!strict

----------------------------------------------------------------------
-- PlaytestRecorder
----------------------------------------------------------------------
-- Server half of Tier 2 of the automated boss-arena playtest
-- (wiki/design/ai-playtest.md). Listens to the domain BindableEvents and
-- writes one event log per arena round in the schema PlaytestMetrics
-- reads, then scores it and publishes it as
-- `workspace.PlaytestReport.Fight_<n>` (a StringValue holding JSON).
--
-- Off unless RunService:IsStudio() and workspace attribute `PlaytestBot`
-- is set; `PlaytestArena` names the arena (default IslandReview). It only
-- listens: no gameplay system knows it exists.
--
-- Not recorded: tow_start and tow_stolen (no server signal), boss
-- projectile counts (shots, shotsHit).
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local Shared = ReplicatedStorage.Shared
local Arena = require(Shared.GameMode.Arena)
local BossConfig = require(Shared.Boss.BossConfig)
local BreakableWallConstants = require(Shared.Arena.BreakableWallConstants)
local Logger = require(Shared.Core.Logger)
local PlaytestMetrics = require(Shared.Playtest.PlaytestMetrics)
local SpellRegistry = require(Shared.SpellRegistry)

local C = require(script.Parent.RecorderConstants)
local log = Logger.new("PlaytestRecorder")

local server = script.Parent.Parent
local blockConsumedEvent = server.BlockShoot.Events.BlockConsumed :: BindableEvent
local wordMemorizedEvent = server.Economy.Events.WordMemorized :: BindableEvent
local memorizeFizzledEvent = server.Economy.Events.MemorizeFizzled :: BindableEvent
local spellCastEvent = server.SpellCast.Events.SpellCast :: BindableEvent
local playerDamagedEvent = server.Health.Events.PlayerDamaged :: BindableEvent
local playerEliminatedEvent = server.Health.Events.PlayerEliminated :: BindableEvent
local roundStartedEvent = server.GameMode.Events.RoundStarted :: BindableEvent
local roundEndedEvent = server.GameMode.Events.RoundEnded :: BindableEvent
local bossDefeatedEvent = Shared.Boss.BossEvents.BossDefeated :: BindableEvent
local playerEnteredEvent = Shared.Arena.ArenaEvents.PlayerEntered :: BindableEvent

type Event = { [string]: any }
type Fight = {
	arena: string,
	persona: string,
	startedAt: number,
	events: { Event },
	won: boolean,
	boss: Model?,
	bossHumanoid: Humanoid?,
	bossMax: number,
	bossLastHp: number,
	attackRange: number,
	lastSpell: string,
	lastTier: number,
	wallsBroken: number,
	conns: { RBXScriptConnection },
}

local fight: Fight? = nil
local fightsDone = 0

local function arenaName(): string
	local value = workspace:GetAttribute(C.ARENA_ATTRIBUTE)
	return if type(value) == "string" and value ~= "" then value else C.DEFAULT_ARENA
end

local function emit(f: Fight, kind: string, fields: Event?)
	local e: Event = fields or {}
	e.t = os.clock() - f.startedAt
	e.kind = kind
	table.insert(f.events, e)
end

local function inArena(f: Fight, player: Player): boolean
	return player:GetAttribute(Arena.ID_ATTRIBUTE) == f.arena
end

-- The player being recorded: the first one standing in the arena.
local function subjectOf(f: Fight): Player?
	for _, player in Players:GetPlayers() do
		if inArena(f, player) then
			return player
		end
	end
	return nil
end

local function bossFraction(f: Fight): number
	local humanoid = f.bossHumanoid
	if not humanoid then
		return 1
	end
	return humanoid.Health / math.max(f.bossMax, 1)
end

local function playerOfHumanoid(humanoid: Instance?): Player?
	local model = humanoid and humanoid:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model)
end

----------------------------------------------------------------------
-- Boss and walls
----------------------------------------------------------------------

local function attachBoss(f: Fight, model: Model)
	if f.boss == model or Arena.idOf(model) ~= f.arena then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local typeName = model:GetAttribute("BossType")
	local spec = BossConfig.BOSS_TYPES[if type(typeName) == "string" then typeName else BossConfig.DEFAULT_TYPE]
		or BossConfig.BOSS_TYPES[BossConfig.DEFAULT_TYPE]
	f.boss = model
	f.bossHumanoid = humanoid
	f.bossMax = humanoid.MaxHealth
	f.bossLastHp = humanoid.Health
	f.attackRange = spec.attackRange
	emit(f, "boss_spawn")
	table.insert(f.conns, humanoid.HealthChanged:Connect(function(hp: number)
		local fraction = (f.bossLastHp - hp) / math.max(f.bossMax, 1)
		if hp < f.bossLastHp then
			emit(f, "boss_damage", {
				amount = fraction,
				tier = math.clamp(f.lastTier, 1, C.MAX_DAMAGE_TIER),
				spell = f.lastSpell,
				bossHp = hp / math.max(f.bossMax, 1),
			})
		elseif hp > f.bossLastHp then
			local subject = subjectOf(f)
			local character = subject and subject.Character
			local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
			emit(f, "tow_eaten", {
				healed = -fraction,
				playerAlive = playerHumanoid ~= nil and playerHumanoid.Health > 0,
			})
		end
		f.bossLastHp = hp
	end))
end

local function watchWall(f: Fight, wall: Instance)
	if not wall:IsA("BasePart") or Arena.idOf(wall) ~= f.arena then
		return
	end
	local stateName = BreakableWallConstants.Published.State
	table.insert(f.conns, wall:GetAttributeChangedSignal(stateName):Connect(function()
		local state = wall:GetAttribute(stateName)
		if state == BreakableWallConstants.State.Broken then
			f.wallsBroken += 1
		end
		emit(f, "wall_state", {
			name = wall.Name,
			state = state,
			gate = wall:GetAttribute(BreakableWallConstants.Authored.GateId),
		})
	end))
end

----------------------------------------------------------------------
-- Fight lifecycle
----------------------------------------------------------------------

local function sample(f: Fight)
	local subject = subjectOf(f)
	local character = subject and subject.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local alive = humanoid.Health > 0
	local bossRoot = f.boss and f.boss:GetPivot().Position
	local bossUp = f.bossHumanoid ~= nil and f.bossHumanoid.Health > 0 and bossRoot ~= nil
	local dist = 0
	if bossRoot then
		local delta = root.Position - bossRoot
		dist = Vector3.new(delta.X, 0, delta.Z).Magnitude
	end
	emit(f, "sample", {
		hp = if alive then humanoid.Health else 0,
		alive = alive,
		bossHp = bossFraction(f),
		dist = dist,
		bossUp = bossUp,
		canHitBoss = alive and bossUp and dist <= SpellRegistry.AUTO_TARGET_RANGE_STUDS,
		bossCanHit = alive and bossUp and dist <= f.attackRange,
	})
end

local function publish(f: Fight, n: number)
	local metrics = PlaytestMetrics.compute(f.events)
	local ok, json = pcall(function(): string
		return HttpService:JSONEncode({ persona = f.persona, metrics = metrics, events = f.events })
	end)
	if not ok then
		log:warn("could not encode fight " .. tostring(n) .. ": " .. tostring(json))
		return
	end
	local folder = workspace:FindFirstChild(C.REPORT_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = C.REPORT_FOLDER
		folder.Parent = workspace
	end
	local value = Instance.new("StringValue")
	value.Name = C.REPORT_PREFIX .. tostring(n)
	value.Value = json
	value.Parent = folder
	log:info(string.format(
		"fight %d (%s): %s ttk=%s deaths=%d pops=%d words=%d fizzles=%d casts=%d",
		n, f.persona, if f.won then C.OUTCOME_WIN else C.OUTCOME_TIMEOUT,
		if metrics.m4_ttk then string.format("%.0fs", metrics.m4_ttk) else "-",
		metrics.deaths, metrics.pops, metrics.words, metrics.fizzles, metrics.casts
	))
end

local function finishFight()
	local f = fight
	if not f then
		return
	end
	fight = nil
	for _, conn in f.conns do
		conn:Disconnect()
	end
	emit(f, "fight_end", {
		outcome = if f.won then C.OUTCOME_WIN else C.OUTCOME_TIMEOUT,
		bossHp = bossFraction(f),
		wallsBroken = f.wallsBroken,
	})
	fightsDone += 1
	publish(f, fightsDone)
	workspace:SetAttribute(C.FIGHTS_DONE_ATTRIBUTE, fightsDone)
end

local function startFight(arenaId: string)
	local persona = workspace:GetAttribute(C.BOT_ATTRIBUTE)
	if type(persona) ~= "string" or arenaId ~= arenaName() then
		return
	end
	finishFight() -- a round that never reported its end
	local f: Fight = {
		arena = arenaId,
		persona = persona,
		startedAt = os.clock(),
		events = {},
		won = false,
		boss = nil,
		bossHumanoid = nil,
		bossMax = 1,
		bossLastHp = 1,
		attackRange = 0,
		lastSpell = "?",
		lastTier = 1,
		wallsBroken = 0,
		conns = {},
	}
	fight = f
	emit(f, "fight_start", { persona = persona })
	for _, boss in CollectionService:GetTagged(C.BOSS_TAG) do
		if boss:IsA("Model") then
			attachBoss(f, boss)
		end
	end
	for _, wall in CollectionService:GetTagged(BreakableWallConstants.TAG) do
		watchWall(f, wall)
	end
	log:info(string.format("fight started: %s in %s", persona, arenaId))
	task.spawn(function()
		while fight == f do
			sample(f)
			task.wait(C.SAMPLE_EVERY_SEC)
		end
	end)
end

----------------------------------------------------------------------
-- Domain signals
----------------------------------------------------------------------

roundStartedEvent.Event:Connect(function(_roster: { Player }?, arenaId: string)
	startFight(arenaId)
end)

roundEndedEvent.Event:Connect(function(_winnerId: number?, _winnerName: string?, arenaId: string, _outcome: string?)
	if fight and fight.arena == arenaId then
		finishFight()
	end
end)

bossDefeatedEvent.Event:Connect(function(arenaId: string)
	if fight and fight.arena == arenaId then
		fight.won = true
	end
end)

-- The boss model is tagged first and stamped with its ArenaId a moment
-- later, so it is also checked when the attribute arrives.
CollectionService:GetInstanceAddedSignal(C.BOSS_TAG):Connect(function(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local function attach()
		if fight then
			attachBoss(fight, instance)
		end
	end
	attach()
	instance:GetAttributeChangedSignal(Arena.ID_ATTRIBUTE):Connect(attach)
end)

blockConsumedEvent.Event:Connect(function(_player: Player, letter: string, color: string, arenaId: string)
	if fight and fight.arena == arenaId then
		emit(fight, "pop", { letter = letter, color = color, zone = "?" })
	end
end)

wordMemorizedEvent.Event:Connect(function(player: Player, word: string, energyByColor: { [string]: number }?)
	if fight and inArena(fight, player) then
		local energy = energyByColor or {}
		emit(fight, "memorize", {
			word = word,
			red = energy.red or 0,
			green = energy.green or 0,
			blue = energy.blue or 0,
		})
	end
end)

memorizeFizzledEvent.Event:Connect(function(player: Player)
	if fight and inArena(fight, player) then
		emit(fight, "fizzle")
	end
end)

spellCastEvent.Event:Connect(function(
	player: Player, spellName: string, color: string, tier: number, cost: number, _targetName: string?
)
	local f = fight
	if not f or not inArena(f, player) then
		return
	end
	f.lastSpell = spellName
	f.lastTier = tier
	local state = if f.boss then f.boss:GetAttribute(C.BOSS_STATE_ATTRIBUTE) else nil
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	emit(f, "cast", {
		spell = spellName, color = color, tier = tier, cost = cost,
		hp = if humanoid then humanoid.Health else 0, bossState = state,
	})
end)

playerDamagedEvent.Event:Connect(function(_source: Player?, targetHumanoid: Instance?, result: any)
	local f = fight
	local victim = playerOfHumanoid(targetHumanoid)
	if not f or not victim or not inArena(f, victim) or not targetHumanoid then
		return
	end
	emit(f, "player_damage", {
		amount = result.finalDamage,
		source = result.cause or "?",
		hp = (targetHumanoid :: Humanoid).Health,
	})
end)

playerEliminatedEvent.Event:Connect(function(_source: Player?, targetHumanoid: Instance?, result: any)
	local f = fight
	local victim = playerOfHumanoid(targetHumanoid)
	if f and victim and inArena(f, victim) then
		emit(f, "death", { source = result and result.cause or "?", bossHp = bossFraction(f) })
	end
end)

playerEnteredEvent.Event:Connect(function(player: Player, arenaId: string)
	if fight and fight.arena == arenaId then
		emit(fight, "reenter", { player = player.Name })
	end
end)

log:info("ready - waiting for a PlaytestBot attribute and a round start")
