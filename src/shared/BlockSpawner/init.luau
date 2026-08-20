--!strict

----------------------------------------------------------------------
-- BlockSpawner
----------------------------------------------------------------------
-- Server-side floating-letter-block populator. Maintains a target
-- count of LetterBlock Models in **one arena**. Blocks are spawned
-- server-authoritative (so every client sees the same set); the
-- client-side LetterBlockAnimator handles motion locally.
--
-- One instance per arena slot. Phase 6 stage 2 turned this from a
-- file-local singleton into `BlockSpawner.new(opts)`, following the same
-- idiom stage 1 gave `RoundManager` — the singleton treated every tagged
-- BlockSpawnVolume in the world as one pool, so two arenas would have
-- shared a block budget and drawn positions from each other's boxes. Each
-- instance owns its own boxes, target count and active set;
-- `BlockSpawnerService` groups the tagged volumes by arena id and starts
-- one instance per group. See `wiki/design/lobby.md` § Session model.
--
-- Instances are isolated by construction: the active set is keyed by Model
-- and the CollectionService removed handler only reacts to blocks in its
-- own set, so a block consumed in one arena refills in that arena.
--
-- A consumed block is replaced after `respawnDelay` seconds
-- (GameConfig.BLOCK_RESPAWN_DELAY) rather than on the next frame, so a
-- replacement doesn't materialise in the player's face the instant
-- they shoot one. Each block is on its own clock — see _scheduleRefill.
--
-- Letter selection is Scrabble-frequency-weighted (English vowels +
-- common consonants dominate) — the SOFT-HEURISTIC the design defers
-- "explicit dictionary-bag scan" complexity to (see
-- wiki/design/gameplay-loop.md § "Spawner"). Color selection is
-- independently weighted (default uniform), so a per-level designer
-- can bias a color scarce without touching the spawner.
--
-- Usage:
--   local spawner = BlockSpawner.new({ arenaId = "Default", boxes = ... })
--   spawner:start()      -- fills to target and holds it
--   spawner:disable()    -- stops refilling; blocks stay in the world
--   spawner:destroy()    -- disable + remove this arena's blocks
--
-- See wiki/systems/BlockSpawner.md.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Wildcard = require(ReplicatedStorage.Shared.Wildcard)

local log = Logger.new("BlockSpawner")

----------------------------------------------------------------------
-- Tunables
----------------------------------------------------------------------

-- Default arena footprint from gameplay-loop "Spawner" — ~24 blocks
-- in a 40×8×40 stud volume, ~8 per color at default uniform weights.
local DEFAULT_TARGET_COUNT = 24
local DEFAULT_BOX_MIN = Vector3.new(-20, 8, -20)
local DEFAULT_BOX_MAX = Vector3.new(20, 16, 20)

-- Color weights default to uniform (33/33/33 per gameplay-loop).
-- Per-level designers may override to bias a color scarce.
local DEFAULT_COLOR_WEIGHT = 1
local COLORS = { "red", "green", "blue" }

-- Scrabble letter frequencies (standard English bag of 98 tiles).
-- These are the SOFT-HEURISTIC weights — English vowels and common
-- consonants dominate so a random sample of ~24 blocks will almost
-- always contain spellable letters without an explicit "must be
-- spellable" guarantee.
--
-- These values intentionally MATCH the standard Scrabble distribution
-- and are kept here (not imported from EnergyEconomy) because frequency
-- is conceptually distinct from per-letter point values. Cross-check
-- against [[systems/EnergyEconomy]] if either drifts.
local LETTER_FREQUENCIES: { [string]: number } = {
	A = 9,  B = 2,  C = 2,  D = 4,  E = 12,
	F = 2,  G = 3,  H = 2,  I = 9,  J = 1,
	K = 1,  L = 4,  M = 2,  N = 6,  O = 8,
	P = 2,  Q = 1,  R = 6,  S = 4,  T = 6,
	U = 4,  V = 2,  W = 2,  X = 1,  Y = 2,
	Z = 1,
}

local ALPHABET = {
	"A","B","C","D","E","F","G","H","I","J","K","L","M",
	"N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
}

