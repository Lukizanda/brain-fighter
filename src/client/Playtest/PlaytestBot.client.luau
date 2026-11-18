--!strict

----------------------------------------------------------------------
-- PlaytestBot
----------------------------------------------------------------------
-- Tier 2 of the automated boss-arena playtest (wiki/design/ai-playtest.md):
-- a client bot that plays one persona through the production path. It
-- walks to the arena's portal and sends the portal request, walks onto the
-- entry pad, then on the island plans words from the blocks it can see,
-- pops them through BlockTapController's `RequestPop`, memorizes through
-- EconomyReport and casts through SpellCastController's `RequestCast`.
--
-- Off unless RunService:IsStudio() and workspace attribute `PlaytestBot`
-- names a persona (PlaytestPersonas). `PlaytestArena` names the arena.
-- The server half is src/server/Playtest/PlaytestRecorder.
--
-- Spores and ward letters are popped on sight (popSpore).
-- Not played yet: cover, reacting to the boss's telegraph, stealing tows.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local Shared = ReplicatedStorage.Shared
local Arena = require(Shared.GameMode.Arena)
local ArenaEntryConstants = require(Shared.Arena.ArenaEntryConstants)
local BlockShoot = require(Shared.BlockShoot)
local WardConstants = require(Shared.BlockSpawner.WardConstants)
local Dictionary = require(Shared.Dictionary)
local LetterBlocks = require(Shared.LetterBlocks)
local Lobby = require(Shared.Lobby)
local Logger = require(Shared.Core.Logger)
local PlaytestPersonas = require(Shared.Playtest.PlaytestPersonas)
local SpellRegistry = require(Shared.SpellRegistry)

local clientRoot = script.Parent.Parent
local BotConstants = require(script.Parent.BotConstants)
local BotVocabulary = require(script.Parent.BotVocabulary)
local EconomyReport = require(clientRoot.EconomyReport)
local PlayerSession = require(clientRoot.PlayerSession)

local C = BotConstants
local log = Logger.new("PlaytestBot")
local player = Players.LocalPlayer
local portalRequest = Shared.Lobby.Remotes.PortalRequest :: RemoteEvent

type Phase = "lobby" | "ready" | "island"
type Mode = "idle" | "think" | "pop" | "charge"
type SporeState = { willPop: boolean, popAfter: number, fails: number }

local runId = 0

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function hdist(a: Vector3, b: Vector3): number
	return (flat(a) - flat(b)).Magnitude
end

