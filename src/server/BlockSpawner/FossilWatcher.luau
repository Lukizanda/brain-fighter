--!strict

----------------------------------------------------------------------
-- FossilWatcher
----------------------------------------------------------------------
-- Fossil letters (Phase 8 stage 8, wiki/design/boss-arena.md § Fossil
-- letters). A `BreakableWall` part with a `FossilTable` attribute hides one
-- letter rolled from that letter table. This module owns the roll, the two
-- attributes it publishes, and the block that is freed when the wall breaks.
-- It is a sibling of WordKitWatcher, not the same module: the kit watcher
-- reacts per pool (re-roll kits on a re-seal or a round start), this one per
-- wall (roll a letter, free a block on a break). They share only the shape
-- (read the published `WallState` and RoundStarted, call pool methods), and
-- each starts only when its feature is in the place.
--
--   Roll. On start, on every RoundStarted of the wall's arena, and when
--   `FossilTable` or `RegenSec` is edited, the wall's fossil is (re)decided:
--   a valid table and no regeneration -> one letter and colour rolled by the
--   wall's arena pool, published as `FossilLetter` / `FossilColor`; an
--   unknown table, or `RegenSec > 0` (it would pay out on every break), warns
--   ONCE naming the part and holds nothing; no `FossilTable` holds nothing.
--   A wall whose arena has no pool in this watcher is not touched at all.
--
--   Break. `WallState` going to "broken" frees the held letter: one timed
--   block of that letter and colour (pool:spawnTimedBlock) at the wall's
--   centre, FossilConstants.HEIGHT_ABOVE_BASE_STUDS above its base, removed
--   after the lifetime. A wall pays once per roll, so once per round.
--
--   Round start. Whatever fossil blocks the arena's pool still holds are
--   removed, then every fossil wall of the arena is re-rolled.
--
-- Reads only the published `WallState` and the authored attributes; writes
-- `FossilLetter` / `FossilColor` (its own) on the wall and nothing else of
-- BreakableWalls'. The pool knows nothing about walls.
--
-- Lifecycle follows the project idiom: `disable()` is a reversible pause
-- (connections dropped; `start()` picks up again), `destroy()` is the
-- permanent teardown (and removes the fossil blocks it freed).
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)
local BreakableWallConstants = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local FossilConstants = require(ReplicatedStorage.Shared.BlockSpawner.FossilConstants)
local LetterTables = require(ReplicatedStorage.Shared.BlockSpawner.LetterTables)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("FossilWatcher")

local WALL_STATE_ATTRIBUTE = BreakableWallConstants.Published.State
local REGEN_ATTRIBUTE = BreakableWallConstants.Authored.RegenSec
local STATE_BROKEN = BreakableWallConstants.State.Broken
local HALF = 0.5

local roundStartedEvent = ServerScriptService.Server.GameMode.Events.RoundStarted :: BindableEvent

type Pools = { [string]: BlockSpawner.BlockSpawner }

export type Opts = {
	-- Seconds a freed letter floats; tests shorten it.
	lifetimeSec: number?,
}

type WallWatch = {
	wall: BasePart,
	connections: { RBXScriptConnection },
	lastState: any,
	-- The roll the wall currently holds; nil when it holds nothing.
	letter: string?,
	color: string?,
	-- A wall pays out once per roll.
	paid: boolean,
	-- Why the wall holds nothing, so each cause warns once, not on every
	-- evaluation. Cleared when the wall becomes valid again.
	warnedCause: string?,
	block: Model?,
}

local FossilWatcher = {}
FossilWatcher.__index = FossilWatcher

export type FossilWatcher = typeof(setmetatable(
	{} :: {
		-- Pools by arena id. Held by reference: a pool added later is picked
		-- up without telling the watcher.
		_pools: Pools,
		_lifetimeSec: number,
		_watches: { [Instance]: WallWatch },
		_connections: { RBXScriptConnection },
		_running: boolean,
		_destroyed: boolean,
	},
	FossilWatcher
))

function FossilWatcher.new(pools: Pools, opts: Opts?): FossilWatcher
	local o: Opts = opts or {}
	return setmetatable({
		_pools = pools,
		_lifetimeSec = if o.lifetimeSec ~= nil then o.lifetimeSec else FossilConstants.LIFETIME_SEC,
		_watches = {},
		_connections = {},
		_running = false,
		_destroyed = false,
	}, FossilWatcher)
