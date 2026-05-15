--!strict

----------------------------------------------------------------------
-- BlockSpawner
----------------------------------------------------------------------
-- Server-side floating-letter-block populator. Maintains a target
-- count of LetterBlock Models in the arena. Blocks are spawned
-- server-authoritative (so every client sees the same set); the
-- client-side LetterBlockAnimator handles motion locally.
--
-- Letter selection is Scrabble-frequency-weighted (English vowels +
-- common consonants dominate) — the SOFT-HEURISTIC the design defers
-- "explicit dictionary-bag scan" complexity to (see
-- wiki/design/gameplay-loop.md § "Spawner"). Color selection is
-- independently weighted (default uniform), so a per-level designer
-- can bias a color scarce without touching the spawner.
--
-- See wiki/systems/BlockSpawner.md.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

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

local FULL_REVOLUTION_RADIANS = math.pi * 2
local MAX_SPAWN_ATTEMPTS = 20

----------------------------------------------------------------------
-- Types
----------------------------------------------------------------------

export type BoxDef = { boxMin: Vector3, boxMax: Vector3 }

export type Opts = {
	targetCount: number?,
	density: number?,
	boxes: { BoxDef }?,
	boxMin: Vector3?,
	boxMax: Vector3?,
	colorWeights: { red: number?, green: number?, blue: number? }?,
	parent: Instance?,
	minSpacing: number?,  -- minimum studs between block centers; 0 disables
}

----------------------------------------------------------------------
-- Internal state
----------------------------------------------------------------------

local running = false
local resolvedOpts = {
	targetCount = DEFAULT_TARGET_COUNT,
	minSpacing = 0,
	colorWeights = {
		red = DEFAULT_COLOR_WEIGHT,
		green = DEFAULT_COLOR_WEIGHT,
		blue = DEFAULT_COLOR_WEIGHT,
	},
	parent = workspace :: Instance,
}

local resolvedBoxes: { BoxDef } = { { boxMin = DEFAULT_BOX_MIN, boxMax = DEFAULT_BOX_MAX } }

-- Set keyed by Model: lookup is O(1) so the removed-signal handler
-- can tell "one of ours?" in constant time. getActiveBlocks()
-- materializes the array for callers.
local active: { [Model]: true } = {}
local activeCount = 0

local removedConnection: RBXScriptConnection? = nil

-- Cumulative letter table — rebuilt once per start() so weighted
-- picks are a single linear scan over 26 entries instead of summing
-- frequencies on every roll.
type LetterCumEntry = { letter: string, threshold: number }
local letterCumulative: { LetterCumEntry } = {}
local letterTotal = 0

-- Cumulative box-volume table — rebuilt in start(); volume-weighted
-- so each cubic stud has equal probability of spawning a block.
type BoxCumEntry = { box: BoxDef, threshold: number }
local boxCumulative: { BoxCumEntry } = {}
local boxVolumeTotal = 0

----------------------------------------------------------------------
-- Pickers
----------------------------------------------------------------------

local function buildLetterTable()
	letterCumulative = {}
	letterTotal = 0
	for _, letter in ipairs(ALPHABET) do
		local weight = LETTER_FREQUENCIES[letter] or 0
		if weight > 0 then
			letterTotal += weight
			table.insert(letterCumulative, { letter = letter, threshold = letterTotal })
		end
	end
end

local function buildBoxTable()
	boxCumulative = {}
	boxVolumeTotal = 0
	for _, box in ipairs(resolvedBoxes) do
		local size = box.boxMax - box.boxMin
		local vol = math.abs(size.X * size.Y * size.Z)
		if vol > 0 then
			boxVolumeTotal += vol
			table.insert(boxCumulative, { box = box, threshold = boxVolumeTotal })
		end
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

local function pickColor(): string
	local weights = resolvedOpts.colorWeights
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

