--!strict

----------------------------------------------------------------------
-- BossBombs
----------------------------------------------------------------------
-- The boss's scramble bomb, a two-phase PUZZLE (wiki/design/scramble-bomb.md;
-- numbers in BossConfig `bomb*`; the contract in BombConstants). It takes the
-- spore lob's slot: every `bombEveryNthAttack`th attack that would have been a
-- FireballVolley lobs one puzzle instead (never while the word ward is up, so
-- a player never faces two letter puzzles at once).
--
--   1. LOB    the boss lobs ONE puzzle at its target (`beginLob`): it lands
--             `bombFlightSec` later, within `bombLandRadius` studs of where the
--             target stood, on a floor-like surface near the target's ground,
--             clear of walls. The attack state ends at the landing.
--   2. REST   at landing the puzzle Model appears: one part per letter of a
--             scrambled key word, resting round the centre. Players tap them in
--             an order that spells an allowed word (BombRules) from within
--             `bombTapReach` of the centre: the letter locks, the last one
--             solves the puzzle (boss damage, BombDefused). An out-of-order tap
--             is refused: progress kept, the timer loses
--             `bombWrongTapPenaltySec`.
--   3. HATCH  if the timer (`bombFuseSecByLetters`) runs out, the unlocked
--             letters hatch into seekers, `bombHatchStaggerSec` apart. Each
--             follows a player (the nearest living one to the puzzle at hatch
--             time; if they die or leave, the nearest living one; nobody, it
--             keeps its heading), speeding up with its age, a side slot apart
--             from its siblings. A seeker that reaches its player, runs into
--             geometry or outlives `bombSeekerLifetimeSec` BURSTS for area
--             damage. A pop within `bombSeekerTapReach` of a seeker only
--             removes it.
--
-- Who owns what. This object decides the word, the scramble, the colour, the
-- landing, the timer, the hatch, every seeker's flight and burst, judges every
-- tap, applies the damage and is the ONLY writer of what the puzzle Model and
-- its parts publish (BombConstants). Like BossSpores it is one small object
-- per boss, not a state: BossStates asks it (`replacesVolley`) when the
-- selection is a volley and hands it the throw (`beginLob`), BossController
-- ticks it with the real dt (`tick`), and the tap service routes a client's
-- tap to it through BombRegistry (`tap`, `reachOf`). Nothing here credits
-- energy: BombDefused is the Economy's cue.
--
-- Movement is server-authoritative: a hatched part is anchored and moved by
-- `tick(dt)`; a step is `speed * dt`, so it does not depend on the frame rate.
-- Tests inject `dt` and `now` (`tick(dt, now)`; `beginLob`'s optional `now`),
-- so nothing waits real seconds.
--
-- Everything a player sees is drawn by clients from the parts, the attributes
-- and VfxBroadcast cues (`lob` for the flight); the server draws and plays
-- nothing of its own. Damage goes through Health's applyDamage.process, the one
-- writer of Humanoid.Health. Every time a client reads is
-- `workspace:GetServerTimeNow()`.
--
-- Ending: the controller's destroy() (boss dead, round ended) removes every
-- puzzle silently in any phase (and drops a lob still in the air): no burst,
-- no events.
--
-- Switched off, with no cost, for a type that does not configure the bomb
-- (Wizard). A type that configures it wrongly warns once and does not throw.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BroadcastAudience = require(ReplicatedStorage.Shared.GameMode.BroadcastAudience)
local BlockShoot = require(ReplicatedStorage.Shared.BlockShoot)
local BombConstants = require(ReplicatedStorage.Shared.Boss.BombConstants)
local BombRules = require(ReplicatedStorage.Shared.Boss.BombRules)
local BossConstants = require(ReplicatedStorage.Shared.Boss.BossConstants)
local BossTypes = require(ReplicatedStorage.Shared.Boss.BossTypes)
local DamageTypes = require(ReplicatedStorage.Shared.Health.DamageTypes)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Hittables = require(ReplicatedStorage.Shared.Skills.Hittables)
local VfxBroadcast = require(ReplicatedStorage.Shared.Vfx.VfxBroadcast)

local applyDamage = require(ServerScriptService.Server.Health.Scripts.HealthService.applyDamage)
local BombRegistry = require(script.Parent.BombRegistry)


local log = Logger.new("BossBombs")

local TAU = math.pi * 2

local BossBombs = {}
BossBombs.__index = BossBombs

local Phase = BombConstants.Phase

-- One live seeker (a hatched letter).
type Seeker = {
	index: number,
	part: BasePart,
	hatchedAt: number,
	-- Who it chases; nil = nobody (it keeps `heading`).
	follow: Player?,
	-- Unit vector, horizontal: where it was last going.
	heading: Vector3,
	-- The way it is actually flying when its turning is limited
	-- (bombSeekerTurnDegPerSec); nil until its first step.
	course: Vector3?,
	-- Set on its final approach: it no longer tracks, and has this many studs
	-- of straight flight left before it bursts.
	committed: boolean?,
	dashLeft: number?,
	-- When it starts to move (its hatch + the arming pause + its turn in the
	-- stagger), and how much of the launch arc's height it carries now.
	launchAt: number,
	arcOffset: number?,
	position: Vector3,
	-- World Y of the ground last found under it (the burst ring's height).
	groundY: number,
}

-- One puzzle: a word's worth of letters, resting and then (maybe) hatched.
type Puzzle = {
	model: Model,
	arenaId: string,
	letters: { string },
	allowed: { string },
	color: string,
	letterCount: number,
	-- Locked letter indices in tap order.
	accepted: { number },
	-- Accepted taps per player, and the order in which each reached its count
	-- (a sequence number, so a tie goes to the earliest).
	pops: { [Player]: { count: number, seq: number } },
	-- The puzzle's centre at hover height, and the ground under it.
	centre: Vector3,
	groundY: number,
	phase: string,
	-- Server time at which the timer ends (moves earlier on a refused tap).
	hatchAt: number,
	-- Parts that have not hatched (locked ones stay here until the hatch).
	parts: { [number]: BasePart },
	-- Letters waiting to hatch, in index order, and when the next one is due.
	pending: { number },
	-- Seekers hatched so far: each launches bombSeekerLaunchStaggerSec after the one before.
	hatchRank: number?,
	nextHatchAt: number,
	seekers: { [number]: Seeker },
	liveCount: number,
	-- The player the seekers follow from the hatch (nil = nobody) and the
	-- heading they start with.
	follow: Player?,
	heading: Vector3,
	targetUserId: number,
}

-- A lob in the air: everything the landing needs, rolled at the throw.
type Lob = {
	landAt: number,
	ground: Vector3,
	letters: { string },
	allowed: { string },
	color: string,
	letterCount: number,
	heading: Vector3,
	onLanded: () -> (),
}

export type BossBombsInstance = typeof(setmetatable(
	{} :: {
		_boss: Model,
		_humanoid: Humanoid,
		_root: BasePart,
		_everyNth: number,
		_flightSec: number,
		_landRadius: number,
		_fuseSecByLetters: { [number]: number },
		_wrongTapPenaltySec: number,
		_hatchStaggerSec: number,
		_speed: number,
		_speedMax: number,
		_lifetimeSec: number,
		_armSec: number,
		-- Radians a second a seeker can turn; 0 = it tracks its player exactly.
		_turnRate: number,
		-- The final approach: inside _commitStuds of its player a seeker stops
		-- tracking and flies straight at _dashSpeed for at most _dashStuds.
		-- Launch: each seeker of a puzzle starts _launchStaggerSec after the one
		-- before, rising _arcHeight over its first _arcSec.
		_launchStaggerSec: number,
		_arcHeight: number,
		_arcSec: number,
		_commitStuds: number,
		_dashSpeed: number,
		_dashStuds: number,
		_spacing: number,
		_convergeStuds: number,
		_triggerStuds: number,
		_hoverHeight: number,
		_lettersByPhase: { number },
		_hintAfterSec: number,
		_defuseDamageByLetters: { [number]: number },
		_burstDamage: number,
		_burstRadius: number,
		_tapReach: number,
		_seekerTapReach: number,
		_colors: { string },
		_energyScale: number?,
		-- false: a solved puzzle pays its word's energy only, the boss is not hurt.
		_defuseDamageEnabled: boolean,
		_defusedEvent: BindableEvent,
		_burstEvent: BindableEvent,
		_landedEvent: BindableEvent,
		_brokenEvent: BindableEvent,
		_poppedEvent: BindableEvent,
		_hatchedEvent: BindableEvent,
		-- Attacks that would have been a volley, counted since the boss spawned.
		_volleys: number,
		_tapSeq: number,
		-- The lob in the air, at most one.
		_lob: Lob?,
		_puzzles: { Puzzle },
		_lastNow: number?,
		_destroyed: boolean,
	},
	BossBombs
))

local function isPositive(value: number?): boolean
	return value ~= nil and value > 0
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Why a type that asks for the bomb cannot have it, or nil when it can.
local function configProblem(spec: BossTypes.BossTypeSpec): string?
	-- A list of pairs, not a table: a missing field must still be named.
	local required: { { string | number? } } = {
		{ "bombFlightSec", spec.bombFlightSec },
		{ "bombLandRadius", spec.bombLandRadius },
		{ "bombHatchStaggerSec", spec.bombHatchStaggerSec },
		{ "bombSeekerSpeed", spec.bombSeekerSpeed },
		{ "bombSeekerSpeedMax", spec.bombSeekerSpeedMax },
		{ "bombSeekerLifetimeSec", spec.bombSeekerLifetimeSec },
		{ "bombSeekerSpacing", spec.bombSeekerSpacing },
		{ "bombSeekerConvergeStuds", spec.bombSeekerConvergeStuds },
		{ "bombSeekerTriggerStuds", spec.bombSeekerTriggerStuds },
		{ "bombHintAfterSec", spec.bombHintAfterSec },
		{ "bombBurstRadius", spec.bombBurstRadius },
		{ "bombTapReach", spec.bombTapReach },
		{ "bombSeekerTapReach", spec.bombSeekerTapReach },
	}
	for _, entry in required do
		local value = entry[2]
		if type(value) ~= "number" or value <= 0 then
			return tostring(entry[1]) .. " is not positive"
		end
	end
	local penalty = spec.bombWrongTapPenaltySec
	if type(penalty) ~= "number" or penalty < 0 then
		return "bombWrongTapPenaltySec is not zero or more"
	end
	local lettersByPhase = spec.bombLettersByPhase
	local damageByLetters = spec.bombDefuseDamageByLetters
	local fuseByLetters = spec.bombFuseSecByLetters
	if lettersByPhase == nil or #lettersByPhase == 0 then
		return "bombLettersByPhase is empty"
	end
	if damageByLetters == nil then
		return "bombDefuseDamageByLetters is missing"
	end
	if fuseByLetters == nil then
		return "bombFuseSecByLetters is missing"
	end
	for _, count in lettersByPhase do
		if count ~= math.floor(count) or count < 1 then
			return "bombLettersByPhase holds " .. tostring(count)
		end
		if damageByLetters[count] == nil or damageByLetters[count] < 0 then
			return "no defuse damage for " .. tostring(count) .. " letters"
		end
		if fuseByLetters[count] == nil or fuseByLetters[count] <= 0 then
			return "no timer for " .. tostring(count) .. " letters"
		end
		if #BombRules.poolFor(count) == 0 then
			return "no words of " .. tostring(count) .. " letters to build a puzzle from"
		end
	end
	local colors = spec.bombColors
	if colors == nil or #colors == 0 then
		return "bombColors is empty"
	end
	for _, color in colors do
		if LetterBlocks.COLOR_TINTS[color] == nil then
			return "bombColors holds unknown colour " .. tostring(color)
		end
	end
	return nil
end

-- Does this boss type lob puzzles at all?
function BossBombs.isEnabledFor(spec: BossTypes.BossTypeSpec): boolean
	return isPositive(spec.bombEveryNthAttack) and configProblem(spec) == nil
end

-- Nil when the type does not lob puzzles, so the controller holds nothing for it.
function BossBombs.new(
	boss: Model,
	humanoid: Humanoid,
	root: BasePart,
	spec: BossTypes.BossTypeSpec
): BossBombsInstance?
	if not isPositive(spec.bombEveryNthAttack) then
		return nil
	end
	local problem = configProblem(spec)
	if problem ~= nil then
		log:warn(string.format("%s asks for a scramble bomb but %s — it will not lob", tostring(spec.name), problem))
		return nil
	end
	local events = ServerScriptService.Server.Boss.Events
	return setmetatable({
		_boss = boss,
		_humanoid = humanoid,
		_root = root,
		_everyNth = math.max(1, math.floor(spec.bombEveryNthAttack :: number)),
		_flightSec = spec.bombFlightSec :: number,
		_landRadius = spec.bombLandRadius :: number,
		_fuseSecByLetters = spec.bombFuseSecByLetters :: { [number]: number },
		_wrongTapPenaltySec = spec.bombWrongTapPenaltySec :: number,
		_hatchStaggerSec = spec.bombHatchStaggerSec :: number,
		_speed = spec.bombSeekerSpeed :: number,
		_speedMax = spec.bombSeekerSpeedMax :: number,
		_lifetimeSec = spec.bombSeekerLifetimeSec :: number,
		_armSec = math.max(spec.bombSeekerArmSec or 0, 0),
		_turnRate = math.rad(math.max(spec.bombSeekerTurnDegPerSec or 0, 0)),
		_launchStaggerSec = math.max(spec.bombSeekerLaunchStaggerSec or 0, 0),
		_arcHeight = math.max(spec.bombSeekerArcHeight or 0, 0),
		_arcSec = math.max(spec.bombSeekerArcSec or 0, 0),
		_commitStuds = math.max(spec.bombSeekerCommitStuds or 0, 0),
		_dashSpeed = math.max(spec.bombSeekerDashSpeed or 0, 0),
		_dashStuds = math.max(spec.bombSeekerDashStuds or 0, 0),
		_spacing = spec.bombSeekerSpacing :: number,
		_convergeStuds = spec.bombSeekerConvergeStuds :: number,
		_triggerStuds = spec.bombSeekerTriggerStuds :: number,
		_hoverHeight = math.max(spec.bombHoverHeight or 0, 0),
		_lettersByPhase = spec.bombLettersByPhase :: { number },
		_hintAfterSec = spec.bombHintAfterSec :: number,
		_defuseDamageByLetters = spec.bombDefuseDamageByLetters :: { [number]: number },
		_burstDamage = math.max(spec.bombBurstDamage or 0, 0),
		_burstRadius = spec.bombBurstRadius :: number,
		-- With bombTapReachEnabled false a resting puzzle can be solved from as
		-- far as any letter block can be tapped. Published as BombReach, so the
		-- client follows without knowing about the switch.
		_tapReach = if spec.bombTapReachEnabled == false
			then BlockShoot.MAX_RAYCAST_DISTANCE
			else spec.bombTapReach :: number,
		_seekerTapReach = spec.bombSeekerTapReach :: number,
		_colors = spec.bombColors :: { string },
		_energyScale = spec.bombEnergyScale,
		_defuseDamageEnabled = spec.bombDefuseDamageEnabled ~= false,
		_defusedEvent = events[BombConstants.DEFUSED_EVENT] :: BindableEvent,
		_burstEvent = events[BombConstants.BURST_EVENT] :: BindableEvent,
		_landedEvent = events[BombConstants.LANDED_EVENT] :: BindableEvent,
		_brokenEvent = events[BombConstants.BROKEN_EVENT] :: BindableEvent,
		_poppedEvent = events[BombConstants.POPPED_EVENT] :: BindableEvent,
		_hatchedEvent = events[BombConstants.HATCHED_EVENT] :: BindableEvent,
		_volleys = 0,
		_tapSeq = 0,
		_lob = nil,
		_puzzles = {},
		_lastNow = nil,
		_destroyed = false,
	}, BossBombs)
end

----------------------------------------------------------------------
-- Selection
----------------------------------------------------------------------

-- Called once for every attack that would have been a FireballVolley: true for
-- every Nth, which is a puzzle instead, unless the word ward is up (the boss's
-- published `WardUp` attribute; the slot is spent, not saved). The count
-- advances either way, so the cadence is the volley slots', not the puzzles'.
function BossBombs.replacesVolley(self: BossBombsInstance): boolean
	self._volleys += 1
	if self._boss:GetAttribute(BossConstants.WARD_UP_ATTRIBUTE) == true then
		return false
	end
	return self._volleys % self._everyNth == 0
end

----------------------------------------------------------------------
-- Players
----------------------------------------------------------------------

-- The player's root when they are in the game and alive, else nil.
local function livingRoot(player: Player?): BasePart?
	if player == nil or player.Parent == nil then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

-- The nearest living player of the arena to `position`, or nil.
function BossBombs._nearestPlayer(self: BossBombsInstance, arenaId: string, position: Vector3): Player?
	local best: Player? = nil
	local bestDistance = math.huge
	for _, hittable in Hittables.collect(BroadcastAudience.forArena(arenaId), arenaId) do
		local player = hittable.player
		if player == nil then
			continue
		end
		local distance = (hittable.hrp.Position - position).Magnitude
		if distance < bestDistance then
			best = player
			bestDistance = distance
		end
	end
	return best
end

----------------------------------------------------------------------
-- World objects
----------------------------------------------------------------------

local function container(): Instance
	local existing = workspace:FindFirstChild(BombConstants.CONTAINER_NAME)
	if existing ~= nil then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = BombConstants.CONTAINER_NAME
	folder.Parent = workspace
	return folder
end

local function greyboxPart(name: string, tint: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Block
	part.Size = BombConstants.TILE_SIZE
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = tint
	part.Transparency = BombConstants.TILE_TRANSPARENCY
	return part
end

-- What a probe must pass through: the boss, the arena's players and NPCs, every
-- player's character (dead or alive: Hittables lists only the living, and a
-- corpse's Head (CanCollide) would otherwise read as a wall), letter blocks,
-- and the puzzles' own folder (so seekers and other puzzles never stop one).
function BossBombs._rayParams(self: BossBombsInstance, arenaId: string): RaycastParams
	local ignore: { Instance } = { self._boss, container() }
	for _, hittable in Hittables.collect(BroadcastAudience.forArena(arenaId), arenaId) do
		table.insert(ignore, hittable.model)
	end
	for _, player in Players:GetPlayers() do
		if player.Character ~= nil then
			table.insert(ignore, player.Character)
		end
	end
	for _, block in CollectionService:GetTagged(LetterBlocks.TAG) do
		table.insert(ignore, block)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return params
end

----------------------------------------------------------------------
-- The lob
----------------------------------------------------------------------

-- Where the puzzle lands: a ground point within bombLandRadius (horizontal) of
-- `targetPosition` (the target's root) that has a real ground hit under it, a
-- floor-like surface, a height within LAND_HEIGHT_TOLERANCE_STUDS of the
-- target's own ground and no colliding part at the centre (not in a wall).
-- After LAND_MAX_ATTEMPTS misses: the target's own ground.
function BossBombs._pickLanding(self: BossBombsInstance, targetPosition: Vector3, arenaId: string): Vector3
	local params = self:_rayParams(arenaId)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = params.FilterDescendantsInstances
	overlap.RespectCanCollide = true

	local function groundAt(x: number, z: number): RaycastResult?
		return workspace:Raycast(
			Vector3.new(x, targetPosition.Y + BombConstants.LAND_PROBE_UP_STUDS, z),
			Vector3.new(0, -(BombConstants.LAND_PROBE_UP_STUDS + BombConstants.LAND_PROBE_DOWN_STUDS), 0),
			params
		)
	end

	local own = groundAt(targetPosition.X, targetPosition.Z)
	local ownY = if own ~= nil then own.Position.Y else targetPosition.Y - BombConstants.LAND_ROOT_TO_FEET_STUDS

	for _ = 1, BombConstants.LAND_MAX_ATTEMPTS do
		local angle = math.random() * TAU
		local distance = math.random() * self._landRadius
		local x = targetPosition.X + math.cos(angle) * distance
		local z = targetPosition.Z + math.sin(angle) * distance
		local hit = groundAt(x, z)
		if hit == nil or hit.Normal.Y < BombConstants.LAND_MIN_NORMAL_Y then
			continue
		end
		if math.abs(hit.Position.Y - ownY) > BombConstants.LAND_HEIGHT_TOLERANCE_STUDS then
			continue
		end
		local centre = Vector3.new(x, hit.Position.Y + self._hoverHeight, z)
		if #workspace:GetPartBoundsInRadius(centre, BombConstants.LAND_CLEARANCE_RADIUS_STUDS, overlap) > 0 then
			continue
		end
		return Vector3.new(x, hit.Position.Y, z)
	end
	return Vector3.new(targetPosition.X, ownY, targetPosition.Z)
end

-- Start a lob at `targetPosition` (the target's root). `onLanded` runs from
-- tick() when the puzzle has landed: the attack state ends then. `_targetRoot`
-- is accepted for the lobbers' shared signature and not used. `now` is the
-- server time of the throw (default: the clock; tests inject theirs). False
-- (and `onLanded` never runs) when a lob is already in the air, the boss is
-- dead, or no word could be rolled. The puzzle Model does not exist until it
-- lands.
function BossBombs.beginLob(
	self: BossBombsInstance,
	targetPosition: Vector3,
	onLanded: () -> (),
	_targetRoot: BasePart?,
	now: number?
): boolean
	if self._destroyed or self._lob ~= nil or self._humanoid.Health <= 0 then
		return false
	end

	local arenaId = Arena.idOf(self._boss)
	local phase = self._boss:GetAttribute(BossConstants.PHASE_ATTRIBUTE)
	local phaseIndex = if type(phase) == "number" then math.max(1, math.floor(phase)) else 1
	local letterCount = self._lettersByPhase[math.min(phaseIndex, #self._lettersByPhase)]
	local pool = BombRules.poolFor(letterCount)
	if #pool == 0 then
		log:warn(string.format("[%s] no word of %d letters to build a puzzle from", arenaId, letterCount))
		return false
	end
	local word = pool[math.random(1, #pool)]
	local allowed = BombRules.allowedWords(word, pool)
	local letters = BombRules.scramble(word, allowed)

	local ground = self:_pickLanding(targetPosition, arenaId)
	local landAt = (now or workspace:GetServerTimeNow()) + self._flightSec
	local toLanding = ground - self._root.Position
	local flat = Vector3.new(toLanding.X, 0, toLanding.Z)
	local heading = if flat.Magnitude > BombConstants.MIN_DIRECTION_STUDS then flat.Unit else Vector3.zAxis

	self._lob = {
		landAt = landAt,
		ground = ground,
		letters = letters,
		allowed = allowed,
		color = self._colors[math.random(1, #self._colors)],
		letterCount = letterCount,
		heading = heading,
		onLanded = onLanded,
	}

	-- The throw (a sound at the boss) and the pod with its landing marker.
	local origin = self._root.Position + Vector3.new(0, BombConstants.LOB_ORIGIN_HEIGHT_STUDS, 0)
	VfxBroadcast.playAt(BossConstants.SPORE_LOB_VFX, origin)
	VfxBroadcast.lob({
		origin = origin,
		landings = {
			{ arrival = ground + Vector3.new(0, self._hoverHeight, 0), ground = ground },
		},
		arriveAt = landAt,
		color = BossConstants.SPORE_LOB_COLOR,
		markerRadius = BossConstants.SPORE_LOB_MARKER_RADIUS_STUDS,
	})
	log:info(string.format("[%s] lobbing a puzzle of %d letters (%s), lands in %.1fs", arenaId, letterCount, table.concat(letters), self._flightSec))
	return true
end

----------------------------------------------------------------------
-- Landing: the puzzle Model and its resting letters
----------------------------------------------------------------------

-- The flight is over: the puzzle Model appears, every attribute in place
-- before it is parented and tagged, so a client that sees it finds them all.
function BossBombs._land(self: BossBombsInstance, lob: Lob, now: number)
	local arenaId = Arena.idOf(self._boss)
	local centre = lob.ground + Vector3.new(0, self._hoverHeight, 0)
	local fuseSec = self._fuseSecByLetters[lob.letterCount]
	local tint = LetterBlocks.COLOR_TINTS[lob.color]

	local model = Instance.new("Model")
	model.Name = BombConstants.MODEL_NAME
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute(Arena.ID_ATTRIBUTE, arenaId)
	model:SetAttribute(BombConstants.LETTERS_ATTRIBUTE, table.concat(lob.letters))
	model:SetAttribute(BombConstants.COLOR_ATTRIBUTE, lob.color)
	model:SetAttribute(BombConstants.WORDS_ATTRIBUTE, BombRules.encodeWords(lob.allowed))
	model:SetAttribute(BombConstants.ACCEPTED_ATTRIBUTE, "")
	model:SetAttribute(BombConstants.HINT_AT_ATTRIBUTE, now + self._hintAfterSec)
	model:SetAttribute(BombConstants.REACH_ATTRIBUTE, self._tapReach)
	model:SetAttribute(BombConstants.SEEKER_REACH_ATTRIBUTE, self._seekerTapReach)
	model:SetAttribute(BombConstants.BURST_RADIUS_ATTRIBUTE, self._burstRadius)
	model:SetAttribute(BombConstants.BROKEN_ATTRIBUTE, false)
	model:SetAttribute(BombConstants.TARGET_USER_ID_ATTRIBUTE, 0)
	model:SetAttribute(BombConstants.PHASE_ATTRIBUTE, Phase.Resting)
	model:SetAttribute(BombConstants.CENTRE_ATTRIBUTE, centre)
	model:SetAttribute(BombConstants.GROUND_Y_ATTRIBUTE, lob.ground.Y)
	model:SetAttribute(BombConstants.HATCH_AT_ATTRIBUTE, now + fuseSec)
	model:SetAttribute(BombConstants.FUSE_SEC_ATTRIBUTE, fuseSec)

	local parts: { [number]: BasePart } = {}
	for index = 1, lob.letterCount do
		local angle = TAU * (index - 1) / lob.letterCount
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * BombConstants.REST_RADIUS_STUDS
		local part = greyboxPart(BombConstants.TILE_PART_PREFIX .. tostring(index), tint)
		part.Position = centre + offset
		part:SetAttribute(BombConstants.TILE_INDEX_ATTRIBUTE, index)
		part.Parent = model
		parts[index] = part
	end
	CollectionService:AddTag(model, BombConstants.TAG)
	model.Parent = container()
	BombRegistry.register(model, self)

	table.insert(self._puzzles, {
		model = model,
		arenaId = arenaId,
		letters = lob.letters,
		allowed = lob.allowed,
		color = lob.color,
		letterCount = lob.letterCount,
		accepted = {},
		pops = {},
		centre = centre,
		groundY = lob.ground.Y,
		phase = Phase.Resting,
		hatchAt = now + fuseSec,
		parts = parts,
		pending = {},
		nextHatchAt = now,
		seekers = {},
		liveCount = 0,
		follow = nil,
		heading = lob.heading,
		targetUserId = 0,
	} :: Puzzle)
	VfxBroadcast.playAt(BombConstants.LAND_VFX, centre)
	self._landedEvent:Fire(arenaId, lob.letterCount)
	log:info(string.format("[%s] a puzzle landed (%s, %.0fs on the timer)", arenaId, table.concat(lob.letters), fuseSec))
end

-- Take the puzzle's Model out of the world and the puzzle out of the list.
function BossBombs._finish(self: BossBombsInstance, puzzle: Puzzle)
	BombRegistry.unregister(puzzle.model)
	puzzle.model:Destroy()
	table.clear(puzzle.parts)
	table.clear(puzzle.seekers)
	puzzle.liveCount = 0
	table.clear(puzzle.pending)
	local index = table.find(self._puzzles, puzzle)
	if index ~= nil then
		table.remove(self._puzzles, index)
	end
end

-- Take a seeker's part out of the world and out of the puzzle's books.
function BossBombs._removeSeeker(_self: BossBombsInstance, puzzle: Puzzle, seeker: Seeker)
	if puzzle.seekers[seeker.index] ~= seeker then
		return
	end
	puzzle.seekers[seeker.index] = nil
	puzzle.liveCount -= 1
	seeker.part:Destroy()
end

-- Once nothing is flying and nothing is left to hatch, a hatched puzzle ends.
function BossBombs._endIfSpent(self: BossBombsInstance, puzzle: Puzzle)
	if puzzle.phase == Phase.Chasing and #puzzle.pending == 0 and puzzle.liveCount <= 0 then
		self:_finish(puzzle)
	end
end

----------------------------------------------------------------------
-- Taps
----------------------------------------------------------------------

function BossBombs._find(self: BossBombsInstance, model: Model): Puzzle?
	for _, puzzle in self._puzzles do
		if puzzle.model == model then
			return puzzle
		end
	end
	return nil
end

-- Where a tap on letter `tileIndex` of `model` is measured from, and how far
-- it may reach: resting, the puzzle's centre and bombTapReach; chasing, that
-- seeker's position and bombSeekerTapReach. Nil (and 0) when there is no such
-- live letter (gone, locked and removed, not hatched yet, bad index): the tap
-- service rejects it.
function BossBombs.reachOf(self: BossBombsInstance, model: Model, tileIndex: number): (Vector3?, number)
	local puzzle = self:_find(model)
	if puzzle == nil then
		return nil, 0
	end
	if puzzle.phase == Phase.Resting then
		if puzzle.parts[tileIndex] ~= nil then
			return puzzle.centre, self._tapReach
		end
		return nil, 0
	end
	local seeker = puzzle.seekers[tileIndex]
	if seeker ~= nil then
		return seeker.position, self._seekerTapReach
	end
	return nil, 0
end

-- The player's tap on letter `tileIndex` of `model`. The caller (the tap
-- service) has already checked who, where and how often; this judges the tap
-- itself:
--   Resting:
--     Accepted  the letter locks (the puzzle is solved if it was the last);
--     Refused   out of order: progress kept, the timer loses the penalty;
--     Locked    already locked: nothing changes;
--   Chasing:
--     Harmless  the seeker is removed, no lock, no reward;
--   Invalid     no such live letter.
function BossBombs.tap(self: BossBombsInstance, player: Player, model: Model, tileIndex: number): string
	local results = BombConstants.TapResult
	if self._destroyed then
		return results.Invalid
	end
	local puzzle = self:_find(model)
	if puzzle == nil or tileIndex ~= math.floor(tileIndex) then
		return results.Invalid
	end

	if puzzle.phase == Phase.Chasing then
		local seeker = puzzle.seekers[tileIndex]
		if seeker == nil then
			return results.Invalid
		end
		VfxBroadcast.playAt(BombConstants.POP_VFX, seeker.position)
		self:_removeSeeker(puzzle, seeker)
		self:_endIfSpent(puzzle)
		return results.Harmless
	end

	local part = puzzle.parts[tileIndex]
	if part == nil then
		return results.Invalid
	end
	if BombRules.isLockedTile(puzzle.accepted, tileIndex) then
		return results.Locked
	end

	if not BombRules.isAccepted(puzzle.letters, puzzle.allowed, puzzle.accepted, tileIndex) then
		puzzle.hatchAt -= self._wrongTapPenaltySec
		puzzle.model:SetAttribute(BombConstants.HATCH_AT_ATTRIBUTE, puzzle.hatchAt)
		VfxBroadcast.playAt(BombConstants.REFUSED_VFX, part.Position)
		self._poppedEvent:Fire(puzzle.arenaId, false)
		return results.Refused
	end

	VfxBroadcast.playAt(BombConstants.POP_VFX, part.Position)
	table.insert(puzzle.accepted, tileIndex)
	puzzle.model:SetAttribute(BombConstants.ACCEPTED_ATTRIBUTE, BombRules.encodeIndices(puzzle.accepted))
	self._tapSeq += 1
	local record = puzzle.pops[player]
	if record == nil then
		record = { count = 0, seq = 0 }
		puzzle.pops[player] = record
	end
	record.count += 1
	record.seq = self._tapSeq
	self._poppedEvent:Fire(puzzle.arenaId, true)

	if BombRules.isSolved(puzzle.letters, puzzle.allowed, puzzle.accepted) then
		self:_complete(puzzle)
	end
	return results.Accepted
end

-- The player with the most accepted taps; a tie goes to the one who reached
-- that count first. Nil when that player has left.
local function creditedPlayer(puzzle: Puzzle): Player?
	local best: Player? = nil
	local bestRecord: { count: number, seq: number }? = nil
	for player, record in puzzle.pops do
		if bestRecord == nil or record.count > bestRecord.count
			or (record.count == bestRecord.count and record.seq < bestRecord.seq)
		then
			best = player
			bestRecord = record
		end
	end
	if best ~= nil and best.Parent == nil then
		return nil
	end
	return best
end

-- Every letter is in: the word goes back at the boss.
function BossBombs._complete(self: BossBombsInstance, puzzle: Puzzle)
	local word = BombRules.solvedWord(puzzle.letters, puzzle.allowed, puzzle.accepted) or table.concat(puzzle.letters)
	local credited = creditedPlayer(puzzle)
	local centre = puzzle.centre
	-- Gone first: damage can end the boss, and with it this object.
	self:_finish(puzzle)
	-- The cue lands on the boss when the word hurts it, else where the puzzle was.
	VfxBroadcast.playAt(BombConstants.DEFUSE_VFX, if self._defuseDamageEnabled then self._root.Position else centre)

	if self._defuseDamageEnabled and self._humanoid.Health > 0 then
		applyDamage.process({
			sourcePlayer = credited,
			targetHumanoid = self._humanoid,
			baseDamage = self._humanoid.MaxHealth * (self._defuseDamageByLetters[puzzle.letterCount] or 0),
			damageType = DamageTypes.DamageType.Spell,
			hitZone = DamageTypes.HitZone.Torso,
			timestamp = os.clock(),
			cause = BombConstants.DEFUSE_CAUSE,
		})
	end
	self._defusedEvent:Fire(credited, word, puzzle.color, puzzle.arenaId, puzzle.letterCount, self._energyScale)
	log:info(string.format("[%s] a puzzle was solved (%s)", puzzle.arenaId, word))
end

----------------------------------------------------------------------
-- Hatch
----------------------------------------------------------------------

-- The timer ran out: the puzzle can no longer be solved. Locked letters'
-- parts go at once; every other letter is queued to hatch, `bombHatchStaggerSec`
-- apart in index order, the first right now.
function BossBombs._hatch(self: BossBombsInstance, puzzle: Puzzle, now: number)
	puzzle.phase = Phase.Chasing
	for _, index in puzzle.accepted do
		local part = puzzle.parts[index]
		if part ~= nil then
			puzzle.parts[index] = nil
			part:Destroy()
		end
	end
	for index = 1, puzzle.letterCount do
		if not BombRules.isLockedTile(puzzle.accepted, index) then
			table.insert(puzzle.pending, index)
		end
	end
	puzzle.nextHatchAt = now

	-- Who they chase: the nearest living player to the puzzle, now.
	local follow = self:_nearestPlayer(puzzle.arenaId, puzzle.centre)
	puzzle.follow = follow
	local root = livingRoot(follow)
	if root ~= nil then
		local toPlayer = root.Position - puzzle.centre
		local flat = Vector3.new(toPlayer.X, 0, toPlayer.Z)
		if flat.Magnitude > BombConstants.MIN_DIRECTION_STUDS then
			puzzle.heading = flat.Unit
		end
	end
	puzzle.targetUserId = if follow ~= nil then follow.UserId else 0

	local model = puzzle.model
	model:SetAttribute(BombConstants.BROKEN_ATTRIBUTE, true)
	model:SetAttribute(BombConstants.PHASE_ATTRIBUTE, Phase.Chasing)
	model:SetAttribute(BombConstants.TARGET_USER_ID_ATTRIBUTE, puzzle.targetUserId)
	self._brokenEvent:Fire(puzzle.arenaId)
	self._hatchedEvent:Fire(puzzle.arenaId, #puzzle.pending)
	log:info(string.format("[%s] the timer ran out, %d letter(s) hatch", puzzle.arenaId, #puzzle.pending))
end

-- Hatch the letters whose turn has come.
function BossBombs._hatchDue(self: BossBombsInstance, puzzle: Puzzle, now: number)
	while #puzzle.pending > 0 and now >= puzzle.nextHatchAt do
		local index = table.remove(puzzle.pending, 1) :: number
		puzzle.nextHatchAt += self._hatchStaggerSec
		local part = puzzle.parts[index]
		if part == nil then
			continue
		end
		puzzle.parts[index] = nil
		part:SetAttribute(BombConstants.SEEKER_EXPIRES_ATTRIBUTE, now + self._lifetimeSec)
		part:SetAttribute(BombConstants.HATCHED_ATTRIBUTE, true)
		local rank = puzzle.hatchRank or 0
		puzzle.hatchRank = rank + 1
		puzzle.seekers[index] = {
			index = index,
			part = part,
			hatchedAt = now,
			launchAt = now + self._armSec + rank * self._launchStaggerSec,
			follow = puzzle.follow,
			heading = puzzle.heading,
			position = part.Position,
			groundY = puzzle.groundY,
		}
		puzzle.liveCount += 1
		VfxBroadcast.playAt(BombConstants.HATCH_VFX, part.Position)
	end
end

----------------------------------------------------------------------
-- Burst
----------------------------------------------------------------------

-- A seeker bursts where it is: remove it, hurt the players inside the radius.
function BossBombs._burst(self: BossBombsInstance, puzzle: Puzzle, seeker: Seeker, why: string)
	local position = seeker.position
	local groundY = seeker.groundY
	self:_removeSeeker(puzzle, seeker)
	VfxBroadcast.playAt(BombConstants.BURST_VFX, position)
	VfxBroadcast.shockwave(Vector3.new(position.X, groundY, position.Z), self._burstRadius, {
		color = BossConstants.SPORE_RING_COLOR,
		lifetimeSec = BossConstants.SPORE_BURST_RING_SEC,
		yOffset = BossConstants.SPORE_BURST_RING_Y_OFFSET_STUDS,
	})

	local hit = 0
	for _, hittable in Hittables.collect(BroadcastAudience.forArena(puzzle.arenaId), puzzle.arenaId) do
		-- Players only, as the boss's slam is: not its own arena's NPCs.
		if hittable.player == nil then
			continue
		end
		if horizontalDistance(hittable.hrp.Position, position) > self._burstRadius then
			continue
		end
		-- Not through a floor or a wall: a player on another level, or with
		-- cover between them and the burst, is not hurt.
		if math.abs(hittable.hrp.Position.Y - position.Y) > BombConstants.BURST_HEIGHT_TOLERANCE_STUDS then
			continue
		end
		if workspace:Raycast(position, hittable.hrp.Position - position, self:_rayParams(puzzle.arenaId)) ~= nil then
			continue
		end
		applyDamage.process({
			sourcePlayer = nil,
			targetHumanoid = hittable.hum,
			baseDamage = self._burstDamage,
			damageType = DamageTypes.DamageType.Explosion,
			hitZone = DamageTypes.HitZone.Torso,
			timestamp = os.clock(),
			cause = BombConstants.BURST_CAUSE,
		})
		hit += 1
	end
	self._burstEvent:Fire(puzzle.arenaId, hit)
	log:info(string.format("[%s] a seeker burst (%s), %d player(s) hit", puzzle.arenaId, why, hit))
end

----------------------------------------------------------------------
-- Flight
----------------------------------------------------------------------

-- A seeker's speed at `age` seconds: linear from bombSeekerSpeed at 0 to
-- bombSeekerSpeedMax at bombSeekerLifetimeSec (and beyond: capped).
function BossBombs.speedAt(self: BossBombsInstance, age: number): number
	local share = math.clamp(age / self._lifetimeSec, 0, 1)
	return self._speed + (self._speedMax - self._speed) * share
end

-- `from` turned toward `to` (both flat unit vectors) by at most `maxRadians`.
local function turnToward(from: Vector3, to: Vector3, maxRadians: number): Vector3
	local angle = math.atan2(from.X * to.Z - from.Z * to.X, from.X * to.X + from.Z * to.Z)
	local turn = math.clamp(angle, -maxRadians, maxRadians)
	local cos, sin = math.cos(turn), math.sin(turn)
	return Vector3.new(from.X * cos - from.Z * sin, 0, from.X * sin + from.Z * cos)
end

-- Move one seeker `dt` seconds along its chase; bursts it when it arrives, hits
-- a wall or has lived its life. Returns true if it burst.
function BossBombs._step(
	self: BossBombsInstance,
	puzzle: Puzzle,
	seeker: Seeker,
	now: number,
	dt: number,
	params: RaycastParams
): boolean
	local age = now - seeker.hatchedAt
	if age >= self._lifetimeSec then
		self:_burst(puzzle, seeker, "its life ended")
		return true
	end
	-- Freshly hatched, it hangs where it is for bombSeekerArmSec before it
	-- moves or can burst: the tell, and the time to pop it or reach cover.
	if now < seeker.launchAt then
		return false
	end

	-- Who it chases: its player while they live, else the nearest living one.
	local root = livingRoot(seeker.follow)
	if root == nil then
		seeker.follow = self:_nearestPlayer(puzzle.arenaId, seeker.position)
		root = livingRoot(seeker.follow)
	end

	local moveDirection = seeker.heading
	local remaining = math.huge
	if root ~= nil then
		local toTarget = root.Position - seeker.position
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		local distance = flat.Magnitude
		if distance <= self._triggerStuds and math.abs(toTarget.Y) <= BombConstants.BURST_HEIGHT_TOLERANCE_STUDS then
			self:_burst(puzzle, seeker, "it reached its player")
			return true
		end
		if distance > BombConstants.MIN_DIRECTION_STUDS then
			seeker.heading = flat.Unit
		end
		-- The final approach: close enough, it locks onto where its player is
		-- at this instant and stops tracking. A step aside now makes it miss.
		if not seeker.committed and self._commitStuds > 0 and self._dashSpeed > 0 and distance <= self._commitStuds then
			seeker.committed = true
			seeker.course = seeker.heading
			seeker.dashLeft = self._dashStuds
			seeker.part:SetAttribute(BombConstants.COMMITTED_ATTRIBUTE, true)
		end
		-- The side slot, centred on 0, closing to nothing inside the converge
		-- distance so the seekers meet on the player.
		local slot = seeker.index - (puzzle.letterCount + 1) / 2
		local lateral = slot * self._spacing * math.clamp(distance / self._convergeStuds, 0, 1)
		local side = Vector3.new(-seeker.heading.Z, 0, seeker.heading.X)
		local aim = flat + side * lateral
		remaining = aim.Magnitude
		if remaining > BombConstants.MIN_DIRECTION_STUDS then
			moveDirection = aim.Unit
		else
			moveDirection = seeker.heading
		end
	end

	local step = self:speedAt(age) * dt
	if seeker.committed then
		-- Straight and fast, no steering; spent, it bursts where it is.
		moveDirection = seeker.course or seeker.heading
		step = self._dashSpeed * dt
		local left = (seeker.dashLeft or 0) - step
		seeker.dashLeft = left
		if left <= 0 then
			self:_burst(puzzle, seeker, "its dash ran out")
			return true
		end
	elseif self._turnRate > 0 then
		-- It cannot turn on the spot: its course swings toward where it wants
		-- to go at bombSeekerTurnDegPerSec, so a player who steps aside late
		-- makes it fly past and come round again.
		local course = seeker.course or moveDirection
		moveDirection = turnToward(course, moveDirection, self._turnRate * dt)
		seeker.course = moveDirection
	else
		step = math.min(step, remaining)
	end
	local horizontal = seeker.position + moveDirection * step

	-- Hover over the ground beneath, gliding toward that height.
	local ground = workspace:Raycast(
		Vector3.new(horizontal.X, seeker.position.Y + BombConstants.GROUND_PROBE_UP_STUDS, horizontal.Z),
		Vector3.new(0, -(BombConstants.GROUND_PROBE_UP_STUDS + BombConstants.GROUND_PROBE_DOWN_STUDS), 0),
		params
	)
	local y = seeker.position.Y
	local groundY = seeker.groundY
	if ground ~= nil then
		groundY = ground.Position.Y
		local reach = BombConstants.VERTICAL_SPEED_STUDS * dt
		y += math.clamp(groundY + self._hoverHeight - (y - (seeker.arcOffset or 0)), -reach, reach)
	end
	-- The launch: it rises in an arc and settles back over its first seconds.
	if self._arcHeight > 0 and self._arcSec > 0 then
		local arc = self._arcHeight * math.sin(math.pi * math.clamp((now - seeker.launchAt) / self._arcSec, 0, 1))
		y += arc - (seeker.arcOffset or 0)
		seeker.arcOffset = arc
	end
	local nextPosition = Vector3.new(horizontal.X, y, horizontal.Z)

	-- A short cast ahead: geometry in the way bursts it where it is.
	local travel = nextPosition - seeker.position
	local wall = workspace:Raycast(
		seeker.position,
		travel + moveDirection * BombConstants.WALL_CAST_MARGIN_STUDS,
		params
	)
	if wall ~= nil then
		self:_burst(puzzle, seeker, "it hit " .. wall.Instance.Name)
		return true
	end

	seeker.position = nextPosition
	seeker.groundY = groundY
	seeker.part.CFrame = CFrame.new(nextPosition)
	return false
end

----------------------------------------------------------------------
-- Tick and ending
----------------------------------------------------------------------

-- Called every Heartbeat by BossController while the boss lives, with the real
-- dt. Lands the lob when it is due, hatches puzzles whose timer ran out and
-- letters whose turn has come, and moves every live seeker. Tests pass `dt`
-- and `now` (workspace:GetServerTimeNow() seconds) themselves; with `now`
-- omitted the clock is read, and with `dt` omitted it is the time since the
-- last tick.
function BossBombs.tick(self: BossBombsInstance, dt: number?, now: number?)
	if self._destroyed then
		return
	end
	if self._humanoid.Health <= 0 then
		self:_clear()
		return
	end
	local current = now or workspace:GetServerTimeNow()
	local last = self._lastNow
	self._lastNow = current
	local step = math.clamp(dt or (if last ~= nil then current - last else 0), 0, BombConstants.MAX_STEP_DT_SEC)

	local lob = self._lob
	if lob ~= nil and current >= lob.landAt then
		self._lob = nil
		self:_land(lob, current)
		lob.onLanded()
	end

	-- Backwards, so a finished puzzle can drop its entry as it goes.
	for puzzleIndex = #self._puzzles, 1, -1 do
		local puzzle = self._puzzles[puzzleIndex]
		if puzzle == nil then
			continue
		end
		-- A model something else destroyed: the puzzle is gone, silently.
		if puzzle.model.Parent == nil then
			BombRegistry.unregister(puzzle.model)
			table.remove(self._puzzles, puzzleIndex)
			continue
		end

		if puzzle.phase == Phase.Resting and current >= puzzle.hatchAt then
			self:_hatch(puzzle, current)
		end
		if puzzle.phase ~= Phase.Chasing then
			continue
		end
		self:_hatchDue(puzzle, current)

		-- Flight. A snapshot of the seekers, since a burst removes one.
		local live: { Seeker } = {}
		for _, seeker in puzzle.seekers do
			table.insert(live, seeker)
		end
		table.sort(live, function(a: Seeker, b: Seeker)
			return a.index < b.index
		end)
		if #live > 0 then
			local params = self:_rayParams(puzzle.arenaId)
			for _, seeker in live do
				if puzzle.seekers[seeker.index] == seeker then
					self:_step(puzzle, seeker, current, step, params)
				end
			end
		end

		-- Who the lowest-index live seeker follows.
		for index = 1, puzzle.letterCount do
			local seeker = puzzle.seekers[index]
			if seeker ~= nil then
				local targetUserId = if seeker.follow ~= nil then seeker.follow.UserId else 0
				if targetUserId ~= puzzle.targetUserId then
					puzzle.targetUserId = targetUserId
					puzzle.model:SetAttribute(BombConstants.TARGET_USER_ID_ATTRIBUTE, targetUserId)
				end
				break
			end
		end

		self:_endIfSpent(puzzle)
	end
end

-- Seekers in flight, over every puzzle.
function BossBombs.liveCount(self: BossBombsInstance): number
	local total = 0
	for _, puzzle in self._puzzles do
		total += puzzle.liveCount
	end
	return total
end

-- The Models of the live puzzles (a copy of the list).
function BossBombs.liveModels(self: BossBombsInstance): { Model }
	local out: { Model } = {}
	for _, puzzle in self._puzzles do
		table.insert(out, puzzle.model)
	end
	return out
end

-- Is a lob in the air? (The attack state is waiting on it.)
function BossBombs.isInFlight(self: BossBombsInstance): boolean
	return self._lob ~= nil
end

-- The player seeker `tileIndex` of `model` follows now, nil if nobody or no
-- such seeker.
function BossBombs.followOf(self: BossBombsInstance, model: Model, tileIndex: number): Player?
	local puzzle = self:_find(model)
	local seeker = puzzle and puzzle.seekers[tileIndex]
	return if seeker then seeker.follow else nil
end

-- Drop the lob in the air and remove every puzzle, no burst, no events.
function BossBombs._clear(self: BossBombsInstance)
	self._lob = nil
	for index = #self._puzzles, 1, -1 do
		local puzzle = self._puzzles[index]
		if puzzle ~= nil then
			self:_finish(puzzle)
		end
	end
end

-- The controller is going (boss dead, round ended): the puzzles go with it.
function BossBombs.destroy(self: BossBombsInstance)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self:_clear()
end

return BossBombs
