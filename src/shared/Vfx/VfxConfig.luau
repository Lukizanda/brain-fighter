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
	upward: boolean?,
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

----------------------------------------------------------------------
-- SFX
----------------------------------------------------------------------
-- Every entry below is a verified-loading asset (checked in Studio via
-- ContentProvider:PreloadAsync — IsLoaded true, TimeLength > 0), but
-- these are INTERIM placeholders, not final art. The project owns no
-- purpose-made spell SFX: the universe inventory is the LaserTag
-- template's gun sounds, and Creator Store audio search returns ripped
-- music and meme clips rather than a usable library. So each spell is
-- mapped to the closest-fitting sound that exists and loads.
--
-- Swapping in a real pack should be a one-line change per entry — that
-- is the whole reason these are named constants here instead of literals
-- buried in the EFFECTS table.
--
-- `UNSET` is honoured by spawnEffect, which skips playback rather than
-- spamming "Unable to load sound" once per cast. Use it for anything
-- that has no defensible stand-in yet.
local UNSET = "rbxassetid://0"

-- Public so UI code that plays spell feedback outside the EFFECTS table
-- (the cast-fizzle buzzer in SpellMenuGui / GameplayHudGui) resolves its
-- id from the same place, instead of keeping its own literal.
VfxConfig.SFX = {
	-- Universe-owned, 0.24 s. Reads as a staff whoosh at every tier; the
	-- tier profiles differentiate it by volume and pitch instead.
	cast = "rbxassetid://134677020800886",

	-- Universe-owned, 0.58 s. A dry percussive hit — generic enough to
	-- carry a spell impact.
	impactDamage = "rbxassetid://131133470069125",

	-- Creator Store, 2.53 s. Genuinely an explosion; the closest thing to
	-- a T3 nuke the library offers.
	impactHeavy = "rbxassetid://9892906940",

	-- Creator Store, 2.01 s. A bright pickup chime, which is the usual
	-- shorthand for "you were healed".
	impactHeal = "rbxassetid://4612374036",

	-- Universe-owned, 0.39 s. Sharper and shorter than impactDamage, so
	-- it passes for a freeze crack. Weakest match in the table.
	impactFreeze = "rbxassetid://88987851128257",

	-- Universe-owned, 0.40 s. A mechanical latch — reads as a ward
	-- snapping into place.
	impactShield = "rbxassetid://17682723174",

	-- Cast fizzle (not enough mana / no target in range). Deliberately the
	-- same swoosh as `cast`, and played pitched-down by the callers: a
	-- deflated version of the cast sound is the clearest way to say "that
	-- cast didn't happen" without a dedicated buzzer asset.
	fizzle = "rbxassetid://134677020800886",
}

