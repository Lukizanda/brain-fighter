--!strict

----------------------------------------------------------------------
-- FreezeVfxController
----------------------------------------------------------------------
-- Raises and drops the ice shards on every frozen rig, driven purely by
-- the `_frozen` character attribute.
--
-- The binding — which rigs, both exits, the first read for a late joiner
-- — is CharacterAttributeWatcher's; read its header for why a replicated
-- attribute beats a broadcast for a *persistent* status. All that is left
-- here is the handler pair.
--
-- Why it exists at all: `SkillEffects.handlers.freeze` runs on both VMs,
-- and used to call `FreezeVfx.start` directly. A player-cast freeze
-- therefore built shards twice — once on the server, replicating down,
-- and once locally on the caster — welded to the same limbs. Moving the
-- drawing here leaves exactly one owner.
--
-- Watches tagged rigs as well as players: freeze is aimed at the boss
-- more often than at anything else.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterAttributeWatcher = require(ReplicatedStorage.Shared.Vfx.CharacterAttributeWatcher)
local FreezeVfx      = require(ReplicatedStorage.Shared.Vfx.StatusVisuals.FreezeVfx)
local Logger         = require(ReplicatedStorage.Shared.Core.Logger)
local SkillConstants = require(ReplicatedStorage.Shared.Skills.SkillConstants)

local log = Logger.new("FreezeVfxController")

local FROZEN_ATTRIBUTE = SkillConstants.FROZEN_ATTRIBUTE

-- Shards grow from zero rather than from a remaining duration: this VM is
-- told *that* a rig is frozen, never for how long. The server owns the
-- thaw and clears the flag when it happens.
local SHARD_ELAPSED_SEC = 0

local watcher = CharacterAttributeWatcher.new({
	label              = "FreezeVfxController",
	attributes         = { FROZEN_ATTRIBUTE },
	includeTaggedRigs  = true,
	includeLocalPlayer = true,

	handlers = {
		-- Level-triggered, unlike Inferno's: shards appearing is the whole
		-- effect, there is no one-shot layer that must not replay, so the
		-- first read and a change are handled identically.
		onRefresh = function(rig: Model, humanoid: Humanoid, _initial: boolean)
			if rig:GetAttribute(FROZEN_ATTRIBUTE) == true then
				FreezeVfx.start(humanoid, SHARD_ELAPSED_SEC)
			else
				FreezeVfx.stop(humanoid)
			end
		end,

		-- The shards are parented to workspace and welded to limbs, so they
		-- outlive their rig unless something takes them off it.
		onDetach = function(_rig: Model, humanoid: Humanoid)
			FreezeVfx.stop(humanoid)
		end,

		onDied = function(_rig: Model, humanoid: Humanoid)
			FreezeVfx.stop(humanoid)
		end,
	},
})

watcher:enable()

-- Rojo replaces this script on every sync. Without this, each replacement
-- strands the previous copy's connections and leaves its welded shards in
-- the world with nothing left that knows how to remove them.
script.Destroying:Connect(function()
	watcher:destroy()
end)

log:info("ready")