-- Wildcard blocks roll as a 27th "letter" against the same cumulative
-- table. The Scrabble bag above totals 98, so weight 4 lands at
-- 4/102 ≈ 3.9% — roughly one ★ visible in the ~24-block reference
-- arena. Scrabble's own 2-blanks-in-98 is stingier than this design
-- wants given blocks recycle continuously as they're consumed.
-- Set to 0 to disable wildcard spawns entirely.
local WILDCARD_FREQUENCY = 4

local FULL_REVOLUTION_RADIANS = math.pi * 2
local MAX_SPAWN_ATTEMPTS = 20

-- Blocks per 1000 cubic studs, when a caller passes `density` instead of
-- an explicit `targetCount`. Named because the divisor is a unit
-- conversion, not a tuning knob — GameConfig.BLOCK_SPAWN_DENSITY is the
-- knob.
local STUDS_PER_DENSITY_UNIT = 1000

-- Seconds between a block being consumed and its replacement spawning.
-- Zero reproduces the original same-frame refill.
--
-- This is only the fallback for callers that pass no `respawnDelay`
-- (the Phase 3 test suites, mostly). The shipped game value is
-- GameConfig.BLOCK_RESPAWN_DELAY, threaded through by
-- BlockSpawnerService — tune it there, not here.
local DEFAULT_RESPAWN_DELAY_SECONDS = 0

----------------------------------------------------------------------
-- Types
----------------------------------------------------------------------

export type BoxDef = { boxMin: Vector3, boxMax: Vector3 }

export type Opts = {
	-- Which arena slot this pool belongs to. Labels the logs and is what
	-- callers key their instances by; defaults to Arena.DEFAULT_ID.
	arenaId: string?,
	targetCount: number?,
	density: number?,
	boxes: { BoxDef }?,
	boxMin: Vector3?,
	boxMax: Vector3?,
	colorWeights: { red: number?, green: number?, blue: number? }?,
	parent: Instance?,
	minSpacing: number?,  -- minimum studs between block centers; 0 disables
	respawnDelay: number?,  -- seconds before a consumed block is replaced; 0 refills next frame
}

type ResolvedOpts = {
	targetCount: number,
	minSpacing: number,
	respawnDelay: number,
	colorWeights: { [string]: number },
	parent: Instance,
}

type LetterCumEntry = { letter: string, threshold: number }
type BoxCumEntry = { box: BoxDef, threshold: number }

----------------------------------------------------------------------
-- Letter table (module-level)
----------------------------------------------------------------------
-- Derived purely from the constants above, never from per-instance opts,
-- so it is built once at require rather than copied into every arena.
-- Cumulative thresholds make a weighted pick a single linear scan over 27
-- entries instead of summing frequencies on every roll.

local letterCumulative: { LetterCumEntry } = {}
local letterTotal = 0

do
	for _, letter in ipairs(ALPHABET) do
		local weight = LETTER_FREQUENCIES[letter] or 0
		if weight > 0 then
			letterTotal += weight
			table.insert(letterCumulative, { letter = letter, threshold = letterTotal })
		end
	end
	if WILDCARD_FREQUENCY > 0 then
		letterTotal += WILDCARD_FREQUENCY
		table.insert(letterCumulative, { letter = Wildcard.CHAR, threshold = letterTotal })
	end
end

