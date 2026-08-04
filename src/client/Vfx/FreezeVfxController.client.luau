--!strict

----------------------------------------------------------------------
-- FreezeVfxController
----------------------------------------------------------------------
-- Raises and drops the ice shards on every frozen rig, driven purely by
-- the `_frozen` character attribute.
--
-- Sibling of ShieldVfxController, and attribute-driven for the same
-- reason: replication does the multiplayer work. The server writes the
-- flag on a replicated character Model, so every client's copy of this
-- script sees every frozen rig without a broadcast RemoteEvent, and a
-- player who joins mid-fight sees an already-frozen boss because the
-- value is simply there when they arrive.
--
-- Why it exists at all: `SkillEffects.handlers.freeze` runs on both VMs,
-- and used to call `FreezeVfx.start` directly. A player-cast freeze
-- therefore built shards twice — once on the server, replicating down,
-- and once locally on the caster — welded to the same limbs. Moving the
-- drawing here leaves exactly one owner.
--
-- Watches more than ShieldVfxController does. A shield only ever sits on
-- a player, but freeze is aimed at the boss more often than at anything
-- else, so this binds player characters *and* every rig carrying one of
-- SkillConstants.DAMAGEABLE_TAGS.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FreezeVfx      = require(ReplicatedStorage.Shared.Vfx.StatusVisuals.FreezeVfx)
local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)

local log = Logger.new("FreezeVfxController")

local FROZEN_ATTRIBUTE = SkillConstants.FROZEN_ATTRIBUTE

-- One entry per rig being watched, holding its connections and the
-- Humanoid the shards are keyed by. The Humanoid is cached because
-- teardown routinely runs after the rig has already been torn down,
-- when `FindFirstChildOfClass` would return nil and the shards — which
-- are parented to workspace, not to the rig — would be stranded there.
type Watch = { conns: { RBXScriptConnection }, humanoid: Humanoid }
local _watched: { [Model]: Watch } = {}

local function isFrozen(character: Model): boolean
	return character:GetAttribute(FROZEN_ATTRIBUTE) == true
end

local function unwatch(character: Model)
	local entry = _watched[character]
	if not entry then return end
	_watched[character] = nil
	for _, conn in entry.conns do
		conn:Disconnect()
	end
	FreezeVfx.stop(entry.humanoid)
end

local function watch(character: Model)
	-- Idempotent: a rig can carry several of the damageable tags, and the
	-- boss additionally arrives through its own tag signal.
	if _watched[character] then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local conns: { RBXScriptConnection } = {}
	_watched[character] = { conns = conns, humanoid = humanoid }

	local function refresh()
		if isFrozen(character) then
			FreezeVfx.start(humanoid, 0)
		else
			FreezeVfx.stop(humanoid)
		end
	end

	table.insert(conns, character:GetAttributeChangedSignal(FROZEN_ATTRIBUTE):Connect(refresh))

	-- The shards are parented to workspace and welded to limbs, so they
	-- outlive their rig unless something destroys them. A rig that dies
	-- normally has its flag cleared by `purgeFreeze`, but one destroyed
	-- outright — a despawned NPC, a boss cycling out — never fires that
	-- change. Both exits are covered here.
	table.insert(conns, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			unwatch(character)
		end
	end))

	table.insert(conns, humanoid.Died:Connect(function()
		FreezeVfx.stop(humanoid)
	end))

	-- A late joiner's first sight of an already-frozen rig arrives as an
	-- initial attribute value, not as a change signal.
	refresh()
end

----------------------------------------------------------------------
-- Binding
----------------------------------------------------------------------

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(watch)
	player.CharacterRemoving:Connect(unwatch)
	if player.Character then
		watch(player.Character)
	end
end

for _, player in Players:GetPlayers() do
	bindPlayer(player)
end
Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player: Player)
	if player.Character then
		unwatch(player.Character)
	end
end)

for _, tag in SkillConstants.DAMAGEABLE_TAGS do
	for _, rig in CollectionService:GetTagged(tag) do
		if rig:IsA("Model") then
			watch(rig :: Model)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(rig: Instance)
		if not rig:IsA("Model") then return end
		-- A rig is routinely tagged before its Humanoid is parented, in
		-- which case `watch` bails and this rig would never be picked up.
		-- Retry once the Humanoid shows up.
		local model = rig :: Model
		if model:FindFirstChildOfClass("Humanoid") then
			watch(model)
			return
		end
		local conn: RBXScriptConnection
		conn = model.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Humanoid") then
				conn:Disconnect()
				watch(model)
			end
		end)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(rig: Instance)
		if rig:IsA("Model") then
			unwatch(rig :: Model)
		end
	end)
end

log:info("ready")
