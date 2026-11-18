--!strict

----------------------------------------------------------------------
-- FightSim
----------------------------------------------------------------------
-- One simulated solo PvE boss fight, start to finish, as an event log.
--
-- The player (a persona, see PlaytestPersonas) and the boss are abstract
-- agents stepped on a fixed tick. The level is not abstract: whether a
-- letter can be tapped and where each boss fireball stops are real
-- raycasts against the greybox (SimLevel). Numbers come from the game's
-- own config modules, so a tuning change in BossConfig or SpellRegistry
-- changes the simulation without touching this file. `tuning` overrides
-- any of them for one run, which is how a fix is judged before it is
-- built.
--
-- What it does NOT model: pathfinding around rocks (agents walk straight
-- lines), knock-up physics, falling off the island, co-op. Those belong
-- to the real bot (Tier 2). See wiki/design/ai-playtest.md.
--
-- Dev tooling: no game system requires this module.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local BlockShoot = require(Shared.BlockShoot)
local BossConfig = require(Shared.Boss.BossConfig)
local BreakableWallConstants = require(Shared.Arena.BreakableWallConstants)
local EnergyEconomy = require(Shared.EnergyEconomy)
local EnergyReservoirs = require(Shared.EnergyReservoirs)
local GameConfig = require(Shared.Core.GameConfig)
local GameModeConstants = require(Shared.GameMode.GameModeConstants)
local HealthConstants = require(Shared.Health.HealthConstants)
local LetterTables = require(Shared.BlockSpawner.LetterTables)
local SpellRegistry = require(Shared.SpellRegistry)
local Wildcard = require(Shared.Wildcard)
local WordKits = require(Shared.BlockSpawner.WordKits)

local SimLevel = require(script.Parent.SimLevel)

local FightSim = {}

