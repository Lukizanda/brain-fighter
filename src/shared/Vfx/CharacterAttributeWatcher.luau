--!strict

----------------------------------------------------------------------
-- CharacterAttributeWatcher
----------------------------------------------------------------------
-- "Call me for every rig in sight, and again whenever these attributes
-- change on it." The binding half of every attribute-driven status
-- visual, extracted from the four client controllers that each had their
-- own copy of it (refactor chunk 10, audit F45).
--
-- Why the status visuals are attribute-driven at all is worth keeping in
-- one place, because it is the reason this module is shaped the way it is:
-- the character Model is server-owned and replicated, so a server write to
-- `_frozen` reaches every client with no fan-out RemoteEvent, and a player
-- who joins mid-fight sees an already-frozen boss because the value is
-- simply *there* when they arrive. Nothing has to be replayed for them.
-- That is a property no broadcast lane can give you, which is why these
-- four visuals do not use WorldVfxEvent.
--
-- What the four copies all had, and what therefore lives here:
--
--   * a rig table keyed by Model, so a rig carrying several damageable
--     tags is watched once;
--   * the Humanoid cached at attach time, because teardown routinely runs
--     *after* the rig has been destroyed, when `FindFirstChildOfClass`
--     answers nil and geometry parented to workspace rather than to the
--     rig would be stranded there forever;
--   * both exits covered — `Humanoid.Died` and `AncestryChanged` — since a
--     rig killed normally has its status flags cleared by the purge hooks,
--     while one destroyed outright (a despawned NPC, a boss cycling out)
--     never fires an attribute change at all;
--   * an `initial` refresh on attach, because a late joiner's first sight
--     of an already-burning rig arrives as a value, not as a change
--     signal. Handlers that punch the screen need to tell that apart from
--     a status that just landed, so the flag is passed through;
--   * the tagged-rig retry: a rig is routinely tagged *before* its
--     Humanoid is parented, and a watcher that gave up at that moment
--     would never pick it up.
--
-- `disable()` is the reversible half — it detaches every rig and drops
-- every connection, and `enable()` rebuilds from the world as it is then,
-- not from what it was. `destroy()` is disable plus "never again".
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)

-- The one Skills require the Vfx layer keeps, and the reason this module
-- exists on this side of the line: the tag list is the definition of "a
-- rig statuses can land on", and it belongs to the Skills layer. Every
-- other gameplay fact a status visual needs is passed in by its caller.
local DAMAGEABLE_TAGS = SkillConstants.DAMAGEABLE_TAGS

-- What the watcher calls, and what a controller supplies. `onRefresh` is
-- the only required one: it is handed the rig, its Humanoid and whether
-- this is the first read of the attributes rather than a change to them.
export type Handlers = {
	onRefresh: (rig: Model, humanoid: Humanoid, initial: boolean) -> (),
	-- The rig is leaving: respawn, disconnect, death-and-despawn, or the
	-- watcher being disabled. Always paired with a preceding attach.
	onDetach: (rig: Model, humanoid: Humanoid) -> (),
	-- Optional, and not a substitute for `onDetach` — a dead rig is still
	-- in the world and still watched. Exists for visuals that must come off
	-- a corpse without waiting for it to be cleaned up.
	onDied: ((rig: Model, humanoid: Humanoid) -> ())?,
}

export type Config = {
	-- Names this watcher in its logs. The owning controller's name.
	label: string,
	-- Every attribute whose change should trigger a refresh. A refresh is
	-- handed no indication of *which* one fired: a status is a state, and
	-- the handlers all read the state back.
	attributes: { string },
	-- Watch NPC, boss and dummy rigs as well as player characters. False
	-- for a status only players can carry — see each controller's header
	-- for which, and why.
	includeTaggedRigs: boolean,
	-- Watch the local player's own character. False for a visual whose
	-- local copy is drawn by the prediction layer on the input frame, where
	-- a second writer would fight it with round-trip-late values.
	includeLocalPlayer: boolean,
	handlers: Handlers,
}

type Watch = {
	conns: { RBXScriptConnection },
	humanoid: Humanoid,
}

local CharacterAttributeWatcher = {}
CharacterAttributeWatcher.__index = CharacterAttributeWatcher

export type Watcher = typeof(setmetatable({} :: {
	_config: Config,
	_log: Logger.Logger,
	_enabled: boolean,
	_destroyed: boolean,
	_watched: { [Model]: Watch },
	-- Player and tag signals, plus the per-player character signals. All
	-- dropped together on disable.
	_bindings: { RBXScriptConnection },
	-- Rigs tagged but not yet carrying a Humanoid, each holding the
	-- ChildAdded connection waiting for one. Tracked so a disable during
	-- that window does not leave a connection that attaches to a disabled
	-- watcher later.
	_pending: { [Model]: RBXScriptConnection },
}, CharacterAttributeWatcher))

function CharacterAttributeWatcher.new(config: Config): Watcher
	local self = setmetatable({}, CharacterAttributeWatcher)
	self._config    = config
	self._log       = Logger.new(config.label)
	self._enabled   = false
	self._destroyed = false
	self._watched   = {}
	self._bindings  = {}
	self._pending   = {}
	return self
end

----------------------------------------------------------------------
-- Per-rig attach / detach
----------------------------------------------------------------------

