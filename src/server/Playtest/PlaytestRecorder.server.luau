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
-- The two-phase scramble puzzle (wiki/design/scramble-bomb.md): the Boss bomb
-- events (BombLanded, BombPopped, BombDefused, BombHatched, BombBurst; BombBroken
-- is not needed, it fires at the hatch just before BombHatched) plus the puzzle
-- Models (tag ScrambleBomb, parts Tile<i>) are written in FightSim's event
-- names: bomb_land, bomb_engage, bomb_accept, bomb_wrong, bomb_defuse,
-- bomb_hatch, seeker_end, seekers_done. The boss damage of a solved word (cause
-- BombDefuse) is spell "Bomb", the player damage of a burst (cause BombBurst)
-- source "Seeker", and the word's energy from WordGranted a memorize flagged
-- `bomb`. The report JSON also gets a `bomb` summary beside `metrics`.
-- Not observable server-side: seekers popped (INFERRED: a hatched part that
-- vanished and no BombBurst claimed within SEEKER_RESOLVE_SEC; BombPopped is
-- not fired for a pop of a seeker), how a burst came about (INFERRED from the
-- part as it was removed: end of life, within the trigger distance of the
-- recorded player, else a wall; "burst" when no removal was seen), whether the
-- player noticed or abandoned a puzzle (bomb_engage is the first resting tap;
-- no bomb_abandon is written), the word-search seconds lost (`lost` is 0), cover,
-- and a tap's player when several are in the arena or which puzzle a tap or burst
-- belongs to when two are live (the oldest is taken).
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
local BombConstants = require(Shared.Boss.BombConstants)

local C = require(script.Parent.RecorderConstants)
local log = Logger.new("PlaytestRecorder")

local server = script.Parent.Parent
local blockConsumedEvent = server.BlockShoot.Events.BlockConsumed :: BindableEvent
local wordMemorizedEvent = server.Economy.Events.WordMemorized :: BindableEvent
local memorizeFizzledEvent = server.Economy.Events.MemorizeFizzled :: BindableEvent
local wordGrantedEvent = server.Economy.Events.WordGranted :: BindableEvent
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
-- A hatched part removed from its puzzle Model: how it looks to have ended if a
-- burst claims it; one that no BombBurst claims in time was a pop (inferred).
type Removal = { id: number, how: string, age: number }
-- A BombBurst that arrived before the removal of the part it belongs to.
type OwedBurst = { hits: number }
-- One puzzle, from its landing (BombLanded) until its model is gone. The model
-- and the event can arrive in either order, so each half is matched to the other.
type PuzzleRec = {
	model: Model?,
	letters: number,
	landed: boolean,
	landedAt: number,
	engagedAt: number?,
	refused: number,
	solved: boolean,
	hatched: boolean,
	seekersLeft: number,
	pending: { Removal },
	owed: { OwedBurst },
	ended: boolean,
}
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
	-- Spell and tier the held damage is labelled with (spore pop or bomb defuse).
	owedSpell: string,
	owedTier: number,
	-- Puzzles landed (and their models seen), oldest first.
	puzzles: { PuzzleRec },
	-- The Brain's seeker numbers, to tell how a removed seeker ended.
	seekerLifetimeSec: number,
	seekerTriggerStuds: number,
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

-- PlayerDamaged side: the boss took `damage` from a spore pop or a bomb
-- defuse (`spell` and `tier` say which).
local function notePopDamage(f: Fight, damage: number, spell: string, tier: number)
	local last = f.lastDrop
	if last and os.clock() - last.at <= C.ATTRIBUTION_WINDOW_SEC and sameDamage(last.amount, damage, last.lethal) then
		last.event.tier = tier
		last.event.spell = spell
		f.lastDrop = nil
	else
		f.sporeOwed = damage
		f.sporeOwedAt = os.clock()
		f.owedSpell = spell
		f.owedTier = tier
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
				fields.tier = f.owedTier
				fields.spell = f.owedSpell
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

