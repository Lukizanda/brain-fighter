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
-- Letter zones (Phase 8 stage 2): a BoxDef may carry `letterTable`,
-- `colorOnly` and `quota`. A box with none of them behaves exactly as the
-- pool always did. A quota box holds exactly `quota` blocks, refills
-- itself in place, and is left out of the density pool: the arena's
-- density target counts non-quota boxes only. See
-- wiki/design/boss-arena.md § Letter zones and ./LetterTables.luau.
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
local Colors = require(ReplicatedStorage.Shared.Core.Colors)
local LetterTables = require(script.LetterTables)

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
local COLORS = Colors.SPELL_COLORS

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

-- Volume-part attribute names BlockSpawnerService reads (the contract in
-- wiki/design/boss-arena.md § Letter zones).
local LETTER_TABLE_ATTRIBUTE = "LetterTable"
local COLOR_ONLY_ATTRIBUTE = "ColorOnly"
local BLOCK_QUOTA_ATTRIBUTE = "BlockQuota"

local UNNAMED_BOX_LABEL = "(unnamed box)"

----------------------------------------------------------------------
-- Types
----------------------------------------------------------------------

export type BoxDef = {
	boxMin: Vector3,
	boxMax: Vector3,
	-- Letter zone fields; all optional, absent means "as always".
	letterTable: string?,  -- LetterTables name; default Standard
	colorOnly: string?,  -- "red" | "green" | "blue"
	quota: number?,  -- holds exactly this many blocks and refills itself
	label: string?,  -- part name, for warnings
}

export type Opts = {
	-- Which arena slot this pool belongs to. Labels the logs and is what
	-- callers key their instances by; defaults to Arena.DEFAULT_ID.
	arenaId: string?,
	-- Density target: the blocks held by the NON-quota boxes. Quota boxes
	-- add their quotas on top (see getTargetCount).
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
	-- Blocks the density (non-quota) boxes hold.
	targetCount: number,
	minSpacing: number,
	respawnDelay: number,
	colorWeights: { [string]: number },
	parent: Instance,
}

-- A box after validation, plus its live bookkeeping.
type BoxState = {
	def: BoxDef,
	label: string,
	letterTable: string,
	colorOnly: string?,
	quota: number?,  -- nil = density box
	count: number,  -- live blocks that came from this box
	spacingWarned: boolean,
}

type BoxCumEntry = { box: BoxState, threshold: number }

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

local function volumeOf(box: BoxDef): number
	local size = box.boxMax - box.boxMin
	return math.abs(size.X * size.Y * size.Z)
end

-- Validates a box's optional zone fields. A bad value warns (naming the
-- part) and falls back to the default instead of silently spawning nothing.
local function makeBoxState(def: BoxDef, arenaId: string): BoxState
	local label = def.label or UNNAMED_BOX_LABEL

	local letterTable = LetterTables.DEFAULT
	if def.letterTable ~= nil then
		if LetterTables.isValid(def.letterTable) then
			letterTable = def.letterTable
		else
			log:warn(string.format(
				"[%s] %s: unknown %s '%s' (valid: %s) — using %s",
				arenaId, label, LETTER_TABLE_ATTRIBUTE, tostring(def.letterTable),
				table.concat(LetterTables.names(), ", "), LetterTables.DEFAULT
			))
		end
	end

	local colorOnly: string? = nil
	if def.colorOnly ~= nil then
		if Colors.isSpellColor(def.colorOnly) then
			colorOnly = def.colorOnly
		else
			log:warn(string.format(
				"[%s] %s: unknown %s '%s' (valid: %s) — using mixed colours",
				arenaId, label, COLOR_ONLY_ATTRIBUTE, tostring(def.colorOnly), table.concat(COLORS, ", ")
			))
		end
	end

	local quota: number? = nil
	if def.quota ~= nil then
		local floored = math.floor(def.quota)
		if floored >= 1 then
			quota = floored
		else
			log:warn(string.format(
				"[%s] %s: %s must be at least 1, got %s — treating as a density volume",
				arenaId, label, BLOCK_QUOTA_ATTRIBUTE, tostring(def.quota)
			))
		end
	end

	return {
		def = def,
		label = label,
		letterTable = letterTable,
		colorOnly = colorOnly,
		quota = quota,
		count = 0,
		spacingWarned = false,
	}