----------------------------------------------------------------------
-- Model constants (the simulator's own assumptions, not game tuning)
----------------------------------------------------------------------

local TICK_SEC = 0.25
local SAMPLE_EVERY_SEC = 1

-- Engine default Humanoid.WalkSpeed; the game does not override it.
local PLAYER_WALK_SPEED = 16
-- Seconds from round start to the player standing on the island: the
-- walk from the ready-room spawn to the entry pad, measured 36 studs.
local ENTRY_TRANSIT_SEC = 3
-- Tap rays start at the camera, which rides above the character.
local EYE_HEIGHT = 7
-- Where a fireball is aimed and where a hit is measured: the root part.
local ROOT_HEIGHT = 3
-- The boss fires from hipHeight plus the origin offset; measured 9 studs
-- up by the 2026-11-14 level review.
local MUZZLE_HEIGHT = 9
-- A ray that stops this close to its target counts as reaching it.
local SIGHT_TOLERANCE = 3
-- A player standing this far above the arena floor is on a shelf the
-- boss has no path to (the overlook is 16 up).
local NO_PATH_HEIGHT = 8
-- How far outside its zone's gate a player counts as "beyond the gate".
local EXCURSION_ARRIVE_RADIUS = 14
-- A player headed for a spot under a roof (the cave) is kept on the floor
-- at that spot's level: the floor is looked for this far below eye height.
local UNDER_ROOF_PROBE = 40
-- How long a strafe keeps one direction before turning round.
local STRAFE_FLIP_SEC = 1.5
-- A stuck planner waits this long before looking again.
local REPLAN_SEC = 2
-- Tries at a different word length before a plan gives up.
local PLAN_LENGTH_TRIES = 3
-- A freed fossil floats this far above its wall.
local FOSSIL_HEIGHT = 6
local FOSSIL_LIFETIME_SEC = 20
-- Island walkable radius used to keep goals on the floor.
local MAX_GOAL_RADIUS = 135
-- How far from the wanted spot a player looks for a rock to hide behind,
-- and how far behind its centre they stand.
local COVER_SEARCH_RADIUS = 45
local COVER_STANDOFF = 9
-- Unbuilt mechanics (wiki/design/ai-playtest.md § Candidate fixes).
-- A lobbed spore is in the air this long, and floats this high once down.
local SPORE_FLIGHT_SEC = 1.5
local SPORE_HEIGHT = 4
-- Letters a player can carry outside a planned word (spores, ward
-- letters) before the 12-slot buffer would be in the way.
local MAX_HELD_LETTERS = 6
-- Ward letters orbit at this height.
local WARD_HEIGHT = 6
-- Key letters (unbuilt; wiki/design/ai-playtest.md § Gate redesign). The
-- keys float this far in front of their gate, toward the island's centre,
-- this far apart and this high; a player who sets out to pop them walks to
-- a spot this far further in.
local KEY_STANDOFF = 6
local KEY_SPACING = 4
local KEY_HEIGHT = 5
local KEY_STAND_BACK = 10
-- A player starts tapping keys at this share of their reach, still walking in.
local KEY_TAP_REACH_SHARE = 0.9
-- What one carried wildcard is counted as when a trip's payoff is added
-- up: about one mid-value letter in a medium word. An estimate.
local WILD_WORTH_ENERGY = 3
-- Inside slam range the boss picks between its two attacks at random.
local SLAM_PICK_CHANCE = 0.5
-- A player who reacts to a windup keeps moving for the length of a volley.
local DODGE_SEC = 4
-- SkillDelivery scales a projectile's vertical spread by this.
local PITCH_SPREAD_SHARE = 0.4

local COLORS = { "red", "green", "blue" }
local WILD = Wildcard.CHAR
local WILD_COLOR = Wildcard.COLOR

export type Event = { [string]: any }
export type Result = { events: { Event }, outcome: string, duration: number }

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function hdist(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

local function weightedPick(rng: Random, weights: { [any]: number }): any
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng:NextNumber() * total
	local last: any = nil
	for key, w in weights do
		last = key
		roll -= w
		if roll <= 0 then
			return key
		end
	end
	return last
end

-- Letter weights for one named table, built from LetterTables' own data
-- so rolls can use the fight's seeded RNG (LetterTables.pick uses
-- math.random and would break run-to-run comparison).
local tableWeights: { [string]: { [string]: number } } = {}
local function rollLetter(rng: Random, tableName: string): string
	local weights = tableWeights[tableName]
	if not weights then
		weights = {}
		for _, letter in LetterTables.members(tableName) do
			if letter == WILD then
				weights[letter] = if tableName == LetterTables.PREMIUM
					then LetterTables.PREMIUM_WILDCARD_FREQUENCY
					elseif tableName == LetterTables.WILDCARD then 1
					else LetterTables.STANDARD_WILDCARD_FREQUENCY
			else
				weights[letter] = LetterTables.LETTER_FREQUENCIES[letter]
			end
		end
		tableWeights[tableName] = weights
	end
	return weightedPick(rng, weights)
end

----------------------------------------------------------------------
-- Vocabulary (cached per persona shape)
----------------------------------------------------------------------

local allWordsByLength: { [number]: { string } }? = nil
local vocabCache: { [string]: { [number]: { string } } } = {}

local function loadAllWords(): { [number]: { string } }
	if allWordsByLength then
		return allWordsByLength
	end
	local byLength: { [number]: { string } } = {}
	for _, module in Shared.Dictionary.words:GetChildren() do
		if module:IsA("ModuleScript") then
			local packed = require(module) :: string
			for word in packed:gmatch("[^\n]+") do
				if word:match("^%a+$") then
					local bucket = byLength[#word]
					if not bucket then
						bucket = {}
						byLength[#word] = bucket
					end
					table.insert(bucket, word:upper())
				end
			end
		end
	end
	allWordsByLength = byLength
	return byLength
end

-- The words this persona knows, by length. `vocabSize` words are drawn
-- evenly across the persona's lengths with a fixed seed, so the same
-- persona knows the same words in every fight.
local function vocabularyFor(persona: any): { [number]: { string } }
	local key = string.format("%d:%d:%d", persona.vocabSize, persona.minLen, persona.maxLen)
	local cached = vocabCache[key]
	if cached then
		return cached
	end
	local all = loadAllWords()
	local total = 0
	for len = persona.minLen, persona.maxLen do
		total += #(all[len] or {})
	end
	local keep = math.min(1, persona.vocabSize / math.max(total, 1))
	local rng = Random.new(persona.vocabSize)
	local vocab: { [number]: { string } } = {}
	for len = persona.minLen, persona.maxLen do
		local bucket: { string } = {}
		for _, word in all[len] or {} do
			if rng:NextNumber() <= keep then
				table.insert(bucket, word)
			end
		end
		vocab[len] = bucket
	end
	vocabCache[key] = vocab
	return vocab
end

----------------------------------------------------------------------
-- The fight
----------------------------------------------------------------------

-- Run one fight. `tuning` keys (all optional):
--   attackRange, stopRange, fireWithoutPath, volleyLead (0..1),
--   dmgFrac = { Firebolt=, Fireball=, Inferno=, ["Frost Nip"]= },
--   ampMult, freezeImmunitySec, minWordEnergy, eatHealFraction,
--   popReach = { [tableName] = studs }, gateHealth, timeLimit,
--   zoneQuota = { [tableName] = blocks } (starting letters per zone of that table),
--   spore = { everyNthAttack, count, landRadius, fuseSec, burstDmg, burstRadius, popDamage? }
--     (defaults to BossConfig's spore numbers now that spores are built;
--     pass `spore = false` for a fight without them),
--   ward = { atHp, letters, orbitRadius, cooldown, walkSpeed },
--   keys = { gateCount, caveCount, popReach, noticeChance?, noticeRange? }
--     (key letters: noticeChance overrides every persona's own
--     `noticeGate`; noticeRange defaults to the tap reach, on the view
--     that a letter can be read from as far as it can be tapped)
function FightSim.run(level: SimLevel.Level, persona: any, tuning: any?, seed: number): Result
	local tune = tuning or {}
	local rng = Random.new(seed)
	local boss = BossConfig.BOSS_TYPES[BossConfig.DEFAULT_TYPE] :: any
	local phase = boss.phases[1]
	local volley = boss.skills.FireballVolley
	local slam = boss.skills.GroundSlam
	local vocab = vocabularyFor(persona)

	local attackRange: number = tune.attackRange or boss.attackRange
	local stopRange: number = tune.stopRange or boss.stopRange or attackRange
	local timeLimit: number = tune.timeLimit or GameModeConstants.PVE_ROUND_TIME_LIMIT_SEC
	local eatHeal: number = tune.eatHealFraction or boss.eatHealFraction
	local manaCap = EnergyReservoirs.CAP_PER_COLOR
	local keys = tune.keys
	local spore = tune.spore
	if spore == nil and boss.sporeEveryNthAttack then
		spore = {
			everyNthAttack = boss.sporeEveryNthAttack, count = boss.sporeCount, landRadius = boss.sporeLandRadius,
			fuseSec = boss.sporeFuseSec, burstDmg = boss.sporeBurstDamage, burstRadius = boss.sporeBurstRadius,
			popDamage = boss.sporePopDamageFraction,
		}
	elseif spore == false then
		spore = nil
	end
	local sporeFlightSec: number = boss.sporeFlightSec or SPORE_FLIGHT_SEC
	local sporeHeight: number = boss.sporeHoverHeight or SPORE_HEIGHT
	local center = flat(level.bossPoint)

	local events: { Event } = {}
	local now = 0
	local function emit(kind: string, fields: Event?)
		local e: Event = fields or {}
		e.t = now
		e.kind = kind
		table.insert(events, e)
	end

	-- Ray parameters: everything but broken walls. Rebuilt when one breaks.
	local broken: { Instance } = {}
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local function rebuildParams()
		rayParams.FilterDescendantsInstances = broken
	end
	rebuildParams()

	local function ground(p: Vector3): Vector3
		local y = SimLevel.floorAt(level, p.X, p.Z, rayParams) or level.floorY
		return Vector3.new(p.X, y, p.Z)
	end

	-- The floor straight below `from`, for places with a roof over them,
	-- where the top-down probe of `ground` would land on the roof.
	local function floorBelow(from: Vector3): Vector3
		local hit = workspace:Raycast(from, Vector3.new(0, -UNDER_ROOF_PROBE, 0), rayParams)
		if hit then
			return Vector3.new(from.X, hit.Position.Y, from.Z)
		end
		return ground(from)
	end

	local function clearBetween(a: Vector3, b: Vector3): boolean
		local delta = b - a
		local hit = workspace:Raycast(a, delta, rayParams)
		return hit == nil or (hit.Position - a).Magnitude >= delta.Magnitude - SIGHT_TOLERANCE
	end

	-- Walls ------------------------------------------------------------
	local walls: { any } = {}
	local wallByPart: { [Instance]: any } = {}
	local gateOpen: { [string]: boolean } = {}
	for _, w in level.walls do
		local hp = w.maxHealth
		if tune.gateHealth and w.regenSec > 0 then
			hp = tune.gateHealth
		end
		local state = { def = w, hp = hp, maxHp = hp, broken = false, resealAt = 0 }
		table.insert(walls, state)
		wallByPart[w.part] = state
	end

	-- Blocks -----------------------------------------------------------
	local blocks: { any } = {}
	local respawns: { any } = {}
	local kitWords: { [any]: string } = {}
	local kitColors: { [any]: string } = {}
	-- Key letters: one entry per regenerating gate that has a GateId.
	local gates: { [string]: any } = {}
	local gateList: { any } = {}
	local onKeyPopped: (block: any) -> ()

	local function spawnBlock(zone: any, letter: string?, color: string?, pos: Vector3?, extra: any?)
		local l = letter or rollLetter(rng, zone.letterTable)
		local c = if l == WILD then WILD_COLOR else (color or zone.colorOnly or COLORS[rng:NextInteger(1, #COLORS)])
		local p = pos
		if not p then
			local h = zone.size / 2
			p = zone.center + Vector3.new(
				rng:NextNumber(-h.X, h.X), rng:NextNumber(-h.Y, h.Y), rng:NextNumber(-h.Z, h.Z))
		end
		local block = { letter = l, color = c, pos = p, zone = zone, alive = true }
		if extra then
			for k, v in extra do
				block[k] = v
			end
		end
		table.insert(blocks, block)
		return block
	end

	local function rollKit(zone: any)
		for _, b in blocks do
			if b.zone == zone and b.kit then
				b.alive = false
			end
		end
		local word = WordKits.pick(WordKits.nearestLength(zone.kitLength))
		kitWords[zone] = word
		local color = zone.colorOnly or COLORS[rng:NextInteger(1, #COLORS)]
		kitColors[zone] = color
		for i = 1, #word do
			spawnBlock(zone, word:sub(i, i), color, nil, { kit = true })
		end
	end

	for _, zone in level.zones do
		if zone.kitLength then
			rollKit(zone)
		else
			local quota = (tune.zoneQuota and tune.zoneQuota[zone.letterTable]) or zone.quota
			for _ = 1, quota do
				spawnBlock(zone)
			end
		end
	end

	-- Hang a fresh ready-made word in front of a gate, replacing what is left
	-- of the last one.
	local function rollKeys(g: any)
		for _, block in g.blocks do
			block.alive = false
		end
		-- WordKits has no 3- or 4-letter list yet, so the model takes any
		-- dictionary word of the length; the built version needs curated ones.
		local words = loadAllWords()[if g.caveZone then keys.caveCount else keys.gateCount]
		local word = words[rng:NextInteger(1, #words)]
		local color = (g.caveZone and kitColors[g.caveZone]) or COLORS[rng:NextInteger(1, #COLORS)]
		g.blocks = {}
		g.word = word
		g.left = #word
		g.whole = true
		g.noticeRolled = false
		for i = 1, #word do
			local block = {
				letter = word:sub(i, i), color = color, alive = true, key = g, reach = keys.popReach,
				pos = g.center + g.side * ((i - (#word + 1) / 2) * KEY_SPACING),
				zone = { name = "Key" },
			}
			table.insert(blocks, block)
			table.insert(g.blocks, block)
		end
	end

	if keys then
		for _, w in walls do
			local id = w.def.gateId
			if id and w.def.regenSec > 0 and not gates[id] then
				local inward = center - flat(w.def.position)
				inward = if inward.Magnitude > 1 then inward.Unit else Vector3.new(1, 0, 0)
				local caveZone: any = nil
				for _, zone in level.zones do
					if zone.gateId == id and zone.kitLength then
						caveZone = zone
					end
				end
				local g = {
					id = id, wall = w, caveZone = caveZone, blocks = {},
					center = ground(flat(w.def.position) + inward * KEY_STANDOFF) + Vector3.new(0, KEY_HEIGHT, 0),
					side = Vector3.new(-inward.Z, 0, inward.X),
					stand = ground(flat(w.def.position) + inward * (KEY_STANDOFF + KEY_STAND_BACK)),
				}
				gates[id] = g
				table.insert(gateList, g)
				rollKeys(g)
			end
		end
	end

	local function removeBlock(block: any)
		block.alive = false
		if block.key then
			onKeyPopped(block)
		elseif not block.kit and not block.fossil then
			table.insert(respawns, { at = now + GameConfig.BLOCK_RESPAWN_DELAY, zone = block.zone })
		end
	end

	local function breakWall(w: any)
		w.broken = true
		table.insert(broken, w.def.part)
		rebuildParams()
		emit("wall_state", { name = w.def.name, state = "broken", gate = w.def.gateId })
		if w.def.regenSec > 0 then
			w.resealAt = now + w.def.regenSec
			if w.def.gateId then
				gateOpen[w.def.gateId] = true
				-- An open gate has no use for its keys.
				local g = gates[w.def.gateId]
				if g then
					for _, block in g.blocks do
						block.alive = false
					end
					g.left = 0
				end
			end
		elseif w.def.fossilTable then
			local zoneLike = { letterTable = w.def.fossilTable, name = "Fossil" }
			spawnBlock(zoneLike, nil, nil, w.def.position + Vector3.new(0, FOSSIL_HEIGHT, 0),
				{ fossil = true, expiresAt = now + FOSSIL_LIFETIME_SEC })
			emit("fossil_freed", { name = w.def.name })
		end
	end

	local function damageWall(part: Instance, amount: number)
		local w = wallByPart[part]
		if w and not w.broken then
			w.hp -= amount
			if w.hp <= 0 then
				breakWall(w)
			end
		end
	end

	-- Agents -----------------------------------------------------------
	local p: any = {
		pos = ground(level.arrival),
		vel = Vector3.zero,
		hp = HealthConstants.DEFAULT_MAX_HEALTH,
		shield = 0,
		mana = { red = 0, green = 0, blue = 0 },
		wilds = 0,
		alive = false,
		mode = "think",
		until_ = 0,
		returnAt = ENTRY_TRANSIT_SEC,
		protectedUntil = 0,
		goal = nil,
		queue = {},
		tiles = {},
		nextTapAt = 0,
		strafeUntil = 0,
		strafeSign = 1,
		excursion = nil,
		gateRolled = {},
		-- Key letters: gates this player opened on purpose (so walks
		-- through), and the trip being timed for M14.
		gateForced = {},
		trip = nil,
		keyWord = false,
	}

	local b: any = {
		pos = ground(level.bossPoint),
		hp = 1,
		spawned = false,
		spawnAt = math.huge,
		state = "Patrol",
		stateUntil = 0,
		attack = nil,
		shots = {},
		frozenUntil = 0,
		freezeImmuneUntil = 0,
		ampUntil = 0,
		ampMult = 1,
		tow = nil,
		nextEatAt = 0,
		attacks = 0,
		warded = false,
		wardDone = false,
		cooldown = phase.attackCooldown,
		walkSpeed = phase.walkSpeed,
	}
	local held: { any } = {} -- letters the player carries outside a plan

	local stats = { shots = 0, shotsHit = 0, shotsBlocked = 0, healed = 0, resealed = 0 }

	local function bossDist(): number
		return (flat(p.pos) - flat(b.pos)).Magnitude
	end

	-- Close the books on a trip beyond a gate. `from` is where the player
	-- turns back; the walk home to the gate is part of the trip's cost.
	local function endTrip(died: boolean, from: Vector3?)
		local trip = p.trip
		if not trip then
			return
		end
		p.trip = nil
		local sec = now - trip.startedAt
		if from then
			sec += hdist(from, trip.gatePos) / PLAYER_WALK_SPEED
		end
		emit("trip_end", {
			gate = trip.gate, sec = sec, memorized = trip.energy, wilds = trip.wilds,
			energy = trip.energy + trip.wilds * WILD_WORTH_ENERGY, died = died, deliberate = trip.deliberate,
		})
	end

	local function startTrip(gateId: string, gatePos: Vector3, deliberate: boolean)
		if not p.trip then
			p.trip = { gate = gateId, gatePos = gatePos, startedAt = now, deliberate = deliberate, energy = 0, wilds = 0 }
		end
	end

	local function hurtPlayer(amount: number, source: string)
		if not p.alive or now < p.protectedUntil then
			return
		end
		local absorbed = math.min(p.shield, amount)
		p.shield -= absorbed
		p.hp -= amount - absorbed
		emit("player_damage", { amount = amount, absorbed = absorbed, source = source, hp = math.max(p.hp, 0) })
		if p.hp <= 0 then
			-- The word in progress survives: the client's buffer and the
			-- player's train of thought both outlive the character.
			p.alive = false
			p.returnAt = now + GameModeConstants.RESPAWN_TIME + ENTRY_TRANSIT_SEC
			if p.mode == "charge" then
				p.mana[p.casting.color] += p.casting.cost -- nothing is drained until release
				p.mode = p.resumeMode
				p.until_ = p.resumeUntil
				p.casting = nil
			end
			if p.excursion then
				p.excursion = nil
				p.queue = {}
				p.tiles = {}
				p.mode = "think"
			end
			p.keyWord = false
			endTrip(true, nil)
			p.vel = Vector3.zero
			emit("death", { source = source, bossHp = b.hp })
		end
	end

	local function hurtBoss(frac: number, spell: string, tier: number)
		if b.warded then
			emit("ward_absorb", { spell = spell })
			return
		end
		local mult = if now < b.ampUntil then b.ampMult else 1
		local dealt = math.min(b.hp, frac * mult)
		local ward = tune.ward
		if ward and not b.wardDone and b.hp - dealt <= ward.atHp then
			-- The ward: health stops at the threshold and letters orbit the
			-- boss until every one is popped.
			dealt = math.max(0, b.hp - ward.atHp)
			b.wardDone = true
			b.warded = true
			b.cooldown = ward.cooldown or b.cooldown
			b.walkSpeed = ward.walkSpeed or b.walkSpeed
			for i = 1, ward.letters do
				local angle = i / ward.letters * math.pi * 2
				local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * ward.orbitRadius
				local zoneLike = { letterTable = LetterTables.COMMON, name = "Ward" }
				local block = { letter = rollLetter(rng, LetterTables.COMMON), color = COLORS[rng:NextInteger(1, #COLORS)],
					pos = b.pos + offset + Vector3.new(0, WARD_HEIGHT, 0), zone = zoneLike, alive = true, ward = true, fossil = true }
				table.insert(blocks, block)
			end
			emit("ward_up", {})
		end
		b.hp -= dealt
		emit("boss_damage", { amount = dealt, spell = spell, tier = tier, bossHp = b.hp })
	end

	-- The last key of a gate breaks it. A key popped as part of an ordinary
	-- word counts too, which is how a gate opens by accident.
	onKeyPopped = function(block: any)
		local g = block.key
		local onPurpose = p.keyWord and p.excursion ~= nil and p.excursion.keyGate == g
		if not onPurpose then
			g.whole = false
		end
		g.left -= 1
		emit("key_pop", { gate = g.id, deliberate = onPurpose })
		if g.left <= 0 and not g.wall.broken then
			if onPurpose then
				p.gateForced[g.id] = true
			end
			emit("gate_keyed", { gate = g.id, deliberate = onPurpose })
			breakWall(g.wall)
		end
	end

	-- Player: planning --------------------------------------------------
	local function reachFor(block: any): number
		if block.reach then
			return block.reach
		end
		local override = tune.popReach and tune.popReach[block.zone.letterTable or ""]
		return override or BlockShoot.MAX_RAYCAST_DISTANCE
	end

	local function visibleBlocks(): { any }
		local eye = p.pos + Vector3.new(0, EYE_HEIGHT, 0)
		local out = {}
		for _, block in blocks do
			if block.alive and (block.pos - eye).Magnitude <= reachFor(block) and clearBetween(eye, block.pos) then
				table.insert(out, block)
			end
		end
		for _, block in held do
			if block.alive then
				table.insert(out, block)
			end
		end
		return out
	end

	local function holdLetter(letter: string, color: string)
		if #held >= MAX_HELD_LETTERS then
			table.remove(held, 1)
		end
		table.insert(held, { letter = letter, color = color, alive = true, held = true, zone = { name = "Held" } })
	end

	-- Choose a word spellable from what is in sight and queue its letters.
	local function planWord(): boolean
		local seen = visibleBlocks()
		local byLetter: { [string]: { any } } = {}
		for _, block in seen do
			local list = byLetter[block.letter]
			if not list then
				list = {}
				byLetter[block.letter] = list
			end
			table.insert(list, block)
		end
		local wildBlocks = byLetter[WILD] or {}
		local wildsAvailable = #wildBlocks + p.wilds

		-- Colour the persona wants this word in, or nil for "whatever".
		local wanted: string? = nil
		if rng:NextNumber() < persona.colorAware then
			wanted = weightedPick(rng, persona.colorWants(p.mana))
		end

		local best: any = nil
		for _ = 1, PLAN_LENGTH_TRIES do
			local len = weightedPick(rng, persona.lengthWeights) :: number
			local bucket = vocab[len]
			if bucket and #bucket > 0 then
				for _ = 1, persona.candidates do
					local word = bucket[rng:NextInteger(1, #bucket)]
					local used: { [string]: number } = {}
					local picks: { any } = {}
					local wildsUsed = 0
					local ok = true
					local score = 0
					for i = 1, len do
						local letter = word:sub(i, i)
						local list = byLetter[letter]
						local index = (used[letter] or 0) + 1
						-- Prefer the wanted colour among this letter's blocks.
						local chosen: any = nil
						if list then
							local skipped = 0
							for _, block in list do
								if not block.claimed then
									if wanted and block.color == wanted then
										chosen = block
										break
									end
									skipped += 1
									if not chosen and skipped >= index then
										chosen = block
									end
								end
							end
						end
						if chosen then
							chosen.claimed = true
							used[letter] = index
							table.insert(picks, { block = chosen, letter = letter })
							local value = EnergyEconomy.letterValue(letter)
							score += if wanted == nil or chosen.color == wanted then value else value / 2
						elseif wildsUsed < wildsAvailable and persona.usesWild then
							wildsUsed += 1
							table.insert(picks, { wild = true, letter = letter })
						else
							ok = false
							break
						end
					end
					for _, pick in picks do
						if pick.block then
							pick.block.claimed = nil
						end
					end
					if ok then
						score *= EnergyEconomy.lengthMultiplier(len)
						if not best or score > best.score then
							best = { word = word, picks = picks, score = score }
						end
					end
				end
			end
			if best then
				break
			end
		end
		if not best then
			return false
		end

		local wildIndex = 0
		p.queue = {}
		p.tiles = {}
		for _, pick in best.picks do
			if pick.block then
				table.insert(p.queue, { block = pick.block, letter = pick.letter })
			else
				wildIndex += 1
				local held = wildIndex <= p.wilds
				table.insert(p.queue, { block = if held then nil else wildBlocks[wildIndex - p.wilds], letter = pick.letter, wild = true, held = held })
			end
		end
		p.word = best.word
		p.kitWord = false
		return true
	end

	local function startThinking(lettersGuess: number)
		p.mode = "think"
		p.until_ = now + persona.searchBaseSec + persona.searchPerLetterSec * lettersGuess
	end

	local function memorize()
		if p.keyWord and not p.kitWord then
			-- Keys left over after some went into other words: loose letters.
			for _, tile in p.tiles do
				holdLetter(tile.letter, tile.color)
			end
			p.tiles = {}
			p.queue = {}
			p.excursion = nil
			p.keyWord = false
			startThinking(persona.typicalLen)
			return
		end
		local fizzled = (not p.kitWord) and rng:NextNumber() < persona.invalidRate
		if fizzled then
			emit("fizzle", { letters = #p.tiles })
		else
			local energy = EnergyEconomy.splitByColor(p.tiles)
			if tune.minWordEnergy then
				local top, topValue = "red", -1
				for _, color in COLORS do
					if (energy[color] or 0) > topValue then
						top, topValue = color, energy[color] or 0
					end
				end
				energy[top] = math.max(topValue, tune.minWordEnergy)
			end
			local wasted = 0
			for _, color in COLORS do
				local gain = energy[color] or 0
				local room = manaCap - p.mana[color]
				wasted += math.max(0, gain - room)
				p.mana[color] = math.min(manaCap, p.mana[color] + gain)
			end
			emit("memorize", {
				word = p.word, red = energy.red or 0, green = energy.green or 0, blue = energy.blue or 0,
				wasted = wasted, kit = p.kitWord, key = p.keyWord, zone = p.wordZone,
			})
			if p.trip then
				p.trip.energy += (energy.red or 0) + (energy.green or 0) + (energy.blue or 0)
			end
			if p.kitWord and not p.keyWord then
				emit("kit_taken", { word = p.word })
				endTrip(false, p.pos)
			end
		end
		p.tiles = {}
		p.queue = {}
		p.excursion = nil
		p.keyWord = false
		startThinking(persona.typicalLen)
	end

	-- Player: casting ---------------------------------------------------
	local function spellReaches(spec: any): boolean
		if not SpellRegistry.needsEnemyTarget(spec) then
			return true
		end
		if not b.spawned or b.hp <= 0 or b.warded then
			return false
		end
		local from = p.pos + Vector3.new(0, ROOT_HEIGHT, 0)
		local to = b.pos + Vector3.new(0, ROOT_HEIGHT, 0)
		local d = (to - from).Magnitude
		if d > SpellRegistry.AUTO_TARGET_RANGE_STUDS then
			return false
		end
		if spec.skill.delivery == "projectile" then
			local params = spec.skill.deliveryParams
			return d <= params.speed * params.lifetimeSec and clearBetween(from, to)
		end
		return true
	end

	local function landSpell(spec: any)
		emit("cast", { spell = spec.name, color = spec.color, tier = spec.tier, cost = spec.cost, hp = p.hp, bossState = b.state })
		for _, effect in spec.skill.onImpact do
			if effect.kind == "damage" then
				local frac = (tune.dmgFrac and tune.dmgFrac[spec.name]) or effect.fractionOfMaxHP or 0
				hurtBoss(frac, spec.name, spec.tier)
			elseif effect.kind == "freeze" then
				if now >= b.freezeImmuneUntil then
					b.frozenUntil = now + effect.durationSec
					b.freezeImmuneUntil = b.frozenUntil + (tune.freezeImmunitySec or 0)
				end
			elseif effect.kind == "buff" then
				b.ampUntil = now + effect.durationSec
				b.ampMult = tune.ampMult or effect.magnitude
			elseif effect.kind == "heal" then
				local before = p.hp
				p.hp = math.min(HealthConstants.DEFAULT_MAX_HEALTH, p.hp + effect.fractionOfMaxHP * HealthConstants.DEFAULT_MAX_HEALTH)
				emit("player_heal", { amount = p.hp - before, spell = spec.name })
			elseif effect.kind == "shield" then
				p.shield = math.max(p.shield, effect.amount)
				emit("player_shield", { amount = effect.amount, spell = spec.name })
			end
		end
	end

	-- Ask the persona what to cast; begin the hold if it names a spell
	-- that can reach. Returns true when a charge started.
	local function tryCast(): boolean
		local choice = persona.chooseCast({
			mana = p.mana, hp = p.hp, shield = p.shield,
			bossAmped = now < b.ampUntil, bossHp = b.hp,
			can = function(color: string, tier: number): boolean
				local spec = SpellRegistry.getSpell(color :: any, tier)
				return p.mana[color] >= spec.cost and spellReaches(spec)
			end,
		})
		if not choice then
			return false
		end
		local spec = SpellRegistry.getSpell(choice.color, choice.tier)
		if p.mana[spec.color] < spec.cost or not spellReaches(spec) then
			return false
		end
		p.mana[spec.color] -= spec.cost
		p.casting = spec
		p.resumeMode = p.mode
		p.resumeUntil = p.until_
		p.mode = "charge"
		p.until_ = now + SpellRegistry.chargeTimeFor(spec.tier)
		return true
	end

	-- Player: movement --------------------------------------------------
	local function homeGoal(): Vector3
		if persona.station == "overlook" then
			return level.arrival
		end
		local away = flat(p.pos) - flat(b.pos)
		if away.Magnitude < 1 then
			away = Vector3.new(1, 0, 0)
		end
		local want = (persona.distMin + persona.distMax) / 2
		local spot = flat(b.pos) + away.Unit * want
		local fromCenter = spot - center
		if fromCenter.Magnitude > MAX_GOAL_RADIUS then
			spot = center + fromCenter.Unit * MAX_GOAL_RADIUS
		end
		-- Some players put a rock between themselves and the boss.
		if rng:NextNumber() < persona.coverUse then
			local nearest: any, nearestDist = nil, COVER_SEARCH_RADIUS
			for _, w in walls do
				if not w.broken and w.def.regenSec == 0 then
					local d = hdist(w.def.position, spot)
					if d < nearestDist then
						nearest, nearestDist = w, d
					end
				end
			end
			if nearest then
				local behind = flat(nearest.def.position) - flat(b.pos)
				if behind.Magnitude > 1 then
					spot = flat(nearest.def.position) + behind.Unit * COVER_STANDOFF
					p.coverWall = nearest
				end
			end
		end
		return spot
	end

	local function movePlayer(dt: number)
		local before = p.pos
		local goal: Vector3? = nil
		if p.excursion then
			goal = p.excursion.spot
		else
			local d = bossDist()
			local settled = p.goal and hdist(p.pos, p.goal) < 2
			if persona.station == "overlook" then
				goal = level.arrival
			elseif not p.goal or (settled and (d < persona.distMin or d > persona.distMax))
				or (p.coverWall and p.coverWall.broken) then
				p.coverWall = nil
				p.goal = homeGoal()
				goal = p.goal
			else
				goal = p.goal
			end
		end

		local strafing = now < p.strafeUntil
		if strafing and b.spawned then
			local toBoss = flat(b.pos) - flat(p.pos)
			if toBoss.Magnitude > 1 then
				local side = Vector3.new(-toBoss.Z, 0, toBoss.X).Unit * p.strafeSign
				if math.floor(now / STRAFE_FLIP_SEC) % 2 == 0 then
					side = -side
				end
				local step = side * PLAYER_WALK_SPEED * dt
				if SimLevel.floorAt(level, p.pos.X + step.X, p.pos.Z + step.Z, rayParams) then
					p.pos = ground(p.pos + step)
				end
			end
		elseif goal then
			local delta = flat(goal) - flat(p.pos)
			if delta.Magnitude > 1 then
				local step = delta.Unit * math.min(delta.Magnitude, PLAYER_WALK_SPEED * dt)
				local nextPos = p.pos + step
				if p.excursion and p.excursion.zone then
					-- Stay at the level of the place being walked to, so a
					-- cave is entered and not walked over.
					p.pos = floorBelow(Vector3.new(nextPos.X, goal.Y + EYE_HEIGHT, nextPos.Z))
				else
					p.pos = ground(nextPos)
				end
			end
		end
		p.vel = flat(p.pos - before) / dt
	end

	-- Decide whether to walk out to a reward behind an open gate.
	local function considerExcursion()
		if p.excursion or p.mode == "charge" then
			return
		end
		for _, zone in level.zones do
			local gate = zone.gateId
			if gate and gateOpen[gate] and not p.gateRolled[gate] then
				p.gateRolled[gate] = true
				local chance = if p.gateForced[gate] then 1 elseif zone.kitLength then persona.goCave else persona.goGates
				p.gateForced[gate] = nil
				if rng:NextNumber() < chance then
					p.excursion = { zone = zone, spot = floorBelow(zone.center), startedAt = now }
					local gatePos = zone.center
					for _, w in walls do
						if w.def.gateId == gate then
							gatePos = w.def.position
						end
					end
					startTrip(gate, gatePos, false)
					p.queue = {}
					p.tiles = {}
					p.mode = "travel"
					emit("excursion_start", { zone = zone.name, kit = zone.kitLength ~= nil })
					return
				end
			end
		end
	end

	-- Key letters: at a pause between words, does the player see a gate's
	-- carved letters and decide to go and pop them? Rolled once per gate
	-- each time its keys are hung.
	local function noticeGate(): boolean
		if not keys or p.excursion or persona.station == "overlook" then
			return false
		end
		local eye = p.pos + Vector3.new(0, EYE_HEIGHT, 0)
		local chance: number = keys.noticeChance or persona.noticeGate
		local range: number = keys.noticeRange or BlockShoot.MAX_RAYCAST_DISTANCE
		-- Nearest gate first: nobody crosses the island past a nearer one.
		table.sort(gateList, function(x: any, y: any): boolean
			return hdist(x.center, p.pos) < hdist(y.center, p.pos)
		end)
		for _, g in gateList do
			if not g.noticeRolled and not g.wall.broken and g.left > 0
				and hdist(g.center, p.pos) <= range and clearBetween(eye, g.center) then
				g.noticeRolled = true
				if rng:NextNumber() < chance then
					p.excursion = { keyGate = g, spot = g.stand, startedAt = now }
					startTrip(g.id, g.wall.def.position, true)
					p.queue = {}
					p.tiles = {}
					p.mode = "travel"
					emit("key_trip_start", { gate = g.id })
					return true
				end
			end
		end
		return false
	end

	local function stepPlayer(dt: number)
		if not p.alive then
			if now >= p.returnAt then
				p.alive = true
				p.hp = HealthConstants.DEFAULT_MAX_HEALTH
				p.shield = 0
				p.pos = ground(level.arrival)
				p.goal = nil
				p.protectedUntil = now + HealthConstants.ARRIVAL_PROTECTION_SEC
				emit("reenter", {})
				if b.spawnAt == math.huge then
					-- First arrival: the entrance countdown starts, and so
					-- does the first look for a word.
					b.spawnAt = now + (boss.entranceDelaySec or 0)
					startThinking(persona.typicalLen)
				end
			end
			return
		end

		movePlayer(dt)
		considerExcursion()

		if p.mode == "charge" then
			if now >= p.until_ then
				landSpell(p.casting)
				p.casting = nil
				p.mode = p.resumeMode
				p.until_ = math.max(p.resumeUntil, now)
			end
			return
		end

		if b.spawned and tryCast() then
			return
		end

		-- Spores and ward letters are popped on sight, one tap each.
		if now >= p.nextTapAt then
			local eye = p.pos + Vector3.new(0, EYE_HEIGHT, 0)
			for _, block in blocks do
				if block.alive and (block.ward or (block.spore and block.willPop and now >= block.popAfter))
					and (block.pos - eye).Magnitude <= BlockShoot.MAX_RAYCAST_DISTANCE and clearBetween(eye, block.pos) then
					block.alive = false
					holdLetter(block.letter, block.color)
					p.nextTapAt = now + 1 / persona.tapsPerSec
					emit("pop", { letter = block.letter, color = block.color, zone = if block.ward then "Ward" else "Spore", value = 0 })
					-- Optional rule: a popped spore snaps back at the boss.
					if block.spore and spore and spore.popDamage then
						hurtBoss(spore.popDamage, "Spore", 1)
					end
					break
				end
			end
			if b.warded then
				local left = false
				for _, block in blocks do
					if block.alive and block.ward then
						left = true
						break
					end
				end
				if not left then
					b.warded = false
					emit("ward_down", {})
				end
			end
		end

		-- Steal a letter the boss is pulling in.
		if b.tow and b.tow.alive and not b.tow.stealRolled then
			b.tow.stealRolled = true
			local eye = p.pos + Vector3.new(0, EYE_HEIGHT, 0)
			if rng:NextNumber() < persona.stealTow and clearBetween(eye, b.tow.pos) then
				removeBlock(b.tow)
				emit("tow_stolen", { letter = b.tow.letter })
				emit("pop", { letter = b.tow.letter, color = b.tow.color, zone = "Tow", value = EnergyEconomy.letterValue(b.tow.letter) })
				b.tow = nil
				b.nextEatAt = now + boss.eatIntervalSec
			end
		end

		if p.mode == "travel" then
			local ex = p.excursion
			if not ex then
				startThinking(persona.typicalLen)
			elseif ex.keyGate then
				local g = ex.keyGate
				if g.wall.broken or g.left <= 0 then
					-- Opened before the player got there (the boss, or their
					-- own earlier pops): walk through all the same.
					p.gateForced[g.id] = true
					p.gateRolled[g.id] = nil
					p.excursion = nil
					startThinking(persona.typicalLen)
				elseif hdist(p.pos, g.center) <= math.max(EXCURSION_ARRIVE_RADIUS, keys.popReach * KEY_TAP_REACH_SHARE) then
					p.queue = {}
					p.tiles = {}
					for _, block in g.blocks do
						if block.alive then
							table.insert(p.queue, { block = block, letter = block.letter })
						end
					end
					p.word = g.word
					p.kitWord = g.whole
					p.keyWord = true
					p.wordZone = "Key"
					p.mode = "pop"
				end
			elseif hdist(p.pos, ex.spot) <= EXCURSION_ARRIVE_RADIUS then
				p.queue = {}
				p.tiles = {}
				if ex.zone.kitLength then
					for _, block in blocks do
						if block.alive and block.zone == ex.zone then
							table.insert(p.queue, { block = block, letter = block.letter })
						end
					end
					p.word = kitWords[ex.zone]
					p.kitWord = true
					p.wordZone = ex.zone.name
					p.mode = "pop"
				else
					local taken = 0
					for _, block in blocks do
						if block.alive and block.zone == ex.zone then
							removeBlock(block)
							taken += 1
							emit("pop", { letter = block.letter, color = block.color, zone = ex.zone.name, value = 0 })
						end
					end
					p.wilds += taken
					emit("excursion_end", { zone = ex.zone.name, wilds = taken, sec = now - ex.startedAt })
					if p.trip then
						p.trip.wilds += taken
					end
					endTrip(false, p.pos)
					p.excursion = nil
					startThinking(persona.typicalLen)
				end
			end
			return
		end

		if p.mode == "think" then
			if now >= p.until_ then
				if noticeGate() then
					return
				end
				if planWord() then
					p.mode = "pop"
					p.wordZone = nil
				else
					emit("stuck", {})
					p.goal = nil
					p.until_ = now + REPLAN_SEC
				end
			end
			return
		end

		if p.mode == "pop" then
			if now < p.nextTapAt then
				return
			end
			local nextPick = p.queue[1]
			if not nextPick then
				memorize()
				return
			end
			p.nextTapAt = now + 1 / persona.tapsPerSec
			if nextPick.held then
				p.wilds -= 1
				table.remove(p.queue, 1)
				table.insert(p.tiles, { letter = nextPick.letter, color = WILD_COLOR })
				return
			end
			local block = nextPick.block
			local eye = p.pos + Vector3.new(0, EYE_HEIGHT, 0)
			if not block or not block.alive then
				-- The letter went (eaten, expired): the word is off.
				emit("plan_lost", { letters = #p.tiles })
				p.tiles = {}
				p.queue = {}
				if p.excursion then
					local g = p.excursion.keyGate
					if g then
						-- The gate opened under the player's hands.
						p.gateForced[g.id] = true
						p.gateRolled[g.id] = nil
						p.keyWord = false
					end
					p.excursion = nil
				end
				startThinking(persona.typicalLen)
				return
			end
			if block.held then
				block.alive = false
				table.remove(p.queue, 1)
				table.insert(p.tiles, { letter = nextPick.letter, color = block.color })
				return
			end
			if block.reach and (block.pos - eye).Magnitude > block.reach then
				if p.excursion then
					return -- still walking up to the gate
				end
				-- Walked out of reach of a key since planning: the word is off.
				emit("plan_lost", { letters = #p.tiles })
				p.tiles = {}
				p.queue = {}
				startThinking(persona.typicalLen)
				return
			end
			if not clearBetween(eye, block.pos) then
				return -- wait for a line of sight (the player is moving)
			end
			removeBlock(block)
			table.remove(p.queue, 1)
			table.insert(p.tiles, { letter = nextPick.letter, color = block.color })
			emit("pop", {
				letter = block.letter, color = block.color, zone = block.zone.name,
				value = EnergyEconomy.letterValue(nextPick.letter), fossil = block.fossil, dist = bossDist(),
			})
		end
	end

	-- Boss --------------------------------------------------------------
	local function reachable(): boolean
		return p.pos.Y - level.floorY < NO_PATH_HEIGHT
	end

	local function fireShot()
		local origin = b.pos + Vector3.new(0, MUZZLE_HEIGHT, 0)
		local params = volley.deliveryParams
		local root = p.pos + Vector3.new(0, ROOT_HEIGHT, 0)
		local travel = (root - origin).Magnitude / params.speed
		local aim = root + p.vel * travel * (tune.volleyLead or 0)
		local dir = (aim - origin).Unit
		local yaw = math.rad(rng:NextNumber(-1, 1) * params.spreadDegrees)
		local pitch = math.rad(rng:NextNumber(-1, 1) * params.spreadDegrees * PITCH_SPREAD_SHARE)
		dir = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(pitch, yaw, 0)).LookVector
		local range = params.speed * params.lifetimeSec
		local hit = workspace:Raycast(origin, dir * range, rayParams)
		local stopAt = if hit then (hit.Position - origin).Magnitude else range

		-- Where the player will be when the shot gets there.
		local future = root + p.vel * travel
		local along = math.clamp((future - origin):Dot(dir), 0, stopAt)
		local miss = (origin + dir * along - future).Magnitude
		stats.shots += 1
		if p.alive and miss <= params.proximityRadius then
			stats.shotsHit += 1
			hurtPlayer(volley.onImpact[1].amount, "FireballVolley")
		elseif hit then
			stats.shotsBlocked += 1
			damageWall(hit.Instance, BreakableWallConstants.FIREBALL_WALL_DAMAGE)
		end
	end

	local function stepBoss(dt: number)
		if not b.spawned then
			if now >= b.spawnAt then
				b.spawned = true
				b.state = "Patrol"
				b.nextEatAt = now + boss.eatIntervalSec
				emit("boss_spawn", {})
			end
			return
		end

		local frozen = now < b.frozenUntil
		local d = bossDist()
		local hasTarget = p.alive and d <= boss.detectionRange

		-- Walking: toward the player until the stop range.
		local walking = b.state == "Patrol" or (stopRange < attackRange and b.state == "Cooldown")
		if walking and hasTarget and not frozen and d > stopRange and reachable() then
			local delta = flat(p.pos) - flat(b.pos)
			b.pos = ground(b.pos + delta.Unit * math.min(b.walkSpeed * dt, d - stopRange))
		end

		local canAttack = hasTarget and d <= attackRange and (reachable() or tune.fireWithoutPath or d <= boss.attackRange)

		if b.state == "Patrol" then
			if canAttack then
				b.state = "AttackPrep"
				b.stateUntil = now + boss.attackWindupSec
				b.attack = if d <= slam.maxSelectRange and rng:NextNumber() < SLAM_PICK_CHANCE then "GroundSlam" else "FireballVolley"
				b.attacks += 1
				if spore and b.attack == "FireballVolley" and b.attacks % spore.everyNthAttack == 0 then
					b.attack = "SporeLob"
				end
				emit("boss_windup", { attack = b.attack, dist = d })
				-- The telegraph: does the player start dodging?
				if not p.coverWall and rng:NextNumber() < persona.reactChance then
					p.strafeUntil = now + persona.reactDelaySec + DODGE_SEC
					p.strafeSign = if rng:NextNumber() < 0.5 then 1 else -1
				end
			end
		elseif b.state == "AttackPrep" then
			if now >= b.stateUntil then
				b.state = "Attack"
				if b.attack == "GroundSlam" then
					b.stateUntil = now + slam.deliveryParams.windupSec
				elseif b.attack == "SporeLob" then
					b.stateUntil = now + sporeFlightSec
				else
					local params = volley.deliveryParams
					b.shots = {}
					for i = 0, params.count - 1 do
						table.insert(b.shots, now + i * params.staggerSec)
					end
					b.stateUntil = now + params.count * params.staggerSec
				end
			end
		elseif b.state == "Attack" then
			if b.attack == "FireballVolley" then
				while b.shots[1] and b.shots[1] <= now do
					table.remove(b.shots, 1)
					fireShot()
				end
			end
			if now >= b.stateUntil then
				if b.attack == "GroundSlam" then
					local radius = slam.deliveryParams.radius
					if p.alive and hdist(p.pos, b.pos) <= radius then
						hurtPlayer(slam.onImpact[1].amount, "GroundSlam")
					end
					for _, w in walls do
						if not w.broken and hdist(w.def.position, b.pos) <= radius then
							damageWall(w.def.part, BreakableWallConstants.SLAM_WALL_DAMAGE)
						end
					end
				end
				if b.attack == "SporeLob" then
					local chance = math.max(persona.reactChance, persona.stealTow) / 2 + 0.5
					for i = 1, spore.count do
						local angle = rng:NextNumber(0, math.pi * 2)
						local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(0, spore.landRadius)
						local zoneLike = { letterTable = LetterTables.COMMON, name = "Spore" }
						table.insert(blocks, {
							letter = rollLetter(rng, LetterTables.COMMON), color = if rng:NextNumber() < 0.5 then "red" else "blue",
							pos = ground(p.pos + offset) + Vector3.new(0, sporeHeight, 0), zone = zoneLike, alive = true,
							spore = true, fossil = true, burstAt = now + spore.fuseSec,
							willPop = rng:NextNumber() < chance, popAfter = now + persona.reactDelaySec + (i - 1) / persona.tapsPerSec,
						})
					end
					emit("spore_lob", { count = spore.count })
				end
				b.state = "Cooldown"
				b.stateUntil = now + b.cooldown
			end
		elseif b.state == "Cooldown" then
			if now >= b.stateUntil then
				b.state = "Patrol"
			end
		end

		-- Hunger.
		if boss.eatIntervalSec and not frozen and not b.warded then
			if b.tow then
				local tow = b.tow
				if not tow.alive then
					b.tow = nil
					b.nextEatAt = now + boss.eatIntervalSec
				else
					local mouth = b.pos + Vector3.new(0, ROOT_HEIGHT, 0)
					local delta = mouth - tow.pos
					if delta.Magnitude <= boss.eatReach then
						removeBlock(tow)
						local healed = math.min(1 - b.hp, eatHeal)
						b.hp += healed
						stats.healed += healed
						emit("tow_eaten", { letter = tow.letter, healed = healed, playerAlive = p.alive })
						b.tow = nil
						b.nextEatAt = now + boss.eatIntervalSec
					else
						tow.pos += delta.Unit * math.min(boss.eatPullSpeed * dt, delta.Magnitude)
					end
				end
			elseif now >= b.nextEatAt then
				local nearest: any, nearestDist = nil, boss.eatRadius
				for _, block in blocks do
					if block.alive and not block.kit and not block.fossil and not block.key then
						local bd = hdist(block.pos, b.pos)
						if bd <= nearestDist then
							nearest, nearestDist = block, bd
						end
					end
				end
				if nearest then
					b.tow = nearest
					emit("tow_start", { letter = nearest.letter, dist = nearestDist })
				end
			end
		end
	end

	-- World upkeep ------------------------------------------------------
	local function stepWorld()
		for i = #respawns, 1, -1 do
			if now >= respawns[i].at then
				spawnBlock(respawns[i].zone)
				table.remove(respawns, i)
			end
		end
		for _, block in blocks do
			if block.alive and block.expiresAt and now >= block.expiresAt then
				block.alive = false
			end
			if block.alive and block.spore and now >= block.burstAt then
				block.alive = false
				local hit = p.alive and hdist(block.pos, p.pos) <= spore.burstRadius
				emit("spore_burst", { hit = hit })
				if hit then
					hurtPlayer(spore.burstDmg, "Spore")
				end
			end
		end
		for _, w in walls do
			if w.broken and w.def.regenSec > 0 and now >= w.resealAt then
				local gate = w.def.gateId
				local ex = p.excursion
				local held = ex ~= nil and gate ~= nil
					and ((ex.zone and ex.zone.gateId == gate) or (ex.keyGate and ex.keyGate.id == gate))
				if not held then
					w.broken = false
					w.hp = w.maxHp
					stats.resealed += 1
					local index = table.find(broken, w.def.part)
					if index then
						table.remove(broken, index)
						rebuildParams()
					end
					emit("wall_state", { name = w.def.name, state = "intact", gate = gate })
					if gate then
						gateOpen[gate] = false
						p.gateRolled[gate] = nil
						for _, zone in level.zones do
							if zone.gateId == gate and zone.kitLength then
								rollKit(zone)
							end
						end
						if gates[gate] then
							rollKeys(gates[gate])
						end
					end
				end
			end
		end
		-- Drop dead blocks now and then so the list stays short.
		if #blocks > 400 then
			local live = {}
			for _, block in blocks do
				if block.alive then
					table.insert(live, block)
				end
			end
			blocks = live
		end
	end

	-- Main loop ---------------------------------------------------------
	emit("fight_start", { persona = persona.name, seed = seed })
	local outcome = "timeout"
	local nextSample = 0
	while now < timeLimit do
		stepWorld()
		stepPlayer(TICK_SEC)
		stepBoss(TICK_SEC)
		if b.spawned and b.hp <= 0 then
			outcome = "win"
			break
		end
		if now >= nextSample then
			nextSample += SAMPLE_EVERY_SEC
			local d = bossDist()
			emit("sample", {
				hp = if p.alive then p.hp else 0, alive = p.alive, bossHp = b.hp, dist = d,
				red = p.mana.red, green = p.mana.green, blue = p.mana.blue,
				canHitBoss = p.alive and b.spawned and d <= SpellRegistry.AUTO_TARGET_RANGE_STUDS,
				bossCanHit = p.alive and b.spawned and d <= attackRange
					and (reachable() or tune.fireWithoutPath or d <= boss.attackRange),
				bossUp = b.spawned,
			})
		end
		now += TICK_SEC
	end
	emit("fight_end", {
		outcome = outcome, bossHp = b.hp, shots = stats.shots, shotsHit = stats.shotsHit,
		shotsBlocked = stats.shotsBlocked, healed = stats.healed, wallsBroken = #broken + stats.resealed,
		redLeft = p.mana.red, greenLeft = p.mana.green, blueLeft = p.mana.blue,
	})

	return { events = events, outcome = outcome, duration = now }
end

return FightSim
