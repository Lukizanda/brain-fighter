--!strict
----------------------------------------------------------------------
-- VfxConfig
----------------------------------------------------------------------
-- Shared VFX configuration: per-color palettes, effect specs, and
-- performance guardrails. Populated across multiple phases:
--   Phase A — COLORS + PERF table (this file)
--   Phase C — EFFECTS entries (cast/impact per tier and kind)
----------------------------------------------------------------------

export type ColorPalette = {
	primary: Color3,
	glow: Color3,
	accent: Color3,
}

export type EmitterSpec = {
	template: string,
	color: ColorPalette?,
	rate: number?,
	lifetime: NumberRange?,
	size: NumberSequence?,
	speed: NumberRange?,
	spreadAngle: Vector2?,
	rotation: NumberRange?,
	transparency: NumberSequence?,
	emitCount: number?,
	durationSec: number?,
}

export type BeamSpec = {
	template: string,
	color: ColorPalette?,
	lifetimeSec: number,
	width0: number?,
	width1: number?,
	segments: number?,
}

export type SoundSpec = {
	soundId: string,
	volume: number?,
	pitchRange: NumberRange?,
}

export type EffectSpec = {
	emitters: { EmitterSpec }?,
	beam: BeamSpec?,
	light: { color: Color3, brightness: number, durationSec: number }?,
	sound: SoundSpec?,
	totalDurationSec: number,
	anchor: "casterStaffTip" | "targetRoot" | "targetHumanoidRootPart" | "targetHead" | "worldPosition",
	durationFromSpec: boolean?,
}

export type PerfConfig = {
	maxEmitters: number,
	maxBeams: number,
	maxLights: number,
	maxVfxInstances: number,
	maxBlockPops: number,
	allowLights: boolean,
	reducedFpsCap: number,
	restoredFpsCap: number,
	fpsMeasureDurSec: number,
}

local VfxConfig = {}

VfxConfig.COLORS = {
	red   = { primary = Color3.fromHex("#FF3030"), glow = Color3.fromHex("#FF8080"), accent = Color3.fromHex("#FFB060") },
	green = { primary = Color3.fromHex("#30FF60"), glow = Color3.fromHex("#80FFB0"), accent = Color3.fromHex("#FFFFFF") },
	blue  = { primary = Color3.fromHex("#3080FF"), glow = Color3.fromHex("#80C0FF"), accent = Color3.fromHex("#80FFFF") },
}

local C = VfxConfig.COLORS

VfxConfig.EFFECTS = {
	cast_red_t1 = {
		emitters = {
			{
				template     = "BurstSmall",
				color        = C.red,
				emitCount    = 14,
				lifetime     = NumberRange.new(0.20, 0.32),
				size         = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.35),
					NumberSequenceKeypoint.new(0.4, 0.55),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed        = NumberRange.new(6, 10),
				spreadAngle  = Vector2.new(35, 35),
				rotation     = NumberRange.new(-180, 180),
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.0),
					NumberSequenceKeypoint.new(1.0, 1.0),
				}),
			},
		},
		sound            = { soundId = "rbxassetid://0", volume = 0.8, pitchRange = NumberRange.new(0.95, 1.10) },
		totalDurationSec = 0.45,
		anchor           = "casterStaffTip",
	},

	cast_red_t2 = {
		emitters = {
			{
				template     = "BurstMedium",
				color        = C.red,
				emitCount    = 30,
				lifetime     = NumberRange.new(0.30, 0.55),
				size         = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.5),
					NumberSequenceKeypoint.new(0.4, 0.8),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed        = NumberRange.new(10, 18),
				spreadAngle  = Vector2.new(50, 50),
				rotation     = NumberRange.new(-180, 180),
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.0),
					NumberSequenceKeypoint.new(1.0, 1.0),
				}),
			},
		},
		sound            = { soundId = "rbxassetid://0", volume = 1.0, pitchRange = NumberRange.new(0.90, 1.05) },
		totalDurationSec = 0.60,
		anchor           = "casterStaffTip",
	},

	impact_damage = {
		emitters = {
			{
				template    = "ImpactBurst",
				emitCount   = 22,
				lifetime    = NumberRange.new(0.30, 0.55),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.5),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(10, 18),
				spreadAngle = Vector2.new(180, 180),
			},
		},
		sound            = { soundId = "rbxassetid://0", volume = 0.85, pitchRange = NumberRange.new(0.92, 1.08) },
		totalDurationSec = 0.65,
		anchor           = "targetHumanoidRootPart",
	},

	impact_heal = {
		emitters = {
			{
				template     = "HealBurst",
				color        = C.green,
				emitCount    = 20,
				lifetime     = NumberRange.new(0.5, 0.9),
				size         = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.0),
					NumberSequenceKeypoint.new(0.2, 0.5),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed        = NumberRange.new(4, 10),
				spreadAngle  = Vector2.new(160, 160),
				rotation     = NumberRange.new(-180, 180),
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.0),
					NumberSequenceKeypoint.new(0.7, 0.1),
					NumberSequenceKeypoint.new(1.0, 1.0),
				}),
			},
		},
		totalDurationSec = 0.95,
		anchor           = "targetHumanoidRootPart",
	},
}

VfxConfig.PERF = {
	maxEmitters      = 32,
	maxBeams         = 6,
	maxLights        = 2,
	maxVfxInstances  = 80,
	maxBlockPops     = 16,
	allowLights      = true,
	reducedFpsCap    = 45,
	restoredFpsCap   = 55,
	fpsMeasureDurSec = 2,
}

function VfxConfig.resolveCastId(color: string, tier: number): string
	return "cast_" .. color .. "_t" .. tier
end

function VfxConfig.resolveImpactId(effectKind: string): string
	return "impact_" .. effectKind
end

return VfxConfig
