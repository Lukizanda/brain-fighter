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
	-- Wins over `color` when both are set.
	--
	-- `color` collapses a palette to `ColorSequence.new(primary)` — one flat
	-- tint for the particle's whole life, which is all a solid-blob sprite
	-- needs. A flipbook flame needs the opposite: white-hot at birth,
	-- orange through the middle, deep red as it dies. That gradient is what
	-- makes the greyscale sheet read as fire rather than as an orange
	-- smudge, and it cannot be expressed as a palette.
	colorSequence: ColorSequence?,
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
	-- 3D attenuation. Roblox defaults (EmitterSize 10, Inverse rolloff)
	-- are tuned for effects that happen on top of you: at the boss's
	-- 100-stud attack range they scale a sound to roughly a tenth of its
	-- volume, which is what made boss fire inaudible from cover. Set both
	-- on anything that must carry across the arena.
	emitterSize: number?,
	rollOffMaxDistance: number?,
}

export type EffectSpec = {
	emitters: { EmitterSpec }?,
	beam: BeamSpec?,
	light: { color: Color3, brightness: number, durationSec: number }?,
	sound: SoundSpec?,
	totalDurationSec: number,
	-- Descriptive metadata: nothing reads this. `spawnEffect` takes its
	-- anchor from the caller, so this documents where an effect is *meant*
	-- to hang rather than deciding it. Kept honest anyway — it named
	-- `casterStaffTip` for a while after Phase 5.7 deleted the staff, and
	-- because no code path consumed it the stale name cost nothing and so
	-- went unnoticed. A field that cannot fail loudly has to be corrected
	-- deliberately.
	anchor: "caster" | "targetRoot" | "targetHumanoidRootPart" | "targetHead" | "worldPosition",
	durationFromSpec: boolean?,
	upward: boolean?,
}

----------------------------------------------------------------------
-- Projectile bodies
----------------------------------------------------------------------
-- The *solid* of a drawn shot — the Part CosmeticProjectile builds and
-- flies — as opposed to the particles spawnEffect hangs off it.
--
-- Kept in its own table (PROJECTILE_BODIES, below the EFFECTS list) and
-- keyed by the same `cosmeticEffectId`, rather than as a field on
-- EffectSpec. spawnEffect deals in emitters, sound and light and has no
-- business knowing a shot has a shape; a projectile-only field on the spec
-- every cast burst also uses would be dead weight on all of them. One id
-- still describes one complete look — the two tables are read with one key.
--
-- A shot with no entry here renders the way every shot did before
-- 2026-08-10: an axis-aligned neon cube. That fallback is what keeps this
-- optional for any future non-fire projectile.
export type ProjectileTrailSpec = {
	-- Distance between the two trail attachments — the ribbon's width where
	-- it leaves the shot. Deliberately independent of the part's size, so a
	-- thin bolt can still drag a streak wide enough to read at range.
	widthStuds: number,
	lifetimeSec: number,
	color: ColorSequence,
	transparency: NumberSequence,
}

export type ProjectileBodySpec = {
	-- "orb" is a plain sphere. "bolt" stretches that sphere along the
	-- direction of travel into a comet head.
	shape: "orb" | "bolt",
	-- Multiplier on the body's length along travel. Ignored for "orb".
	stretch: number?,
	-- Multiplier on the cross-section. Cosmetic only, and it has to stay
	-- that way: CosmeticProjectile measures shield contact against the
	-- *gameplay* size it was launched with, never the rendered one. A
	-- slimmed bolt that shrank the shell padding would start slipping
	-- through bubbles the server blocks it on.
	girth: number?,
	-- Replaces the shot's own colour on the solid core. Fire wants a
	-- white-hot centre with the spell's orange living in the flame and the
	-- trail around it; without this the core is one flat orange ball and the
	-- particles have nothing to be hotter than.
	coreColor: Color3?,
	trail: ProjectileTrailSpec?,
	-- Honours PERF.allowLights like every other light in this file. Worth
	-- setting only on shots that arrive one at a time — one light per shot
	-- means a 20-round boss volley puts 20 dynamic lights in the arena.
	light: { color: Color3, brightness: number, rangeStuds: number }?,
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
-- Fire
----------------------------------------------------------------------
-- Shared by the two lanes that draw Inferno's fire, so they can't drift
-- into looking like two different spells: the one-shot eruption
-- (`impact_damage_t3` below, via spawnEffect) and the lingering burn
-- (`StatusVisuals/InfernoVfx`, driven by the `_burning` attribute).
--
-- Deliberately NOT an entry in COLORS. That table is the *spell* palette
-- keyed by the three castable colours, and a fourth key would imply a
-- fourth castable colour — the same reasoning that keeps STONE_DUST out of
-- it further down.
--
-- These are ColorSequences rather than flat tints because the flipbook
-- sheet they drive (`FireFlame` / `FireSmoke` in ReplicatedStorage.
-- VfxTemplates) is greyscale. A flat orange over greyscale flame frames
-- reads as an orange smudge; a gradient that cools from white-hot through
-- orange to a dying red over the particle's life is what actually reads as
-- combustion. The emitters are additive (LightEmission 1, LightInfluence
-- 0), so these values are light being added, not surface colour — which is
-- why the early keypoints run brighter than a Color3 normally would.
VfxConfig.FIRE = {
	-- The body of the flame.
	flame = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 246, 200)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 176, 44)),
		ColorSequenceKeypoint.new(0.65, Color3.fromRGB(255, 88, 16)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(122, 20, 8)),
	}),

	-- Sparks thrown clear of the body. Stays hot longer than the flame —
	-- an ember that cooled on the same curve would vanish into the smoke
	-- instead of arcing away from it.
	ember = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 236, 170)),
		ColorSequenceKeypoint.new(0.60, Color3.fromRGB(255, 140, 30)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(190, 46, 10)),
	}),

	-- Charcoal, not black: pure black smoke disappears against the arena's
	-- dark geometry and silhouettes badly against the skybox.
	smoke = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(92, 68, 58)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(38, 34, 34)),
	}),

	-- The glow Inferno casts on its surroundings, shared by the eruption's
	-- one-shot light and the flicker that rides the burn.
	light = Color3.fromRGB(255, 138, 46),

	-- What the blast does to the viewer's screen (ScreenImpact.Profile).
	--
	-- Restrained on purpose, and the numbers are small for a reason: this
	-- fires for every player who can see the hit, several times a fight,
	-- and a screen effect that is merely strong the first time is nausea by
	-- the tenth. Brightness 0.09 and a 0.4-stud shake are at the threshold
	-- where you feel the hit without being able to point at an effect.
	--
	-- `releaseSec` is short next to the 3 s burn on purpose. This is the
	-- detonation's punch, not the fire's mood — the lingering warmth comes
	-- from the burning rig's own PointLight, which is in the world and
	-- therefore falls off with distance and hides behind cover the way a
	-- fire should. A screen tint held for three seconds would do neither.
	screen = {
		tintColor  = Color3.fromRGB(255, 214, 176),
		brightness = 0.09,
		contrast   = 0.12,
		blurSize   = 8,
		shakeStuds = 0.4,
		shakeHz    = 11,
		releaseSec = 0.55,
	},

	-- Beyond this the blast gets no screen layer at all: the falloff is
	-- linear from the camera to here. Roughly the width of the arena, so an
	-- Inferno across the map still registers faintly and one across the
	-- room lands at nearly full strength.
	screenFalloffStuds = 140,
}

