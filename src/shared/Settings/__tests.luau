--!strict

----------------------------------------------------------------------
-- Settings smoke tests
----------------------------------------------------------------------
-- Self-contained — exposes `M.run()` which throws on any assertion
-- failure.
--
--   require(ReplicatedStorage.Shared.Settings.__tests).run()
--
-- Covers: defaults on an empty holder, clamp + snap on the volume,
-- garbage → default for every key, write returns what it stored, the
-- changed signal fires once per real change and not on a no-op write,
-- and the palette round-trip through Colors (tint switches, unknown
-- palette refused, default restored so later tests see the shipped
-- look). Uses a Folder as the holder — the module is holder-agnostic.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.Core.Colors)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Settings = require(script.Parent)

local log = Logger.new("Settings.tests")

local K = Settings.Keys

local function runTests(): boolean
	local holder = Instance.new("Folder")
	holder.Name = "SettingsTestHolder"

	-- Defaults on an empty holder.
	assert(Settings.read(holder, K.SfxVolume) == Settings.DEFAULTS[K.SfxVolume], "empty holder: volume default")
	assert(Settings.read(holder, K.ReducedVfx) == false, "empty holder: reduced VFX default false")
	assert(Settings.read(holder, K.Palette) == Colors.Palette.Default, "empty holder: palette default")

	-- Volume: clamp, snap, garbage.
	assert(Settings.normalize(K.SfxVolume, 150) == Settings.SFX_VOLUME_MAX, "volume clamps high")
	assert(Settings.normalize(K.SfxVolume, -5) == Settings.SFX_VOLUME_MIN, "volume clamps low")
	assert(Settings.normalize(K.SfxVolume, 42) == 40, "volume snaps to the step (42 → 40)")
	assert(Settings.normalize(K.SfxVolume, 43) == 45, "volume snaps to the step (43 → 45)")
	assert(Settings.normalize(K.SfxVolume, "loud") == Settings.DEFAULTS[K.SfxVolume], "volume: string → default")
	assert(Settings.normalize(K.SfxVolume, 0 / 0) == Settings.DEFAULTS[K.SfxVolume], "volume: NaN → default")
	assert(Settings.volumeToGain(Settings.SFX_VOLUME_MAX) == 1, "max volume is unity gain")
	assert(Settings.volumeToGain(0) == 0, "zero volume is silence")

	-- Reduced VFX: only booleans.
	assert(Settings.normalize(K.ReducedVfx, true) == true, "reduced: true kept")
	assert(Settings.normalize(K.ReducedVfx, 1) == false, "reduced: number → default")
	assert(Settings.normalize(K.ReducedVfx, "yes") == false, "reduced: string → default")

	-- Palette: only known names.
	assert(Settings.normalize(K.Palette, Colors.Palette.HighContrast) == Colors.Palette.HighContrast, "palette: known kept")
	assert(Settings.normalize(K.Palette, "neon") == Colors.Palette.Default, "palette: unknown → default")
	assert(Settings.normalize(K.Palette, 7) == Colors.Palette.Default, "palette: number → default")

	-- Write stores the normalized value and returns it.
	local stored = Settings.write(holder, K.SfxVolume, 999)
	assert(stored == Settings.SFX_VOLUME_MAX, "write returns the stored (clamped) value")
	assert(holder:GetAttribute(K.SfxVolume) == Settings.SFX_VOLUME_MAX, "write lands on the attribute")
	assert(Settings.read(holder, K.SfxVolume) == Settings.SFX_VOLUME_MAX, "read sees the write")

	-- A hand-edited illegal attribute is normalized on read.
	holder:SetAttribute(K.Palette, "neon")
	assert(Settings.read(holder, K.Palette) == Colors.Palette.Default, "illegal attribute reads as default")

	-- Changed fires once per real change, not on a no-op write.
	local fires = 0
	local connection = Settings.changed(holder, K.ReducedVfx):Connect(function()
		fires += 1
	end)
	Settings.write(holder, K.ReducedVfx, true)
	Settings.write(holder, K.ReducedVfx, true) -- same value: Roblox does not fire
	Settings.write(holder, K.ReducedVfx, false)
	task.wait() -- attribute-changed signals are deferred
	connection:Disconnect()
	assert(fires == 2, "changed fired " .. fires .. " times, expected 2")

	-- Unknown key is a programming error, not a silent default.
	local okUnknown = pcall(Settings.normalize, "Settings_Nope", 1)
	assert(okUnknown == false, "unknown key should assert")

	-- Colors palette round-trip.
	local before = Colors.getPalette()
	assert(before == Colors.Palette.Default, "tests expect the default palette active")
	local defaultRed = Colors.tint("red")
	local switched = 0
	local paletteConnection = Colors.paletteChanged:Connect(function()
		switched += 1
	end)
	assert(Colors.setPalette("neon") == false, "unknown palette refused")
	assert(Colors.getPalette() == before, "unknown palette left the active one alone")
	assert(Colors.setPalette(Colors.Palette.HighContrast) == true, "known palette accepted")
	assert(Colors.tint("red") ~= defaultRed, "tint changed with the palette")
	assert(Colors.tint("wild") == Colors.PALETTES[Colors.Palette.HighContrast].wild, "wild tint from the new palette")
	assert(Colors.tint("nope") == Colors.tint("red"), "unknown colour falls back to red")
	assert(Colors.setPalette(Colors.Palette.HighContrast) == true, "re-setting the same palette is a no-op success")
	assert(Colors.setPalette(Colors.Palette.Default) == true, "restore default")
	task.wait()
	paletteConnection:Disconnect()
	assert(switched == 2, "paletteChanged fired " .. switched .. " times, expected 2")
	assert(Colors.tint("red") == defaultRed, "default tint restored")

	holder:Destroy()
	return true
end

local M = {}

function M.run(): boolean
	local ok, err = pcall(runTests)
	if not ok then
		log:warn("FAILED: " .. tostring(err))
		error(err)
	end
	log:info("all tests passed")
	return true
end

return M
