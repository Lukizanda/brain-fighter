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
-- Spores: pops carry zone "Spore", their boss damage is spell "Spore" tier 1,
-- and spore_lob / spore_burst are observed off the blocks (see the end).
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
local BossConstants = require(Shared.Boss.BossConstants)
local BreakableWallConstants = require(Shared.Arena.BreakableWallConstants)
local LetterBlocks = require(Shared.LetterBlocks)
local Logger = require(Shared.Core.Logger)
local PlaytestMetrics = require(Shared.Playtest.PlaytestMetrics)
local SpellRegistry = require(Shared.SpellRegistry)
local SporeConstants = require(Shared.BlockSpawner.SporeConstants)

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
type Drop = { event: Event, amount: number, lethal: boolean, at: number }
type Burst = { event: Event, at: number }
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
	-- Spore bookkeeping. The last boss health drop and a spore-pop damage not
	-- yet seen as a drop, so either arrival order pairs them up.
	lastDrop: Drop?,
	sporeOwed: number,
	sporeOwedAt: number,
	-- Spores landed and not yet written out as one `spore_lob`.
	lobPending: number,
	lobScheduled: boolean,
	-- `spore_burst` events still waiting to learn whether they hurt anyone.
	bursts: { Burst },
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

-- Spore pop damage. The boss's HealthChanged and the Health system's
-- PlayerDamaged (which carries the cause) can arrive in either order, so
-- each side checks for the other: whichever comes second pairs them. A drop
-- of the right size that arrived first is relabelled; damage that arrived
-- first is held (`sporeOwed`) for the drop. A lethal drop may be smaller
-- than the damage (health stops at 0).
local function sameDamage(drop: number, damage: number, lethal: boolean): boolean
	return math.abs(drop - damage) <= C.DAMAGE_MATCH_TOLERANCE or (lethal and drop <= damage + C.DAMAGE_MATCH_TOLERANCE)
end

-- HealthChanged side: is this drop the spore pop already announced?
local function sporePopOwes(f: Fight, drop: number, lethal: boolean): boolean
	if f.sporeOwed > 0 and os.clock() - f.sporeOwedAt <= C.ATTRIBUTION_WINDOW_SEC and sameDamage(drop, f.sporeOwed, lethal) then
		f.sporeOwed = 0
		return true
	end
	return false
end

-- PlayerDamaged side: the boss took `damage` from a spore pop.
local function notePopDamage(f: Fight, damage: number)
	local last = f.lastDrop
	if last and os.clock() - last.at <= C.ATTRIBUTION_WINDOW_SEC and sameDamage(last.amount, damage, last.lethal) then
		last.event.tier = C.SPORE_DAMAGE_TIER
		last.event.spell = C.SPORE_SPELL
		f.lastDrop = nil
	else
		f.sporeOwed = damage
		f.sporeOwedAt = os.clock()
	end
end

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
			local drop = f.bossLastHp - hp
			local fields: Event = {
				amount = fraction,
				tier = math.clamp(f.lastTier, 1, C.MAX_DAMAGE_TIER),
				spell = f.lastSpell,
				bossHp = hp / math.max(f.bossMax, 1),
			}
			if sporePopOwes(f, drop, hp <= 0) then
				fields.tier = C.SPORE_DAMAGE_TIER
				fields.spell = C.SPORE_SPELL
				f.lastDrop = nil
			else
				f.lastDrop = { event = fields, amount = drop, lethal = hp <= 0, at = os.clock() }
			end
			emit(f, "boss_damage", fields)
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
		lastDrop = nil,
		sporeOwed = 0,
		sporeOwedAt = 0,
		lobPending = 0,
		lobScheduled = false,
		bursts = {},
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

blockConsumedEvent.Event:Connect(function(_player: Player, letter: string, color: string, arenaId: string, wasSpore: boolean?)
	if fight and fight.arena == arenaId then
		emit(fight, "pop", { letter = letter, color = color, zone = if wasSpore == true then C.SPORE_ZONE else "?" })
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
	if f and targetHumanoid and targetHumanoid == f.bossHumanoid and result.cause == BossConstants.SPORE_POP_CAUSE then
		notePopDamage(f, result.finalDamage)
		return
	end
	local victim = playerOfHumanoid(targetHumanoid)
	if not f or not victim or not inArena(f, victim) or not targetHumanoid then
		return
	end
	if result.cause == BossConstants.SPORE_BURST_CAUSE then
		for _, burst in f.bursts do
			if os.clock() - burst.at <= C.ATTRIBUTION_WINDOW_SEC and not burst.event.hit then
				burst.event.hit = true
				break
			end
		end
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

-- Spore lobs and bursts have no signal of their own (the Boss system fires
-- none), so they are read off the blocks: a letter block gaining the spore
-- mark has landed, and a marked block destroyed at its fuse time has burst
-- (earlier it was popped or cleared). The times are landing and burst times,
-- not the throw. Which burst hurt anyone comes from the SporeBurst damage.
local watchedSpores: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function sporeLanded(f: Fight)
	f.lobPending += 1
	if f.lobScheduled then
		return
	end
	f.lobScheduled = true
	task.delay(C.LOB_BATCH_SEC, function()
		f.lobScheduled = false
		local count = f.lobPending
		f.lobPending = 0
		if fight == f and count > 0 then
			emit(f, "spore_lob", { count = count })
		end
	end)
end

local function sporeGone(f: Fight, block: Instance)
	local expires = block:GetAttribute(SporeConstants.EXPIRES_ATTRIBUTE)
	if type(expires) ~= "number" or workspace:GetServerTimeNow() < expires - C.BURST_SLACK_SEC then
		return
	end
	local fields: Event = { hit = false }
	emit(f, "spore_burst", fields)
	table.insert(f.bursts, { event = fields, at = os.clock() })
end

CollectionService:GetInstanceAddedSignal(LetterBlocks.TAG):Connect(function(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local function check()
		if watchedSpores[instance] or instance:GetAttribute(SporeConstants.ATTRIBUTE) ~= true then
			return
		end
		watchedSpores[instance] = true
		local f = fight
		if f and Arena.idOf(instance) == f.arena then
			sporeLanded(f)
		end
		instance.Destroying:Connect(function()
			local g = fight
			if g and Arena.idOf(instance) == g.arena then
				sporeGone(g, instance)
			end
		end)
	end
	check()
	instance:GetAttributeChangedSignal(SporeConstants.ATTRIBUTE):Connect(check)
end)

log:info("ready - waiting for a PlaytestBot attribute and a round start")