----------------------------------------------------------------------
-- Projectile look constants
----------------------------------------------------------------------
-- Shared by a delivery cosmetic's particle entry (EFFECTS) and its solid
-- body (PROJECTILE_BODIES), which are two tables read with one key and so
-- must not drift apart on colour.

-- A projectile core is a Neon sphere, so this is light being emitted rather
-- than surface colour — and that is exactly the trap. The first version of
-- this was FIRE.flame's white-hot birth colour (255, 238, 196), on the
-- reasoning that the orange belongs to the sheath and the core should be
-- what the sheath is hotter than. On screen every shot rendered as a flat
-- white disc: Neon clips a near-white tint to pure white, there is no
-- gradient across a single Part to recover it, and the stretched bolt
-- silhouette vanished inside the blowout.
--
-- So the core carries the orange and the *particles* carry the white — the
-- opposite of the original split, and the one that actually reads as
-- molten. Verified by screenshot, not reasoning; a value this close to
-- clipping cannot be judged from the hex.
local FIRE_CORE_COLOR = Color3.fromRGB(255, 152, 48)

-- The Wizard boss's bolt. Deliberately neither in COLORS nor in FIRE: it is
-- not a castable spell colour and it is not fire (the shot freezes). The
-- only two things that draw it are its own EFFECTS entry and its trail, so
-- it stays a local rather than becoming a fourth public palette.
--
-- Core pulled off near-white for the same clipping reason as the fire one
-- above; the pale end of the gradient survives on the particles, which are
-- small and sparse enough not to saturate.
local ARCANE_CORE_COLOR = Color3.fromRGB(166, 110, 255)
local ARCANE_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(226, 208, 255)),
	ColorSequenceKeypoint.new(0.45, Color3.fromRGB(150, 96, 255)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(72, 30, 150)),
})

-- What a fire trail fades through, and pointedly NOT FIRE.flame.
--
-- That sequence is built for a particle that is born white-hot and cools
-- over its own lifetime, which is right for a sprite and wrong for a
-- ribbon: a Trail's gradient runs along its *length*, so FIRE.flame put the
-- white end at the shot and left a wide pale band trailing behind every
-- projectile. This one starts at the core's own orange — so the ribbon
-- looks like it is leaving the shot rather than being a separate white
-- object attached to it — and cools into the same deep red the flame dies at.
local FIRE_TRAIL_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 170, 60)),
	ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 92, 20)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(140, 26, 8)),
})

-- Every projectile trail fades over its own length rather than ending on a
-- hard edge — a ribbon that stops dead reads as a bug, not as a streak.
--
-- The midpoint is what keeps it from reading as a solid bar. A straight
-- 0→1 ramp holds most of its opacity across most of its length, which at
-- these widths is a painted stripe; dropping it to 0.7 by the halfway mark
-- puts the visible mass right behind the shot where a wake belongs.
local TRAIL_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0.0, 0.35),
	NumberSequenceKeypoint.new(0.5, 0.70),
	NumberSequenceKeypoint.new(1.0, 1.00),
})

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
-- 2026-08-04: every entry now points at a real (if reused/mismatched)
-- asset rather than sitting silent — spawnEffect would skip playback for
-- `"rbxassetid://0"`, but a stub you can't hear defeats the point of a
-- stub. If a future effect genuinely has no defensible stand-in, that
-- literal id is still the honoured "silent" sentinel.

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

	-- The shield failing under the last hit. Its own named entry even
	-- though it currently points at the same asset as `impactFreeze` —
	-- that *is* the hook: a shell breaking wants a sharp crack, the freeze
	-- crack is the only crack in the inventory, and swapping in a real
	-- glass-shatter later is a one-line change here rather than an edit
	-- inside the EFFECTS table. Callers play it pitched down from the
	-- freeze use so the two still read as different events.
	shieldBreak = "rbxassetid://88987851128257",

	-- A letter block popping. Its own named entry even though it currently
	-- points at the same asset as `impactFreeze` — same hook as
	-- `shieldBreak`: a block bursting wants a short bright crack, that is
	-- the only crack in the inventory, and a real pop lands as a one-line
	-- change here rather than an edit inside the EFFECTS table. This is the
	-- single most-heard sound in the game (once per letter, several times a
	-- word), so it is the first id worth replacing with real audio.
	blockPop = "rbxassetid://88987851128257",

	-- Cast fizzle (not enough mana / no target in range). Deliberately the
	-- same swoosh as `cast`, and played pitched-down by the callers: a
	-- deflated version of the cast sound is the clearest way to say "that
	-- cast didn't happen" without a dedicated buzzer asset.
	--
	-- This is now the only copy. It used to be duplicated into
	-- StarterPack/Spelling Staff/Handle/FizzleSound.model.json because Rojo
	-- JSON cannot reference a Luau constant and every client needed the id
	-- on its own replicated copy of that Sound. Phase 5.7 deleted the staff,
	-- and BlockTapController's refusal cue is a client-local Sound built
	-- from this constant like every other caller — so a swap here is now
	-- genuinely a swap everywhere.
	fizzle = "rbxassetid://134677020800886",

	-- Boss FireballVolley launch. No owned or findable asset reads as a
	-- boss projectile whoosh yet, so this deliberately reuses the same
	-- asset as `cast` rather than sitting UNSET/silent — callers pitch it
	-- down so a boss launch doesn't sound identical to a player cast.
	bossProjectileLaunch = "rbxassetid://134677020800886",

	-- The ground giving way as a Stone Wall pushes up through it. Points at
	-- the same dry percussive hit as `impactDamage`, but played at roughly
	-- a third speed, which stretches a 0.58 s slap into ~1.8 s of low
	-- grinding — the nearest thing to an earth rumble the inventory has.
	-- Its own entry despite sharing an asset, for the same reason as
	-- `shieldBreak`: a real rumble sample is then a one-line swap here
	-- rather than an edit inside the EFFECTS table.
	stoneRumble = "rbxassetid://131133470069125",

	-- A single fracture opening across a Stone Wall's face, in the seconds
	-- before it collapses. Points at the same short sharp asset as
	-- `impactFreeze` — the only thing in the inventory that snaps rather
	-- than thuds — played well below the pitch either of its other uses
	-- takes, which pulls it off ice and onto stone.
	--
	-- Its own entry despite sharing an asset, for the same reason as
	-- `shieldBreak` and `stoneRumble`: a real stone-crack sample is then a
	-- one-line swap here rather than an edit inside the EFFECTS table.
	stoneCrack = "rbxassetid://88987851128257",
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
		-- Was "casterStaffTip" until Phase 5.7 deleted the staff.
		anchor           = "caster",
	}