local function pickLetter(): string
	local roll = math.random() * letterTotal
	for _, entry in ipairs(letterCumulative) do
		if roll <= entry.threshold then
			return entry.letter
		end
	end
	-- Numerical-edge fallback: math.random() can return values very
	-- close to letterTotal due to float rounding; cumulative threshold
	-- comparisons may miss the last entry.
	return letterCumulative[#letterCumulative].letter
end

----------------------------------------------------------------------
-- Options resolution
----------------------------------------------------------------------

local function resolveBoxes(u: Opts): { BoxDef }
	-- Prefer an explicit array, fall back to the single-box shorthand.
	if u.boxes and #u.boxes > 0 then
		return u.boxes
	end
	return { {
		boxMin = u.boxMin or DEFAULT_BOX_MIN,
		boxMax = u.boxMax or DEFAULT_BOX_MAX,
	} }
end

local function totalVolumeOf(boxes: { BoxDef }): number
	local total = 0
	for _, box in ipairs(boxes) do
		local size = box.boxMax - box.boxMin
		total += math.abs(size.X * size.Y * size.Z)
	end
	return total
end

local function resolveOpts(u: Opts, boxes: { BoxDef }): ResolvedOpts
	-- Resolve target count: explicit > density-computed > hardcoded default.
	--
	-- The density term is over THIS arena's boxes only. As a singleton it
	-- summed every tagged volume in the world, which is the same number
	-- while one arena exists and quietly the wrong one the moment a second
	-- appears — both arenas would size themselves off the combined volume.
	local targetCount: number
	if u.targetCount then
		targetCount = u.targetCount
	elseif u.density and u.density > 0 then
		targetCount = math.max(1, math.round(u.density * totalVolumeOf(boxes) / STUDS_PER_DENSITY_UNIT))
	else
		targetCount = DEFAULT_TARGET_COUNT
	end

	-- Partial colorWeights tables fill unset keys from the default.
	-- Using ~= nil (not `or`) so an explicit zero is honoured —
	-- `{ red = 0 }` means "no red", not "default red".
	local cw = u.colorWeights or {}

	return {
		targetCount = targetCount,
		colorWeights = {
			red = if cw.red ~= nil then cw.red else DEFAULT_COLOR_WEIGHT,
			green = if cw.green ~= nil then cw.green else DEFAULT_COLOR_WEIGHT,
			blue = if cw.blue ~= nil then cw.blue else DEFAULT_COLOR_WEIGHT,
		},
		parent = u.parent or workspace,
		minSpacing = u.minSpacing or 0,
		-- ~= nil, not `or` — an explicit 0 means "refill next frame", which
		-- is what the Phase 3 suites pin, and `or` would silently swap it
		-- for the default.
		respawnDelay = if u.respawnDelay ~= nil then u.respawnDelay else DEFAULT_RESPAWN_DELAY_SECONDS,
	}
end

----------------------------------------------------------------------
-- Instance
----------------------------------------------------------------------

local BlockSpawner = {}
BlockSpawner.__index = BlockSpawner

BlockSpawner.LETTER_FREQUENCIES = LETTER_FREQUENCIES
BlockSpawner.WILDCARD_FREQUENCY = WILDCARD_FREQUENCY

export type BlockSpawner = typeof(setmetatable(
	{} :: {
		arenaId: string,
		_opts: ResolvedOpts,
		_boxes: { BoxDef },
		-- Cumulative box-volume table; volume-weighted so each cubic stud
		-- of this arena has equal probability of spawning a block.
		_boxCumulative: { BoxCumEntry },
		_boxVolumeTotal: number,
		-- Set keyed by Model: lookup is O(1) so the removed-signal handler
		-- can tell "one of mine?" in constant time. getActiveBlocks()
		-- materializes the array for callers.
		_active: { [Model]: true },
		_activeCount: number,
		_running: boolean,
		_destroyed: boolean,
		_removedConnection: RBXScriptConnection?,
	},
	BlockSpawner
))

function BlockSpawner.new(userOpts: Opts?): BlockSpawner
	local u = userOpts or {}
	local boxes = resolveBoxes(u)
	local opts = resolveOpts(u, boxes)

	local boxCumulative: { BoxCumEntry } = {}
	local boxVolumeTotal = 0
	for _, box in ipairs(boxes) do
		local size = box.boxMax - box.boxMin
		local vol = math.abs(size.X * size.Y * size.Z)
		if vol > 0 then
			boxVolumeTotal += vol
			table.insert(boxCumulative, { box = box, threshold = boxVolumeTotal })
		end
	end

	local self = setmetatable({
		arenaId = u.arenaId or Arena.DEFAULT_ID,
		_opts = opts,
		_boxes = boxes,
		_boxCumulative = boxCumulative,
		_boxVolumeTotal = boxVolumeTotal,
		_active = {},
		_activeCount = 0,
		_running = false,
		_destroyed = false,
		_removedConnection = nil,
	}, BlockSpawner)

	log:info(string.format("[%s] Pool created — %d boxes, %.0f cubic studs, target %d blocks",
		self.arenaId, #boxes, boxVolumeTotal, opts.targetCount))

	return self
end

----------------------------------------------------------------------
-- Pickers
----------------------------------------------------------------------

function BlockSpawner._pickColor(self: BlockSpawner): string
	local weights = self._opts.colorWeights
	local total = 0
	for _, color in ipairs(COLORS) do
		total += weights[color] or 0
	end
	if total <= 0 then
		return COLORS[math.random(1, #COLORS)]
	end
	local roll = math.random() * total
	local runningSum = 0
	for _, color in ipairs(COLORS) do
		runningSum += weights[color] or 0
		if roll <= runningSum then
			return color
		end
	end
	return COLORS[#COLORS]
end

function BlockSpawner._pickPosition(self: BlockSpawner): Vector3
	-- Volume-weighted box selection: roll against cumulative volume thresholds
	-- so each cubic stud across this arena's boxes has equal spawn probability.
	local roll = math.random() * self._boxVolumeTotal
	local chosen = self._boxCumulative[#self._boxCumulative].box
	for _, entry in ipairs(self._boxCumulative) do
		if roll <= entry.threshold then
			chosen = entry.box
			break
		end
	end
	local minV, maxV = chosen.boxMin, chosen.boxMax
	return Vector3.new(
		minV.X + math.random() * (maxV.X - minV.X),
		minV.Y + math.random() * (maxV.Y - minV.Y),
		minV.Z + math.random() * (maxV.Z - minV.Z)
	)
end

function BlockSpawner._pickCFrame(self: BlockSpawner): CFrame
	-- Random initial yaw so a cluster of blocks doesn't read as a
	-- synchronised baseline before the client animator phase-offset
	-- kicks in.
	local position = self:_pickPosition()
	local yaw = math.random() * FULL_REVOLUTION_RADIANS
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

----------------------------------------------------------------------
-- Spawn / track helpers
----------------------------------------------------------------------

-- Rejection sampling, but keeping the roomiest candidate seen rather
-- than the last one rolled.
--
-- The previous loop re-rolled on collision and, when every attempt
-- collided, fell through and spawned at the LAST rejected position --
-- which is an arbitrary failing candidate, not the least-bad one, and
-- it did so silently. That made a too-dense arena indistinguishable
-- from a healthy one right up until blocks visibly interpenetrated.
--
-- Now a spacing failure degrades to "as far from its neighbours as 20
-- rolls could manage" and says so in the log.
--
-- Clearance is measured against this arena's blocks only. Two arenas
-- never share space, so a neighbour in another one is not a collision.
function BlockSpawner._pickSpacedCFrame(self: BlockSpawner): CFrame
	local minDist = self._opts.minSpacing
	if minDist <= 0 then
		return self:_pickCFrame()
	end

	local best = self:_pickCFrame()
	local bestClearance = -1

	for attempt = 1, MAX_SPAWN_ATTEMPTS do
		local cf = if attempt == 1 then best else self:_pickCFrame()

		-- Distance to the nearest existing block. Stays math.huge on an
		-- empty arena, which clears the check on the first attempt.
		local clearance = math.huge
		for block in self._active do
			local d = (cf.Position - block:GetPivot().Position).Magnitude
			if d < clearance then
				clearance = d
			end
		end

		if clearance >= minDist then
			return cf
		end
		if clearance > bestClearance then
			best = cf
			bestClearance = clearance
		end
	end

	log:warn(string.format(
		"[%s] no clear spawn point in %d attempts — wanted %.1f studs, best was %.1f. "
			.. "Arena is too dense for %d blocks; lower BLOCK_SPAWN_DENSITY or add spawn volume.",
		self.arenaId, MAX_SPAWN_ATTEMPTS, minDist, bestClearance, self._opts.targetCount
	))
	return best
end

function BlockSpawner._spawnOne(self: BlockSpawner): Model
	local cf = self:_pickSpacedCFrame()
	-- A wildcard's color is fixed to gold rather than rolled, so it can't
	-- masquerade as a reservoir color the player might be hunting for.
	local letter = pickLetter()
	local color = if Wildcard.isWildcard(letter) then Wildcard.COLOR else self:_pickColor()

	local block = LetterBlocks.spawn(letter, color, cf, self._opts.parent)
	self._active[block] = true
	self._activeCount += 1
	return block
end

function BlockSpawner._maintainCount(self: BlockSpawner)
	while self._running and self._activeCount < self._opts.targetCount do
		self:_spawnOne()
	end
end

-- Replaces exactly ONE block, not "however many are missing".
--
-- Deliberately not _maintainCount(): with a respawn delay, each consumed
-- block owns its own timer, and the first timer to expire must not
-- refill the arena to target. If it did, three blocks shot a second
-- apart would all reappear the instant the first cooldown elapsed —
-- two of them early, in a burst. One-in-one-out keeps each replacement
-- on the clock that its own destruction started.
--
-- Still bounded by targetCount so a stale timer surviving a
-- disable()/start() cycle can't push the arena over.
function BlockSpawner._spawnOneIfBelowTarget(self: BlockSpawner)
	if not self._running or self._destroyed then
		return
	end
	if self._activeCount >= self._opts.targetCount then
		return
	end
	self:_spawnOne()
end

function BlockSpawner._scheduleRefill(self: BlockSpawner)
	local delaySeconds = self._opts.respawnDelay
	if delaySeconds > 0 then
		task.delay(delaySeconds, function()
			self:_spawnOneIfBelowTarget()
		end)
	else
		-- task.defer rather than an inline call: this runs inside the
		-- removed-signal handler, which is mid-iteration over `_active`.
		task.defer(function()
			self:_spawnOneIfBelowTarget()
		end)
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function BlockSpawner.getArenaId(self: BlockSpawner): string
	return self.arenaId
end

function BlockSpawner.getTargetCount(self: BlockSpawner): number
	return self._opts.targetCount
end

function BlockSpawner.getActiveBlocks(self: BlockSpawner): { Model }
	local out: { Model } = {}
	for block in self._active do
		table.insert(out, block)
	end
	return out
end

function BlockSpawner.start(self: BlockSpawner)
	if self._destroyed then
		log:warn(string.format("[%s] Cannot start a destroyed pool", self.arenaId))
		return
	end
	if self._running then
		log:warn(string.format("[%s] start() called while already running — no-op", self.arenaId))
		return
	end

	-- Hook consumption BEFORE the initial fill so any destroys
	-- triggered mid-fill (rare, but a rapid test could do it) still
	-- refill correctly.
	--
	-- The tag is global, so this fires for every arena's blocks; the
	-- `_active` lookup is what makes it this arena's business only.
	self._removedConnection = CollectionService:GetInstanceRemovedSignal(LetterBlocks.TAG):Connect(function(instance)
		local block = instance :: Model
		if self._active[block] then
			self._active[block] = nil
			self._activeCount -= 1
			if self._running then
				self:_scheduleRefill()
			end
		end
	end)

	self._running = true
	self:_maintainCount()
	log:info(string.format("[%s] started — %d blocks", self.arenaId, self._activeCount))
end

-- Reversible halt: stop refilling, leave the blocks standing. A later
-- start() reconnects and tops the surviving set back up to target.
--
-- The singleton's stop()/start() pair could not do that — start() reset
-- `active` to empty while the Models it described were still parented to
-- the workspace, so a restart spawned a second full field on top of an
-- orphaned one. Keeping the set across a disable() is what makes this the
-- reversible half of the project's disable/destroy pair.
function BlockSpawner.disable(self: BlockSpawner)
	if not self._running then
		return
	end
	self._running = false
	if self._removedConnection then
		self._removedConnection:Disconnect()
		self._removedConnection = nil
	end
	log:info(string.format("[%s] disabled — %d blocks left standing", self.arenaId, self._activeCount))
end

-- Permanent teardown: halt, then remove this arena's blocks from the world.
-- The connection is already dropped by disable(), so the destroys below
-- cannot schedule refills.
function BlockSpawner.destroy(self: BlockSpawner)
	if self._destroyed then
		return
	end

	self:disable()
	self._destroyed = true

	-- Snapshot first: :Destroy() fires the removed signal synchronously
	-- and other live pools iterate their own sets from that handler.
	local snapshot = self:getActiveBlocks()
	table.clear(self._active)
	self._activeCount = 0
	for _, block in ipairs(snapshot) do
		block:Destroy()
	end

	log:info(string.format("[%s] destroyed — %d blocks removed", self.arenaId, #snapshot))
end

function BlockSpawner.rerollAll(self: BlockSpawner)
	log:info(string.format("[%s] rerollAll triggered", self.arenaId))
	-- Snapshot the keys first because :Destroy() fires the removed
	-- signal synchronously and mutates `_active` mid-iteration.
	local snapshot = self:getActiveBlocks()
	for _, block in ipairs(snapshot) do
		block:Destroy()
	end
	-- The removed-signal handler has cleared `_active` by now and
	-- queued one refill per destroy, each replacing a single block.
	-- With a respawnDelay set, the whole field comes back one
	-- cooldown later rather than immediately.
end

return BlockSpawner
