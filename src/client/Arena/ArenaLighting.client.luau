--!strict

----------------------------------------------------------------------
-- ArenaLighting
----------------------------------------------------------------------
-- Gives an arena its own light. The Lighting service is one per place, so
-- the hub, the duel pads and the boss islands share it; this controller
-- cross-fades the local player's Lighting to the preset their arena asks
-- for while they are in it, and back to the place's own look when they
-- leave. Presets and the arena -> preset map: Shared/Arena/
-- ArenaLightingConstants. Design: wiki/design/boss-arena.md § Lighting.
--
-- Ownership. On this client this controller is the only writer of:
--   * every Lighting property a preset names,
--   * the properties a preset names on the place's Atmosphere and
--     BloomEffect (the first of each class under Lighting),
--   * the ColorCorrectionEffect it creates (`GRADE_NAME`).
-- ScreenImpact's post-processing instances are its own and untouched.
-- Server code never writes Lighting.
--
-- The hub look is not a preset: it is whatever the place file holds,
-- recorded here at start, so editing the lobby's lighting in Studio needs
-- no code change.
--
-- Which preset: the Player's `PlayerState` / `ArenaId` attributes
-- (written by GameModeService, see Shared/GameMode/Arena). In an arena,
-- `ARENA_PRESET[arenaId]` wins; otherwise the arena's `ArenaSlot` part
-- names its `Mode`, and `MODE_PRESET[mode]` picks. Slots can stream in
-- after the attributes change, so a slot appearing re-resolves.
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)
local ArenaLightingConstants = require(ReplicatedStorage.Shared.Arena.ArenaLightingConstants)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("ArenaLighting")

local C = ArenaLightingConstants
local player = Players.LocalPlayer

type Props = { [string]: any }

-- One thing this controller writes, and the values it puts back in the hub.
type Target = {
	instance: Instance,
	baseline: Props,
	tween: Tween?,
}

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = C.GRADE_NAME
for key, value in C.GRADE_NEUTRAL do
	(grade :: any)[key] = value
end
grade.Parent = Lighting

-- Every key any preset names, per group, so the baseline covers whatever a
-- preset might change.
local function keysOf(group: string): { string }
	local seen: { [string]: boolean } = {}
	local keys = {}
	for _, preset in C.Preset do
		local props = (preset :: any)[group] :: Props?
		if props then
			for key in props do
				if not seen[key] then
					seen[key] = true
					table.insert(keys, key)
				end
			end
		end
	end
	return keys
end

local function record(instance: Instance, keys: { string }): Target
	local baseline: Props = {}
	for _, key in keys do
		baseline[key] = (instance :: any)[key]
	end
	return { instance = instance, baseline = baseline, tween = nil }
end

local targets: { [string]: Target } = {
	lighting = record(Lighting, keysOf("lighting")),
	grade = { instance = grade, baseline = table.clone(C.GRADE_NEUTRAL), tween = nil },
}
if atmosphere then
	targets.atmosphere = record(atmosphere, keysOf("atmosphere"))
end
if bloom then
	targets.bloom = record(bloom, keysOf("bloom"))
end

local function fadeTo(target: Target, props: Props, seconds: number)
	if target.tween then
		target.tween:Cancel()
		target.tween = nil
	end
	if seconds <= 0 then
		for key, value in props do
			(target.instance :: any)[key] = value
		end
		return
	end
	local tween = TweenService:Create(
		target.instance,
		TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		props
	)
	target.tween = tween
	tween:Play()
end

-- What each group should hold under `preset`: the preset's value where it
-- names one, the baseline everywhere else (so switching between two
-- presets never leaves one's leftovers behind).
local function resolveGroup(target: Target, presetProps: Props?): Props
	local props = table.clone(target.baseline)
	if presetProps then
		for key, value in presetProps do
			props[key] = value
		end
	end
	return props
end

local function presetFor(arenaId: string): string?
	local byArena = C.ARENA_PRESET[arenaId]
	if byArena then
		return byArena
	end
	for _, slot in CollectionService:GetTagged(Arena.SLOT_TAG) do
		if Arena.idOf(slot) == arenaId then
			local mode = slot:GetAttribute(Arena.MODE_ATTRIBUTE)
			return if type(mode) == "string" then C.MODE_PRESET[mode] else nil
		end
	end
	return nil
end

local applied: string? = nil -- "" = the hub look

local function apply(seconds: number)
	local state = player:GetAttribute(Arena.STATE_ATTRIBUTE)
	local wanted: string? = nil
	if state == Arena.PlayerState.InArena then
		wanted = presetFor(Arena.idOf(player))
	end
	local key = wanted or ""
	if key == applied then
		return
	end

	local preset: ArenaLightingConstants.Preset? = if wanted then C.Preset[wanted] else nil
	if wanted and not preset then
		log:warn("arena asks for unknown preset", wanted, "- keeping the hub look")
		key = ""
	end
	applied = key

	for group, target in targets do
		local presetProps = if preset then (preset :: any)[group] :: Props? else nil
		fadeTo(target, resolveGroup(target, presetProps), seconds)
	end
	log:info("lighting ->", if key == "" then "hub" else key)
end

-- First paint is instant: a player who joins straight into an arena
-- should not watch the sky change.
apply(0)

player:GetAttributeChangedSignal(Arena.STATE_ATTRIBUTE):Connect(function()
	apply(C.FADE_SEC)
end)
player:GetAttributeChangedSignal(Arena.ID_ATTRIBUTE):Connect(function()
	apply(C.FADE_SEC)
end)
CollectionService:GetInstanceAddedSignal(Arena.SLOT_TAG):Connect(function()
	apply(C.FADE_SEC)
end)