end

local function resolveOpts(u: Opts, densityBoxes: { BoxState }): ResolvedOpts
	-- Resolve the density target: explicit > density-computed > hardcoded
	-- default.
	--
	-- The density term is over THIS arena's non-quota boxes only. As a
	-- singleton it summed every tagged volume in the world, which is the
	-- same number while one arena exists and quietly the wrong one the
	-- moment a second appears. Quota boxes hold their own fixed counts and
	-- must not inflate (or be thinned out of) the open-arena density.
	local targetCount: number
	if #densityBoxes == 0 then
		-- Nothing for density blocks to live in (an all-quota pool).
		targetCount = 0
	elseif u.targetCount then
		targetCount = u.targetCount
	elseif u.density and u.density > 0 then
		local volume = 0
		for _, box in ipairs(densityBoxes) do
			volume += volumeOf(box.def)
		end
		targetCount = math.max(1, math.round(u.density * volume / STUDS_PER_DENSITY_UNIT))
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

BlockSpawner.LETTER_FREQUENCIES = LetterTables.LETTER_FREQUENCIES
BlockSpawner.WILDCARD_FREQUENCY = LetterTables.STANDARD_WILDCARD_FREQUENCY
BlockSpawner.LETTER_TABLE_ATTRIBUTE = LETTER_TABLE_ATTRIBUTE
BlockSpawner.COLOR_ONLY_ATTRIBUTE = COLOR_ONLY_ATTRIBUTE
BlockSpawner.BLOCK_QUOTA_ATTRIBUTE = BLOCK_QUOTA_ATTRIBUTE

export type BlockSpawner = typeof(setmetatable(
	{} :: {
		arenaId: string,
		_opts: ResolvedOpts,
		_boxes: { BoxState },
		_quotaBoxes: { BoxState },
		-- Cumulative box-volume table over the DENSITY (non-quota) boxes;
		-- volume-weighted so each cubic stud of the open arena has equal
		-- probability of spawning a block.
		_boxCumulative: { BoxCumEntry },
		_boxVolumeTotal: number,
		-- Map keyed by Model, valued with the box the block came from:
		-- lookup is O(1) so the removed-signal handler can tell "one of
		-- mine?" in constant time and knows which box to refill.
		-- getActiveBlocks() materializes the array for callers.
		_active: { [Model]: BoxState },
		_activeCount: number,
		-- Live blocks that came from density (non-quota) boxes.
		_densityCount: number,
		_quotaTotal: number,
		_running: boolean,
		_destroyed: boolean,
		_removedConnection: RBXScriptConnection?,
	},
	BlockSpawner
))

function BlockSpawner.new(userOpts: Opts?): BlockSpawner
	local u = userOpts or {}
	local boxDefs = resolveBoxes(u)
	local arenaId = u.arenaId or Arena.DEFAULT_ID

	local boxes: { BoxState } = {}
	local densityBoxes: { BoxState } = {}
	local quotaBoxes: { BoxState } = {}
	local quotaTotal = 0
	for _, def in ipairs(boxDefs) do
		local state = makeBoxState(def, arenaId)
		table.insert(boxes, state)
		if state.quota then
			table.insert(quotaBoxes, state)
			quotaTotal += state.quota
		else
			table.insert(densityBoxes, state)
		end
	end

	local opts = resolveOpts(u, densityBoxes)

	local boxCumulative: { BoxCumEntry } = {}
	local boxVolumeTotal = 0
	for _, box in ipairs(densityBoxes) do
		local vol = volumeOf(box.def)
		if vol > 0 then
			boxVolumeTotal += vol
			table.insert(boxCumulative, { box = box, threshold = boxVolumeTotal })
		end
	end

	local self = setmetatable({
		arenaId = arenaId,
		_opts = opts,
		_boxes = boxes,
		_quotaBoxes = quotaBoxes,
		_boxCumulative = boxCumulative,
		_boxVolumeTotal = boxVolumeTotal,
		_active = {},
		_activeCount = 0,
		_densityCount = 0,
		_quotaTotal = quotaTotal,
		_running = false,
		_destroyed = false,
		_removedConnection = nil,
	}, BlockSpawner)

	log:info(string.format(
		"[%s] Pool created — %d boxes (%d quota), %.0f cubic studs of density volume, target %d blocks (%d density + %d quota)",
		arenaId, #boxes, #quotaBoxes, boxVolumeTotal,
		opts.targetCount + quotaTotal, opts.targetCount, quotaTotal
	))

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

