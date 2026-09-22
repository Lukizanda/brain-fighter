----------------------------------------------------------------------
-- TrainingDummyConfig
----------------------------------------------------------------------
-- Tunable constants for the world-space health readout over a training
-- dummy, and for the damage numbers that pop off it.
--
-- Pixel values here are billboard-local, not HUD pixels: a BillboardGui
-- sized in offset is 50 px to the stud, so BAR_SIZE is ~7 x 1 studs.
-- They are not scaled by the HUD's UIScale — this is scene furniture,
-- not HUD, and it should read the same whatever the viewport is.
----------------------------------------------------------------------

local TrainingDummyConfig = {
	----------------------------------------------------------------------
	-- The readout
	----------------------------------------------------------------------
	-- Studs above the anchor part. The anchor is the rig's Head, so this
	-- is clearance over a head, not over the whole rig.
	HEIGHT_STUDS        = 2.2,
	-- 4.4 x 0.7 studs. Sized against the rig rather than for legibility
	-- alone: a bar much wider than the dummy's shoulders stops reading as
	-- part of it and starts reading as scenery.
	BAR_SIZE            = UDim2.fromOffset(220, 34),
	CORNER_RADIUS       = UDim.new(0, 8),

	TRACK_COLOR         = Color3.fromRGB(22, 22, 26),
	TRACK_TRANSPARENCY  = 0.15,
	BORDER_COLOR        = Color3.fromRGB(255, 255, 255),
	BORDER_THICKNESS    = 2,
	BORDER_TRANSPARENCY = 0.65,

	-- The same three colours the player's own health bar uses, so a
	-- fraction reads the same on the dummy as it does on your HUD.
	FILL_COLOR          = Color3.fromRGB(80, 200, 80),
	FILL_WARNING_COLOR  = Color3.fromRGB(220, 180, 40),
	FILL_CRITICAL_COLOR = Color3.fromRGB(210, 60, 60),
	MID_THRESHOLD       = 0.5,
	LOW_THRESHOLD       = 0.25,
	FILL_TWEEN          = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	TEXT_FONT           = Enum.Font.RobotoMono,
	TEXT_COLOR          = Color3.fromRGB(255, 255, 255),
	TEXT_STROKE_TRANSPARENCY = 0.4,
	-- Inset so the glyphs do not touch the rounded ends of the track.
	TEXT_INSET          = UDim.new(0, 10),
	TEXT_FORMAT         = "%d / %d",

	-- Far enough to read from the portals across the hub, near enough
	-- that it is not drawn for a player in another arena.
	MAX_DISTANCE        = 160,

	----------------------------------------------------------------------
	-- Damage numbers
	----------------------------------------------------------------------
	-- One short-lived billboard per hit, rising and fading. Anchored to
	-- the same part as the readout and started just above it, so a number
	-- never launches from inside the bar.
	DAMAGE_SIZE         = UDim2.fromOffset(220, 70),
	DAMAGE_FONT         = Enum.Font.GothamBold,
	DAMAGE_COLOR        = Color3.fromRGB(255, 96, 78),
	DAMAGE_STROKE_TRANSPARENCY = 0.25,
	DAMAGE_FORMAT       = "-%d",
	DAMAGE_START_OFFSET = 1.2,
	DAMAGE_RISE_STUDS   = 3.4,
	DAMAGE_TWEEN        = TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	-- Fading over the whole rise leaves the number unreadable for most of
	-- its life, so it holds opaque and then fades over the tail.
	DAMAGE_FADE_TWEEN   = TweenInfo.new(0.35, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
	DAMAGE_FADE_DELAY   = 0.55,
	-- Sideways scatter, so two hits in quick succession do not stack into
	-- one illegible number.
	DAMAGE_JITTER_STUDS = 1.1,

	----------------------------------------------------------------------
	-- Healing
	----------------------------------------------------------------------
	-- A dummy is healed only by a respawn or a heal spell, so the green
	-- number is rare. It exists so a heal landing on the dummy is not
	-- silent when every other change to the bar is annotated.
	HEAL_COLOR          = Color3.fromRGB(96, 226, 118),
	HEAL_FORMAT         = "+%d",
}

return TrainingDummyConfig