end

----------------------------------------------------------------------
-- Block pop (Phase 5.7)
----------------------------------------------------------------------
-- The burst when a letter block is tapped. One entry per block colour so
-- the pop reads as "you took a red" at a glance, which is tactical
-- information once PvP lands — see design/tap-to-pop.md.
--
-- Wildcard gold is a fourth palette here but deliberately NOT a fourth
-- key in COLORS: that table is the *spell* palette keyed by the three
-- castable colours, and a gold entry would imply a gold spell. Same
-- reasoning as STONE_DUST below. The tint matches
-- LetterBlocks.COLOR_TINTS' gold so the burst matches the block it came
-- from; the two are duplicated rather than shared because VfxConfig has
-- no business requiring a gameplay module.
local WILDCARD_GOLD: ColorPalette = {
	primary = Color3.fromHex("#EAB308"),
	glow    = Color3.fromHex("#FDE68A"),
	accent  = Color3.fromHex("#FFFFFF"),
}

-- Smaller and faster than a cast burst on purpose. A pop happens several
-- times per word — at cast-burst weight it would dominate the screen and
-- bury the spell it is feeding.
local function blockPopEntry(palette: ColorPalette): EffectSpec
	return {
		emitters = {
			castEmitter("BurstSmall", palette, {
				emitCount = 18,
				lifetime  = NumberRange.new(0.18, 0.34),
				sizePeak  = 0.5,
				speed     = NumberRange.new(8, 16),
				spreadDeg = 180, -- a block bursts outward in every direction
			}),
		},
		sound            = { soundId = SFX.blockPop, volume = 0.55, pitchRange = NumberRange.new(0.94, 1.12) },
		totalDurationSec = 0.45,
		-- "worldPosition", not a "blockPosition" of its own: the block is
		-- already being destroyed when this plays, so the burst is handed a
		-- Vector3 read before the teardown. There is no block left to anchor
		-- to, which is the same reason BlockShootService uses playAt rather
		-- than playOn.
		anchor           = "worldPosition",
	}
end

----------------------------------------------------------------------
-- Stone Wall rise
----------------------------------------------------------------------
-- Grit and dust, not a spell colour. The wall shoulders its way up out
-- of the floor, so what comes off the base is earth — tinting it green
-- like the rest of the green tier would read as sparks.
--
-- Deliberately not a fourth entry in COLORS: that table is the *spell*
-- palette, keyed by the three spell colours, and adding to it would
-- imply a fourth castable colour.
local STONE_DUST: ColorPalette = {
	primary = Color3.fromRGB(122, 108, 92),
	glow    = Color3.fromRGB(160, 146, 128),
	accent  = Color3.fromRGB(96, 86, 74),
}

-- How long the emitters keep throwing dust. Must outlast the wall's whole
-- arrival — SkillVisuals BARRIER_TELL_SEC + BARRIER_RISE_SEC, 0.18 + 0.55
-- — so the plume is still going when the slab lands and doesn't cut out
-- mid-climb. Can't read those constants directly: SkillVisuals requires
-- this module, so the dependency only runs one way. Hence the duplicated
-- number and this note.
local WALL_RISE_EMIT_SEC = 0.85

-- Longest a dust particle lives. The anchor has to outlive the last
-- particle spawned on the last frame of the emit window, so both entries
-- below set totalDurationSec to the sum of the two.
local WALL_RISE_DUST_MAX_LIFETIME_SEC = 1.1

-- How long the crack snap needs its anchor to survive. The sample is
-- 0.39 s, and `wall_crack` plays it as slow as 0.55 speed, which stretches
-- it to ~0.71 s; a shorter anchor would cut the tail off the fracture that
-- fires closest to the wall's collapse.
local WALL_CRACK_SOUND_SEC = 0.75

