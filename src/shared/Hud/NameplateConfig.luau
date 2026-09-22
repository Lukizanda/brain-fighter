----------------------------------------------------------------------
-- NameplateConfig
----------------------------------------------------------------------
-- Tunable constants for the plate over a combatant's head: the name
-- line, the health bar under it, and the damage numbers that pop off it.
--
-- The bar carries no `current / max` text. It was unreadable at any range
-- worth reading a health bar at, and the floating damage number already
-- says what a hit was worth — which is the number a player actually wants.
-- The bar is left to do the one job it is good at from a distance: show a
-- fraction.
--
-- The plate is sized in STUDS, not pixels, so it stays proportionate to
-- the rig it belongs to at every range. A BillboardGui sized in Offset
-- holds a fixed *pixel* size however far away it is — which sounds
-- desirable and is not: from the lobby spawn, 137 studs out, a 220 px
-- plate was a banner covering a dummy the size of a thumbnail. Sized in
-- studs it shrinks with its rig, so it reads as part of the character.
--
-- Everything inside the plate is therefore in Scale too. Pixel trim
-- (a 6 px corner, a 2 px stroke) is meaningless against a canvas that is
-- only a couple of dozen units across at range, and would swallow it.
----------------------------------------------------------------------

local NameplateConfig = {
	----------------------------------------------------------------------
	-- The plate
	----------------------------------------------------------------------
	-- Studs above the anchor part. The anchor is the rig's Head, so this
	-- is clearance over a head, not over the whole rig.
	HEIGHT_STUDS        = 2.6,
	-- Studs. Name row stacked over the bar, both this wide.
	PLATE_SIZE          = UDim2.new(5.2, 0, 1.2, 0),
	-- Relative weights, not pixels: the two rows split the plate's height
	-- in this ratio whatever the plate currently renders at.
	--
	-- To make the bar thicker, these are the two knobs and they do
	-- different things. Raising BAR_ROW_WEIGHT alone thickens the bar by
	-- taking height from the name; raising PLATE_SIZE's height alone
	-- thickens both together. Moving both, as here, thickens the bar and
	-- leaves the name where it was.
	NAME_ROW_WEIGHT     = 62,
	BAR_ROW_WEIGHT      = 50,

	----------------------------------------------------------------------
	-- Name row
	----------------------------------------------------------------------
	NAME_FONT           = Enum.Font.GothamBold,
	NAME_COLOR          = Color3.fromRGB(230, 232, 238),
	NAME_STROKE_COLOR   = Color3.fromRGB(0, 0, 0),
	NAME_STROKE_TRANSPARENCY = 0.2,

	----------------------------------------------------------------------
	-- Health bar
	----------------------------------------------------------------------
	CORNER_RADIUS       = UDim.new(0.25, 0),
	TRACK_COLOR         = Color3.fromRGB(22, 22, 26),
	TRACK_TRANSPARENCY  = 0.15,
	BORDER_COLOR        = Color3.fromRGB(255, 255, 255),
	BORDER_THICKNESS    = 0.12,
	BORDER_TRANSPARENCY = 0.65,

	-- The same three colours the player's own health bar uses, so a
	-- fraction reads the same on an opponent as it does on your HUD.
	FILL_COLOR          = Color3.fromRGB(80, 200, 80),
	FILL_WARNING_COLOR  = Color3.fromRGB(220, 180, 40),
	FILL_CRITICAL_COLOR = Color3.fromRGB(210, 60, 60),
	MID_THRESHOLD       = 0.5,
	LOW_THRESHOLD       = 0.25,
	FILL_TWEEN          = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- Hide behind walls: combat reads need line of sight, the same call
	-- the old nametag made.
	ALWAYS_ON_TOP       = false,
	MAX_DISTANCE        = 200,

	----------------------------------------------------------------------
	-- Damage numbers
	----------------------------------------------------------------------
	-- One short-lived billboard per hit, rising and fading. Anchored to
	-- the same part as the plate and started just above it, so a number
	-- never launches from inside the bar.
	DAMAGE_SIZE         = UDim2.new(4.2, 0, 1.5, 0),
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
	-- Rare on an opponent and rare on the dummy, but it exists so a heal
	-- is not silent when every other change to the bar is annotated.
	HEAL_COLOR          = Color3.fromRGB(96, 226, 118),
	HEAL_FORMAT         = "+%d",
}

return NameplateConfig
