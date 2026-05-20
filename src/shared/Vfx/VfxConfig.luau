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

-- Tier-keyed emitter knobs. Pattern: T1 small/narrow → T3 wide/dense.
-- One shared profile per tier so red/green/blue cast bursts feel uniform
-- in *intensity* (the spell tier) and only differ in *hue* (the color).
local function castEmitter(template: string, palette: ColorPalette, profile: {
	emitCount: number,
	lifetime: NumberRange,
	sizePeak: number,
	speed: NumberRange,
	spreadDeg: number,
}): EmitterSpec
	return {
		template     = template,
		color        = palette,
		emitCount    = profile.emitCount,
		lifetime     = profile.lifetime,
		size         = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, profile.sizePeak * 0.65),
			NumberSequenceKeypoint.new(0.4, profile.sizePeak),
			NumberSequenceKeypoint.new(1.0, 0.0),
		}),
		speed        = profile.speed,
		spreadAngle  = Vector2.new(profile.spreadDeg, profile.spreadDeg),
		rotation     = NumberRange.new(-180, 180),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, 0.0),
			NumberSequenceKeypoint.new(1.0, 1.0),
		}),
	}
end

local TIER_PROFILES = {
	[1] = { template = "BurstSmall",  emitCount = 14, lifetime = NumberRange.new(0.20, 0.32), sizePeak = 0.55, speed = NumberRange.new(6, 10),   spreadDeg = 35, totalSec = 0.45, soundVol = 0.8, pitch = NumberRange.new(0.95, 1.10) },
	[2] = { template = "BurstMedium", emitCount = 30, lifetime = NumberRange.new(0.30, 0.55), sizePeak = 0.80, speed = NumberRange.new(10, 18),  spreadDeg = 50, totalSec = 0.60, soundVol = 1.0, pitch = NumberRange.new(0.90, 1.05) },
	[3] = { template = "BurstMedium", emitCount = 50, lifetime = NumberRange.new(0.40, 0.75), sizePeak = 1.10, speed = NumberRange.new(15, 25),  spreadDeg = 60, totalSec = 0.75, soundVol = 1.0, pitch = NumberRange.new(0.85, 1.00) },
	[4] = { template = "BurstMedium", emitCount = 36, lifetime = NumberRange.new(0.35, 0.60), sizePeak = 0.90, speed = NumberRange.new(12, 20),  spreadDeg = 45, totalSec = 0.65, soundVol = 1.0, pitch = NumberRange.new(0.88, 1.02) },
}

local function castEntry(palette: ColorPalette, tier: number): EffectSpec
	local p = TIER_PROFILES[tier]
	return {
		emitters = {
			castEmitter(p.template, palette, {
				emitCount = p.emitCount,
				lifetime  = p.lifetime,
				sizePeak  = p.sizePeak,
				speed     = p.speed,
				spreadDeg = p.spreadDeg,
			}),
		},
		sound            = { soundId = "rbxassetid://0", volume = p.soundVol, pitchRange = p.pitch },
		totalDurationSec = p.totalSec,
		anchor           = "casterStaffTip",
	}
end

VfxConfig.EFFECTS = {
	-- ── Cast bursts ────────────────────────────────────────────────────
	cast_red_t1   = castEntry(C.red,   1),
	cast_red_t2   = castEntry(C.red,   2),
	cast_red_t3   = castEntry(C.red,   3),
	cast_red_t4   = castEntry(C.red,   4),
	cast_green_t1 = castEntry(C.green, 1),
	cast_green_t2 = castEntry(C.green, 2),
	cast_green_t3 = castEntry(C.green, 3),
	cast_blue_t1  = castEntry(C.blue,  1),
	cast_blue_t2  = castEntry(C.blue,  2),
	cast_blue_t3  = castEntry(C.blue,  3),

	-- ── Impact bursts ──────────────────────────────────────────────────
	-- Red flavor; reused for any onImpact { kind = "damage" } entry.
	impact_damage = {
		emitters = {
			{
				template    = "ImpactBurst",
				color       = C.red,
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
		sound            = { soundId = "rbxassetid://0", volume = 0.75, pitchRange = NumberRange.new(0.95, 1.05) },
		totalDurationSec = 0.95,
		anchor           = "targetHumanoidRootPart",
	},

	-- Frost shatter on the moment of freeze. The persistent ice shards
	-- are handled by Vfx/StatusVisuals/FreezeVfx (welded geometry, not
	-- a burst) — this entry just adds the visible "hit" feedback.
	impact_freeze = {
		emitters = {
			{
				template    = "ImpactBurst",
				color       = C.blue,
				emitCount   = 18,
				lifetime    = NumberRange.new(0.35, 0.60),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.45),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(8, 14),
				spreadAngle = Vector2.new(180, 180),
			},
		},
		sound            = { soundId = "rbxassetid://0", volume = 0.85, pitchRange = NumberRange.new(0.90, 1.05) },
		totalDurationSec = 0.70,
		anchor           = "targetHumanoidRootPart",
	},

	-- Ward shimmer when a Shield / Sanctuary lands on a target.
	impact_shield = {
		emitters = {
			{
				template    = "ImpactBurst",
				color       = C.blue,
				emitCount   = 16,
				lifetime    = NumberRange.new(0.5, 0.85),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.3),
					NumberSequenceKeypoint.new(0.4, 0.6),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(2, 5),
				spreadAngle = Vector2.new(180, 180),
			},
		},
		sound            = { soundId = "rbxassetid://0", volume = 0.7, pitchRange = NumberRange.new(0.95, 1.05) },
		totalDurationSec = 0.90,
		anchor           = "targetHumanoidRootPart",
	},

	-- Stubs for effect kinds whose gameplay handlers are also stubs.
	-- Authored so the resolver doesn't no-op the day those effects ship.
	impact_knockup = {
		emitters = {
			{
				template    = "ImpactBurst",
				color       = C.red,
				emitCount   = 12,
				lifetime    = NumberRange.new(0.25, 0.40),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.4),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(12, 22),
				spreadAngle = Vector2.new(60, 60),
			},
		},
		totalDurationSec = 0.50,
		anchor           = "targetHumanoidRootPart",
	},

	impact_wall = {
		emitters = {
			{
				template    = "ImpactBurst",
				color       = C.green,
				emitCount   = 14,
				lifetime    = NumberRange.new(0.30, 0.55),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.5),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(6, 12),
				spreadAngle = Vector2.new(180, 180),
			},
		},
		totalDurationSec = 0.65,
		anchor           = "worldPosition",
	},

	impact_buff = {
		emitters = {
			{
				template    = "HealBurst",
				color       = C.green,
				emitCount   = 14,
				lifetime    = NumberRange.new(0.4, 0.8),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.3),
					NumberSequenceKeypoint.new(0.4, 0.5),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(3, 8),
				spreadAngle = Vector2.new(160, 160),
			},
		},
		totalDurationSec = 0.85,
		anchor           = "targetHumanoidRootPart",
	},

	-- ── Delivery cosmetics ─────────────────────────────────────────────
	-- Attached to the moving projectile Part by SkillDelivery.projectile
	-- when deliveryParams.cosmeticEffectId is set. `durationSec` matches
	-- Volley's lifetimeSec so the trail emits for the whole flight.
	projectile_red_t4 = {
		emitters = {
			{
				template    = "BurstSmall",
				color       = C.red,
				durationSec = 3.0,
				lifetime    = NumberRange.new(0.15, 0.30),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.40),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(0, 2),
				spreadAngle = Vector2.new(20, 20),
			},
		},
		totalDurationSec = 3.2,
		anchor           = "worldPosition",
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
