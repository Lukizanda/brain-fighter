----------------------------------------------------------------------
-- SpellMenuConfig
----------------------------------------------------------------------
-- Default styling for the three-color spell cast panel.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnergyReservoirs = require(ReplicatedStorage.Shared.EnergyReservoirs)

local SpellMenuConfig = {
	BUTTON_WIDTH  = 180,
	BUTTON_HEIGHT = 160,
	BUTTON_GAP    = 12,
	CORNER_RADIUS = 10,

	-- Per-color panel backgrounds
	COLORS = {
		red   = { bg = Color3.fromRGB(180, 55, 55),  label = ""   },
		green = { bg = Color3.fromRGB(50, 155, 65),  label = "" },
		blue  = { bg = Color3.fromRGB(55, 105, 195), label = ""  },
	},

	-- Fill: dim base layer (always-visible "empty" bg) and animated fill bar
	FILL_BASE_TRANSPARENCY = 0.72,
	FILL_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	FILL_MAX   = EnergyReservoirs.CAP_PER_COLOR,

	-- The fill bar's vertical ramp, as a *multiplier* over its
	-- BackgroundColor3 rather than as two absolute colours.
	--
	-- It used to be a ColorSequence of the panel's own hue, which meant the
	-- bar's colour lived in two places at once (BackgroundColor3 and the
	-- gradient, multiplied together). That made the below-T1 desaturation
	-- below impossible to express as a tween, because TweenService cannot
	-- tween a ColorSequence. With the gradient reduced to a neutral ramp,
	-- BackgroundColor3 carries all the hue and one tween drains it.
	FILL_GRADIENT_BOTTOM_TINT = Color3.fromRGB(150, 150, 150),
	FILL_GRADIENT_TOP_TINT    = Color3.fromRGB(255, 255, 255),

	-- Text
	LABEL_FONT  = Enum.Font.GothamBold,
	LABEL_SIZE  = 26,
	SPELL_FONT  = Enum.Font.GothamBold,
	SPELL_SIZE  = 32,
	TEXT_COLOR  = Color3.fromRGB(255, 255, 255),
	DIM_COLOR   = Color3.fromRGB(160, 160, 175),
	TEXT_STROKE = 0.5,

	NO_SPELL_TEXT = "—",

	-- Persistent mana numeral ("35/60"), top-right of each panel.
	--
	-- Replaces the transient popup that used to appear on tap and fade
	-- after POPUP_DURATION. A number you only see *after* committing to a
	-- cast is the wrong side of the decision; hold-to-charge needs it
	-- readable the whole time, because it counts down live against the
	-- reserve band while the charge climbs.
	NUMERAL_FONT   = Enum.Font.GothamBold,
	NUMERAL_SIZE   = 20,
	NUMERAL_HEIGHT = 20,
	NUMERAL_INSET  = 6,
	NUMERAL_COLOR  = Color3.fromRGB(255, 255, 255),
	NUMERAL_DIM_COLOR = Color3.fromRGB(170, 170, 185),
	-- The reserved portion, shown while a charge is held. Matches
	-- CHARGE_RESERVE_COLOR so the number and the band read as one thing.
	NUMERAL_RESERVED_COLOR = Color3.fromRGB(255, 236, 150),
	NUMERAL_STROKE = 0.4,

	-- ── Tier notches ──────────────────────────────────────────────────
	-- Hard lines across the fill at each TIER_COSTS threshold. The bar was
	-- continuous and therefore unreadable: memorizing CAT (5 red) moves a
	-- 0–60 fill by 8%, which is a barely visible nudge for what is
	-- actually a whole T1 cast. The notch it crosses is the event.
	NOTCH_COLOR         = Color3.fromRGB(255, 255, 255),
	NOTCH_THICKNESS     = 2,
	NOTCH_TRANSPARENCY  = 0.55,
	-- The notch for the tier a held charge has currently reached.
	NOTCH_ACTIVE_TRANSPARENCY = 0,
	NOTCH_THICKNESS_ACTIVE    = 4,
	NOTCH_TWEEN         = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- ── Below-T1 treatment ────────────────────────────────────────────
	-- A panel that cannot cast anything is drained toward grey, so
	-- "castable" is a state you can see across the whole HUD at a glance
	-- rather than a spell name you have to read. Snaps to full colour on
	-- the frame T1 becomes affordable, alongside the afford bounce.
	DESATURATED_GREY  = Color3.fromRGB(96, 96, 104),
	-- 0 = untouched, 1 = fully grey.
	DESATURATED_BLEND = 0.72,
	DESATURATED_TWEEN = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- ── Hold-to-charge ────────────────────────────────────────────────
	-- The band eaten out of the top of the fill while a charge is held:
	-- the mana this release is about to spend. Nothing is drained until
	-- release (see wiki/systems/ChargeCast.md § Reserve, spend on
	-- release), so cancelling snaps the band away and costs nothing.
	CHARGE_RESERVE_COLOR        = Color3.fromRGB(255, 236, 150),
	CHARGE_RESERVE_TRANSPARENCY = 0.25,
	CHARGE_RESERVE_TWEEN        = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- Snapping back on cancel is deliberately faster than growing: the
	-- refund should feel like nothing happened, not like an animation.
	CHARGE_RELEASE_TWEEN        = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- At the affordability ceiling the panel pulses instead of climbing —
	-- "this is as big as it gets", with no text.
	--
	-- A dedicated overlay Frame rather than a UIScale pulse, because
	-- playAffordBounce already owns the panel's UIScale and two systems
	-- tweening one property is the fight concepts/SingleOwnership exists to
	-- stop. The overlay is nobody else's.
	CHARGE_CEILING_PULSE_COLOR = Color3.fromRGB(255, 255, 255),
	CHARGE_CEILING_PULSE_MIN   = 0.88,
	CHARGE_CEILING_PULSE_MAX   = 0.62,
	CHARGE_CEILING_PULSE_TWEEN = TweenInfo.new(
		0.42,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true
	),

	-- UI VFX tweens
	AFFORD_BOUNCE_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	AFFORD_BOUNCE_SCALE = 1.08,
	FIRED_FLASH_TWEEN   = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	FIRED_DIM_TWEEN     = TweenInfo.new(0.40, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

return SpellMenuConfig