-- The puzzle's per-fight numbers, read off the event log: puzzles landed /
-- solved / hatched, accepted and refused resting taps, landing to solve,
-- seekers hatched, popped (inferred) and burst, the players the bursts hurt,
-- boss damage from solved words and its share of all boss damage, player damage
-- and deaths from bursts, and the energy of the words.
local function bombSummary(events: { Event }): { [string]: any }
	local out: { [string]: any } = {
		puzzles = 0, solved = 0, hatched = 0, tapsAccepted = 0, tapsRefused = 0,
		landToSolveSecs = {}, landToSolveMedianSec = 0,
		seekersHatched = 0, seekersPopped = 0, bursts = 0, burstHits = 0,
		wordBossDamage = 0, bossDamageTotal = 0, wordShare = 0,
		burstPlayerDamage = 0, burstDeaths = 0, wordEnergy = 0,
	}
	local secs: { number } = out.landToSolveSecs
	for _, e in events do
		local kind = e.kind
		if kind == "bomb_land" then
			out.puzzles += 1
		elseif kind == "bomb_defuse" then
			out.solved += 1
			table.insert(secs, e.sinceLand)
		elseif kind == "bomb_hatch" then
			out.hatched += 1
			out.seekersHatched += e.seekers
		elseif kind == "bomb_accept" then
			out.tapsAccepted += 1
		elseif kind == "bomb_wrong" then
			out.tapsRefused += 1
		elseif kind == "seeker_end" then
			if e.how == "popped" then
				out.seekersPopped += 1 -- inferred, see the header
			else
				out.bursts += 1
				out.burstHits += e.hits or 0
			end
		elseif kind == "memorize" and e.bomb then
			out.wordEnergy += e.red + e.green + e.blue
		elseif kind == "boss_damage" then
			out.bossDamageTotal += e.amount
			if e.spell == C.BOMB_SPELL then
				out.wordBossDamage += e.amount
			end
		elseif kind == "player_damage" then
			if e.source == C.SEEKER_BURST_SOURCE then
				out.burstPlayerDamage += e.amount
			end
		elseif kind == "death" and e.source == C.SEEKER_BURST_SOURCE then
			out.burstDeaths += 1
		end
	end
	if #secs > 0 then
		table.sort(secs)
		out.landToSolveMedianSec = secs[(#secs + 1) // 2]
	end
	if out.bossDamageTotal > 0 then
		out.wordShare = out.wordBossDamage / out.bossDamageTotal
	end
	return out
end

local function publish(f: Fight, n: number)
	local metrics = PlaytestMetrics.compute(f.events)
	local ok, json = pcall(function(): string
		return HttpService:JSONEncode({ persona = f.persona, metrics = metrics, bomb = bombSummary(f.events), events = f.events })
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
	local bossSpec: any = BossConfig.BOSS_TYPES[BossConfig.DEFAULT_TYPE]
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
		owedSpell = C.SPORE_SPELL,
		owedTier = C.SPORE_DAMAGE_TIER,
		puzzles = {},
		seekerLifetimeSec = bossSpec.bombSeekerLifetimeSec or C.SEEKER_LIFETIME_FALLBACK_SEC,
		seekerTriggerStuds = bossSpec.bombSeekerTriggerStuds or C.SEEKER_TRIGGER_FALLBACK_STUDS,
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

-- A word credited without the buffer (the scramble bomb's defuse), fired by
-- EconomyService after the ledger took it. Recorded as FightSim records it: a
-- memorize flagged `bomb`, so PlaytestMetrics counts its energy in M3 and in
-- bombEnergy.
wordGrantedEvent.Event:Connect(function(player: Player, word: string, energyByColor: { [string]: number }?, source: string?)
	if fight and inArena(fight, player) then
		local energy = energyByColor or {}
		emit(fight, "memorize", {
			word = word,
			red = energy.red or 0,
			green = energy.green or 0,
			blue = energy.blue or 0,
			bomb = true,
			source = source,
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
		notePopDamage(f, result.finalDamage, C.SPORE_SPELL, C.SPORE_DAMAGE_TIER)
		return
	end
	if f and targetHumanoid and targetHumanoid == f.bossHumanoid and result.cause == BombConstants.DEFUSE_CAUSE then
		notePopDamage(f, result.finalDamage, C.BOMB_SPELL, C.BOMB_DAMAGE_TIER)
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
	local isBurst = result.cause == BombConstants.BURST_CAUSE
	emit(f, "player_damage", {
		amount = result.finalDamage,
		source = if isBurst then C.SEEKER_BURST_SOURCE else (result.cause or "?"),
		hp = (targetHumanoid :: Humanoid).Health,
	})
end)

playerEliminatedEvent.Event:Connect(function(_source: Player?, targetHumanoid: Instance?, result: any)
	local f = fight
	local victim = playerOfHumanoid(targetHumanoid)
	if f and victim and inArena(f, victim) then
		emit(f, "death", {
			source = if result and result.cause == BombConstants.BURST_CAUSE then C.SEEKER_BURST_SOURCE else (result and result.cause or "?"),
			bossHp = bossFraction(f),
		})
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

----------------------------------------------------------------------
-- The two-phase scramble puzzle
----------------------------------------------------------------------
-- Written in FightSim's event names: bomb_land, bomb_engage (the first resting
-- tap), bomb_accept / bomb_wrong (accepted / refused resting taps), bomb_defuse,
-- bomb_hatch, seeker_end (how = popped | player | wall | expired | burst) and
-- seekers_done. The boss damage of a solved word (cause BombDefuse) is a
-- boss_damage with spell "Bomb"; a burst's player damage and death carry source
-- "Seeker"; the word's energy is a memorize flagged `bomb` (WordGranted).

local removalSeq = 0

-- The oldest live puzzle of this arena that `wanted` accepts (the recorded
-- player is alone in the arena, so puzzles rarely overlap; with two the oldest
-- is taken).
local function findPuzzle(f: Fight, arenaId: string, wanted: (PuzzleRec) -> boolean): PuzzleRec?
	if f.arena ~= arenaId then
		return nil
	end
	for _, rec in f.puzzles do
		if not rec.ended and wanted(rec) then
			return rec
		end
	end
	return nil
end

local function restingPuzzle(f: Fight, arenaId: string): PuzzleRec?
	return findPuzzle(f, arenaId, function(rec: PuzzleRec): boolean
		return not rec.hatched and not rec.solved
	end)
end

local function chasingPuzzle(f: Fight, arenaId: string): PuzzleRec?
	return findPuzzle(f, arenaId, function(rec: PuzzleRec): boolean
		return rec.hatched and rec.seekersLeft > 0
	end)
end

local function newPuzzleRec(model: Model?, letters: number, landed: boolean): PuzzleRec
	return {
		model = model, letters = letters, landed = landed, landedAt = os.clock(), engagedAt = nil, refused = 0,
		solved = false, hatched = false, seekersLeft = 0, pending = {}, owed = {}, ended = false,
	}
end

local function seekerEnded(f: Fight, rec: PuzzleRec, how: string, hits: number, age: number)
	if fight ~= f then
		return
	end
	emit(f, "seeker_end", { how = how, hit = hits > 0, hits = hits, age = age })
	rec.seekersLeft = math.max(rec.seekersLeft - 1, 0)
	if rec.seekersLeft == 0 then
		-- Word-search seconds lost are not observable server-side.
		emit(f, "seekers_done", { lost = 0 })
	end
end

-- How a seeker that is gone ended, judged from the part as it was removed (the
-- server's BombBurst carries only a hit count): at the end of its life,
-- within the trigger distance of the recorded player, else on a wall.
local function classifyRemoval(f: Fight, part: Instance): (string, number)
	local expires = part:GetAttribute(BombConstants.SEEKER_EXPIRES_ATTRIBUTE)
	local now = workspace:GetServerTimeNow()
	local age = if type(expires) == "number" then math.max(f.seekerLifetimeSec - (expires - now), 0) else 0
	if type(expires) == "number" and now >= expires - C.SEEKER_EXPIRE_SLACK_SEC then
		return "expired", age
	end
	local subject = subjectOf(f)
	local root = subject and subject.Character and subject.Character:FindFirstChild("HumanoidRootPart")
	if part:IsA("BasePart") and root and root:IsA("BasePart") then
		local delta = part.Position - root.Position
		if Vector3.new(delta.X, 0, delta.Z).Magnitude <= f.seekerTriggerStuds + C.SEEKER_CLASSIFY_SLACK_STUDS then
			return "player", age
		end
	end
	return "wall", age
end

-- A hatched part left its puzzle Model: a burst (the BombBurst event arrives in
-- the same frame, either side of it) or a pop (nothing tells: BombPopped is
-- not fired for a harmless pop, so a removal no burst claims in time is
-- INFERRED to be a pop). Parts that never hatched vanish at the hatch or the
-- solve and are ignored.
local function seekerRemoved(f: Fight, rec: PuzzleRec, part: Instance)
	if part:GetAttribute(BombConstants.HATCHED_ATTRIBUTE) ~= true then
		return
	end
	local how, age = classifyRemoval(f, part)
	local owed = table.remove(rec.owed, 1)
	if owed then
		seekerEnded(f, rec, how, owed.hits, age)
		return
	end
	removalSeq += 1
	local id = removalSeq
	table.insert(rec.pending, { id = id, how = how, age = age })
	task.delay(C.SEEKER_RESOLVE_SEC, function()
		for i, removal in rec.pending do
			if removal.id == id then
				table.remove(rec.pending, i)
				seekerEnded(f, rec, "popped", 0, removal.age)
				return
			end
		end
	end)
end

local tracked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- A puzzle Model appeared: match it to its BombLanded record, or make one that
-- BombLanded will claim.
local function trackPuzzle(model: Model)
	local f = fight
	if not f or tracked[model] or Arena.idOf(model) ~= f.arena then
		return
	end
	local lettersText = model:GetAttribute(BombConstants.LETTERS_ATTRIBUTE)
	if type(lettersText) ~= "string" then
		log:warn("a ScrambleBomb without its letters was not tracked")
		return
	end
	tracked[model] = true
	local rec: PuzzleRec? = nil
	for _, candidate in f.puzzles do
		if candidate.model == nil and candidate.letters == #lettersText then
			rec = candidate
			break
		end
	end
	if not rec then
		rec = newPuzzleRec(model, #lettersText, false)
		table.insert(f.puzzles, rec :: PuzzleRec)
	end
	local puzzle = rec :: PuzzleRec
	puzzle.model = model
	table.insert(f.conns, model.ChildRemoved:Connect(function(child: Instance)
		seekerRemoved(f, puzzle, child)
	end))
	-- The model is destroyed when solved, with its last seeker, or on boss
	-- death / round end. Late, so the events of that frame have arrived.
	model.Destroying:Connect(function()
		task.delay(C.SEEKER_RESOLVE_SEC, function()
			puzzle.ended = true
		end)
	end)
end

CollectionService:GetInstanceAddedSignal(BombConstants.TAG):Connect(function(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local function attach()
		trackPuzzle(instance)
	end
	attach()
	instance:GetAttributeChangedSignal(Arena.ID_ATTRIBUTE):Connect(attach)
end)

local bombEvents = server.Boss:FindFirstChild("Events")
local function bombEvent(name: string): BindableEvent?
	local found = bombEvents and bombEvents:WaitForChild(name, C.BOMB_EVENT_WAIT_SEC)
	if not found or not found:IsA("BindableEvent") then
		log:warn(string.format("bomb event %s not found - the puzzle is not recorded through it", name))
		return nil
	end
	return found
end

task.spawn(function()
	local landed = bombEvent(BombConstants.LANDED_EVENT)
	local defused = bombEvent(BombConstants.DEFUSED_EVENT)
	local burst = bombEvent(BombConstants.BURST_EVENT)
	local popped = bombEvent(BombConstants.POPPED_EVENT)
	local hatched = bombEvent(BombConstants.HATCHED_EVENT)
	-- BombBroken is not listened to: it now fires at the hatch, just before
	-- BombHatched, which carries everything the recorder writes for it.
	if landed then
		landed.Event:Connect(function(arenaId: string, letterCount: number)
			local f = fight
			if not f or f.arena ~= arenaId then
				return
			end
			local rec: PuzzleRec? = nil
			for _, candidate in f.puzzles do
				if not candidate.landed and candidate.letters == letterCount then
					rec = candidate
					break
				end
			end
			if not rec then
				rec = newPuzzleRec(nil, letterCount, true)
				table.insert(f.puzzles, rec :: PuzzleRec)
			end
			local puzzle = rec :: PuzzleRec
			puzzle.landed = true
			puzzle.landedAt = os.clock()
			emit(f, "bomb_land", { letters = letterCount })
		end)
	end
	-- A resting tap that was judged: accepted (the letter locked) or refused.
	if popped then
		popped.Event:Connect(function(arenaId: string, accepted: boolean)
			local f = fight
			local rec = if f then restingPuzzle(f, arenaId) else nil
			if not f or not rec then
				return
			end
			if rec.engagedAt == nil then
				rec.engagedAt = os.clock()
				emit(f, "bomb_engage", { letters = rec.letters })
			end
			if accepted then
				emit(f, "bomb_accept")
			else
				rec.refused += 1
				emit(f, "bomb_wrong")
			end
		end)
	end
	-- The word was completed: the boss damage and the energy come from their
	-- own signals (the damage request, WordGranted).
	if defused then
		defused.Event:Connect(function(_player: Player?, _word: string, _color: string, arenaId: string, letterCount: number)
			local f = fight
			local rec = if f then restingPuzzle(f, arenaId) else nil
			if not f or not rec then
				return
			end
			rec.solved = true
			local now = os.clock()
			emit(f, "bomb_defuse", {
				sec = now - (rec.engagedAt or rec.landedAt), wrong = rec.refused, lost = 0, energy = 0,
				letters = letterCount, sinceLand = now - rec.landedAt,
			})
		end)
	end
	-- The timer ran out: seekerCount letters become seekers.
	if hatched then
		hatched.Event:Connect(function(arenaId: string, seekerCount: number)
			local f = fight
			local rec = if f then restingPuzzle(f, arenaId) else nil
			if not f or not rec then
				return
			end
			rec.hatched = true
			rec.seekersLeft = seekerCount
			emit(f, "bomb_hatch", {
				seekers = seekerCount, locked = rec.letters - seekerCount, engaged = rec.engagedAt ~= nil, lost = 0,
			})
		end)
	end
	-- One seeker burst. Its part's removal arrives in the same frame, either
	-- side of this event.
	if burst then
		burst.Event:Connect(function(arenaId: string, hitCount: number)
			local f = fight
			local rec = if f then chasingPuzzle(f, arenaId) else nil
			if not f or not rec then
				return
			end
			local removal = table.remove(rec.pending, 1)
			if removal then
				seekerEnded(f, rec, removal.how, hitCount, removal.age)
				return
			end
			local owed = { hits = hitCount }
			table.insert(rec.owed, owed)
			task.delay(C.SEEKER_RESOLVE_SEC, function()
				local at = table.find(rec.owed, owed)
				if at then
					-- No removal seen: the burst is real, how it ended is not known.
					table.remove(rec.owed, at)
					seekerEnded(f, rec, "burst", hitCount, 0)
				end
			end)
		end)
	end
end)

log:info("ready - waiting for a PlaytestBot attribute and a round start")