function CharacterAttributeWatcher:_detach(rig: Model)
	local entry = self._watched[rig]
	if not entry then return end
	self._watched[rig] = nil
	for _, conn in entry.conns do
		conn:Disconnect()
	end
	self._config.handlers.onDetach(rig, entry.humanoid)
end

function CharacterAttributeWatcher:_attach(rig: Model)
	if self._destroyed or not self._enabled then return end
	-- Idempotent: a rig can carry several of the damageable tags, and a
	-- player's character arrives through both the player signal and, if it
	-- is tagged, the tag signal.
	if self._watched[rig] then return end

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local handlers = self._config.handlers
	local conns: { RBXScriptConnection } = {}
	self._watched[rig] = { conns = conns, humanoid = humanoid }

	for _, attribute in self._config.attributes do
		table.insert(conns, rig:GetAttributeChangedSignal(attribute):Connect(function()
			-- Guarded because a detach and an attribute write can land in
			-- the same frame, in either order.
			if self._watched[rig] then
				handlers.onRefresh(rig, humanoid, false)
			end
		end))
	end

	table.insert(conns, rig.AncestryChanged:Connect(function()
		if not rig:IsDescendantOf(workspace) then
			self:_detach(rig)
		end
	end))

	local onDied = handlers.onDied
	if onDied then
		table.insert(conns, humanoid.Died:Connect(function()
			onDied(rig, humanoid)
		end))
	end

	handlers.onRefresh(rig, humanoid, true)
end

----------------------------------------------------------------------
-- Binding
----------------------------------------------------------------------

function CharacterAttributeWatcher:_bindPlayer(player: Player)
	if not self._config.includeLocalPlayer and player == Players.LocalPlayer then return end

	table.insert(self._bindings, player.CharacterAdded:Connect(function(character: Model)
		self:_attach(character)
	end))
	table.insert(self._bindings, player.CharacterRemoving:Connect(function(character: Model)
		self:_detach(character)
	end))

	if player.Character then
		self:_attach(player.Character)
	end
end

function CharacterAttributeWatcher:_bindTag(tag: string)
	for _, rig in CollectionService:GetTagged(tag) do
		if rig:IsA("Model") then
			self:_attach(rig :: Model)
		end
	end

	table.insert(self._bindings, CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
		if not instance:IsA("Model") then return end
		local rig = instance :: Model
		if rig:FindFirstChildOfClass("Humanoid") then
			self:_attach(rig)
			return
		end
		-- Tagged before its Humanoid was parented. Wait for one rather than
		-- dropping the rig; see the header.
		if self._pending[rig] then return end
		local conn: RBXScriptConnection
		conn = rig.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Humanoid") then
				conn:Disconnect()
				self._pending[rig] = nil
				self:_attach(rig)
			end
		end)
		self._pending[rig] = conn
	end))

	table.insert(self._bindings, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		if not instance:IsA("Model") then return end
		local rig = instance :: Model
		local pending = self._pending[rig]
		if pending then
			pending:Disconnect()
			self._pending[rig] = nil
		end
		self:_detach(rig)
	end))
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

-- Binds the world as it is right now and starts watching. Safe to call on
-- an already-enabled watcher.
function CharacterAttributeWatcher:enable()
	if self._destroyed then
		self._log:warn("enable() on a destroyed watcher — ignored")
		return
	end
	if self._enabled then return end
	self._enabled = true

	for _, player in Players:GetPlayers() do
		self:_bindPlayer(player)
	end
	table.insert(self._bindings, Players.PlayerAdded:Connect(function(player: Player)
		self:_bindPlayer(player)
	end))
	table.insert(self._bindings, Players.PlayerRemoving:Connect(function(player: Player)
		if player.Character then
			self:_detach(player.Character)
		end
	end))

	if self._config.includeTaggedRigs then
		for _, tag in DAMAGEABLE_TAGS do
			self:_bindTag(tag)
		end
	end
end

-- Reversible teardown: every rig is detached — so the handlers get to take
-- their geometry off — and every connection dropped. `enable()` afterwards
-- rebuilds from the world as it is then.
function CharacterAttributeWatcher:disable()
	if not self._enabled then return end
	self._enabled = false

	for _, conn in self._bindings do
		conn:Disconnect()
	end
	table.clear(self._bindings)

	for rig, conn in self._pending do
		conn:Disconnect()
		self._pending[rig] = nil
	end

	-- Snapshotted because `_detach` mutates `_watched` as it goes.
	local rigs: { Model } = {}
	for rig in self._watched do
		table.insert(rigs, rig)
	end
	for _, rig in rigs do
		self:_detach(rig)
	end
end

-- Permanent: disable, then drop the state. A destroyed watcher refuses to
-- enable again rather than quietly half-working.
function CharacterAttributeWatcher:destroy()
	self:disable()
	self._destroyed = true
	table.clear(self._watched)
	table.clear(self._pending)
	table.clear(self._bindings)
end

-- Count of rigs currently attached. For the client-side verification
-- snippets and for logging — nothing in the drawing path reads it.
function CharacterAttributeWatcher:watchedCount(): number
	local count = 0
	for _ in self._watched do
		count += 1
	end
	return count
end

return CharacterAttributeWatcher
