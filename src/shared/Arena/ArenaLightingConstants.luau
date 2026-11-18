--!strict

----------------------------------------------------------------------
-- ArenaLightingConstants
----------------------------------------------------------------------
-- The lighting presets an arena can ask for, and which arena asks for
-- which. Read only by client/Arena/ArenaLighting, which is the one writer
-- of the Lighting properties named here (see that file for the ownership
-- rules). See wiki/design/boss-arena.md § Lighting.
--
-- The Lighting service is one per place, so the hub, the duel pads and the
-- boss islands share it. The hub's look is whatever the place file holds:
-- ArenaLighting records it at start and goes back to it, so it is not a
-- preset and is not repeated here.
--
-- A preset only names what it changes. A key missing from a group is left
-- at the place's value.
--
-- Readability rules the numbers below were tuned against (designer
-- rulings, boss-arena.md § Level art; checked in screenshots):
--   * Letter faces are SurfaceGuis with LightInfluence 0, so lighting does
--     not change a letter's hue; it changes what the letter is read
--     against. Keep the floor in shadow above a dark navy (OutdoorAmbient)
--     and the grade's Saturation at 0, so neither palette loses chroma.
--   * The key light stays near-neutral warm (ColorShift_Top): a strong
--     orange cast would sit on wildcard gold and letter red.
--   * Bloom's Threshold stays above ordinary sunlit stone, so only Neon
--     (gate seams, dais runes, the Brain's core, spell VFX) blooms.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.GameMode.Arena)

local ArenaLightingConstants = {}

export type Preset = {
	-- Properties of the Lighting service itself.
	lighting: { [string]: any },
	-- Properties of the place's Atmosphere and BloomEffect children (the
	-- first of each class under Lighting). Skipped if the place has none.
	atmosphere: { [string]: any }?,
	bloom: { [string]: any }?,
	-- A ColorCorrectionEffect ArenaLighting creates and owns. Neutral in
	-- the hub (ArenaLightingConstants.GRADE_NEUTRAL).
	grade: { [string]: any }?,
}

local rgb = Color3.fromRGB

ArenaLightingConstants.Preset = {
	-- High-altitude dusk for the boss island. The sun sits about 14 degrees
	-- up, toward -X and about 24 degrees toward -Z (direction about
	-- (-0.88, 0.25, -0.40)): beyond the Spit side of the island as seen from
	-- the arrival overlook, so the first view of the arena looks into the
	-- sunset and the Spit's ring-out edge is a dark ledge against peach
	-- haze. The place's skybox stays a daytime blue overhead (it is the
	-- hub's too), so the mood reads as late afternoon with a sunset horizon.
	-- The haze thins the other islands to faint shapes at 400-600 studs but
	-- does not remove them: the swap removes them (boss-arena.md § Lighting).
	BossDusk = {
		lighting = {
			ClockTime = 16.95,
			Brightness = 2.4,
			ColorShift_Top = rgb(255, 196, 148),
			ColorShift_Bottom = rgb(0, 0, 0),
			-- Ambient lights what the sky cannot see (the cave): dark and
			-- cool, so the cave reads as a dark mouth.
			Ambient = rgb(38, 42, 60),
			-- The fill in sun shadow. Near-neutral, not blue: with the sun
			-- behind the west ridge, its inner face is lit by this alone, and
			-- a blue fill made it a navy that swallowed high-contrast blue
			-- letters (designer review, 2026-11-18).
			OutdoorAmbient = rgb(126, 120, 132),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.5,
			ShadowSoftness = 0.35,
			ExposureCompensation = 0.1,
		},
		atmosphere = {
			Density = 0.45,
			Offset = 0,
			Color = rgb(196, 162, 150),
			Decay = rgb(58, 52, 100),
			Glare = 0.3,
			Haze = 1.6,
		},
		bloom = {
			Intensity = 0.7,
			Size = 28,
			-- Low enough that the backlit Spit gate's and the cave plug's
			-- seams still bloom; above sunlit stone.
			Threshold = 1.2,
		},
		grade = {
			Contrast = 0.12,
			Saturation = 0,
			Brightness = 0,
			TintColor = rgb(255, 244, 236),
		},
	},
} :: { [string]: Preset }

-- Which preset a mode asks for. A mode absent here keeps the hub's look
-- (the lobby and duels today).
ArenaLightingConstants.MODE_PRESET = {
	PvEBoss = "BossDusk",
} :: { [string]: string }

-- Arenas created in code rather than authored as an ArenaSlot, so there is
-- no slot part to read a `Mode` from. The shipped Default arena runs PvEBoss.
ArenaLightingConstants.ARENA_PRESET = {
	[Arena.DEFAULT_ID] = "BossDusk",
} :: { [string]: string }

-- The effect ArenaLighting creates under Lighting. Named so it is never
-- confused with ScreenImpact's own post-processing instances.
ArenaLightingConstants.GRADE_NAME = "ArenaGrade"

ArenaLightingConstants.GRADE_NEUTRAL = {
	Contrast = 0,
	Saturation = 0,
	Brightness = 0,
	TintColor = rgb(255, 255, 255),
}

-- Seconds to cross-fade between the hub look and a preset. Entering an
-- arena is a teleport, so the fade plays while the player gets their
-- bearings; long enough to read as dusk falling, short enough to finish
-- before the boss entrance.
ArenaLightingConstants.FADE_SEC = 2

return ArenaLightingConstants