end

-- True when the place has at least one wall that asks for a fossil: the
-- service starts the watcher only then.
function FossilWatcher.isNeeded(): boolean
	for _, instance in ipairs(CollectionService:GetTagged(BreakableWallConstants.TAG)) do
		if instance:GetAttribute(FossilConstants.TABLE_ATTRIBUTE) ~= nil then
			return true
		end
	end
	return false
end

local function clearPublished(wall: BasePart)
	wall:SetAttribute(FossilConstants.LETTER_ATTRIBUTE, nil)
	wall:SetAttribute(FossilConstants.COLOR_ATTRIBUTE, nil)
end

-- Warns once per cause, naming the part.
local function warnOnce(watch: WallWatch, cause: string, message: string)
	if watch.warnedCause == cause then
		return
	end
	watch.warnedCause = cause
	log:warn(string.format("%s: %s — no fossil", watch.wall:GetFullName(), message))
end

-- Decides what the wall holds. `forceRoll` re-rolls even if it already holds
-- a valid roll (a new round).
function FossilWatcher._evaluate(self: FossilWatcher, watch: WallWatch, forceRoll: boolean)
	local wall = watch.wall
	local tableName = wall:GetAttribute(FossilConstants.TABLE_ATTRIBUTE)

	local function holdNothing()
		watch.letter = nil
		watch.color = nil
		clearPublished(wall)
	end

	-- A wall in an arena this watcher has no pool for is not its wall: leave
	-- it alone entirely, published attributes included. Another watcher may
	-- own it (the game's and a test's run side by side), and clearing here
	-- would wipe that watcher's letter.
	local pool = self._pools[Arena.idOf(wall)]
	if pool == nil then
		watch.letter = nil
		watch.color = nil
		return
	end

	if tableName == nil then
		watch.warnedCause = nil
		holdNothing()
		return
	end
	if type(tableName) ~= "string" or not LetterTables.isValid(tableName) then
		warnOnce(watch, "table", string.format(
			"%s '%s' is not a letter table (valid: %s)",
			FossilConstants.TABLE_ATTRIBUTE, tostring(tableName), table.concat(LetterTables.names(), ", ")
		))
		holdNothing()
		return
	end
	local regen = wall:GetAttribute(REGEN_ATTRIBUTE)
	if type(regen) == "number" and regen > 0 then
		warnOnce(watch, "regen", string.format(
			"%s with %s %s: a regenerating wall would pay out on every break, so it cannot hold a fossil",
			FossilConstants.TABLE_ATTRIBUTE, REGEN_ATTRIBUTE, tostring(regen)
		))
		holdNothing()
		return
	end
	watch.warnedCause = nil

	if watch.letter ~= nil and not forceRoll then
		return
	end
	local letter, color = pool:rollLetter(tableName)
	watch.letter = letter
	watch.color = color
	watch.paid = false
	-- Letter first: a client woken by the colour reads a letter that matches.
	wall:SetAttribute(FossilConstants.LETTER_ATTRIBUTE, letter)
	wall:SetAttribute(FossilConstants.COLOR_ATTRIBUTE, color)
end

-- The wall's state changed. Only a transition INTO broken frees the letter.
function FossilWatcher._onWallState(self: FossilWatcher, watch: WallWatch)
	local previous = watch.lastState
	local current = watch.wall:GetAttribute(WALL_STATE_ATTRIBUTE)
	watch.lastState = current
	if current ~= STATE_BROKEN or previous == STATE_BROKEN then
		return
	end
	local letter, color = watch.letter, watch.color
	if letter == nil or color == nil or watch.paid then
		return
	end
	local wall = watch.wall
	local pool = self._pools[Arena.idOf(wall)]
	if pool == nil then
		return
	end

	watch.paid = true
	local base = wall.Position - Vector3.new(0, wall.Size.Y * HALF, 0)
	local position = base + Vector3.new(0, FossilConstants.HEIGHT_ABOVE_BASE_STUDS, 0)
	local block = pool:spawnTimedBlock(letter, color, CFrame.new(position), self._lifetimeSec)
	if block == nil then
		return
	end
	block:SetAttribute(FossilConstants.EXPIRES_ATTRIBUTE, workspace:GetServerTimeNow() + self._lifetimeSec)
	watch.block = block
	log:info(string.format(
		"[%s] %s broke — fossil '%s' (%s) freed for %.0fs",
		Arena.idOf(wall), wall:GetFullName(), letter, color, self._lifetimeSec
	))