local SFX = VfxConfig.SFX

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
		sound            = { soundId = SFX.cast, volume = p.soundVol, pitchRange = p.pitch },
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
	cast_blue_t1  = castEntry(C.blue,  1),
	cast_blue_t2  = castEntry(C.blue,  2),
	cast_blue_t3  = castEntry(C.blue,  3),
	-- Green was missing entirely until 2026-08-03: resolveCastId built
	-- "cast_green_tN", found no entry, and VfxController silently skipped
	-- the burst — so Mend, Stone Wall and Sanctuary cast with no muzzle
	-- effect and no sound at all. Green has only three tiers (no T4).
	cast_green_t1 = castEntry(C.green, 1),
	cast_green_t2 = castEntry(C.green, 2),
	cast_green_t3 = castEntry(C.green, 3),

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
		sound            = { soundId = SFX.impactDamage, volume = 0.85, pitchRange = NumberRange.new(0.92, 1.08) },
		totalDurationSec = 0.65,
		anchor           = "targetHumanoidRootPart",
	},

	-- Inferno (red T3) — the only *instant* damage spell, and at 50% of
	-- max HP the biggest single hit a player has. It used to fall through
	-- to the shared `impact_damage` burst above, so the game's heaviest
	-- nuke landed with exactly the same 22-particle pop as a T1 Firebolt.
	--
	-- Resolved by resolveImpactId's tier lookup: "impact_damage_t3" wins
	-- over "impact_damage" when the caster is T3. An eruption rather than
	-- a splash — slower, taller particles thrown upward off the target,
	-- with the explosion SFX instead of the dry percussive hit.
	impact_damage_t3 = {
		emitters = {
			{
				template    = "ImpactBurst",
				color       = C.red,
				emitCount   = 60,
				lifetime    = NumberRange.new(0.55, 1.10),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.9),
					NumberSequenceKeypoint.new(0.3, 1.6),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(18, 34),
				-- Narrower than the 180-degree splash so the column reads
				-- as rising out of the target rather than spraying past it.
				spreadAngle = Vector2.new(70, 70),
				rotation    = NumberRange.new(-180, 180),
			},
			-- Second, slower layer of embers that outlives the initial
			-- flash and gives the eruption a falling tail.
			{
				template    = "BurstMedium",
				color       = C.red,
				emitCount   = 26,
				lifetime    = NumberRange.new(0.9, 1.6),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.5),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(4, 12),
				spreadAngle = Vector2.new(120, 120),
			},
		},
		sound            = { soundId = SFX.impactHeavy, volume = 1.0, pitchRange = NumberRange.new(0.88, 1.0) },
		totalDurationSec = 1.8,
		upward           = true,
		anchor           = "targetHumanoidRootPart",
	},

	-- Fireball (red T2) — sits between the T1 pop and the T3 eruption.
	-- Reached through the registry's explicit impactEffectId rather than
	-- the tier lookup, because projectile spells fire their own impact
	-- burst from SkillDelivery at the real hit position.
	impact_damage_t2 = {
		emitters = {
			{
				template    = "ImpactBurst",
				color       = C.red,
				emitCount   = 38,
				lifetime    = NumberRange.new(0.40, 0.75),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.7),
					NumberSequenceKeypoint.new(0.35, 1.0),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(14, 26),
				spreadAngle = Vector2.new(180, 180),
				rotation    = NumberRange.new(-180, 180),
			},
		},
		sound            = { soundId = SFX.impactDamage, volume = 1.0, pitchRange = NumberRange.new(0.82, 0.94) },
		totalDurationSec = 0.90,
		anchor           = "targetHumanoidRootPart",
	},

	impact_heal = {
		emitters = {
			{
				template    = "HealBurst",
				color       = C.green,
				durationSec = 1.8,
				rate        = 12,
				lifetime    = NumberRange.new(1.2, 1.8),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0,  0.0),
					NumberSequenceKeypoint.new(0.15, 0.35),
					NumberSequenceKeypoint.new(1.0,  0.0),
				}),
				speed       = NumberRange.new(1, 3),
				spreadAngle = Vector2.new(22, 22),
				rotation    = NumberRange.new(-180, 180),
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.2),
					NumberSequenceKeypoint.new(0.5, 0.0),
					NumberSequenceKeypoint.new(1.0, 1.0),
				}),
			},
		},
		sound            = { soundId = SFX.impactHeal, volume = 0.75, pitchRange = NumberRange.new(0.95, 1.05) },
		totalDurationSec = 2.3,
		upward           = true,
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
		sound            = { soundId = SFX.impactFreeze, volume = 0.85, pitchRange = NumberRange.new(0.90, 1.05) },
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
		sound            = { soundId = SFX.impactShield, volume = 0.7, pitchRange = NumberRange.new(0.95, 1.05) },
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
		-- Still genuinely unmapped: no owned or findable asset reads as a
		-- launch. spawnEffect skips UNSET rather than erroring, and knockup
		-- has no gameplay handler yet either.
		sound            = { soundId = UNSET },
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
		-- Pitched down hard so the percussive hit lands as stone settling
		-- rather than as a weapon strike.
		sound            = { soundId = SFX.impactDamage, volume = 0.9, pitchRange = NumberRange.new(0.55, 0.68) },
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
		sound            = { soundId = SFX.impactShield, volume = 0.8, pitchRange = NumberRange.new(1.10, 1.25) },
		totalDurationSec = 0.85,
		anchor           = "targetHumanoidRootPart",
	},

	-- ── Delivery cosmetics ─────────────────────────────────────────────
	-- Attached to the moving projectile Part by SkillDelivery.projectile
	-- when deliveryParams.cosmeticEffectId is set. `durationSec` matches
	-- each spell's lifetimeSec so the trail emits for the whole flight.

	-- Firebolt (T1) — small, fast, low-rate trail.
	projectile_red_t1 = {
		emitters = {
			{
				template    = "BurstSmall",
				color       = C.red,
				durationSec = 1.5,           -- matches FIREBOLT_LIFETIME_SEC
				lifetime    = NumberRange.new(0.08, 0.18),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.22),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(0, 1),
				spreadAngle = Vector2.new(12, 12),
			},
		},
		totalDurationSec = 1.7,
		anchor           = "worldPosition",
	},

	-- Fireball (T2) — denser, larger, longer-lived trail.
	projectile_red_t2 = {
		emitters = {
			{
				template    = "BurstSmall",
				color       = C.red,
				durationSec = 2.0,           -- matches FIREBALL_LIFETIME_SEC
				lifetime    = NumberRange.new(0.20, 0.40),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.55),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(0, 2),
				spreadAngle = Vector2.new(18, 18),
			},
		},
		totalDurationSec = 2.2,
		anchor           = "worldPosition",
	},

	-- Volley (T4) — existing, longer-lived trail for the staggered stream.
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

-- Impact effects are keyed by effect kind, optionally refined by tier.
-- A tiered entry ("impact_damage_t3") wins when one is authored for the
-- casting tier; otherwise the shared per-kind entry is used.
--
-- Opt-in by design: most kinds read fine at every tier and only need one
-- entry, so authoring a tiered variant is how you say "this tier should
-- land differently" — currently just Inferno's T3 eruption. Callers that
-- have no tier in hand can keep omitting the argument.
function VfxConfig.resolveImpactId(effectKind: string, tier: number?): string
	local base = "impact_" .. effectKind
	if tier then
		local tiered = base .. "_t" .. tier
		if VfxConfig.EFFECTS[tiered] then return tiered end
	end
	return base
end

return VfxConfig