local function pickPosition(): Vector3
	-- Volume-weighted box selection: roll against cumulative volume thresholds
	-- so each cubic stud across all boxes has equal spawn probability.
	local roll = math.random() * boxVolumeTotal
	local chosen = boxCumulative[#boxCumulative].box
	for _, entry in ipairs(boxCumulative) do
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

local function pickCFrame(): CFrame
	-- Random initial yaw so a cluster of blocks doesn't read as a
	-- synchronised baseline before the client animator phase-offset
	-- kicks in.
	local position = pickPosition()
	local yaw = math.random() * FULL_REVOLUTION_RADIANS
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

----------------------------------------------------------------------
-- Spawn / track helpers
----------------------------------------------------------------------

local function spawnOne(): Model
	local cf = pickCFrame()
	local minDist = resolvedOpts.minSpacing
	if minDist > 0 then
		for _ = 1, MAX_SPAWN_ATTEMPTS do
			local clear = true
			for block in active do
				if (cf.Position - block:GetPivot().Position).Magnitude < minDist then
					clear = false
					break
				end
			end
			if clear then
				break
			end
			cf = pickCFrame()
		end
	end
	local block = LetterBlocks.spawn(pickLetter(), pickColor(), cf, resolvedOpts.parent)
	active[block] = true
	activeCount += 1
	return block
end

local function maintainCount()
	while running and activeCount < resolvedOpts.targetCount do
		spawnOne()
	end
end

local function scheduleRefill()
	task.defer(function()
		if not running then
			return
		end
		maintainCount()
	end)
end

----------------------------------------------------------------------
-- Options resolution
----------------------------------------------------------------------

local function applyOpts(userOpts: Opts?)
	local u = userOpts or {}

	-- Resolve boxes: prefer explicit array, fall back to single-box shorthand.
	if u.boxes and #u.boxes > 0 then
		resolvedBoxes = u.boxes
	else
		resolvedBoxes = { {
			boxMin = u.boxMin or DEFAULT_BOX_MIN,
			boxMax = u.boxMax or DEFAULT_BOX_MAX,
		} }
	end

	-- Resolve target count: explicit > density-computed > hardcoded default.
	if u.targetCount then
		resolvedOpts.targetCount = u.targetCount
	elseif u.density and u.density > 0 then
		local totalVol = 0
		for _, box in ipairs(resolvedBoxes) do
			local size = box.boxMax - box.boxMin
			totalVol += math.abs(size.X * size.Y * size.Z)
		end
		resolvedOpts.targetCount = math.max(1, math.round(u.density * totalVol / 1000))
	else
		resolvedOpts.targetCount = DEFAULT_TARGET_COUNT
	end

	-- Partial colorWeights tables fill unset keys from the default.
	-- Using ~= nil (not `or`) so an explicit zero is honoured —
	-- `{ red = 0 }` means "no red", not "default red".
	local cw = u.colorWeights or {}
	resolvedOpts.colorWeights = {
		red = if cw.red ~= nil then cw.red else DEFAULT_COLOR_WEIGHT,
		green = if cw.green ~= nil then cw.green else DEFAULT_COLOR_WEIGHT,
		blue = if cw.blue ~= nil then cw.blue else DEFAULT_COLOR_WEIGHT,
	}

	resolvedOpts.parent = u.parent or workspace
	resolvedOpts.minSpacing = u.minSpacing or 0
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

local BlockSpawner = {}

BlockSpawner.LETTER_FREQUENCIES = LETTER_FREQUENCIES

function BlockSpawner.start(userOpts: Opts?)
	if running then
		log:warn("start() called while already running — no-op")
		return
	end

	active = {}
	activeCount = 0

	applyOpts(userOpts)
	buildLetterTable()
	buildBoxTable()

	-- Hook consumption BEFORE the initial fill so any destroys
	-- triggered mid-fill (rare, but a rapid test could do it) still
	-- refill correctly.
	removedConnection = CollectionService:GetInstanceRemovedSignal(LetterBlocks.TAG):Connect(function(instance)
		local block = instance :: Model
		if active[block] then
			active[block] = nil
			activeCount -= 1
			if running then
				scheduleRefill()
			end
		end
	end)

	running = true
	maintainCount()
	log:info(string.format("started — spawned %d blocks", activeCount))
end

function BlockSpawner.stop()
	if not running then
		return
	end
	running = false
	if removedConnection then
		removedConnection:Disconnect()
		removedConnection = nil
	end
	log:info("stopped")
end

function BlockSpawner.rerollAll()
	log:info("rerollAll triggered")
	-- Snapshot the keys first because :Destroy() fires the removed
	-- signal synchronously and mutates `active` mid-iteration.
	local snapshot: { Model } = {}
	for block in active do
		table.insert(snapshot, block)
	end
	for _, block in ipairs(snapshot) do
		block:Destroy()
	end
	-- The removed-signal handler has cleared `active` by now and
	-- queued a deferred refill per destroy. The first deferred to
	-- fire drains to target; the rest are no-ops.
end

function BlockSpawner.getActiveBlocks(): { Model }
	local out: { Model } = {}
	for block in active do
		table.insert(out, block)
	end
	return out
end

return BlockSpawner