end

function FossilWatcher._watchWall(self: FossilWatcher, instance: Instance)
	if not instance:IsA("BasePart") or self._watches[instance] then
		return
	end
	local watch: WallWatch = {
		wall = instance,
		connections = {},
		lastState = instance:GetAttribute(WALL_STATE_ATTRIBUTE),
		letter = nil,
		color = nil,
		paid = false,
		warnedCause = nil,
		block = nil,
	}
	table.insert(watch.connections, instance:GetAttributeChangedSignal(WALL_STATE_ATTRIBUTE):Connect(function()
		self:_onWallState(watch)
	end))
	-- A designer (or a test) editing the authoring attributes live re-decides.
	for _, attribute in { FossilConstants.TABLE_ATTRIBUTE, REGEN_ATTRIBUTE } do
		table.insert(watch.connections, instance:GetAttributeChangedSignal(attribute):Connect(function()
			self:_evaluate(watch, false)
		end))
	end
	self._watches[instance] = watch
	self:_evaluate(watch, false)
end

function FossilWatcher._unwatchWall(self: FossilWatcher, instance: Instance)
	local watch = self._watches[instance]
	if watch then
		for _, connection in watch.connections do
			connection:Disconnect()
		end
		self._watches[instance] = nil
	end
end

function FossilWatcher._onRoundStarted(self: FossilWatcher, _roster: any, arenaId: any)
	if type(arenaId) ~= "string" then
		return
	end
	local pool = self._pools[arenaId]
	if pool ~= nil then
		pool:clearTimedBlocks()
	end
	local rolled = 0
	for _, watch in self._watches do
		if Arena.idOf(watch.wall) == arenaId then
			watch.block = nil
			self:_evaluate(watch, true)
			if watch.letter ~= nil then
				rolled += 1
			end
		end
	end
	if rolled > 0 then
		log:info(string.format("[%s] round started — %d fossil(s) rolled", arenaId, rolled))
	end
end

function FossilWatcher.start(self: FossilWatcher)
	if self._running or self._destroyed then
		return
	end
	self._running = true

	-- Listen for new walls first, then take the existing ones, so a wall
	-- tagged between the two is not missed.
	table.insert(self._connections, CollectionService:GetInstanceAddedSignal(BreakableWallConstants.TAG):Connect(function(instance)
		self:_watchWall(instance)
	end))
	table.insert(self._connections, CollectionService:GetInstanceRemovedSignal(BreakableWallConstants.TAG):Connect(function(instance)
		self:_unwatchWall(instance)
	end))
	table.insert(self._connections, roundStartedEvent.Event:Connect(function(roster: any, arenaId: any)
		self:_onRoundStarted(roster, arenaId)
	end))
	for _, instance in ipairs(CollectionService:GetTagged(BreakableWallConstants.TAG)) do
		self:_watchWall(instance)
	end
	log:info(string.format("watching %d wall(s), %d holding a fossil", self:wallCount(), self:fossilCount()))
end

function FossilWatcher.wallCount(self: FossilWatcher): number
	local count = 0
	for _ in self._watches do
		count += 1
	end
	return count
end

-- Walls currently holding a rolled letter.
function FossilWatcher.fossilCount(self: FossilWatcher): number
	local count = 0
	for _, watch in self._watches do
		if watch.letter ~= nil then
			count += 1
		end
	end
	return count
end

-- Reversible pause: stop listening. Walls keep what they published and any
-- freed block keeps its own timer. start() resumes (and re-reads walls).
function FossilWatcher.disable(self: FossilWatcher)
	if not self._running then
		return
	end
	self._running = false
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	for _, watch in self._watches do
		for _, connection in watch.connections do
			connection:Disconnect()
		end
	end
	table.clear(self._watches)
end

-- Permanent teardown: stop, and remove the fossil blocks this watcher freed.
function FossilWatcher.destroy(self: FossilWatcher)
	if self._destroyed then
		return
	end
	for _, watch in self._watches do
		-- Only walls this watcher published on; see _evaluate.
		if watch.letter ~= nil then
			clearPublished(watch.wall)
		end
		if watch.block ~= nil and watch.block.Parent ~= nil then
			watch.block:Destroy()
		end
	end
	self:disable()
	self._destroyed = true
end

return FossilWatcher