-- Volume-weighted pick among the density boxes: roll against cumulative
-- volume thresholds so each cubic stud across this arena's open volumes
-- has equal spawn probability. Quota boxes are never chosen here.
function BlockSpawner._pickDensityBox(self: BlockSpawner): BoxState
	local roll = math.random() * self._boxVolumeTotal
	local chosen = self._boxCumulative[#self._boxCumulative].box
	for _, entry in ipairs(self._boxCumulative) do
		if roll <= entry.threshold then
			chosen = entry.box
			break
		end
	end
	return chosen
end

function BlockSpawner._pickPosition(_self: BlockSpawner, box: BoxState): Vector3
	local minV, maxV = box.def.boxMin, box.def.boxMax
	return Vector3.new(
		minV.X + math.random() * (maxV.X - minV.X),
		minV.Y + math.random() * (maxV.Y - minV.Y),
		minV.Z + math.random() * (maxV.Z - minV.Z)
	)
end

-- `fixedBox` pins the roll to one box (quota refills); nil rolls a fresh
-- density box per call, as the pool always did.
function BlockSpawner._pickCFrame(self: BlockSpawner, fixedBox: BoxState?): (CFrame, BoxState)
	-- Random initial yaw so a cluster of blocks doesn't read as a
	-- synchronised baseline before the client animator phase-offset
	-- kicks in.
	local box = fixedBox or self:_pickDensityBox()
	local position = self:_pickPosition(box)
	local yaw = math.random() * FULL_REVOLUTION_RADIANS
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0), box
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
--
-- Quota boxes (`fixedBox`) are measured against their OWN box's blocks
-- only, and warn at most once per box. A vault is a sealed room: its
-- neighbours across the wall are irrelevant, and a quota set too high for
-- its volume would otherwise log on every refill, forever.
function BlockSpawner._pickSpacedCFrame(self: BlockSpawner, fixedBox: BoxState?): (CFrame, BoxState)
	local minDist = self._opts.minSpacing
	if minDist <= 0 then
		return self:_pickCFrame(fixedBox)
	end

	local best, bestBox = self:_pickCFrame(fixedBox)
	local bestClearance = -1

	for attempt = 1, MAX_SPAWN_ATTEMPTS do
		local cf, box = best, bestBox
		if attempt > 1 then
			cf, box = self:_pickCFrame(fixedBox)
		end

		-- Distance to the nearest existing block. Stays math.huge on an
		-- empty arena, which clears the check on the first attempt.
		local clearance = math.huge
		for block, blockBox in self._active do
			if fixedBox == nil or blockBox == fixedBox then
				local d = (cf.Position - block:GetPivot().Position).Magnitude
				if d < clearance then
					clearance = d
				end
			end
		end

		if clearance >= minDist then
			return cf, box
		end
		if clearance > bestClearance then
			best = cf
			bestBox = box
			bestClearance = clearance
		end
	end

	if fixedBox == nil then
		log:warn(string.format(
			"[%s] no clear spawn point in %d attempts — wanted %.1f studs, best was %.1f. "
				.. "Arena is too dense for %d blocks; lower BLOCK_SPAWN_DENSITY or add spawn volume.",
			self.arenaId, MAX_SPAWN_ATTEMPTS, minDist, bestClearance, self._opts.targetCount
		))
	elseif not fixedBox.spacingWarned then
		fixedBox.spacingWarned = true
		log:warn(string.format(
			"[%s] %s: no clear spawn point in %d attempts — wanted %.1f studs, best was %.1f. "
				.. "%s %d is too many for this volume; shrink the quota or enlarge the part. (Warning shown once per volume.)",
			self.arenaId, fixedBox.label, MAX_SPAWN_ATTEMPTS, minDist, bestClearance,
			BLOCK_QUOTA_ATTRIBUTE, fixedBox.quota or 0
		))
	end
	return best, bestBox
