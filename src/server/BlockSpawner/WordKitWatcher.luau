--!strict

----------------------------------------------------------------------
-- WordKitWatcher
----------------------------------------------------------------------
-- Tells the spawn pools when a word kit has to be replaced. Two things do
-- that, and this module owns both, because it is the layer that reads the
-- scene (the pool knows nothing about walls or rounds, and BreakableWalls
-- knows nothing about spawn pools; see wiki/design/boss-arena.md § Word
-- kits):
--
--   Gate re-seal. A `BreakableWall` part with a `GateId` attribute publishes
--   its state as `WallState` (BreakableWallConstants.Published.State). When a
--   wall goes from "broken" back to "intact" this asks the pool of the wall's
--   arena to re-roll every kit whose `KitGate` equals that GateId.
--
--   Round start. BreakableWallService returns every wall of an arena to
--   intact on that arena's RoundStarted, but a wall that was intact all along
--   publishes no change, so a kit half-eaten last round would carry into the
--   next. So this also re-rolls every kit of the pool whose arena just started
--   a round, whatever its gate. (A broken wall that the round start resets
--   also trips the gate path; both rolls land within a frame, the second
--   replaces the first, and the player sees one fresh kit.)
--
-- Matching is per arena: a wall's arena (Arena.idOf, so no ArenaId means
-- Default) selects the pool, so two arenas can reuse a GateId without
-- re-rolling each other's kits.
--
-- It reads only the published `WallState` and the `GateId` attribute; it
-- writes nothing on a wall.
--
-- Lifecycle follows the project idiom: `disable()` is a reversible pause
-- (connections dropped; `start()` picks up again), `destroy()` is the
-- permanent teardown.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local BlockSpawner = require(ReplicatedStorage.Shared.BlockSpawner)
local BreakableWallConstants = require(ReplicatedStorage.Shared.Arena.BreakableWallConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("WordKitWatcher")

-- The wall-side half of the word-kit contract: a BreakableWall part names
-- itself with this attribute and a kit volume's `KitGate` refers to it. The
-- walls system owns the name (it reads it for gate hold zones too).
local GATE_ID_ATTRIBUTE = BreakableWallConstants.Authored.GateId

local WALL_STATE_ATTRIBUTE = BreakableWallConstants.Published.State
local STATE_BROKEN = BreakableWallConstants.State.Broken
local STATE_INTACT = BreakableWallConstants.State.Intact

local roundStartedEvent = ServerScriptService.Server.GameMode.Events.RoundStarted :: BindableEvent

type Pools = { [string]: BlockSpawner.BlockSpawner }

type WallWatch = {
	connection: RBXScriptConnection,
	lastState: any,
}

local WordKitWatcher = {}
WordKitWatcher.__index = WordKitWatcher

WordKitWatcher.GATE_ID_ATTRIBUTE = GATE_ID_ATTRIBUTE

export type WordKitWatcher = typeof(setmetatable(
	{} :: {
		-- Pools by arena id. Held by reference: a pool added to the table
		-- later is picked up without telling the watcher.
		_pools: Pools,
		_watches: { [Instance]: WallWatch },
		_connections: { RBXScriptConnection },
		_running: boolean,
		_destroyed: boolean,
	},
	WordKitWatcher
))

function WordKitWatcher.new(pools: Pools): WordKitWatcher
	return setmetatable({
		_pools = pools,
		_watches = {},
		_connections = {},
		_running = false,
		_destroyed = false,
	}, WordKitWatcher)
end

-- A wall's state changed. Only broken -> intact is a re-seal.
function WordKitWatcher._onWallState(self: WordKitWatcher, wall: Instance, watch: WallWatch)
	local previous = watch.lastState
	local current = wall:GetAttribute(WALL_STATE_ATTRIBUTE)
	watch.lastState = current
	if previous ~= STATE_BROKEN or current ~= STATE_INTACT then
		return
	end

	local gate = wall:GetAttribute(GATE_ID_ATTRIBUTE)
	if type(gate) ~= "string" or gate == "" then
		return
	end
	local arenaId = Arena.idOf(wall)
	local pool = self._pools[arenaId]
	if pool == nil then
		return
	end
	local rolled = pool:rerollKitsForGate(gate)
	if rolled > 0 then
		log:info(string.format(
			"[%s] gate '%s' re-sealed (%s) — %d kit(s) re-rolled", arenaId, gate, wall:GetFullName(), rolled
		))
	end
end

function WordKitWatcher._watchWall(self: WordKitWatcher, instance: Instance)
	if not instance:IsA("BasePart") or self._watches[instance] then
		return
	end
	local watch: WallWatch = {
		-- Replaced just below; the handler needs the table it lives in.
		connection = (nil :: any) :: RBXScriptConnection,
		lastState = instance:GetAttribute(WALL_STATE_ATTRIBUTE),
	}
	watch.connection = instance:GetAttributeChangedSignal(WALL_STATE_ATTRIBUTE):Connect(function()
		self:_onWallState(instance, watch)
	end)
	self._watches[instance] = watch
end

function WordKitWatcher._unwatchWall(self: WordKitWatcher, instance: Instance)
	local watch = self._watches[instance]
	if watch then
		watch.connection:Disconnect()
		self._watches[instance] = nil
	end
end

function WordKitWatcher._onRoundStarted(self: WordKitWatcher, _roster: any, arenaId: any)
	if type(arenaId) ~= "string" then
		return
	end
	local pool = self._pools[arenaId]
	if pool == nil then
		return
	end
	local rolled = pool:rerollKits()
	if rolled > 0 then
		log:info(string.format("[%s] round started — %d kit(s) re-rolled", arenaId, rolled))
	end
end

function WordKitWatcher.start(self: WordKitWatcher)
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
	log:info(string.format("watching %d wall(s) and round starts", self:wallCount()))
end

function WordKitWatcher.wallCount(self: WordKitWatcher): number
	local count = 0
	for _ in self._watches do
		count += 1
	end
	return count
end

-- Reversible pause: stop listening. start() resumes.
function WordKitWatcher.disable(self: WordKitWatcher)
	if not self._running then
		return
	end
	self._running = false
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	for _, watch in self._watches do
		watch.connection:Disconnect()
	end
	table.clear(self._watches)
end

function WordKitWatcher.destroy(self: WordKitWatcher)
	if self._destroyed then
		return
	end
	self:disable()
	self._destroyed = true
end

return WordKitWatcher