-- Two layers, shared by the sounded centre entry and the silent flank
-- one so they can never drift apart:
--   dust — slow, wide, long-lived; the body of the plume
--   grit — fast chips thrown clear of the base; the detail that sells it
--          as rock rather than smoke
local function stoneRiseEmitters(): { EmitterSpec }
	return {
		{
			template    = "BurstMedium",
			color       = STONE_DUST,
			rate        = 80,
			durationSec = WALL_RISE_EMIT_SEC,
			lifetime    = NumberRange.new(0.50, WALL_RISE_DUST_MAX_LIFETIME_SEC),
			size        = NumberSequence.new({
				NumberSequenceKeypoint.new(0.0, 0.6),
				NumberSequenceKeypoint.new(0.5, 1.5),
				NumberSequenceKeypoint.new(1.0, 2.2),
			}),
			-- Slow and wide: dust boiling up around the base, not a jet.
			speed        = NumberRange.new(2, 7),
			spreadAngle  = Vector2.new(80, 80),
			rotation     = NumberRange.new(-180, 180),
			transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0.0, 0.45),
				NumberSequenceKeypoint.new(0.3, 0.55),
				NumberSequenceKeypoint.new(1.0, 1.00),
			}),
		},
		{
			template    = "ImpactBurst",
			color       = STONE_DUST,
			rate        = 35,
			durationSec = WALL_RISE_EMIT_SEC,
			lifetime    = NumberRange.new(0.35, 0.70),
			size        = NumberSequence.new({
				NumberSequenceKeypoint.new(0.0, 0.35),
				NumberSequenceKeypoint.new(1.0, 0.0),
			}),
			speed       = NumberRange.new(9, 20),
			-- Narrower than the dust so the chips arc up along the slab's
			-- face instead of spraying flat across the floor.
			spreadAngle = Vector2.new(45, 45),
			rotation    = NumberRange.new(-180, 180),
		},
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
	--
	-- Rebuilt on the flipbook templates (2026-08-08). The previous version
	-- was already the biggest entry in this table — 86 particles across two
	-- layers — and still read as a firework, because every template in
	-- VfxTemplates shared one soft round blob texture. Particle count was
	-- never the problem: a hundred round dots is a hundred round dots. What
	-- fixed it was `FireFlame`/`FireSmoke`, whose 8x8 sheet animates each
	-- particle through a full flame birth-and-dissipate over its lifetime.
	--
	-- This is only half of Inferno's fire. It is the one-shot blast; the
	-- flames that stay on the target afterwards are drawn by
	-- StatusVisuals/InfernoVfx off the `_burning` attribute. Note there is
	-- deliberately no `impact_burn` entry — `resolveImpactEffectIds` will
	-- look one up for the skill's second onImpact kind and find nothing,
	-- which is correct. A burst there would fire at cast time on the
	-- caster's prediction and double the eruption.
	impact_damage_t3 = {
		emitters = {
			-- The eruption body. Big, brief, and thrown upward off the hit.
			{
				template      = "FireFlame",
				colorSequence = VfxConfig.FIRE.flame,
				emitCount     = 34,
				lifetime      = NumberRange.new(0.55, 1.00),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 3.0),
					NumberSequenceKeypoint.new(0.4, 7.5),
					NumberSequenceKeypoint.new(1.0, 5.0),
				}),
				speed         = NumberRange.new(14, 26),
				-- Narrower than the 180-degree splash so the column reads
				-- as rising out of the target rather than spraying past it.
				spreadAngle   = Vector2.new(70, 70),
			},
			-- Sparks. The one layer that keeps the old blob texture, and
			-- should: a spark IS a bright round dot, and swapping it for a
			-- flipbook would only cost frames.
			{
				template      = "FireEmber",
				colorSequence = VfxConfig.FIRE.ember,
				emitCount     = 44,
				lifetime      = NumberRange.new(0.9, 1.9),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.55),
					NumberSequenceKeypoint.new(1.0, 0.00),
				}),
				speed         = NumberRange.new(20, 44),
				spreadAngle   = Vector2.new(120, 120),
			},
			-- The tail. Outlives both layers above and is what makes the
			-- blast read as having left something behind rather than
			-- switching off — it sets `totalDurationSec` below.
			{
				template      = "FireSmoke",
				colorSequence = VfxConfig.FIRE.smoke,
				emitCount     = 20,
				lifetime      = NumberRange.new(1.4, 2.4),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 4.0),
					NumberSequenceKeypoint.new(1.0, 11.0),
				}),
				speed         = NumberRange.new(5, 13),
				spreadAngle   = Vector2.new(100, 100),
			},
		},
		-- First use of the `light` field, which the EffectSpec type has
		-- always declared and spawnEffect never read. Short: it is the
		-- flash of the detonation, not the burn's steady glow — that one
		-- belongs to InfernoVfx and lasts as long as the flames do.
		light            = { color = VfxConfig.FIRE.light, brightness = 6, durationSec = 0.45 },
		sound            = { soundId = SFX.impactHeavy, volume = 1.0, pitchRange = NumberRange.new(0.88, 1.0) },
		-- Covers the longest emitter above (smoke, up to 2.4 s) plus the
		-- frame it is emitted on. Cutting this short destroys the attachment
		-- mid-plume and the smoke pops out of existence.
		totalDurationSec = 2.5,
		upward           = true,
		anchor           = "targetHumanoidRootPart",
	},

	-- Fireball (red T2) — sits between the T1 pop and the T3 eruption.
	-- Reached through the registry's explicit impactEffectId rather than
	-- the tier lookup, because projectile spells fire their own impact
	-- burst from SkillDelivery at the real hit position.
	--
	-- Built from the same three flipbook layers as `impact_damage_t3`
	-- (2026-08-09), for the reason that entry's comment gives: the round
	-- blob texture on `ImpactBurst` reads as a firework at any particle
	-- count, and 38 of them was still a firework. A fire spell should look
	-- like fire at every tier, and having T2 and T3 draw from one visual
	-- vocabulary is what makes the tier ladder read as *more of the same
	-- thing* rather than three unrelated effects.
	--
	-- What separates it from T3 is scale and, above all, **how long the
	-- fire lasts**. T3 is a detonation that leaves the target alight for
	-- three seconds (StatusVisuals/InfernoVfx); T2 has no burn lane at all,
	-- so its flames must be gone almost as soon as they arrive or the hit
	-- reads as a status that never applied. Every lifetime below is roughly
	-- half its T3 counterpart, and the smoke tail — the layer that sets
	-- totalDurationSec — is cut hardest.
	--
	-- Fireball also lands far more often than Inferno (T2 cost, and it is
	-- the workhorse of the red school), which is the second reason to keep
	-- it brief: a 2.5 s plume per cast would leave the arena permanently
	-- hazed in a fight.
	-- Scaled up and the ground disc dropped (2026-08-09, second pass).
	-- These two go together: `impactRing = false` in the registry means the
	-- neon shockwave no longer draws a 14-stud-wide circle under the hit,
	-- so the fire is now the *only* thing communicating that this spell has
	-- a blast radius at all. It has to be wide enough to imply the 7 studs
	-- the damage query actually uses, which is why the growth here is as
	-- much in `spreadAngle` as in `size`.
	--
	-- The flame peak sits at 7.0 against T3's 7.5 — deliberately close.
	-- With the disc gone there was no room left to be subtle about scale,
	-- and the tier separation now rests on duration, ember/smoke volume and
	-- the light rather than on footprint. If Fireball starts reading as
	-- interchangeable with Inferno, scale T3 up rather than pulling this
	-- back down; the ladder wants headroom at the top, not a smaller T2.
	impact_damage_t2 = {
		emitters = {
			-- The blast body. Sized to cover the impact radius, and still
			-- gone inside ~0.6 s.
			{
				template      = "FireFlame",
				colorSequence = VfxConfig.FIRE.flame,
				emitCount     = 36,
				-- Nudged up from 0.28–0.50 alongside the size increase.
				-- Particles this large reaching full transparency in a
				-- quarter second read as being switched off rather than
				-- burning out.
				lifetime      = NumberRange.new(0.32, 0.58),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 3.0),
					NumberSequenceKeypoint.new(0.4, 7.0),
					NumberSequenceKeypoint.new(1.0, 4.8),
				}),
				speed         = NumberRange.new(16, 30),
				-- Much wider than T3's 70-degree column. That one is an
				-- eruption climbing out of a target; this is a projectile
				-- bursting on contact, and since it no longer has a disc
				-- underneath it, spreading is what sells the radius.
				spreadAngle   = Vector2.new(130, 130),
			},
			-- Sparks. Outlive the flame on purpose — embers arcing away
			-- from a blast that has already gone out is the cheapest way to
			-- keep a short effect from ending abruptly, and thrown wide
			-- they also mark roughly where the splash stopped.
			{
				template      = "FireEmber",
				colorSequence = VfxConfig.FIRE.ember,
				emitCount     = 44,
				lifetime      = NumberRange.new(0.55, 1.05),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.55),
					NumberSequenceKeypoint.new(1.0, 0.00),
				}),
				speed         = NumberRange.new(24, 48),
				spreadAngle   = Vector2.new(160, 160),
			},
			-- The tail, and the layer that sets totalDurationSec. Still
			-- thin and short next to T3's 20 particles over 2.4 s — enough
			-- to say something burned here, not enough to hang around.
			{
				template      = "FireSmoke",
				colorSequence = VfxConfig.FIRE.smoke,
				emitCount     = 14,
				lifetime      = NumberRange.new(0.75, 1.15),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 3.5),
					NumberSequenceKeypoint.new(1.0, 9.5),
				}),
				speed         = NumberRange.new(6, 13),
				spreadAngle   = Vector2.new(140, 140),
			},
		},
		-- Same flash as the eruption, dimmer and shorter. Honours
		-- PERF.allowLights inside spawnEffect, so it sheds first on a
		-- machine already dropping frames.
		light            = { color = VfxConfig.FIRE.light, brightness = 5.0, durationSec = 0.32 },
		-- Deliberately still the T1 hit sound pitched down, not T3's
		-- `impactHeavy`. The visual language is shared; the *weight* is not
		-- — a Fireball that booms like the 50%-max-HP nuke would flatten
		-- the audio ladder the tiers are supposed to climb.
		sound            = { soundId = SFX.impactDamage, volume = 1.0, pitchRange = NumberRange.new(0.82, 0.94) },
		-- Covers the longest emitter above (smoke, up to 1.15 s) plus the
		-- frame it is emitted on. Cutting this short destroys the
		-- attachment mid-plume and the smoke pops out of existence.
		totalDurationSec = 1.25,
		upward           = true,
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

	-- A projectile dying on a shield shell. Deliberately unlike the
	-- `impact_shield` ward shimmer above, which marks the shield going
	-- *up*: this one is a spark off glass, so it's faster, narrower and
	-- pitched high. Anchored at the contact point on the bubble's surface
	-- rather than on the holder's HRP — the whole point of the shell is
	-- that the shot never reached the body.
	shield_block = {
		emitters = {
			{
				template    = "ImpactBurst",
				color       = C.blue,
				emitCount   = 24,
				lifetime    = NumberRange.new(0.18, 0.35),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.45),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(12, 22),
				spreadAngle = Vector2.new(140, 140),
				rotation    = NumberRange.new(-180, 180),
			},
		},
		sound            = { soundId = SFX.impactShield, volume = 0.9, pitchRange = NumberRange.new(1.15, 1.35) },
		totalDurationSec = 0.45,
		anchor           = "worldPosition",
	},

	-- The shell failing under the last hit. Two layers so it reads as
	-- glass rather than a puff: a fast outward spray of fragments that
	-- clears the body in the first fraction of a second, and a slower
	-- glitter that hangs in the air after the shell is already gone.
	-- Emitted from the holder's root, so the fragments fly out through
	-- where the bubble was.
	shield_break = {
		emitters = {
			{
				template    = "ImpactBurst",
				color       = C.blue,
				emitCount   = 40,
				lifetime    = NumberRange.new(0.35, 0.70),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.55),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(16, 30),
				spreadAngle = Vector2.new(180, 180),
				rotation    = NumberRange.new(-180, 180),
			},
			{
				template    = "BurstSmall",
				color       = C.blue,
				emitCount   = 28,
				lifetime    = NumberRange.new(0.7, 1.3),
				size        = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.30),
					NumberSequenceKeypoint.new(0.5, 0.18),
					NumberSequenceKeypoint.new(1.0, 0.0),
				}),
				speed       = NumberRange.new(3, 9),
				spreadAngle = Vector2.new(180, 180),
				rotation    = NumberRange.new(-180, 180),
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.10),
					NumberSequenceKeypoint.new(0.6, 0.35),
					NumberSequenceKeypoint.new(1.0, 1.00),
				}),
			},
		},
		sound            = { soundId = SFX.shieldBreak, volume = 1.0, pitchRange = NumberRange.new(0.80, 0.92) },
		totalDurationSec = 1.5,
		anchor           = "targetHumanoidRootPart",
	},

	-- knockup's gameplay handler is real (SkillEffects.knockup — an upward
	-- AssemblyLinearVelocity shove), used today by boss GroundSlam. The
	-- sound was left UNSET pending a real "launch" asset; no owned or
	-- findable asset reads as one, so this reuses impactDamage's percussive
	-- hit pitched up, standing in for the whump of being thrown skyward.
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
		sound            = { soundId = SFX.impactDamage, volume = 0.85, pitchRange = NumberRange.new(1.15, 1.30) },
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

	-- Ground rumble under a Stone Wall while it climbs out of the floor.
	--
	-- Rate-based rather than a one-shot burst because it has to run for
	-- the whole rise: a single puff at t=0 reads as the wall having
	-- already arrived, which is the pop this effect exists to replace.
	--
	-- Played at the centre of the wall's base. The flanks get the silent
	-- `wall_rise_dust` instead — see SkillVisuals BARRIER_RISE_DUST_SPAN
	-- for why the plume is three points wide and why only one of them
	-- carries the audio.
	wall_rise_rumble = {
		emitters         = stoneRiseEmitters(),
		sound            = { soundId = SFX.stoneRumble, volume = 0.65, pitchRange = NumberRange.new(0.28, 0.36) },
		-- Emit window plus the slowest dust particle's full lifetime, so
		-- the anchor is never destroyed out from under a plume still in
		-- the air.
		totalDurationSec = WALL_RISE_EMIT_SEC + WALL_RISE_DUST_MAX_LIFETIME_SEC,
		anchor           = "worldPosition",
	},

	-- The same plume without the sound, for the points either side of the
	-- wall's centre. Identical emitters by construction, not by copy.
	wall_rise_dust = {
		emitters         = stoneRiseEmitters(),
		totalDurationSec = WALL_RISE_EMIT_SEC + WALL_RISE_DUST_MAX_LIFETIME_SEC,
		anchor           = "worldPosition",
	},

	-- One fracture snapping open across a Stone Wall, played by
	-- `client/Vfx/BarrierCrumbleController` as each crack appears.
	--
	-- Sound-only: the crack itself is SurfaceGui geometry on the slab, and
	-- this effect exists purely to give that geometry a voice. Nothing to
	-- emit, so no emitters — see spawnEffect, which plays audio outside the
	-- emitters guard precisely so a spec like this one works.
	--
	-- Pitched to 0.55–0.70, well under the 0.90–1.05 the freeze impact
	-- takes from the same asset and under `shieldBreak`'s 0.80–0.92. Ice
	-- cracks bright and stone cracks dull, and the three uses have to stay
	-- distinguishable while they share a sample. The range is also wide
	-- enough that six fractures on one wall don't read as one sound looped.
	--
	-- Quiet, and deliberately left on Roblox's default attenuation rather
	-- than the wide settings the boss cues use: this is the one case those
	-- defaults are tuned for. A crack matters to whoever is sheltering
	-- behind the wall, and it should fade for everyone else.
	wall_crack = {
		sound            = { soundId = SFX.stoneCrack, volume = 0.45, pitchRange = NumberRange.new(0.55, 0.70) },
		totalDurationSec = WALL_CRACK_SOUND_SEC,
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

	-- ⚠ Every entry below sets `rate` explicitly, and must.
	--
	-- Rebuilt 2026-08-10, and this is the first version of the three that
	-- has ever drawn a particle. They were authored on `BurstSmall` with a
	-- `durationSec` and no `rate` — and every template in
	-- ReplicatedStorage.VfxTemplates ships `Rate = 0`, which is correct for
	-- the burst effects that are the overwhelming majority of this file and
	-- reach spawnEffect through `emitCount`. So spawnEffect dutifully set
	-- `Enabled = true` on an emitter with a rate of zero, three times, and
	-- every fire projectile in the game has been a bare neon cube with no
	-- trail at all since the day these landed. A rate-based entry here is
	-- the exception, not the norm — state the rate.
	--
	-- The second change is the vocabulary. These were the last things in the
	-- red school still built on `BurstSmall`'s round blob texture, months
	-- after the impacts moved to the `FireFlame`/`FireEmber`/`FireSmoke`
	-- flipbook sheets (2026-08-08, -09) for exactly the reason those entries
	-- give: a hundred round dots is a hundred round dots. A fire spell
	-- should look like fire from the muzzle to the blast, not only where it
	-- lands.
	--
	-- Each entry pairs with a PROJECTILE_BODIES entry under the same key,
	-- which owns the shape, the trail ribbon and the light. Read them
	-- together — the sizes here are chosen against the body sizes there.

	-- Firebolt (T1) — a streaking bolt: thin stretched core, a flame sheath
	-- that is gone about a body-length behind it, sparks shedding wide.
	--
	-- The short sheath lifetime is the whole character of this one. Let the
	-- flame live as long as Fireball's and a Firebolt stops reading as fast
	-- and starts reading as a small fireball, which is the T2 slot's job.
	--
	-- `sound` plays once at launch (spawnEffect has no looping path, so it
	-- can't cover the whole 1.5 s flight — the wiki still lists a proper
	-- in-flight whoosh as a gap). It deliberately layers under the
	-- cast_red_t1 staff-tip whoosh that fires the same instant, so it's
	-- kept quiet rather than a second full-volume copy of the same asset.
	projectile_red_t1 = {
		emitters = {
			{
				template      = "FireFlame",
				colorSequence = VfxConfig.FIRE.flame,
				durationSec   = 1.5,           -- matches FIREBOLT_LIFETIME_SEC
				rate          = 55,
				lifetime      = NumberRange.new(0.14, 0.26),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 1.10),
					NumberSequenceKeypoint.new(1.0, 0.15),
				}),
				-- Near zero, and that is deliberate for every sheath layer in
				-- this block: the shot's own travel is what spaces the
				-- particles into a trail. Give them real speed and the sheath
				-- blooms outward into a cloud the bolt sits inside instead of
				-- staying wrapped around it.
				speed         = NumberRange.new(0, 1),
				spreadAngle   = Vector2.new(10, 10),
			},
			-- Sparks. The one layer thrown wide, and what gives the bolt a
			-- silhouette once the sheath behind it has burned out.
			{
				template      = "FireEmber",
				colorSequence = VfxConfig.FIRE.ember,
				durationSec   = 1.5,
				rate          = 26,
				lifetime      = NumberRange.new(0.25, 0.50),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.28),
					NumberSequenceKeypoint.new(1.0, 0.00),
				}),
				speed         = NumberRange.new(1, 4),
				spreadAngle   = Vector2.new(35, 35),
			},
		},
		sound            = { soundId = SFX.cast, volume = 0.35, pitchRange = NumberRange.new(1.10, 1.25) },
		totalDurationSec = 1.7,
		anchor           = "worldPosition",
	},

	-- Fireball (T2) — the orb. The only projectile in the roster that is
	-- meant to read as a burning *ball* rather than as a streak, which is
	-- what separates it from the T1 and T4 bolts either side of it: three
	-- layers instead of two, the flame growing after birth instead of
	-- shrinking, and a smoke tail no bolt gets.
	--
	-- Slightly louder/lower than T1 so it reads as the bigger shot.
	projectile_red_t2 = {
		emitters = {
			-- The body. Grows for the first half of its life so the orb looks
			-- like it is boiling outward rather than shedding, then collapses
			-- — the same birth-and-dissipate arc impact_damage_t2 uses.
			-- Rate is the tuning dial here, and it is far lower than it looks
			-- like it should be. Fireball travels at 55 studs/s, so rate 95
			-- drops a particle every 0.58 studs while each one is ~3 studs
			-- across: five-plus additive layers stacked at every point of the
			-- path, which blows out to flat white cotton rather than fire.
			-- Roughly one particle-width of spacing is what reads as flame —
			-- past that, more particles buy saturation, not density.
			{
				template      = "FireFlame",
				colorSequence = VfxConfig.FIRE.flame,
				durationSec   = 2.0,           -- matches FIREBALL_LIFETIME_SEC
				rate          = 40,
				lifetime      = NumberRange.new(0.30, 0.55),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.00, 2.20),
					NumberSequenceKeypoint.new(0.45, 2.70),
					NumberSequenceKeypoint.new(1.00, 0.60),
				}),
				speed         = NumberRange.new(0, 2),
				spreadAngle   = Vector2.new(24, 24),
			},
			{
				template      = "FireEmber",
				colorSequence = VfxConfig.FIRE.ember,
				durationSec   = 2.0,
				rate          = 30,
				lifetime      = NumberRange.new(0.45, 0.90),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.42),
					NumberSequenceKeypoint.new(1.0, 0.00),
				}),
				speed         = NumberRange.new(2, 7),
				spreadAngle   = Vector2.new(60, 60),
			},
			-- The tail. Kept thin and short-lived on purpose — Fireball is the
			-- workhorse of the red school and a generous smoke trail per cast
			-- would leave the arena permanently hazed, the same argument that
			-- caps the smoke on its impact burst.
			{
				template      = "FireSmoke",
				colorSequence = VfxConfig.FIRE.smoke,
				durationSec   = 2.0,
				rate          = 12,
				lifetime      = NumberRange.new(0.55, 0.95),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 1.4),
					NumberSequenceKeypoint.new(1.0, 4.2),
				}),
				speed         = NumberRange.new(0, 2),
				spreadAngle   = Vector2.new(30, 30),
			},
		},
		sound            = { soundId = SFX.cast, volume = 0.45, pitchRange = NumberRange.new(0.95, 1.05) },
		-- Covers the smoke layer (up to 0.95 s) emitted on the last frame of
		-- a full 2.0 s flight. Cutting it to the flight time destroys the
		-- attachment mid-plume and the tail pops out of existence.
		totalDurationSec = 3.0,
		anchor           = "worldPosition",
	},

	-- Volley (T4) — three staggered bolts. Same two-layer bolt build as T1,
	-- a touch wider and longer-lived so a stream of them still resolves into
	-- three separate shots at spread.
	--
	-- Loudest/lowest of the three so a T4 volley reads as heavier per-shot.
	projectile_red_t4 = {
		emitters = {
			{
				template      = "FireFlame",
				colorSequence = VfxConfig.FIRE.flame,
				durationSec   = 3.0,
				rate          = 40,
				lifetime      = NumberRange.new(0.16, 0.30),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 1.35),
					NumberSequenceKeypoint.new(1.0, 0.20),
				}),
				speed         = NumberRange.new(0, 1),
				spreadAngle   = Vector2.new(12, 12),
			},
			{
				template      = "FireEmber",
				colorSequence = VfxConfig.FIRE.ember,
				durationSec   = 3.0,
				rate          = 20,
				lifetime      = NumberRange.new(0.30, 0.60),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.32),
					NumberSequenceKeypoint.new(1.0, 0.00),
				}),
				speed         = NumberRange.new(1, 5),
				spreadAngle   = Vector2.new(40, 40),
			},
		},
		sound            = { soundId = SFX.cast, volume = 0.55, pitchRange = NumberRange.new(0.80, 0.90) },
		totalDurationSec = 3.2,
		anchor           = "worldPosition",
	},

	-- Brain boss FireballVolley — the in-flight trail these shots never had.
	-- Until now the boss's only projectile cosmetic was the launch *sound*
	-- (projectile_boss_fireball, below), so a Brain volley was 20 orange
	-- cubes crossing the arena in silence.
	--
	-- Rates are roughly a third of the player Firebolt's for a shot four
	-- times its size, and that is the whole tuning constraint: this entry
	-- runs 20 times concurrently, ~0.15 s apart, against a player spell that
	-- runs once. Scale the sizes when it needs to read bigger, never the
	-- rates.
	projectile_boss_bolt = {
		emitters = {
			{
				template      = "FireFlame",
				colorSequence = VfxConfig.FIRE.flame,
				durationSec   = 3.0,
				rate          = 30,
				lifetime      = NumberRange.new(0.18, 0.32),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 3.20),
					NumberSequenceKeypoint.new(1.0, 0.60),
				}),
				speed         = NumberRange.new(0, 2),
				spreadAngle   = Vector2.new(14, 14),
			},
			{
				template      = "FireEmber",
				colorSequence = VfxConfig.FIRE.ember,
				durationSec   = 3.0,
				rate          = 14,
				lifetime      = NumberRange.new(0.30, 0.55),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.50),
					NumberSequenceKeypoint.new(1.0, 0.00),
				}),
				speed         = NumberRange.new(2, 6),
				spreadAngle   = Vector2.new(45, 45),
			},
		},
		-- Deliberately silent. `projectile_boss_fireball` already fires once
		-- per shot at the muzzle and its own comment explains why it is held
		-- so quiet — a second per-shot sound riding the trail would make one
		-- Brain attack 40 overlapping plays.
		totalDurationSec = 3.2,
		anchor           = "worldPosition",
	},

	-- Wizard boss FireballVolley — same bolt build, violet, and no flame
	-- layer at all. The shot freezes rather than burns, so dressing it in
	-- the fire flipbook would promise the wrong status; `FireEmber` is a
	-- plain round spark and takes a tint cleanly, which is exactly what this
	-- needs. Named for the boss, not the school, because it is neither red
	-- nor blue in the castable sense.
	projectile_boss_arcane_bolt = {
		emitters = {
			{
				template      = "FireEmber",
				colorSequence = ARCANE_GRADIENT,
				durationSec   = 4.0,
				rate          = 40,
				lifetime      = NumberRange.new(0.22, 0.45),
				size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0.0, 0.75),
					NumberSequenceKeypoint.new(1.0, 0.00),
				}),
				speed         = NumberRange.new(0, 3),
				spreadAngle   = Vector2.new(25, 25),
			},
		},
		totalDurationSec = 4.2,
		anchor           = "worldPosition",
	},

	-- Boss FireballVolley launch (Brain + Wizard), fired at the muzzle via
	-- deliveryParams.launchEffectId. Sound-only: the boss projectile has no
	-- trail authored yet.
	--
	-- The rolloff is the point of this entry, not the asset. Brain engages
	-- from up to 100 studs and the whole reason a launch cue exists is to be
	-- heard by someone in cover who cannot see the boss — at Roblox's
	-- default EmitterSize of 10 that sound arrives at roughly a tenth
	-- volume, i.e. inaudible, which is exactly what it did. EmitterSize is
	-- set past the engagement range so attenuation stays flat across the
	-- arena instead of falling off before it reaches the listener.
	--
	-- Volume is held down because a Brain volley is 30 shots: this plays 30
	-- times, ~0.15 s apart, and at full volume with a flat rolloff that is a
	-- wall of noise rather than a readable cue.
	projectile_boss_fireball = {
		sound = {
			soundId            = SFX.bossProjectileLaunch,
			volume             = 0.55,
			pitchRange         = NumberRange.new(0.70, 0.82),
			emitterSize        = 120,
			rollOffMaxDistance = 400,
		},
		totalDurationSec = 0.1,
		anchor           = "worldPosition",
	},

	-- A projectile dying with nothing else to announce it — stopped by a
	-- wall, or spent on expiry in mid-air.
	--
	-- This is an audio-readability requirement, not decoration: a player
	-- in cover with no line of sight to the boss needs to hear the volley
	-- stop landing to know when it is safe to break out. The impact burst
	-- only fires on a direct hit, so precisely the case where the listener
	-- cannot see the shot — it struck the wall they are hiding behind —
	-- was the silent one.
	--
	-- Deliberately quiet, short and pitched below `impactDamage`: it reads
	-- as a dull thud against cover rather than a hit on a body, and a
	-- 30-shot Brain volley plays it up to 30 times ~0.15 s apart.
	projectile_destroy = {
		sound = {
			soundId    = SFX.impactDamage,
			volume     = 0.40,
			pitchRange = NumberRange.new(0.62, 0.78),
			-- Modest, unlike the launch cue: the wall a player is hiding
			-- behind is right next to them, so this mostly plays at close
			-- range anyway. The bump is for shots landing further off, so
			-- "the volley is still coming down over there" still registers.
			emitterSize        = 40,
			rollOffMaxDistance = 300,
		},
		totalDurationSec = 0.1,
		anchor           = "worldPosition",
	},

	-- Boss GroundSlam impact shockwave (Brain). Sound-only stub reusing
	-- the same T3-Inferno explosion asset, pitched down for a duller
	-- ground thud instead of a fiery blast — no owned/findable asset reads
	-- as a slam yet.
	aoe_boss_groundslam = {
		sound = {
			soundId    = SFX.impactHeavy,
			volume     = 0.9,
			pitchRange = NumberRange.new(0.60, 0.72),
			-- Same reasoning as the launch cue: it happens at the boss, and
			-- a slam you can't hear from across the arena tells you nothing.
			-- Only one plays per attack, so it can afford to be loud.
			emitterSize        = 120,
			rollOffMaxDistance = 400,
		},
		totalDurationSec = 0.1,
		anchor           = "worldPosition",
	},

	----------------------------------------------------------------------
	-- Block pops (Phase 5.7) — one per block colour, resolved by
	-- VfxConfig.resolveBlockPopId.
	----------------------------------------------------------------------
	block_pop_red   = blockPopEntry(C.red),
	block_pop_green = blockPopEntry(C.green),
	block_pop_blue  = blockPopEntry(C.blue),
	block_pop_wild  = blockPopEntry(WILDCARD_GOLD),
}