end

-- Spawns one block, into `fixedBox` for quota boxes or a density box
-- otherwise.
function BlockSpawner._spawnOne(self: BlockSpawner, fixedBox: BoxState?): Model
	local cf, box = self:_pickSpacedCFrame(fixedBox)
	-- A wildcard's color is fixed to gold rather than rolled, so it can't
	-- masquerade as a reservoir color the player might be hunting for. That
	-- holds in a ColorOnly volume too.
	local letter = LetterTables.pick(box.letterTable)
	local color: string
	if Wildcard.isWildcard(letter) then
		color = Wildcard.COLOR
	elseif box.colorOnly then
		color = box.colorOnly
	else
		color = self:_pickColor()
	end

	local block = LetterBlocks.spawn(letter, color, cf, self._opts.parent)
	-- Which pool's block this is. ConsumeBlock refuses a player whose
	-- session is in a different arena — the range check alone would let a
	-- hub player at the boundary pop arena blocks (chunk 9).
	block:SetAttribute(Arena.ID_ATTRIBUTE, self.arenaId)
	self._active[block] = box
	self._activeCount += 1
	box.count += 1
	if not box.quota then
		self._densityCount += 1
	end
	return block
end

function BlockSpawner._maintainCount(self: BlockSpawner)
	if #self._boxCumulative > 0 then
		while self._running and self._densityCount < self._opts.targetCount do
			self:_spawnOne()
		end
	end
	for _, box in ipairs(self._quotaBoxes) do
		local quota = box.quota or 0
		while self._running and box.count < quota do
			self:_spawnOne(box)
		end
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
-- Still bounded by the target (the density target, or the box's quota) so
-- a stale timer surviving a disable()/start() cycle can't push it over.
-- `box` is the box the consumed block came from: a quota block comes back
-- in the same volume.
function BlockSpawner._spawnOneIfBelowTarget(self: BlockSpawner, box: BoxState)
	if not self._running or self._destroyed then
		return
	end
	if box.quota then
		if box.count >= box.quota then
			return
		end
		self:_spawnOne(box)
		return
	end
	if self._densityCount >= self._opts.targetCount or #self._boxCumulative == 0 then
		return
	end
	self:_spawnOne()
end

function BlockSpawner._scheduleRefill(self: BlockSpawner, box: BoxState)
	local delaySeconds = self._opts.respawnDelay
	if delaySeconds > 0 then
		task.delay(delaySeconds, function()
			self:_spawnOneIfBelowTarget(box)
		end)
	else
		-- task.defer rather than an inline call: this runs inside the
		-- removed-signal handler, which is mid-iteration over `_active`.
		task.defer(function()
			self:_spawnOneIfBelowTarget(box)
		end)
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function BlockSpawner.getArenaId(self: BlockSpawner): string
	return self.arenaId
end

-- Total blocks the pool holds when full: the density target plus every
-- quota. For a pool with no quota boxes this is the density target alone,
-- exactly what it returned before zones existed.
function BlockSpawner.getTargetCount(self: BlockSpawner): number
	return self._opts.targetCount + self._quotaTotal
end

-- Blocks the non-quota boxes hold; resolved from those boxes only.
function BlockSpawner.getDensityTarget(self: BlockSpawner): number
	return self._opts.targetCount
end

-- Sum of every quota box's quota.
function BlockSpawner.getQuotaTotal(self: BlockSpawner): number
	return self._quotaTotal
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
		local box = self._active[block]
		if box then
			self._active[block] = nil
			self._activeCount -= 1
			box.count -= 1
			if not box.quota then
				self._densityCount -= 1
			end
			if self._running then
				self:_scheduleRefill(box)
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
-- orphaned one. Keeping the set (and each box's count) across a disable()
-- is what makes this the reversible half of the project's disable/destroy
-- pair.
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
	self._densityCount = 0
	for _, box in ipairs(self._boxes) do
		box.count = 0
	end
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
	-- queued one refill per destroy, each replacing a single block in the
	-- box it came from (so a quota volume refills in place).
	-- With a respawnDelay set, the whole field comes back one
	-- cooldown later rather than immediately.
end

return BlockSpawner
