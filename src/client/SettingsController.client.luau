--!strict

----------------------------------------------------------------------
-- SettingsController
----------------------------------------------------------------------
-- Makes two settings *do* something on this client:
--
--   * SFX volume — one `SoundGroup` under SoundService, its `Volume` the
--     stored setting, and every `Sound` on this client routed into it.
--     Routing is a scan plus `DescendantAdded` on SoundService and the
--     workspace, adopting any Sound that has no group yet: the HUD's
--     fizzle sounds, `spawnEffect`'s per-cast sounds, and Sounds the
--     server authored on replicated parts all arrive that way. A Sound's
--     `SoundGroup` property therefore has one writer.
--
--   * Letter palette — `Colors.setPalette` from the stored setting, and a
--     repaint of every LetterBlock already in the world when it changes.
--     Blocks are painted by the server at spawn in the default palette;
--     the client overwrites the colours locally (property writes do not
--     replicate upward), and paints any block that arrives later while a
--     non-default palette is active. Buffer tiles and the spell menu
--     repaint themselves off `Colors.paletteChanged`.
--
-- Reduced effects needs no controller: `spawnEffect` and `ScreenImpact`
-- read the flag at the moment they draw.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Colors = require(ReplicatedStorage.Shared.Core.Colors)
local LetterBlocks = require(ReplicatedStorage.Shared.LetterBlocks)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local Settings = require(ReplicatedStorage.Shared.Settings)

local log = Logger.new("SettingsController")

local holder = Settings.localHolder()
local K = Settings.Keys

----------------------------------------------------------------------
-- SFX volume
----------------------------------------------------------------------

local SFX_GROUP_NAME = "Sfx"

local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = SFX_GROUP_NAME
sfxGroup.Volume = Settings.volumeToGain(Settings.read(holder, K.SfxVolume))
sfxGroup.Parent = SoundService

local function adopt(instance: Instance)
	if instance:IsA("Sound") and instance.SoundGroup == nil then
		instance.SoundGroup = sfxGroup
	end
end

local function adoptAll(root: Instance)
	for _, descendant in root:GetDescendants() do
		adopt(descendant)
	end
	root.DescendantAdded:Connect(adopt)
end

adoptAll(SoundService)
adoptAll(workspace)

Settings.changed(holder, K.SfxVolume):Connect(function()
	local volume = Settings.read(holder, K.SfxVolume)
	sfxGroup.Volume = Settings.volumeToGain(volume)
	log:info(string.format("sfx volume -> %d", volume))
end)

----------------------------------------------------------------------
-- Letter palette
----------------------------------------------------------------------

local function repaintBlock(block: Instance)
	if block:IsA("Model") and block:IsDescendantOf(workspace) then
		LetterBlocks.applyVisualState(block)
	end
end

local function repaintAllBlocks()
	local count = 0
	for _, block in CollectionService:GetTagged(LetterBlocks.TAG) do
		repaintBlock(block)
		count += 1
	end
	return count
end

Colors.setPalette(Settings.read(holder, K.Palette))

Settings.changed(holder, K.Palette):Connect(function()
	Colors.setPalette(Settings.read(holder, K.Palette))
end)

Colors.paletteChanged:Connect(function(name: string)
	local count = repaintAllBlocks()
	log:info(string.format("palette -> %s (%d block(s) repainted)", name, count))
end)

-- A block that arrives while a non-default palette is active was painted
-- by the server in the default one. Deferred so its face GUIs have
-- replicated with it.
CollectionService:GetInstanceAddedSignal(LetterBlocks.TAG):Connect(function(block: Instance)
	if Colors.getPalette() == Colors.Palette.Default then
		return
	end
	task.defer(repaintBlock, block)
end)

if Colors.getPalette() ~= Colors.Palette.Default then
	repaintAllBlocks()
end

log:info(string.format("ready — sfx group %.2f, palette %s", sfxGroup.Volume, Colors.getPalette()))