-- The entry pad of the arena nearest to `from`.
local function findPad(arenaId: string, from: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, instance in CollectionService:GetTagged(ArenaEntryConstants.PAD_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) and Arena.idOf(instance) == arenaId then
			local d = hdist(instance.Position, from)
			if d < bestDist then
				best, bestDist = instance, d
			end
		end
	end
	return best
end

-- A portal does not carry the arena it sits in but the one it leads to, so
-- it is matched on TargetArenaId alone.
local function findPortal(targetArena: string, from: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, instance in CollectionService:GetTagged(Lobby.PORTAL_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace)
			and instance:GetAttribute(Lobby.Attributes.TargetArenaId) == targetArena then
			local d = hdist(instance.Position, from)
			if d < bestDist then
				best, bestDist = instance, d
			end
		end
	end
	return best
end

local function run(persona: PlaytestPersonas.Persona, myRun: number)
	local rng = Random.new()
	local session = PlayerSession.get()
	local reservoirs: any = session.energyReservoirs
	local tapController = clientRoot:WaitForChild(C.TAP_CONTROLLER_NAME)
	local castController = clientRoot:WaitForChild(C.CAST_CONTROLLER_NAME)
	local requestPop = tapController:WaitForChild(C.REQUEST_POP_NAME, C.BINDABLE_WAIT_SEC) :: BindableFunction?
	local requestCast = castController:WaitForChild(C.REQUEST_CAST_NAME, C.BINDABLE_WAIT_SEC) :: BindableFunction?
	if not requestPop or not requestCast then
		log:warn("RequestPop or RequestCast not found - the bot cannot play")
		return
	end
	BotVocabulary.preload(persona)
	log:info(string.format("started as %s", persona.name))

	local phase: Phase = "lobby"
	local mode: Mode = "idle"
	local modeUntil = 0
	local character: Model? = nil
	local lastPos: Vector3? = nil
	local goal: Vector3? = nil
	local goalSetAt = 0
	local moveIssuedAt = -math.huge
	local movedTo: Vector3? = nil
	local bossHome: Vector3? = nil
	local nextJoinAt = 0
	local nextTapAt = 0
	local popFails = 0
	local nextCastAt = 0
	local ampUntil = 0
	local queue: { BotVocabulary.Pick } = {}
	local word = ""
	local casting: { color: string, tier: number }? = nil
	-- What the bot was doing when a cast hold began, to go back to after.
	local resumeMode: Mode = "idle"
	local resumeUntil = 0
	-- Per spore seen: whether to pop it, from when, and refused taps so far.
	local sporeStates: { [Model]: SporeState } = {}
	-- When the bot got into the ready room (see PAD_WAIT_SEC).
	local readySince = 0

	local function setPhase(to: Phase)
		if to ~= phase then
			log:info(string.format("phase %s -> %s", phase, to))
			phase = to
		end
	end

	local function setMode(to: Mode, untilTime: number)
		mode = to
		modeUntil = untilTime
	end

	local function startThinking(now: number)
		setMode("think", now + persona.searchBaseSec + persona.searchPerLetterSec * persona.typicalLen)
	end

	local function walkTo(humanoid: Humanoid, target: Vector3, now: number)
		local changed = movedTo == nil or (movedTo - target).Magnitude > C.GOAL_CHANGE_STUDS
		if changed or now - moveIssuedAt >= C.MOVE_REISSUE_SEC then
			humanoid:MoveTo(target)
			movedTo = target
			moveIssuedAt = now
		end
	end

	local function readMana(): { [string]: number }
		local mana: { [string]: number } = {}
		for _, color in C.COLORS do
			mana[color] = reservoirs:get(color)
		end
		return mana
	end

	local function currentArena(): string
		local value = workspace:GetAttribute(C.ARENA_ATTRIBUTE)
		return if type(value) == "string" and value ~= "" then value else C.DEFAULT_ARENA
	end

	local function bossModel(): Model?
		local boss = workspace:FindFirstChild(C.BOSS_NAME)
		local humanoid = boss and boss:FindFirstChildOfClass("Humanoid")
		if boss and boss:IsA("Model") and humanoid and humanoid.Health > 0 then
			return boss
		end
		return nil
	end

	-- A ward letter (the boss's word ward): popped on sight like a spore, and
	-- always, since the boss cannot be hurt while one is left.
	local function isWardLetter(block: Model): boolean
		return block:GetAttribute(WardConstants.ATTRIBUTE) == true
	end

	-- Whether `block` is within tap reach of `eye` with a clear line to it.
	local function canTap(eye: Vector3, params: RaycastParams, block: Model): boolean
		local delta = block:GetPivot().Position - eye
		if delta.Magnitude > BlockShoot.MAX_RAYCAST_DISTANCE then
			return false
		end
		-- Key letters: a shorter reach of their own, from the root.
		if not BlockShoot.withinOwnReach(block, eye - Vector3.new(0, C.EYE_HEIGHT, 0)) then
			return false
		end
		local hit = workspace:Raycast(eye, delta, params)
		return hit == nil or hit.Instance:IsDescendantOf(block)
	end

	local function sightParams(char: Model): RaycastParams
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		return params
	end

	-- Blocks of this arena the character can see from head height. Spores are
	-- left out: they are popped on sight (popSpore), never spelled with.
	local function visibleBlocks(char: Model, root: BasePart, arenaId: string): { BotVocabulary.Visible }
		local eye = root.Position + Vector3.new(0, C.EYE_HEIGHT, 0)
		local params = sightParams(char)
		local out: { BotVocabulary.Visible } = {}
		for _, instance in CollectionService:GetTagged(LetterBlocks.TAG) do
			if instance:IsA("Model") and instance:IsDescendantOf(workspace) and Arena.idOf(instance) == arenaId
				and not BlockShoot.isSpore(instance) and not isWardLetter(instance) and canTap(eye, params, instance) then
				local letter, color = BlockShoot.readBlock(instance)
				if letter and color then
					table.insert(out, { model = instance, letter = letter:upper(), color = color })
				end
			end
		end
		return out
	end

	-- Pop a spore or a ward letter on sight, ahead of whatever the bot was
	-- going for (a ward letter always; the rest of this is about spores). Each spore
	-- is rolled once for whether this persona bothers (FightSim's chance) and
	-- waits the persona's reaction delay from when it was first seen. The
	-- tap shares nextTapAt with word popping, so the two never tap together.
	-- The popped letter lands in the real word buffer like any pop; it is
	-- taken straight back out, as a player discarding a tile (FightSim keeps
	-- such letters outside the plan), so the planned word is not disturbed.
	-- True if a tap was spent.
	local function popSpore(char: Model, root: BasePart, arenaId: string, now: number): boolean
		local eye = root.Position + Vector3.new(0, C.EYE_HEIGHT, 0)
		local params = sightParams(char)
		local chance = math.max(persona.reactChance, persona.stealTow) / C.SPORE_CHANCE_DIVISOR + C.SPORE_CHANCE_BASE
		for model in sporeStates do
			if not model:IsDescendantOf(workspace) then
				sporeStates[model] = nil
			end
		end
		local fresh = 0
		local target: Model? = nil
		for _, instance in CollectionService:GetTagged(LetterBlocks.TAG) do
			if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) or Arena.idOf(instance) ~= arenaId
				or not (BlockShoot.isSpore(instance) or isWardLetter(instance)) then
				continue
			end
			local ward = isWardLetter(instance)
			local state = sporeStates[instance]
			if not state then
				state = {
					willPop = ward or rng:NextNumber() < chance,
					popAfter = now + persona.reactDelaySec + fresh / persona.tapsPerSec,
					fails = 0,
				}
				sporeStates[instance] = state
				fresh += 1
			end
			if target == nil and state.willPop and now >= state.popAfter and (ward or state.fails < C.MAX_POP_FAILS)
				and canTap(eye, params, instance) then
				target = instance
			end
		end
		if not target then
			return false
		end
		local spore: Model = target
		local letter, color = BlockShoot.readBlock(spore)
		local ok, popped = pcall(function(): any
			return (requestPop :: BindableFunction):Invoke(spore)
		end)
		if ok and popped == true then
			nextTapAt = now + 1 / persona.tapsPerSec
			sporeStates[spore] = nil
			if letter and color then
				session.wordBuffer:removeLastMatching(letter, color)
			end
			log:info(string.format("popped a %s (%s)", if isWardLetter(spore) then "ward letter" else "spore", tostring(letter)))
		else
			local state = sporeStates[spore]
			if state then
				state.fails += 1
			end
			nextTapAt = now + C.TICK_SEC
		end
		return true
	end

	-- Whether a spell can land now: affordable and, for an attack, a boss in
	-- reach with a clear line. Mirrors FightSim.spellReaches.
	local function spellReaches(spec: any, char: Model, root: BasePart): boolean
		if not SpellRegistry.needsEnemyTarget(spec) then
			return true
		end
		local boss = bossModel()
		if not boss then
			return false
		end
		local lift = Vector3.new(0, C.ROOT_HEIGHT, 0)
		local from = root.Position + lift
		local to = boss:GetPivot().Position + lift
		local d = (to - from).Magnitude
		if d > SpellRegistry.AUTO_TARGET_RANGE_STUDS then
			return false
		end
		if spec.skill.delivery == "projectile" then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { char, boss }
			local hit = workspace:Raycast(from, to - from, params)
			local reach = spec.skill.deliveryParams.speed * spec.skill.deliveryParams.lifetimeSec
			return d <= reach and (hit == nil or (hit.Position - from).Magnitude >= d - C.SIGHT_TOLERANCE)
		end
		return true
	end

	-- Ask the persona what to cast and start the hold. True if one started.
	local function tryStartCast(char: Model, root: BasePart, humanoid: Humanoid, now: number): boolean
		local mana = readMana()
		local boss = bossModel()
		local bossHumanoid = boss and boss:FindFirstChildOfClass("Humanoid")
		local choice = persona.chooseCast({
			mana = mana,
			hp = humanoid.Health,
			-- The client has no shield pool to read; Shield is rarely chosen.
			shield = 0,
			bossAmped = now < ampUntil,
			bossHp = if bossHumanoid then bossHumanoid.Health / math.max(bossHumanoid.MaxHealth, 1) else 1,
			can = function(color: string, tier: number): boolean
				local spec: any = SpellRegistry.getSpell(color :: any, tier)
				return mana[color] >= spec.cost and spellReaches(spec, char, root)
			end,
		})
		if not choice then
			return false
		end
		casting = { color = choice.color, tier = choice.tier }
		resumeMode, resumeUntil = mode, modeUntil
		setMode("charge", now + SpellRegistry.chargeTimeFor(choice.tier))
		log:info(string.format("charging %s T%d", choice.color, choice.tier))
		return true
	end

	local function releaseCast(char: Model, root: BasePart, now: number)
		local cast = casting
		casting = nil
		setMode(resumeMode, math.max(resumeUntil, now))
		if not cast then
			return
		end
		local spec: any = SpellRegistry.getSpell(cast.color :: any, cast.tier)
		if readMana()[cast.color] < spec.cost or not spellReaches(spec, char, root) then
			nextCastAt = now + C.CAST_RETRY_SEC
			return
		end
		local ok, result = pcall(function(): any
			return (requestCast :: BindableFunction):Invoke(cast.color, cast.tier)
		end)
		if ok and type(result) == "table" and result.ok then
			for _, effect in spec.skill.onImpact do
				if effect.kind == "buff" then
					ampUntil = now + effect.durationSec
				end
			end
		else
			nextCastAt = now + C.CAST_RETRY_SEC
			log:info(string.format("cast refused: %s", tostring(if ok and type(result) == "table" then result.reason else result)))
		end
	end

	local function dropPlan(now: number, why: string)
		log:info(string.format("plan dropped (%s)", why))
		queue = {}
		popFails = 0
		session.wordBuffer:clear()
		startThinking(now)
	end

	-- Swap two neighbouring tiles until the buffer no longer spells a word,
	-- so the server really fizzles the memorize.
	local function spoilWord()
		local buffer = session.wordBuffer
		for i = 1, buffer:size() - 1 do
			buffer:reorder(i, i + 1)
			if not Dictionary.isSpellable(buffer:asWord()) then
				return
			end
			buffer:reorder(i + 1, i)
		end
	end

	local function memorize(now: number)
		local spoiled = rng:NextNumber() < persona.invalidRate
		if spoiled then
			spoilWord()
		end
		local result = EconomyReport.memorize(session)
		log:info(string.format("memorize '%s' spoiled=%s ok=%s reason=%s", word, tostring(spoiled), tostring(result.ok), tostring(result.reason)))
		startThinking(now)
	end

	local function planWord(char: Model, root: BasePart, arenaId: string, now: number)
		local plan = BotVocabulary.plan(persona, visibleBlocks(char, root, arenaId), readMana(), rng)
		if not plan then
			log:infoThrottled("no_plan", C.REPLAN_SEC, "no word spellable from what is in sight")
			setMode("think", now + C.REPLAN_SEC)
			return
		end
		session.wordBuffer:clear()
		queue = plan.picks
		word = plan.word
		popFails = 0
		setMode("pop", now)
		log:info(string.format("planned '%s' (%d letters)", word, #queue))
	end

	local function popNext(now: number)
		local nextPick = queue[1]
		if not nextPick then
			memorize(now)
			return
		end
		if not nextPick.model:IsDescendantOf(workspace) then
			dropPlan(now, "block gone")
			return
		end
		local ok, popped = pcall(function(): any
			return (requestPop :: BindableFunction):Invoke(nextPick.model)
		end)
		if ok and popped == true then
			table.remove(queue, 1)
			popFails = 0
			nextTapAt = now + 1 / persona.tapsPerSec
			return
		end
		popFails += 1
		nextTapAt = now + C.TICK_SEC
		if popFails >= C.MAX_POP_FAILS then
			dropPlan(now, "pop refused")
		end
	end

	-- Keep the horizontal distance to the boss inside the persona's band.
	local function steer(humanoid: Humanoid, root: BasePart, now: number)
		local boss = bossModel()
		if persona.station == "overlook" or not boss then
			return
		end
		local bossPos = boss:GetPivot().Position
		bossHome = bossHome or bossPos
		local d = hdist(root.Position, bossPos)
		local outside = d < persona.distMin or d > persona.distMax
		local settled = goal ~= nil and hdist(root.Position, goal) < C.GOAL_REACHED_STUDS
		if not goal or (outside and (settled or now - goalSetAt > C.GOAL_STALE_SEC)) then
			local away = flat(root.Position) - flat(bossPos)
			if away.Magnitude < 1 then
				away = Vector3.xAxis
			end
			local spot = flat(bossPos) + away.Unit * ((persona.distMin + persona.distMax) / 2)
			local offset = spot - flat(bossHome)
			if offset.Magnitude > C.MAX_GOAL_RADIUS then
				spot = flat(bossHome) + offset.Unit * C.MAX_GOAL_RADIUS
			end
			goal = Vector3.new(spot.X, root.Position.Y, spot.Z)
			goalSetAt = now
		end
		walkTo(humanoid, goal :: Vector3, now)
	end

	local function onNewCharacter(now: number)
		lastPos, goal, movedTo = nil, nil, nil
		casting = nil
		queue = {}
		setMode("idle", now)
		local here = player:GetAttribute(Arena.ID_ATTRIBUTE)
		setPhase(if here == currentArena() then "ready" else "lobby")
		readySince = now
	end

	local function step()
		local now = os.clock()
		local arenaId = currentArena()
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not char or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
			character = nil
			return
		end
		if char ~= character then
			character = char
			onNewCharacter(now)
		end
		local position = root.Position

		local here = player:GetAttribute(Arena.ID_ATTRIBUTE)
		if here ~= arenaId then
			setPhase("lobby")
		elseif phase == "lobby" then
			setPhase("ready")
			lastPos = nil
			readySince = now
		end

		if phase == "lobby" then
			local portal = findPortal(arenaId, position)
			if not portal then
				log:infoThrottled("no_portal", C.JOIN_RETRY_SEC, "no ModePortal leads to " .. arenaId)
			elseif hdist(portal.Position, position) > C.PORTAL_JOIN_RADIUS then
				walkTo(humanoid, portal.Position, now)
			elseif now >= nextJoinAt then
				nextJoinAt = now + C.JOIN_RETRY_SEC
				portalRequest:FireServer(portal, C.JOIN_ACTION)
				log:info("join request sent for " .. arenaId)
			end
		elseif phase == "ready" then
			local pad = findPad(arenaId, position)
			if not pad then
				-- Not streamed in yet, or an arena with no ready room.
				if now - readySince >= C.PAD_WAIT_SEC then
					log:info("no entry pad found - taking this arena to have no ready room")
					setPhase("island")
					startThinking(now)
				end
			elseif lastPos and (position - lastPos).Magnitude > C.TELEPORT_JUMP_STUDS
				and hdist(pad.Position, lastPos) <= C.PAD_NEAR_STUDS then
				log:info("the entry pad moved the character onto the island")
				setPhase("island")
				startThinking(now)
				goal, movedTo = nil, nil
			else
				walkTo(humanoid, pad.Position, now)
			end
		else
			steer(humanoid, root, now)
			if mode == "charge" then
				if now >= modeUntil then
					releaseCast(char, root, now)
				end
			else
				local startedCast = bossModel() ~= nil and now >= nextCastAt and tryStartCast(char, root, humanoid, now)
				if startedCast then
					return
				end
				-- Spores first; a tap spent on one holds the word popping
				-- back through nextTapAt.
				if now >= nextTapAt and popSpore(char, root, arenaId, now) then
					return
				end
				if mode == "think" then
					if now >= modeUntil then
						planWord(char, root, arenaId, now)
					end
				elseif mode == "pop" and now >= nextTapAt then
					popNext(now)
				end
			end
		end
		lastPos = position
	end

	while myRun == runId do
		step()
		task.wait(C.TICK_SEC)
	end
	log:info("stopped")
end

local function refresh()
	runId += 1
	local name = workspace:GetAttribute(C.BOT_ATTRIBUTE)
	if type(name) ~= "string" then
		return
	end
	local persona = PlaytestPersonas.byName(name)
	if not persona then
		log:warn(string.format("%s = '%s' is not a persona", C.BOT_ATTRIBUTE, name))
		return
	end
	task.spawn(run, persona, runId)
end

workspace:GetAttributeChangedSignal(C.BOT_ATTRIBUTE):Connect(refresh)
refresh()
