--!strict

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
-- The player's client-side preferences: the keys, their defaults, the
-- rule that makes any stored value legal, and the one place that reads
-- and writes them.
--
-- Values live as `Settings_*` attributes on a holder Instance — the
-- LocalPlayer in the game (`Settings.localHolder()`), any Instance in a
-- test. Attributes because every consumer (a sound router, a VFX
-- spawner, a palette painter, the panel itself) can read the current
-- value the moment it asks and subscribe to changes with no module in
-- between; a client-side attribute write on the LocalPlayer does not
-- replicate to the server, which is correct today — nothing server-side
-- cares what volume a player runs at — and is what Phase 5.5 persistence
-- will read back from a remote when settings start to follow the player.
--
-- This module is pure: no LocalPlayer at module scope, no SoundService,
-- no palette switching. What a setting *does* belongs to the system it
-- tunes (`SettingsController`, `spawnEffect`, `Colors`). See
-- wiki/systems/Settings.md.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Colors = require(ReplicatedStorage.Shared.Core.Colors)

local Settings = {}

-- Attribute names. Prefixed so they sort together in the Properties
-- panel and cannot collide with the session attributes (`ArenaId`,
-- `PlayerState`) the server writes on the same Instance.
Settings.Keys = {
	-- 0–100, integer. Master volume for every sound effect.
	SfxVolume = "Settings_SfxVolume",
	-- true = skip screen shake / tint / flash and thin particle bursts.
	ReducedVfx = "Settings_ReducedVfx",
	-- A `Colors.Palette` name: which colours the letter blocks, buffer
	-- tiles and spell menu are drawn with.
	Palette = "Settings_Palette",
}

Settings.SFX_VOLUME_MIN = 0
Settings.SFX_VOLUME_MAX = 100
-- The slider snaps to this so "80" is reachable by dragging and reads as
-- a round number rather than 79.
Settings.SFX_VOLUME_STEP = 5

local DEFAULTS: { [string]: any } = {
	[Settings.Keys.SfxVolume] = 80,
	[Settings.Keys.ReducedVfx] = false,
	[Settings.Keys.Palette] = Colors.Palette.Default,
}
Settings.DEFAULTS = DEFAULTS

-- Every key, in the order the panel lists them.
local ORDERED_KEYS: { string } = {
	Settings.Keys.SfxVolume,
	Settings.Keys.ReducedVfx,
	Settings.Keys.Palette,
}
Settings.ORDERED_KEYS = ORDERED_KEYS

local function snap(value: number, step: number): number
	return math.round(value / step) * step
end

-- The legal value nearest to `value` for `key`, or the default when
-- `value` is not the right shape at all. Applied on every read *and*
-- write, so a stale or hand-edited attribute can never leak an illegal
-- value into a consumer.
function Settings.normalize(key: string, value: any): any
	local default = DEFAULTS[key]
	assert(default ~= nil, "Settings.normalize: unknown key " .. tostring(key))

	if key == Settings.Keys.SfxVolume then
		if type(value) ~= "number" or value ~= value then
			return default
		end
		local clamped = math.clamp(value, Settings.SFX_VOLUME_MIN, Settings.SFX_VOLUME_MAX)
		return snap(clamped, Settings.SFX_VOLUME_STEP)
	elseif key == Settings.Keys.ReducedVfx then
		if type(value) ~= "boolean" then
			return default
		end
		return value
	elseif key == Settings.Keys.Palette then
		if not Colors.isPalette(value) then
			return default
		end
		return value
	end
	return default
end

-- Current value of `key` on `holder`, normalized; the default when unset.
function Settings.read(holder: Instance, key: string): any
	return Settings.normalize(key, holder:GetAttribute(key))
end

-- Store `value` for `key` on `holder`, normalized. Returns what was
-- actually stored. Writing the value already stored is a no-op that
-- fires no attribute-changed signal — Roblox does that for us.
function Settings.write(holder: Instance, key: string, value: any): any
	local normalized = Settings.normalize(key, value)
	holder:SetAttribute(key, normalized)
	return normalized
end

-- Fires after `key` changes on `holder`. Read the new value with `read`.
function Settings.changed(holder: Instance, key: string): RBXScriptSignal
	assert(DEFAULTS[key] ~= nil, "Settings.changed: unknown key " .. tostring(key))
	return holder:GetAttributeChangedSignal(key)
end

-- Where the live game keeps them: the local player. Client only — the
-- server has no player of its own to hold preferences for.
function Settings.localHolder(): Instance
	assert(RunService:IsClient(), "Settings.localHolder is client-only")
	local player = Players.LocalPlayer
	assert(player, "Settings.localHolder: no LocalPlayer")
	return player
end

-- Whether the holder exists on this VM at all — `spawnEffect` and
-- `ScreenImpact` are shared modules that run on the client but are
-- required on the server too, and want a cheap "is there anyone whose
-- settings apply?" rather than an assert.
function Settings.localHolderIfAny(): Instance?
	if not RunService:IsClient() then
		return nil
	end
	return Players.LocalPlayer
end

-- 0–100 → the 0–1 gain a SoundGroup takes.
function Settings.volumeToGain(volume: number): number
	return volume / Settings.SFX_VOLUME_MAX
end

return Settings