----------------------------------------------------------------------
-- PROJECTILE_BODIES
----------------------------------------------------------------------
-- The solid of a drawn shot, keyed by the same `cosmeticEffectId` as its
-- EFFECTS entry above. CosmeticProjectile reads it; nothing else does. See
-- the ProjectileBodySpec type at the top of this file for what each field
-- means and why this isn't a field on EffectSpec.
--
-- A cosmeticEffectId with no entry here still flies — it just flies as the
-- untouched axis-aligned neon cube every projectile in this game was until
-- 2026-08-10. That fallback is what keeps this optional for a future
-- non-fire projectile that wants particles and nothing else.
--
-- Two shapes across five entries, and the split is per the design call of
-- 2026-08-10: Fireball is the one shot that reads as a burning *ball*;
-- everything else — Firebolt, Volley and both bosses — is a comet head with
-- a streak behind it. `stretch` is what makes that difference, and it is
-- large (≈3×) on purpose. A bolt only reads as travelling if it is visibly
-- longer than it is wide at the speeds these move.
--
-- Declared as an annotated local and then assigned, rather than built
-- inline with a trailing `::` cast. The annotation gives Luau an expected
-- type while it reads the literal, which is what lets `shape = "bolt"`
-- narrow to the "orb" | "bolt" union; a cast applied afterwards is checking
-- an already-inferred plain `string` against that union and rejects it.
local PROJECTILE_BODIES: { [string]: ProjectileBodySpec } = {
	-- Firebolt. 0.5-stud gameplay size × 1.6 girth × 3.4 stretch ≈ a
	-- 0.8 × 2.7 stud sliver.
	projectile_red_t1 = {
		shape     = "bolt",
		stretch   = 3.4,
		girth     = 1.6,
		coreColor = FIRE_CORE_COLOR,
		trail = {
			widthStuds   = 0.85,
			lifetimeSec  = 0.22,
			color        = FIRE_TRAIL_GRADIENT,
			transparency = TRAIL_FADE,
		},
	},

	-- Fireball. The only body with a light, and it can afford one precisely
	-- because it is the only projectile spell that arrives one at a time —
	-- see the note on ProjectileBodySpec.light.
	projectile_red_t2 = {
		shape     = "orb",
		girth     = 1.35,
		coreColor = FIRE_CORE_COLOR,
		trail = {
			widthStuds   = 1.90,
			lifetimeSec  = 0.34,
			color        = FIRE_TRAIL_GRADIENT,
			transparency = TRAIL_FADE,
		},
		light = { color = VfxConfig.FIRE.light, brightness = 3.0, rangeStuds = 16 },
	},

	-- Volley. A hair fatter and longer-lived than Firebolt so three of them
	-- at 12° spread still resolve as three shots rather than one smear.
	projectile_red_t4 = {
		shape     = "bolt",
		stretch   = 3.0,
		girth     = 1.50,
		coreColor = FIRE_CORE_COLOR,
		trail = {
			widthStuds   = 0.95,
			lifetimeSec  = 0.26,
			color        = FIRE_TRAIL_GRADIENT,
			transparency = TRAIL_FADE,
		},
	},

	-- Brain boss. Girth barely above 1 because the gameplay size is already
	-- 2 studs — the multipliers the player bolts use would put a 3-stud-wide
	-- slab on screen 20 times over.
	projectile_boss_bolt = {
		shape     = "bolt",
		stretch   = 2.8,
		girth     = 1.15,
		coreColor = FIRE_CORE_COLOR,
		trail = {
			widthStuds   = 2.40,
			lifetimeSec  = 0.30,
			color        = FIRE_TRAIL_GRADIENT,
			transparency = TRAIL_FADE,
		},
	},

	-- Wizard boss.
	projectile_boss_arcane_bolt = {
		shape     = "bolt",
		stretch   = 3.2,
		girth     = 1.40,
		coreColor = ARCANE_CORE_COLOR,
		trail = {
			widthStuds   = 1.10,
			lifetimeSec  = 0.28,
			color        = ARCANE_GRADIENT,
			transparency = TRAIL_FADE,
		},
	},
}

VfxConfig.PROJECTILE_BODIES = PROJECTILE_BODIES

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

-- Block pop burst for a block's `Block.Color` attribute.
--
-- The wildcard's colour is stored as Wildcard.COLOR rather than one of the
-- three spell colours, and its entry is keyed "wild" instead, so unknown
-- and wildcard both land somewhere real. Falling back to the red pop for
-- an unrecognised colour is deliberate: a missing burst reads as "the tap
-- didn't register", which is a worse lie than a wrong hue.
function VfxConfig.resolveBlockPopId(color: string?): string
	local id = "block_pop_" .. tostring(color)
	if VfxConfig.EFFECTS[id] then return id end
	if color ~= nil and color ~= "red" and color ~= "green" and color ~= "blue" then
		return "block_pop_wild"
	end
	return "block_pop_red"
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
